import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/budget_notification_gateway.dart';
import '../../../core/notifications/local_budget_notification_gateway.dart';
import '../../../core/providers/database_providers.dart';
import '../services/budget_alert_service.dart';

final budgetNotificationGatewayProvider =
    Provider<BudgetNotificationGateway>((ref) {
  return LocalBudgetNotificationGateway();
});

final budgetAlertServiceProvider = Provider<BudgetAlertService>((ref) {
  return BudgetAlertService(
    repository: ref.watch(budgetRepositoryProvider),
    gateway: ref.watch(budgetNotificationGatewayProvider),
  );
});
