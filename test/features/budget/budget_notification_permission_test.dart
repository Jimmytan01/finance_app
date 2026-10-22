import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/notifications/budget_notification_gateway.dart';
import 'package:finance_app/core/providers/database_providers.dart';
import 'package:finance_app/core/sync/sync_aware_budget_service.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/providers/budget_alert_providers.dart';
import 'package:finance_app/features/budget/providers/budget_providers.dart';
import 'package:finance_app/features/budget/repositories/budget_repository.dart';
import 'package:finance_app/features/transactions/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('denied OS permission still saves budget and keeps in-app progress',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = BudgetRepository(database);
    final gateway = _DeniedNotificationGateway();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      currentUserIdProvider.overrideWithValue('user-1'),
      budgetMonthProvider.overrideWithValue(const SelectedMonth(2026, 10)),
      budgetNotificationGatewayProvider.overrideWithValue(gateway),
      syncAwareBudgetServiceProvider.overrideWithValue(
        SyncAwareBudgetService(repository: repository),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: const Value('food'),
            userId: 'user-1',
            name: 'Makanan',
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: const Value('tx-1'),
            userId: 'user-1',
            date: DateTime(2026, 10, 10),
          ),
        );
    await database.into(database.transactionItems).insert(
          TransactionItemsCompanion.insert(
            id: const Value('item-1'),
            transactionId: 'tx-1',
            categoryId: const Value('food'),
            name: 'Makan siang',
            subtotal: const Value(80000),
          ),
        );

    await container.read(budgetListProvider.future);
    final permissionGranted = await container
        .read(budgetListProvider.notifier)
        .save(const BudgetInput(
          userId: 'user-1',
          categoryId: 'food',
          year: 2026,
          month: 10,
          limitAmount: 100000,
          notificationsEnabled: true,
        ));
    await Future<void>.delayed(Duration.zero);

    final budget = (await repository.getForMonth('user-1', 2026, 10)).single;
    expect(permissionGranted, isFalse);
    expect(gateway.permissionRequests, 1);
    expect(budget.notificationsEnabled, isFalse);
    expect(budget.progress.reachedThresholds, [80]);
  });
}

class _DeniedNotificationGateway implements BudgetNotificationGateway {
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return false;
  }

  @override
  Future<void> showBudgetAlert({
    required String budgetId,
    required String categoryName,
    required int thresholdPercent,
  }) async {}
}
