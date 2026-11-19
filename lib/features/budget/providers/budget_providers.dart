import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/providers/database_providers.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../models/budget_models.dart';
import 'budget_alert_providers.dart';

final budgetMonthProvider = Provider<SelectedMonth>(
  (ref) => ref.watch(selectedMonthProvider),
);

final budgetListProvider =
    AsyncNotifierProvider<BudgetListNotifier, List<BudgetSummary>>(
  BudgetListNotifier.new,
);

class BudgetListNotifier extends AsyncNotifier<List<BudgetSummary>> {
  @override
  Future<List<BudgetSummary>> build() {
    ref.watch(syncTickProvider);
    final month = ref.watch(budgetMonthProvider);
    final userId = ref.watch(currentUserIdProvider);
    return ref
        .watch(budgetRepositoryProvider)
        .getForMonth(userId, month.year, month.month);
  }

  Future<bool> save(BudgetInput input) async {
    if (state.isLoading) return false;
    final previous = state;
    state =
        const AsyncLoading<List<BudgetSummary>>().copyWithPrevious(previous);
    var permissionGranted = true;

    try {
      final repository = ref.read(budgetRepositoryProvider);
      final existing = await repository.getForMonth(
        input.userId,
        input.year,
        input.month,
      );
      final old =
          existing.where((budget) => budget.categoryId == input.categoryId);
      if (input.notificationsEnabled &&
          (old.isEmpty || !old.first.notificationsEnabled)) {
        try {
          permissionGranted = await ref
              .read(budgetNotificationGatewayProvider)
              .requestPermission();
        } catch (error) {
          AppLogger.warning(
            'Budget notification permission request failed: $error',
            scope: 'budget',
          );
          permissionGranted = false;
        }
      }

      final savedInput = permissionGranted || !input.notificationsEnabled
          ? input
          : BudgetInput(
              id: input.id,
              userId: input.userId,
              categoryId: input.categoryId,
              year: input.year,
              month: input.month,
              limitAmount: input.limitAmount,
              notificationsEnabled: false,
            );
      await ref.read(syncAwareBudgetServiceProvider).save(savedInput);
      state = AsyncData(await repository.getForMonth(
        input.userId,
        input.year,
        input.month,
      ));
      unawaited(ref.read(budgetAlertServiceProvider).evaluateForMonth(
            userId: input.userId,
            year: input.year,
            month: input.month,
          ));
      return permissionGranted;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Could not save budget',
        scope: 'budget',
        error: error,
        stackTrace: stackTrace,
      );
      state = AsyncError<List<BudgetSummary>>(error, stackTrace);
      rethrow;
    }
  }

  Future<void> delete(String budgetId) async {
    if (state.isLoading) return;
    final previous = state;
    state =
        const AsyncLoading<List<BudgetSummary>>().copyWithPrevious(previous);
    try {
      await ref.read(syncAwareBudgetServiceProvider).delete(budgetId);
      final month = ref.read(budgetMonthProvider);
      final userId = ref.read(currentUserIdProvider);
      state = AsyncData(await ref
          .read(budgetRepositoryProvider)
          .getForMonth(userId, month.year, month.month));
    } catch (error, stackTrace) {
      AppLogger.error(
        'Could not delete budget',
        scope: 'budget',
        error: error,
        stackTrace: stackTrace,
      );
      state = AsyncError<List<BudgetSummary>>(error, stackTrace);
      rethrow;
    }
  }

  Future<bool> setNotificationsEnabled(
    BudgetSummary budget,
    bool enabled,
  ) =>
      save(BudgetInput(
        id: budget.id,
        userId: budget.userId,
        categoryId: budget.categoryId,
        year: budget.year,
        month: budget.month,
        limitAmount: budget.limitAmount,
        notificationsEnabled: enabled,
      ));
}
