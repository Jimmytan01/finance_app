import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../models/budget_models.dart';

class BudgetRepository {
  final AppDatabase _db;
  final TransactionDao _transactions;

  BudgetRepository(AppDatabase db)
      : _db = db,
        _transactions = TransactionDao(db);

  Future<List<BudgetSummary>> getForMonth(
    String userId,
    int year,
    int month,
  ) async {
    final rows = await (_db.select(_db.categoryBudgets)
          ..where((budget) =>
              budget.userId.equals(userId) &
              budget.year.equals(year) &
              budget.month.equals(month) &
              budget.isDeleted.equals(false))
          ..orderBy([(budget) => OrderingTerm.asc(budget.createdAt)]))
        .get();
    final spentByCategory = {
      for (final summary
          in await _transactions.getMonthlyCategorySummary(userId, year, month))
        if (summary.categoryId != null) summary.categoryId!: summary.total,
    };

    return Future.wait(rows.map((row) async {
      final category = await (_db.select(_db.categories)
            ..where((value) => value.id.equals(row.categoryId)))
          .getSingleOrNull();
      final spent = spentByCategory[row.categoryId] ?? 0.0;
      return BudgetSummary(
        id: row.id,
        userId: row.userId,
        categoryId: row.categoryId,
        categoryName: category?.name ?? 'Kategori tidak ditemukan',
        year: row.year,
        month: row.month,
        limitAmount: row.limitAmount,
        spentAmount: spent,
        notificationsEnabled: row.notificationsEnabled,
        progress: BudgetProgress.fromAmounts(
          limitAmount: row.limitAmount,
          spentAmount: spent,
        ),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
    }));
  }

  Future<BudgetSummary?> getById(String budgetId) async {
    final row = await (_db.select(_db.categoryBudgets)
          ..where((budget) => budget.id.equals(budgetId)))
        .getSingleOrNull();
    if (row == null) return null;
    final summaries = await getForMonth(row.userId, row.year, row.month);
    for (final summary in summaries) {
      if (summary.id == budgetId) return summary;
    }
    return null;
  }

  Future<void> save(BudgetInput input) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.categoryBudgets)
            ..where((budget) =>
                budget.userId.equals(input.userId) &
                budget.categoryId.equals(input.categoryId) &
                budget.year.equals(input.year) &
                budget.month.equals(input.month)))
          .getSingleOrNull();

      if (existing == null) {
        await _db.into(_db.categoryBudgets).insert(
              CategoryBudgetsCompanion.insert(
                id: Value(input.id ?? const Uuid().v4()),
                userId: input.userId,
                categoryId: input.categoryId,
                year: input.year,
                month: input.month,
                limitAmount: input.limitAmount,
                notificationsEnabled: Value(input.notificationsEnabled),
                isDeleted: const Value(false),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_db.update(_db.categoryBudgets)
              ..where((budget) => budget.id.equals(existing.id)))
            .write(CategoryBudgetsCompanion(
          limitAmount: Value(input.limitAmount),
          notificationsEnabled: Value(input.notificationsEnabled),
          isDeleted: const Value(false),
          updatedAt: Value(now),
        ));
      }
    });
  }

  Future<void> softDelete(String budgetId) async {
    await (_db.update(_db.categoryBudgets)
          ..where((budget) => budget.id.equals(budgetId)))
        .write(CategoryBudgetsCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<bool> markAlertSent(String budgetId, int thresholdPercent) async {
    if (thresholdPercent != 80 && thresholdPercent != 100) {
      throw ArgumentError.value(thresholdPercent, 'thresholdPercent');
    }
    return _db.transaction(() async {
      final existing = await (_db.select(_db.budgetAlertMarkers)
            ..where((marker) =>
                marker.budgetId.equals(budgetId) &
                marker.thresholdPercent.equals(thresholdPercent)))
          .getSingleOrNull();
      if (existing != null) return false;
      await _db.into(_db.budgetAlertMarkers).insert(
            BudgetAlertMarkersCompanion.insert(
              budgetId: budgetId,
              thresholdPercent: thresholdPercent,
            ),
          );
      return true;
    });
  }

  Future<void> clearAlertSent(String budgetId, int thresholdPercent) async {
    await (_db.delete(_db.budgetAlertMarkers)
          ..where((marker) =>
              marker.budgetId.equals(budgetId) &
              marker.thresholdPercent.equals(thresholdPercent)))
        .go();
  }
}
