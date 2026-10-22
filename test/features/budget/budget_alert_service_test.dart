import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/notifications/budget_notification_gateway.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/repositories/budget_repository.dart';
import 'package:finance_app/features/budget/services/budget_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BudgetRepository repository;
  late _FakeNotificationGateway gateway;
  late BudgetAlertService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = BudgetRepository(database);
    gateway = _FakeNotificationGateway();
    service = BudgetAlertService(repository: repository, gateway: gateway);

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
    await repository.save(_input());
  });

  tearDown(() => database.close());

  test('notifies at exactly 80 percent', () async {
    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);

    expect(gateway.alerts.map((alert) => alert.thresholdPercent), [80]);
    expect(gateway.alerts.single.categoryName, 'Makanan');
  });

  test('notifies at exactly 100 percent', () async {
    await _setSpentAmount(database, 100000);

    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);

    expect(gateway.alerts.map((alert) => alert.thresholdPercent), [80, 100]);
  });

  test('keeps over-budget progress and does not repeat reached thresholds',
      () async {
    await _setSpentAmount(database, 120000);

    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);
    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);

    expect(gateway.alerts.map((alert) => alert.thresholdPercent), [80, 100]);
    final budget = (await repository.getForMonth('user-1', 2026, 10)).single;
    expect(budget.progress.usageRatio, 1.2);
  });

  test('does not notify when the budget notifications are disabled', () async {
    await repository.save(_input(notificationsEnabled: false));

    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);

    expect(gateway.alerts, isEmpty);
  });

  test('notification plugin failure does not affect the saved budget',
      () async {
    gateway.failOnShow = true;

    await expectLater(
      service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10),
      completes,
    );

    expect(await repository.getForMonth('user-1', 2026, 10), hasLength(1));
    gateway.failOnShow = false;
    await service.evaluateForMonth(userId: 'user-1', year: 2026, month: 10);
    expect(gateway.alerts.map((alert) => alert.thresholdPercent), [80]);
  });
}

Future<void> _setSpentAmount(AppDatabase database, double amount) async {
  await (database.update(database.transactionItems)
        ..where((item) => item.id.equals('item-1')))
      .write(TransactionItemsCompanion(subtotal: Value(amount)));
}

BudgetInput _input({bool notificationsEnabled = true}) => BudgetInput(
      userId: 'user-1',
      categoryId: 'food',
      year: 2026,
      month: 10,
      limitAmount: 100000,
      notificationsEnabled: notificationsEnabled,
    );

class _FakeNotificationGateway implements BudgetNotificationGateway {
  final List<_Alert> alerts = [];
  bool failOnShow = false;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showBudgetAlert({
    required String budgetId,
    required String categoryName,
    required int thresholdPercent,
  }) async {
    if (failOnShow) throw StateError('Notification permission denied');
    alerts.add(_Alert(categoryName, thresholdPercent));
  }
}

class _Alert {
  final String categoryName;
  final int thresholdPercent;
  const _Alert(this.categoryName, this.thresholdPercent);
}
