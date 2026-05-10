// State management untuk halaman History.
// Sengaja dipisah dari transaction_providers.dart karena concern-nya beda:
// history = lintas bulan + search + filter,
// sedangkan transaction_providers = spesifik bulan yang sedang dilihat.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../../transactions/providers/transaction_providers.dart';
import '../../transactions/services/transaction_service.dart';

// ─────────────────────────────────────────────────────────────
// Filter state — semua pilihan user disimpan di sini
// ─────────────────────────────────────────────────────────────

class HistoryFilter {
  final String  searchQuery;
  final String? categoryId;   // null = semua kategori
  final SortOrder sortOrder;

  const HistoryFilter({
    this.searchQuery = '',
    this.categoryId,
    this.sortOrder   = SortOrder.dateDesc,
  });

  // Helper untuk cek apakah ada filter aktif (selain sort default)
  bool get isFiltered =>
      searchQuery.isNotEmpty || categoryId != null;

  HistoryFilter copyWith({
    String?    searchQuery,
    String?    categoryId,
    bool       clearCategory = false,
    SortOrder? sortOrder,
  }) =>
      HistoryFilter(
        searchQuery: searchQuery ?? this.searchQuery,
        categoryId:  clearCategory ? null : (categoryId ?? this.categoryId),
        sortOrder:   sortOrder ?? this.sortOrder,
      );
}

enum SortOrder {
  dateDesc,   // terbaru dulu (default)
  dateAsc,    // terlama dulu
  amountDesc, // terbesar dulu
  amountAsc,  // terkecil dulu
}

extension SortOrderLabel on SortOrder {
  String get label {
    switch (this) {
      case SortOrder.dateDesc:   return 'Terbaru';
      case SortOrder.dateAsc:    return 'Terlama';
      case SortOrder.amountDesc: return 'Terbesar';
      case SortOrder.amountAsc:  return 'Terkecil';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Filter notifier
// ─────────────────────────────────────────────────────────────

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setSearch(String q)      => state = state.copyWith(searchQuery: q);
  void setCategory(String? id)  => state = state.copyWith(
        categoryId:    id,
        clearCategory: id == null,
      );
  void setSortOrder(SortOrder o) => state = state.copyWith(sortOrder: o);
  void clearAll()               => state = const HistoryFilter();
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
        HistoryFilterNotifier.new);

// ─────────────────────────────────────────────────────────────
// Raw data — semua transaksi tanpa filter
// autoDispose biar tidak nempel di memori waktu user keluar dari tab ini
// ─────────────────────────────────────────────────────────────

final allTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  // FIX: watch syncTick — setiap kali sync selesai, provider ini re-fetch
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(transactionDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  return dao.getAllTransactions(userId);
});
 
// ─────────────────────────────────────────────────────────────
// Filtered + sorted — derive dari allTransactions, jadi
// tidak perlu watch syncTick lagi secara terpisah
// ─────────────────────────────────────────────────────────────
 
final filteredTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  final all    = await ref.watch(allTransactionsProvider.future);
  final filter = ref.watch(historyFilterProvider);
 
  var result = all.toList();
 
  if (filter.searchQuery.isNotEmpty) {
    final q = filter.searchQuery.toLowerCase();
    result = result
        .where((t) =>
            (t.placeName?.toLowerCase().contains(q) ?? false) ||
            (t.notes?.toLowerCase().contains(q) ?? false))
        .toList();
  }
 
  if (filter.categoryId != null) {
    final dao    = ref.read(transactionDaoProvider);
    final userId = ref.read(currentUserIdProvider);
    final byCategory =
        await dao.getByCategory(userId, filter.categoryId!);
    final byCategoryIds = byCategory.map((t) => t.id).toSet();
    result =
        result.where((t) => byCategoryIds.contains(t.id)).toList();
  }
 
  switch (filter.sortOrder) {
    case SortOrder.dateDesc:
      result.sort((a, b) => b.date.compareTo(a.date));
    case SortOrder.dateAsc:
      result.sort((a, b) => a.date.compareTo(b.date));
    case SortOrder.amountDesc:
      result.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    case SortOrder.amountAsc:
      result.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
  }
 
  return result;
});
 
final groupedHistoryProvider = FutureProvider.autoDispose
    <Map<String, List<Transaction>>>((ref) async {
  final txs    = await ref.watch(filteredTransactionsProvider.future);
  final filter = ref.watch(historyFilterProvider);
 
  final sortByAmount = filter.sortOrder == SortOrder.amountDesc ||
      filter.sortOrder == SortOrder.amountAsc;
 
  if (sortByAmount) return {'': txs};
 
  final result = <String, List<Transaction>>{};
  for (final tx in txs) {
    final key =
        TransactionService.formatMonth(tx.date.year, tx.date.month);
    result.putIfAbsent(key, () => []).add(tx);
  }
  return result;
});