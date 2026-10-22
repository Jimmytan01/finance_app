abstract interface class BudgetNotificationGateway {
  Future<bool> requestPermission();

  Future<void> showBudgetAlert({
    required String budgetId,
    required String categoryName,
    required int thresholdPercent,
  });
}
