// Wrapper di atas BillService yang otomatis enqueue setiap operasi
// ke SyncQueue supaya ter-push ke Supabase.
//
// Pola yang sama dengan SyncAwareTransactionService — setelah operasi
// ke SQLite lokal selesai, ambil data yang tersimpan dari DB (UUID sudah final),
// baru enqueue ke SyncQueue. Ini mencegah UUID mismatch yang menyebabkan dobel.

import 'dart:convert';
import '../database/app_database.dart';
import '../sync/sync_service.dart';
import '../../features/bill/services/bill_service.dart';

class SyncAwareBillService extends BillService {
  final SyncService? _sync;
  final BillDao      _billDao;

  SyncAwareBillService({
    required BillDao        billDao,
    required TransactionDao txDao,
    required String         userId,
    required String         deviceId,
    SyncService?            syncService,
  })  : _sync    = syncService,
        _billDao  = billDao,
        super(
          billDao:  billDao,
          txDao:    txDao,
          userId:   userId,
          deviceId: deviceId,
        );

  // ── Save session + enqueue semua tabel terkait ────────────
  @override
  Future<String> saveSession(
    BillFormState  form,
    BillCalcResult result,
  ) async {
    // Simpan ke SQLite lokal dulu via parent
    final sessionId = await super.saveSession(form, result);

    if (_sync == null) return sessionId;

    // Setelah parent selesai insert, ambil semua data dari DB
    // supaya UUID yang di-push ke Supabase identik dengan yang ada di lokal
    final detail = await _billDao.getSessionDetail(sessionId);
    final now    = DateTime.now().toIso8601String();

    // Enqueue bill_sessions header
    await _sync!.enqueue(
      tableName: 'bill_sessions',
      recordId:  sessionId,
      operation: 'insert',
      payload: {
        'id':             sessionId,
        'user_id':        userId,
        'title':          detail.session.title,
        'date':           detail.session.date
            .toIso8601String()
            .substring(0, 10),
        'place_name':     detail.session.placeName,
        'discount_type':  detail.session.discountType,
        'discount_value': detail.session.discountValue,
        'tax_percent':    detail.session.taxPercent,
        'total_amount':   detail.session.totalAmount,
        'linked_tx_id':   detail.session.linkedTxId,
        'created_at':     now,
        'updated_at':     now,
      },
    );

    // Enqueue bill_participants
    for (final p in detail.participants) {
      await _sync!.enqueue(
        tableName: 'bill_participants',
        recordId:  p.id,
        operation: 'insert',
        payload: {
          'id':              p.id,
          'bill_session_id': sessionId,
          'name':            p.name,
          'is_self':         p.isSelf,
          'created_at':      now,
        },
      );
    }

    // Enqueue bill_items
    for (final item in detail.items) {
      await _sync!.enqueue(
        tableName: 'bill_items',
        recordId:  item.id,
        operation: 'insert',
        payload: {
          'id':              item.id,
          'bill_session_id': sessionId,
          'name':            item.name,
          'unit_price':      item.unitPrice,
          'quantity':        item.quantity,
          'subtotal':        item.subtotal,
          'created_at':      now,
        },
      );
    }

    // Enqueue bill_item_participants (splits)
    for (final split in detail.splits) {
      await _sync!.enqueue(
        tableName: 'bill_item_participants',
        recordId:  split.id,
        operation: 'insert',
        payload: {
          'id':             split.id,
          'bill_item_id':   split.billItemId,
          'participant_id': split.participantId,
          'share_qty':      split.shareQty,
          'share_amount':   split.shareAmount,
        },
      );
    }

    return sessionId;
  }

  // ── Delete session + enqueue delete semua tabel terkait ───
  // Urutan: splits → items → participants → session (child sebelum parent)
  Future<void> deleteSessionWithSync(String sessionId) async {
    // Ambil detail dulu sebelum dihapus — kita perlu ID-nya
    BillSessionDetail? detail;
    try {
      detail = await _billDao.getSessionDetail(sessionId);
    } catch (_) {
      // Kalau gagal ambil detail, tetap hapus lokal
    }

    // Hapus dari SQLite lokal
    await _billDao.deleteSession(sessionId);

    if (_sync == null || detail == null) return;

    // Enqueue delete untuk setiap split
    for (final split in detail.splits) {
      await _sync!.enqueue(
        tableName: 'bill_item_participants',
        recordId:  split.id,
        operation: 'delete',
        payload:   {'id': split.id},
      );
    }

    // Enqueue delete untuk setiap item
    for (final item in detail.items) {
      await _sync!.enqueue(
        tableName: 'bill_items',
        recordId:  item.id,
        operation: 'delete',
        payload:   {'id': item.id},
      );
    }

    // Enqueue delete untuk setiap participant
    for (final p in detail.participants) {
      await _sync!.enqueue(
        tableName: 'bill_participants',
        recordId:  p.id,
        operation: 'delete',
        payload:   {'id': p.id},
      );
    }

    // Terakhir: enqueue delete session header
    await _sync!.enqueue(
      tableName: 'bill_sessions',
      recordId:  sessionId,
      operation: 'delete',
      payload:   {'id': sessionId},
    );
  }

  // ── Link session ke transaksi + update Supabase ────────────
  @override
  Future<void> saveMyShareToTransaction({
    required String         sessionId,
    required BillFormState  form,
    required BillCalcResult result,
    required List<Category> categories,
  }) async {
    // Parent simpan transaksi ke lokal
    await super.saveMyShareToTransaction(
      sessionId:  sessionId,
      form:       form,
      result:     result,
      categories: categories,
    );

    if (_sync == null) return;

    // Update linked_tx_id di Supabase
    // Ambil session terbaru dari DB untuk dapat linked_tx_id yang benar
    try {
      final sessions = await (_billDao.getAllSessions(userId));
      final session  = sessions.where((s) => s.id == sessionId).firstOrNull;
      if (session?.linkedTxId != null) {
        await _sync!.enqueue(
          tableName: 'bill_sessions',
          recordId:  sessionId,
          operation: 'update',
          payload: {
            'id':           sessionId,
            'user_id':      userId,
            'linked_tx_id': session!.linkedTxId,
            'updated_at':   DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (_) {}
  }
}