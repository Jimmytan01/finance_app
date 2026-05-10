// Wrapper di atas TransactionService dan BillService yang secara
// otomatis menambahkan setiap write ke SyncQueue.
//
// KENAPA PENDEKATAN WRAPPER BUKAN MODIFIKASI DAO LANGSUNG?
// Karena DAO idealnya tidak tahu soal sync — itu bukan urusannya.
// DAO hanya tahu cara baca/tulis ke SQLite. SyncQueue adalah concern
// layer di atasnya. Dengan wrapper ini, kita bisa test DAO dan
// SyncService secara terpisah tanpa coupling.
//
// CARA PAKAI:
// Di providers, ganti transactionServiceProvider dengan
// syncAwareTransactionServiceProvider. Semua pemanggil di UI
// tidak perlu berubah sama sekali karena interface-nya sama.

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../sync/sync_service.dart';
import '../../features/transactions/services/transaction_service.dart';
 
class SyncAwareTransactionService extends TransactionService {
  final SyncService?   _sync;
  final TransactionDao _txDao;
 
  SyncAwareTransactionService({
    required TransactionDao dao,
    required String         userId,
    required String         deviceId,
    SyncService?            syncService,
  })  : _sync  = syncService,
        _txDao  = dao,
        super(dao: dao, userId: userId, deviceId: deviceId);
 
  @override
  Future<String> saveTransaction(TransactionInput input) async {
    // Tulis ke SQLite lokal dulu via parent — ini yang assign UUID final
    final txId = await super.saveTransaction(input);
 
    if (_sync == null) return txId;
 
    final now = DateTime.now().toIso8601String();
 
    // Enqueue header transaksi
    await _sync!.enqueue(
      tableName: 'transactions',
      recordId:  txId,
      operation: 'insert',
      payload: {
        'id':           txId,
        'user_id':      userId,
        'date':         input.date.toIso8601String().substring(0, 10),
        'place_name':   input.placeName,
        'notes':        input.notes,
        'total_amount': input.total,
        'device_id':    deviceId,
        'created_at':   now,
        'updated_at':   now,
      },
    );
 
    // Ambil items dari DB setelah parent selesai insert —
    // supaya UUID yang di-push ke Supabase identik dengan yang ada di lokal
    final savedItems = await _txDao.getItemsByTxId(txId);
 
    for (final item in savedItems) {
      await _sync!.enqueue(
        tableName: 'transaction_items',
        recordId:  item.id,
        operation: 'insert',
        payload:   _itemPayload(item),
      );
    }
 
    return txId;
  }
 
  // ── Update transaksi yang sudah ada ──────────────────────
  @override
  Future<void> updateTransaction(String txId, TransactionInput input) async {
    // FIX: ambil item LAMA dulu sebelum super dipanggil.
    // Setelah super.updateTransaction(), item lama sudah terhapus dari lokal
    // dan tidak bisa diambil lagi — makanya harus diambil sekarang.
    final oldItems = await _txDao.getItemsByTxId(txId);
 
    // Super: hapus item lama dari SQLite lokal, insert item baru dengan UUID baru
    await super.updateTransaction(txId, input);
 
    if (_sync == null) return;
 
    final now = DateTime.now().toIso8601String();
 
    // Enqueue update header
    await _sync!.enqueue(
      tableName: 'transactions',
      recordId:  txId,
      operation: 'update',
      payload: {
        'id':           txId,
        'user_id':      userId,
        'date':         input.date.toIso8601String().substring(0, 10),
        'place_name':   input.placeName,
        'notes':        input.notes,
        'total_amount': input.total,
        'device_id':    deviceId,
        'updated_at':   now,
      },
    );
 
    // FIX: Enqueue DELETE untuk setiap item LAMA di Supabase.
    // Tanpa ini, Supabase masih punya item lama + item baru sekaligus
    // → saat pull, keduanya masuk ke lokal → item dobel.
    for (final old in oldItems) {
      await _sync!.enqueue(
        tableName: 'transaction_items',
        recordId:  old.id,
        operation: 'delete',
        payload:   {'id': old.id},
      );
    }
 
    // Ambil item BARU dari DB (UUID sudah final setelah super selesai)
    // lalu enqueue INSERT ke Supabase
    final newItems = await _txDao.getItemsByTxId(txId);
    for (final item in newItems) {
      await _sync!.enqueue(
        tableName: 'transaction_items',
        recordId:  item.id,
        operation: 'insert',
        payload:   _itemPayload(item),
      );
    }
  }
 
  // ── Hapus transaksi ───────────────────────────────────────
  @override
  Future<void> deleteTransaction(String txId) async {
    // Ambil items sebelum dihapus — perlu ID-nya untuk enqueue delete
    final itemsToDelete = await _txDao.getItemsByTxId(txId);
 
    await super.deleteTransaction(txId);
 
    if (_sync == null) return;
 
    // Hapus items di Supabase dulu (child sebelum parent)
    for (final item in itemsToDelete) {
      await _sync!.enqueue(
        tableName: 'transaction_items',
        recordId:  item.id,
        operation: 'delete',
        payload:   {'id': item.id},
      );
    }
 
    // Baru hapus header
    await _sync!.enqueue(
      tableName: 'transactions',
      recordId:  txId,
      operation: 'delete',
      payload:   {'id': txId},
    );
  }
 
  // ── Helper: build payload item dari TransactionItem ───────
  Map<String, dynamic> _itemPayload(TransactionItem item) => {
    'id':              item.id,
    'transaction_id':  item.transactionId,
    'category_id':     item.categoryId,
    'name':            item.name,
    'unit_price':      item.unitPrice,
    'quantity':        item.quantity,
    'discount_amount': item.discountAmount,
    'subtotal':        item.subtotal,
    'notes':           item.notes,
    'created_at':      item.createdAt.toIso8601String(),
    'updated_at':      item.updatedAt.toIso8601String(),
  };
}