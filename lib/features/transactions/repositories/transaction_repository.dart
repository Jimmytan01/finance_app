import '../../../core/database/app_database.dart';

abstract interface class TransactionRepository {
  Future<List<Transaction>> getByMonth(String userId, int year, int month);
  Future<List<CategorySummary>> getMonthlyCategorySummary(
      String userId, int year, int month);
  Future<List<Category>> getCategories(String userId);
  Future<List<TransactionItem>> getItemsByTxId(String txId);
  Future<void> insertFull({
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  });
  Future<void> deleteItemsByTxId(String txId);
  Future<void> updateHeaderAndItems({
    required String txId,
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  });
  Future<void> deleteTransaction(String txId);
}

class DriftTransactionRepository implements TransactionRepository {
  final TransactionDao _transactions;
  final CategoryDao _categories;

  const DriftTransactionRepository({
    required TransactionDao transactions,
    required CategoryDao categories,
  })  : _transactions = transactions,
        _categories = categories;

  @override
  Future<List<Transaction>> getByMonth(String userId, int year, int month) =>
      _transactions.getByMonth(userId, year, month);

  @override
  Future<List<CategorySummary>> getMonthlyCategorySummary(
          String userId, int year, int month) =>
      _transactions.getMonthlyCategorySummary(userId, year, month);

  @override
  Future<List<Category>> getCategories(String userId) =>
      _categories.getAll(userId);

  @override
  Future<List<TransactionItem>> getItemsByTxId(String txId) =>
      _transactions.getItemsByTxId(txId);

  @override
  Future<void> insertFull({
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      _transactions.insertFull(header: header, items: items);

  @override
  Future<void> deleteItemsByTxId(String txId) =>
      _transactions.deleteItemsByTxId(txId);

  @override
  Future<void> updateHeaderAndItems({
    required String txId,
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      _transactions.updateHeaderAndItems(
          txId: txId, header: header, items: items);

  @override
  Future<void> deleteTransaction(String txId) =>
      _transactions.deleteTransaction(txId);
}
