import '../../features/budget/models/budget_models.dart';
import '../../features/budget/repositories/budget_repository.dart';
import '../../features/budget/services/budget_service.dart';
import 'sync_service.dart';

class SyncAwareBudgetService {
  final BudgetRepository _repository;
  final BudgetService _service;
  final SyncService? _sync;

  SyncAwareBudgetService({
    required BudgetRepository repository,
    SyncService? syncService,
  })  : _repository = repository,
        _service = BudgetService(repository),
        _sync = syncService;

  Future<void> save(BudgetInput input) async {
    await _service.save(input);
    final sync = _sync;
    if (sync == null) return;

    final summaries = await _repository.getForMonth(
      input.userId,
      input.year,
      input.month,
    );
    final matching =
        summaries.where((item) => item.categoryId == input.categoryId);
    if (matching.isEmpty) return;
    final budget = matching.first;
    await sync.enqueue(
      tableName: 'category_budgets',
      recordId: budget.id,
      operation: 'insert',
      payload: _payload(budget),
    );
  }

  Future<void> delete(String budgetId) async {
    final budget = await _repository.getById(budgetId);
    if (budget == null) return;
    await _repository.softDelete(budgetId);
    final sync = _sync;
    if (sync == null) return;

    await sync.enqueue(
      tableName: 'category_budgets',
      recordId: budget.id,
      operation: 'update',
      payload: {
        ..._payload(budget),
        'is_deleted': true,
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _payload(BudgetSummary budget) => {
        'id': budget.id,
        'user_id': budget.userId,
        'category_id': budget.categoryId,
        'year': budget.year,
        'month': budget.month,
        'limit_amount': budget.limitAmount,
        'notifications_enabled': budget.notificationsEnabled,
        'is_deleted': false,
        'created_at': budget.createdAt.toIso8601String(),
        'updated_at': budget.updatedAt.toIso8601String(),
      };
}
