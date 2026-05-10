// Provider untuk AppDatabase dan semua DAO.
// Di-expose ke seluruh app via Riverpod.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/transactions/providers/transaction_providers.dart';
import '../../features/transactions/services/transaction_service.dart';
import '../auth/auth_providers.dart';
import '../database/app_database.dart';
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


final syncAwareTransactionServiceProvider = Provider<TransactionService>((ref) {
    final dao      = ref.watch(transactionDaoProvider);
    final userId   = ref.watch(currentUserIdProvider);
    final deviceId = ref.watch(currentDeviceIdProvider);
    final sync     = ref.watch(syncNotifierProvider).valueOrNull;

    return SyncAwareTransactionService(
      dao:         dao,
      userId:      userId,
      deviceId:    deviceId,
      syncService: sync,
    );
});