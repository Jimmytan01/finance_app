import '../../../core/notifications/budget_notification_gateway.dart';
import '../repositories/budget_repository.dart';

class BudgetAlertService {
  final BudgetRepository _repository;
  final BudgetNotificationGateway _gateway;

  const BudgetAlertService({
    required BudgetRepository repository,
    required BudgetNotificationGateway gateway,
  })  : _repository = repository,
        _gateway = gateway;

  Future<void> evaluateForMonth({
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final budgets = await _repository.getForMonth(userId, year, month);
      for (final budget in budgets) {
        if (!budget.notificationsEnabled) continue;
        for (final threshold in budget.progress.reachedThresholds) {
          try {
            if (await _repository.markAlertSent(budget.id, threshold)) {
              try {
                await _gateway.showBudgetAlert(
                  budgetId: budget.id,
                  categoryName: budget.categoryName,
                  thresholdPercent: threshold,
                );
              } catch (_) {
                await _repository.clearAlertSent(budget.id, threshold);
              }
            }
          } catch (_) {
            // The budget and its in-app progress remain available without OS notifications.
          }
        }
      }
    } catch (_) {
      // Alert delivery must never block a local transaction save or sync.
    }
  }
}
