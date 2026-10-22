import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/repositories/budget_repository.dart';
import 'package:finance_app/features/budget/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BudgetProgress', () {
    test('calculates ratio, remaining amount, and exact alert thresholds', () {
      final progress =
          BudgetProgress.fromAmounts(limitAmount: 1000, spentAmount: 800);

      expect(progress.usageRatio, 0.8);
      expect(progress.remainingAmount, 200);
      expect(progress.reachedThresholds, [80]);
    });

    test('reaches both thresholds at the exact budget limit', () {
      final progress =
          BudgetProgress.fromAmounts(limitAmount: 1000, spentAmount: 1000);

      expect(progress.reachedThresholds, [80, 100]);
      expect(progress.remainingAmount, 0);
    });

    test('keeps over-budget ratio visible and clamps remaining to zero', () {
      final progress =
          BudgetProgress.fromAmounts(limitAmount: 1000, spentAmount: 1200);

      expect(progress.usageRatio, 1.2);
      expect(progress.remainingAmount, 0);
      expect(progress.reachedThresholds, [80, 100]);
    });

    test('rejects an invalid limit', () {
      expect(
        () => BudgetProgress.fromAmounts(limitAmount: 0, spentAmount: 10),
        throwsArgumentError,
      );
    });
  });

  group('BudgetService validation', () {
    test('accepts a positive finite budget', () {
      expect(BudgetService.validate(_input(250000)), isNull);
    });

    test('rejects non-finite, zero, and negative budget amounts', () {
      for (final amount in [double.nan, double.infinity, 0.0, -1.0]) {
        expect(BudgetService.validate(_input(amount)), isNotNull,
            reason: '$amount');
      }
    });

    test('does not persist an invalid amount', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final service = BudgetService(BudgetRepository(database));
      addTearDown(database.close);

      await expectLater(
        service.save(_input(0)),
        throwsA(isA<BudgetValidationException>()),
      );
      expect(await database.select(database.categoryBudgets).get(), isEmpty);
    });
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
