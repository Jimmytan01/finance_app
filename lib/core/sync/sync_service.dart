import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

// Hanya tabel parent yang punya user_id langsung
const _parentTables = [
  'categories',
  'transactions',
  'bill_sessions',
];
 
// Tabel child — tidak punya user_id, perlu pull via parent IDs
const _childTables = [
  'transaction_items',
  'bill_participants',
  'bill_items',
  'bill_item_participants',
];
 
enum SyncStatus { idle, syncing, success, error }
 
class SyncResult {
  final SyncStatus status;
  final String?    errorMessage;
  final int        pushedCount;
  final int        pulledCount;
  final DateTime   timestamp;
 
  const SyncResult({
    required this.status,
    this.errorMessage,
    this.pushedCount = 0,
    this.pulledCount = 0,
    required this.timestamp,
  });
 
  factory SyncResult.idle() => SyncResult(
        status:    SyncStatus.idle,
        timestamp: DateTime.now(),
      );
}
 
class InitialPullResult {
  final bool    success;
  final String? errorMessage;
  final int     pulledCount;
 
  const InitialPullResult({
    required this.success,
    this.errorMessage,
    this.pulledCount = 0,
  });
}
 
class SyncService {
  final AppDatabase    _db;
  final SupabaseClient _supabase;
  final String         _userId;
  final String         _deviceId;
 
  final _statusController = StreamController<SyncResult>.broadcast();
  Stream<SyncResult> get statusStream => _statusController.stream;
 
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool   _isSyncing = false;
 
  SyncService({
    required AppDatabase    db,
    required SupabaseClient supabase,
    required String         userId,
    required String         deviceId,
  })  : _db      = db,
        _supabase = supabase,
        _userId   = userId,
        _deviceId = deviceId;
 
  void init() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 2), fullSync);
      }
    });
  }
 
  void dispose() {
    _connectivitySub?.cancel();
    _debounceTimer?.cancel();
    _statusController.close();
  }
 
  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
 
  // ── Full sync: push → pull → reconcile ───────────────────
  Future<SyncResult> fullSync() async {
    if (_isSyncing) return SyncResult.idle();
 
    _isSyncing = true;
    _statusController.add(
        SyncResult(status: SyncStatus.syncing, timestamp: DateTime.now()));
 
    try {
      if (!await isOnline()) {
        _isSyncing = false;
        return SyncResult(
          status:       SyncStatus.idle,
          errorMessage: 'Offline',
          timestamp:    DateTime.now(),
        );
      }
 
      final pushed = await pushPendingQueue();
      final pulled = await pullDelta();
 
      // Setelah pull, cek apakah ada yang perlu dihapus lokal
      await _reconcileDeletes();
 
      await _updateLastSyncAt();
 
      final result = SyncResult(
        status:      SyncStatus.success,
        pushedCount: pushed,
        pulledCount: pulled,
        timestamp:   DateTime.now(),
      );
      _statusController.add(result);
      _isSyncing = false;
      return result;
    } catch (e) {
      final result = SyncResult(
        status:       SyncStatus.error,
        errorMessage: e.toString(),
        timestamp:    DateTime.now(),
      );
      _statusController.add(result);
      _isSyncing = false;
      return result;
    }
  }
 
  // ── Push queue ke Supabase ────────────────────────────────
  Future<int> pushPendingQueue() async {
    final queueDao = SyncQueueDao(_db);
    final pending  = await queueDao.getPending(limit: 100);
    if (pending.isEmpty) return 0;
 
    int successCount = 0;
    for (final entry in pending) {
      try {
        final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
 
        switch (entry.operation) {
          case 'insert':
          case 'update':
            await _supabase.from(entry.targetTable).upsert(payload);
          case 'delete':
            await _supabase
                .from(entry.targetTable)
                .delete()
                .eq('id', entry.recordId);
        }
 
        await queueDao.deleteById(entry.id);
        successCount++;
      } catch (e) {
        if (entry.retryCount >= 5) {
          await queueDao.deleteById(entry.id);
        } else {
          await queueDao.incrementRetry(entry.id);
        }
        continue;
      }
    }
 
    return successCount;
  }
 
  // ── Pull delta dari Supabase ──────────────────────────────
  // FIX 1: Pisah handling tabel parent (punya user_id) vs
  // child (tidak punya user_id, perlu pull via parent IDs).
  Future<int> pullDelta() async {
    final deviceRow = await (_db.select(_db.devices)
          ..where((d) => d.id.equals(_deviceId)))
        .getSingleOrNull();
 
    final since      = deviceRow?.lastSyncAt;
    int   pulledCount = 0;
 
    // ── Pull tabel parent ─────────────────────────────────
    for (final table in _parentTables) {
      try {
        final List<Map<String, dynamic>> rows;
 
        if (since != null) {
          rows = await _supabase
              .from(table)
              .select()
              .eq('user_id', _userId)
              .gt('updated_at', since.toIso8601String());
        } else {
          rows = await _supabase
              .from(table)
              .select()
              .eq('user_id', _userId);
        }
 
        for (final row in rows) {
          await _upsertToLocal(table, row);
          pulledCount++;
        }
      } catch (_) {
        continue;
      }
    }
 
    // ── Pull tabel child via parent IDs ───────────────────
    // Setelah parent sudah ada di lokal, ambil child-nya
    // menggunakan ID parent yang kita punya
    pulledCount += await _pullChildTables(since: since);
 
    return pulledCount;
  }
 
  // Pull tabel child yang tidak punya user_id langsung.
  // Caranya: ambil parent IDs dari lokal DB, lalu pull child
  // yang parent_id-nya ada di list tersebut.
  Future<int> _pullChildTables({DateTime? since}) async {
    int pulledCount = 0;
 
    // ── transaction_items via transaction IDs ─────────────
    try {
      final localTxRows = await (_db.select(_db.transactions)
            ..where((t) => t.userId.equals(_userId)))
          .get();
      final txIds = localTxRows.map((t) => t.id).toList();
 
      if (txIds.isNotEmpty) {
        // Supabase .inFilter() untuk IN clause
        final List<Map<String, dynamic>> rows;
 
        if (since != null) {
          rows = await _supabase
              .from('transaction_items')
              .select()
              .inFilter('transaction_id', txIds)
              .gt('updated_at', since.toIso8601String());
        } else {
          rows = await _supabase
              .from('transaction_items')
              .select()
              .inFilter('transaction_id', txIds);
        }
 
        for (final row in rows) {
          await _upsertToLocal('transaction_items', row);
          pulledCount++;
        }
      }
    } catch (_) {}
 
    // ── bill_participants via bill_session IDs ─────────────
    try {
      final sessionRows = await (_db.select(_db.billSessions)
            ..where((b) => b.userId.equals(_userId)))
          .get();
      final sessionIds = sessionRows.map((s) => s.id).toList();
 
      if (sessionIds.isNotEmpty) {
        final partRows = await _supabase
            .from('bill_participants')
            .select()
            .inFilter('bill_session_id', sessionIds);
 
        for (final row in partRows) {
          await _upsertToLocal('bill_participants', row);
          pulledCount++;
        }
 
        // ── bill_items via bill_session IDs ───────────────
        final itemRows = await _supabase
            .from('bill_items')
            .select()
            .inFilter('bill_session_id', sessionIds);
 
        final billItemIds = <String>[];
        for (final row in itemRows) {
          await _upsertToLocal('bill_items', row);
          billItemIds.add(row['id'] as String);
          pulledCount++;
        }
 
        // ── bill_item_participants via bill_item IDs ───────
        if (billItemIds.isNotEmpty) {
          final splitRows = await _supabase
              .from('bill_item_participants')
              .select()
              .inFilter('bill_item_id', billItemIds);
 
          for (final row in splitRows) {
            await _upsertToLocal('bill_item_participants', row);
            pulledCount++;
          }
        }
      }
    } catch (_) {}
 
    return pulledCount;
  }
 
  // ── Reconcile deletes ─────────────────────────────────────
  // FIX 2: Cek ID di server vs lokal untuk deteksi record yang dihapus.
  // Hanya cek tabel transactions dan bill_sessions karena child-nya
  // akan ikut terhapus via cascade di SQLite.
  Future<void> _reconcileDeletes() async {
    try {
      // Ambil semua transaction ID milik user ini dari Supabase
      final serverTxRows = await _supabase
          .from('transactions')
          .select('id')
          .eq('user_id', _userId);
 
      final serverTxIds = (serverTxRows as List)
          .map((r) => r['id'] as String)
          .toSet();
 
      // Ambil semua transaction ID dari lokal
      final localTxRows = await (_db.select(_db.transactions)
            ..where((t) => t.userId.equals(_userId)))
          .get();
 
      // Yang ada di lokal tapi tidak di server → dihapus dari device lain
      for (final localTx in localTxRows) {
        if (!serverTxIds.contains(localTx.id)) {
          // Hapus dari lokal — cascade akan hapus transaction_items juga
          await (_db.delete(_db.transactionItems)
                ..where((i) => i.transactionId.equals(localTx.id)))
              .go();
          await (_db.delete(_db.transactions)
                ..where((t) => t.id.equals(localTx.id)))
              .go();
        }
      }
    } catch (_) {
      // Kalau reconcile gagal, skip — tidak kritis, akan dicoba di sync berikutnya
    }
 
    // Hal yang sama untuk bill_sessions
    try {
      final serverSessionRows = await _supabase
          .from('bill_sessions')
          .select('id')
          .eq('user_id', _userId);
 
      final serverSessionIds = (serverSessionRows as List)
          .map((r) => r['id'] as String)
          .toSet();
 
      final localSessionRows = await (_db.select(_db.billSessions)
            ..where((b) => b.userId.equals(_userId)))
          .get();
 
      for (final local in localSessionRows) {
        if (!serverSessionIds.contains(local.id)) {
          // Hapus manual karena cascade di SQLite perlu pragma foreign_keys ON
          final itemRows = await (_db.select(_db.billItems)
                ..where((i) => i.billSessionId.equals(local.id)))
              .get();
 
          for (final item in itemRows) {
            await (_db.delete(_db.billItemParticipants)
                  ..where((s) => s.billItemId.equals(item.id)))
                .go();
          }
 
          await (_db.delete(_db.billItems)
                ..where((i) => i.billSessionId.equals(local.id)))
              .go();
          await (_db.delete(_db.billParticipants)
                ..where((p) => p.billSessionId.equals(local.id)))
              .go();
          await (_db.delete(_db.billSessions)
                ..where((b) => b.id.equals(local.id)))
              .go();
        }
      }
    } catch (_) {}
  }
 
  // ── Initial pull ──────────────────────────────────────────
  Future<InitialPullResult> initialPull() async {
    if (!await isOnline()) {
      return const InitialPullResult(
        success:      false,
        errorMessage: 'Tidak ada koneksi internet. '
            'Sambungkan ke internet sebelum pull ulang dari server.',
      );
    }
 
    // Push dulu — pastikan data lokal sudah aman di server
    final queueDao      = SyncQueueDao(_db);
    final pendingBefore = await queueDao.getPending();
 
    if (pendingBefore.isNotEmpty) {
      await pushPendingQueue();
      final pendingAfter = await queueDao.getPending();
      if (pendingAfter.isNotEmpty) {
        return InitialPullResult(
          success:      false,
          errorMessage: 'Ada ${pendingAfter.length} data yang gagal dikirim ke server. '
              'Pastikan koneksi stabil dan coba lagi.',
        );
      }
    }
 
    // Hapus data lokal — sekarang aman karena sudah di server
    await _clearLocalUserData();
 
    // Pull parent tables
    int pulledCount = 0;
    for (final table in _parentTables) {
      try {
        final rows = await _supabase
            .from(table)
            .select()
            .eq('user_id', _userId);
 
        for (final row in rows) {
          await _upsertToLocal(table, row);
          pulledCount++;
        }
      } catch (_) {
        continue;
      }
    }
 
    // Pull child tables — setelah parent sudah ada
    pulledCount += await _pullChildTables();
 
    await _updateLastSyncAt();
 
    return InitialPullResult(success: true, pulledCount: pulledCount);
  }
 
  // ── Enqueue perubahan lokal ───────────────────────────────
  Future<void> enqueue({
    required String               tableName,
    required String               recordId,
    required String               operation,
    required Map<String, dynamic> payload,
  }) async {
    final queueDao = SyncQueueDao(_db);
    await queueDao.enqueue(SyncQueueCompanion(
      targetTable: Value(tableName),
      recordId:    Value(recordId),
      operation:   Value(operation),
      payload:     Value(jsonEncode(payload)),
      queuedAt:    Value(DateTime.now()),
      retryCount:  const Value(0),
    ));
 
    if (await isOnline()) {
      _debounceTimer?.cancel();
      _debounceTimer =
          Timer(const Duration(milliseconds: 500), pushPendingQueue);
    }
  }
 
  // ── Realtime subscription ─────────────────────────────────
  RealtimeChannel? _realtimeChannel;
 
  void subscribeRealtime() {
    _realtimeChannel = _supabase
        .channel('user-$_userId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'transactions',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'user_id',
            value:  _userId,
          ),
          callback: (_) {
            // Ada perubahan dari device lain — jalankan full sync
            // (bukan hanya pull) supaya reconcile delete juga jalan
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(seconds: 1), fullSync);
          },
        )
        .subscribe();
  }
 
  void unsubscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }
 
  // ── Upsert satu row dari Supabase ke SQLite lokal ─────────
  Future<void> _upsertToLocal(
      String table, Map<String, dynamic> row) async {
    try {
      switch (table) {
        case 'categories':
          await _db.into(_db.categories).insertOnConflictUpdate(
                CategoriesCompanion(
                  id:        Value(row['id'] as String),
                  userId:    Value(row['user_id'] as String),
                  name:      Value(row['name'] as String),
                  icon:      Value(row['icon'] as String? ?? 'category'),
                  color:     Value(row['color'] as String? ?? '#888888'),
                  isDefault: Value(row['is_default'] as bool? ?? false),
                  createdAt: Value(_parseDate(row['created_at'])),
                  updatedAt: Value(_parseDate(row['updated_at'])),
                ),
              );
 
        case 'transactions':
          await _db.into(_db.transactions).insertOnConflictUpdate(
                TransactionsCompanion(
                  id:          Value(row['id'] as String),
                  userId:      Value(row['user_id'] as String),
                  date:        Value(_parseDate(row['date'])),
                  placeName:   Value(row['place_name'] as String?),
                  notes:       Value(row['notes'] as String?),
                  totalAmount: Value((row['total_amount'] as num).toDouble()),
                  deviceId:    Value(row['device_id'] as String?),
                  syncedAt:    Value(DateTime.now()),
                  createdAt:   Value(_parseDate(row['created_at'])),
                  updatedAt:   Value(_parseDate(row['updated_at'])),
                ),
              );
 
        case 'transaction_items':
          await _db.into(_db.transactionItems).insertOnConflictUpdate(
                TransactionItemsCompanion(
                  id:             Value(row['id'] as String),
                  transactionId:  Value(row['transaction_id'] as String),
                  categoryId:     Value(row['category_id'] as String?),
                  name:           Value(row['name'] as String),
                  unitPrice:      Value((row['unit_price'] as num).toDouble()),
                  quantity:       Value((row['quantity'] as num).toDouble()),
                  discountAmount: Value(
                      (row['discount_amount'] as num?)?.toDouble() ?? 0),
                  subtotal:       Value((row['subtotal'] as num).toDouble()),
                  notes:          Value(row['notes'] as String?),
                  createdAt:      Value(_parseDate(row['created_at'])),
                  updatedAt:      Value(_parseDate(row['updated_at'])),
                ),
              );
 
        case 'bill_sessions':
          await _db.into(_db.billSessions).insertOnConflictUpdate(
                BillSessionsCompanion(
                  id:            Value(row['id'] as String),
                  userId:        Value(row['user_id'] as String),
                  title:         Value(row['title'] as String),
                  date:          Value(_parseDate(row['date'])),
                  placeName:     Value(row['place_name'] as String?),
                  discountType:  Value(row['discount_type'] as String? ?? 'flat'),
                  discountValue: Value(
                      (row['discount_value'] as num?)?.toDouble() ?? 0),
                  taxPercent:    Value(
                      (row['tax_percent'] as num?)?.toDouble() ?? 0),
                  totalAmount:   Value((row['total_amount'] as num).toDouble()),
                  linkedTxId:    Value(row['linked_tx_id'] as String?),
                  createdAt:     Value(_parseDate(row['created_at'])),
                  updatedAt:     Value(_parseDate(row['updated_at'])),
                ),
              );
 
        case 'bill_participants':
          await _db.into(_db.billParticipants).insertOnConflictUpdate(
                BillParticipantsCompanion(
                  id:            Value(row['id'] as String),
                  billSessionId: Value(row['bill_session_id'] as String),
                  name:          Value(row['name'] as String),
                  isSelf:        Value(row['is_self'] as bool? ?? false),
                  createdAt:     Value(_parseDate(row['created_at'])),
                ),
              );
 
        case 'bill_items':
          await _db.into(_db.billItems).insertOnConflictUpdate(
                BillItemsCompanion(
                  id:            Value(row['id'] as String),
                  billSessionId: Value(row['bill_session_id'] as String),
                  name:          Value(row['name'] as String),
                  unitPrice:     Value((row['unit_price'] as num).toDouble()),
                  quantity:      Value((row['quantity'] as num).toInt()),
                  subtotal:      Value((row['subtotal'] as num).toDouble()),
                  createdAt:     Value(_parseDate(row['created_at'])),
                ),
              );
 
        case 'bill_item_participants':
          await _db.into(_db.billItemParticipants).insertOnConflictUpdate(
                BillItemParticipantsCompanion(
                  id:            Value(row['id'] as String),
                  billItemId:    Value(row['bill_item_id'] as String),
                  participantId: Value(row['participant_id'] as String),
                  shareQty:      Value((row['share_qty'] as num).toDouble()),
                  shareAmount:   Value((row['share_amount'] as num).toDouble()),
                ),
              );
      }
    } catch (_) {
      // Skip row yang gagal — akan coba lagi di sync berikutnya
    }
  }
 
  Future<void> _clearLocalUserData() async {
  await _db.transaction(() async {
    await _db.delete(_db.transactionItems).go();
    await _db.delete(_db.transactions).go();
    await _db.delete(_db.billItemParticipants).go();
    await _db.delete(_db.billItems).go();
    await _db.delete(_db.billParticipants).go();
    await _db.delete(_db.billSessions).go();
    await _db.delete(_db.categories).go();
    await _db.delete(_db.syncQueue).go();
  });
}
 
  Future<void> _updateLastSyncAt() async {
    await (_db.update(_db.devices)
          ..where((d) => d.id.equals(_deviceId)))
        .write(DevicesCompanion(lastSyncAt: Value(DateTime.now())));
  }
 
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value as String);
    } catch (_) {
      return DateTime.now();
    }
  }
}