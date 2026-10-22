import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/repositories/budget_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BudgetRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = BudgetRepository(database);
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
  });

  tearDown(() => database.close());

  test('upserts one budget per category and period and calculates spending',
      () async {
    await repository.save(_input(100000));
    final first = (await repository.getForMonth('user-1', 2026, 10)).single;
    await repository.save(_input(150000));

    final rows = await repository.getForMonth('user-1', 2026, 10);

    expect(rows, hasLength(1));
    expect(rows.single.id, first.id);
    expect(rows.single.limitAmount, 150000);
    expect(rows.single.categoryName, 'Makanan');
    expect(rows.single.progress.usageRatio, closeTo(80000 / 150000, 0.0001));
  });

  test('hides soft-deleted budgets and reuses their stable record on recreate',
      () async {
    await repository.save(_input(100000));
    final original = (await repository.getForMonth('user-1', 2026, 10)).single;

    await repository.softDelete(original.id);
    expect(await repository.getForMonth('user-1', 2026, 10), isEmpty);

    await repository.save(_input(125000));
    final recreated = (await repository.getForMonth('user-1', 2026, 10)).single;

    expect(recreated.id, original.id);
    expect(recreated.limitAmount, 125000);
    expect(await database.select(database.categoryBudgets).get(), hasLength(1));
  });

  test('records each alert threshold once per device', () async {
    await repository.save(_input(100000));
    final budget = (await repository.getForMonth('user-1', 2026, 10)).single;

    expect(await repository.markAlertSent(budget.id, 80), isTrue);
    expect(await repository.markAlertSent(budget.id, 80), isFalse);
    expect(await repository.markAlertSent(budget.id, 100), isTrue);
  });
}

BudgetInput _input(double amount) => BudgetInput(
      userId: 'user-1',
      categoryId: 'food',
      year: 2026,
      month: 10,
      limitAmount: amount,
      notificationsEnabled: true,
    );
