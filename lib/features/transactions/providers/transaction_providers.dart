// State management untuk semua yang berkaitan dengan transaksi.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../services/transaction_service.dart';

// ─────────────────────────────────────────────────────────────
// syncTickProvider — "detak jantung" sync.
// Nilainya tidak penting, yang penting perubahan nilainya.
// Setiap kali naik, semua provider yang watch ini ikut rebuild.
// Di-increment oleh SyncNotifier setiap kali sync berhasil.
// ─────────────────────────────────────────────────────────────
 
final syncTickProvider = StateProvider<int>((ref) => 0);
 
// ─────────────────────────────────────────────────────────────
// Auth state (sementara — akan di-override di main.dart Phase 5)
// ─────────────────────────────────────────────────────────────
 
final currentUserIdProvider = Provider<String>((ref) {
  return 'local-user-001';
});
 
final currentDeviceIdProvider = Provider<String>((ref) {
  return 'device-001';
});
 
// ─────────────────────────────────────────────────────────────
// TransactionService provider
// ─────────────────────────────────────────────────────────────
 
final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(
    dao:      ref.watch(transactionDaoProvider),
    userId:   ref.watch(currentUserIdProvider),
    deviceId: ref.watch(currentDeviceIdProvider),
  );
});
 
// ─────────────────────────────────────────────────────────────
// Bulan yang sedang dilihat
// ─────────────────────────────────────────────────────────────
 
class SelectedMonth {
  final int year;
  final int month;
  const SelectedMonth(this.year, this.month);
 
  SelectedMonth prev() {
    if (month == 1) return SelectedMonth(year - 1, 12);
    return SelectedMonth(year, month - 1);
  }
 
  SelectedMonth next() {
    if (month == 12) return SelectedMonth(year + 1, 1);
    return SelectedMonth(year, month + 1);
  }
 
  bool get isCurrentMonth {
    final now = DateTime.now();
    return year == now.year && month == now.month;
  }
}
 
class SelectedMonthNotifier extends Notifier<SelectedMonth> {
  @override
  SelectedMonth build() {
    final now = DateTime.now();
    return SelectedMonth(now.year, now.month);
  }
 
  void goPrev()  => state = state.prev();
  void goNext()  => state = state.next();
  void goToNow() {
    final now = DateTime.now();
    state = SelectedMonth(now.year, now.month);
  }
}
 
final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, SelectedMonth>(
        SelectedMonthNotifier.new);
 
// ─────────────────────────────────────────────────────────────
// Data providers — semuanya watch syncTickProvider.
//
// Cara kerjanya: ref.watch(syncTickProvider) membuat provider ini
// terdaftar sebagai dependen dari syncTick. Begitu syncTick naik,
// Riverpod otomatis invalidate dan re-run semua provider ini.
// Kita tidak perlu memanggil ref.invalidate() manual dari mana-mana.
// ─────────────────────────────────────────────────────────────
 
final monthlyTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  // Watch syncTick — kalau naik, provider ini auto re-fetch
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(transactionDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  final month  = ref.watch(selectedMonthProvider);
  return dao.getByMonth(userId, month.year, month.month);
});
 
final monthlyCategorySummaryProvider =
    FutureProvider.autoDispose<List<CategorySummary>>((ref) async {
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(transactionDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  final month  = ref.watch(selectedMonthProvider);
  return dao.getMonthlyCategorySummary(userId, month.year, month.month);
});
 
final monthlyTotalProvider =
    FutureProvider.autoDispose<double>((ref) async {
  // Derive dari summary — tidak perlu watch syncTick lagi
  // karena monthlyCategorySummaryProvider sudah watch
  final summaries =
      await ref.watch(monthlyCategorySummaryProvider.future);
  return summaries.fold<double>(0.0, (sum, s) => sum + s.total);
});
 
final categoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(categoryDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  return dao.getAll(userId);
});
 
final transactionItemsProvider = FutureProvider.autoDispose
    .family<List<TransactionItem>, String>((ref, txId) async {
  ref.watch(syncTickProvider);
 
  final dao = ref.watch(transactionDaoProvider);
  return dao.getItemsByTxId(txId);
});
 
// ─────────────────────────────────────────────────────────────
// State form tambah/edit transaksi — tidak perlu watch syncTick
// karena ini state input user, bukan data dari DB
// ─────────────────────────────────────────────────────────────
 
class AddTransactionNotifier extends Notifier<TransactionInput> {
  @override
  TransactionInput build() => TransactionInput();
 
  void setDate(DateTime date) => state = TransactionInput(
      date:      date,
      placeName: state.placeName,
      notes:     state.notes,
      items:     state.items);
 
  void setPlaceName(String v) => state = TransactionInput(
      date:      state.date,
      placeName: v,
      notes:     state.notes,
      items:     state.items);
 
  void setNotes(String v) => state = TransactionInput(
      date:      state.date,
      placeName: state.placeName,
      notes:     v,
      items:     state.items);
 
  void addItem() => state = TransactionInput(
      date:      state.date,
      placeName: state.placeName,
      notes:     state.notes,
      items:     [...state.items, TransactionItemInput()]);
 
  void removeItem(int index) {
    final newItems = [...state.items]..removeAt(index);
    state = TransactionInput(
        date:      state.date,
        placeName: state.placeName,
        notes:     state.notes,
        items:     newItems);
  }
 
  void updateItem(int index, TransactionItemInput item) {
    final newItems = [...state.items]..[index] = item;
    state = TransactionInput(
        date:      state.date,
        placeName: state.placeName,
        notes:     state.notes,
        items:     newItems);
  }
 
  void reset() => state = TransactionInput();
 
  void loadExisting(Transaction tx, List<TransactionItem> items) {
    state = TransactionInput(
      date:      tx.date,
      placeName: tx.placeName,
      notes:     tx.notes,
      items:     items
          .map((i) => TransactionItemInput(
                id:             i.id,
                name:           i.name,
                categoryId:     i.categoryId,
                unitPrice:      i.unitPrice,
                quantity:       i.quantity,
                discountValue: i.discountAmount,
                discountType:  'flat',
                notes:          i.notes,
              ))
          .toList(),
    );
  }
}
 
final addTransactionProvider =
    NotifierProvider<AddTransactionNotifier, TransactionInput>(
        AddTransactionNotifier.new);