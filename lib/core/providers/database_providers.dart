// Provider untuk AppDatabase dan semua DAO.
// Di-expose ke seluruh app via Riverpod.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/transactions/providers/transaction_providers.dart';
import '../../features/transactions/services/transaction_service.dart';
import '../../features/budget/repositories/budget_repository.dart';
import '../auth/auth_providers.dart';
import '../database/app_database.dart';
import '../sync/sync_aware_budget_service.dart';
import '../sync/sync_aware_service.dart';

// ── Singleton database ──────────────────────────────────────
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── DAO providers ───────────────────────────────────────────
final transactionDaoProvider = Provider<TransactionDao>((ref) {
  return TransactionDao(ref.watch(appDatabaseProvider));
});

final categoryDaoProvider = Provider<CategoryDao>((ref) {
  return CategoryDao(ref.watch(appDatabaseProvider));
});

final billDaoProvider = Provider<BillDao>((ref) {
  return BillDao(ref.watch(appDatabaseProvider));
});

final syncQueueDaoProvider = Provider<SyncQueueDao>((ref) {
  return SyncQueueDao(ref.watch(appDatabaseProvider));
});

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepository(ref.watch(appDatabaseProvider));
});

final syncAwareBudgetServiceProvider = Provider<SyncAwareBudgetService>((ref) {
  return SyncAwareBudgetService(
    repository: ref.watch(budgetRepositoryProvider),
    syncService: ref.watch(syncNotifierProvider).valueOrNull,
  );
});

final syncNowProvider = Provider<Future<void> Function()>((ref) => () async {
      await ref.read(syncNotifierProvider.notifier).sync();
    });

final syncAwareTransactionServiceProvider = Provider<TransactionService>((ref) {
  final repository = ref.watch(transactionRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final deviceId = ref.watch(currentDeviceIdProvider);
  final sync = ref.watch(syncNotifierProvider).valueOrNull;

  return SyncAwareTransactionService(
    repository: repository,
    userId: userId,
    deviceId: deviceId,
    syncService: sync,
  );
});
