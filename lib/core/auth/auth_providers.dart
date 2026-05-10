import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../providers/database_providers.dart';
import '../sync/sync_service.dart';
import '../../features/transactions/providers/transaction_providers.dart';
import 'auth_service.dart';
 
// ─────────────────────────────────────────────────────────────
// Supabase client — singleton, tidak boleh di-recreate
// ─────────────────────────────────────────────────────────────
 
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
 
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    supabase: ref.watch(supabaseClientProvider),
    db:       ref.watch(appDatabaseProvider),
  );
});
 
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateStream;
});
 
final currentUserProvider = Provider<User?>((ref) {
  final authAsync = ref.watch(authStateProvider);
  return authAsync.valueOrNull?.session?.user ??
      Supabase.instance.client.auth.currentUser;
});
 
// ─────────────────────────────────────────────────────────────
// SyncNotifier — FIX: increment syncTick setelah sync sukses
// ─────────────────────────────────────────────────────────────
 
class SyncNotifier extends AsyncNotifier<SyncService?> {
  @override
  Future<SyncService?> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;
 
    final db       = ref.watch(appDatabaseProvider);
    final supabase = ref.watch(supabaseClientProvider);
    final auth     = ref.watch(authServiceProvider);
 
    final deviceId = await auth.getLocalDeviceId();
    if (deviceId == null) return null;
 
    final service = SyncService(
      db:       db,
      supabase: supabase,
      userId:   user.id,
      deviceId: deviceId,
    );
 
    service.init();
    service.subscribeRealtime();
 
    // FIX: listen ke statusStream — setiap kali sync sukses,
    // increment syncTickProvider supaya semua data provider rebuild
    final sub = service.statusStream.listen((result) {
      if (result.status == SyncStatus.success) {
        // Naikan tick → semua FutureProvider yang watch syncTick
        // otomatis di-invalidate dan re-fetch dari SQLite
        ref.read(syncTickProvider.notifier).state++;
      }
    });
 
    ref.onDispose(() {
      sub.cancel();
      service.unsubscribeRealtime();
      service.dispose();
    });
 
    // Sync pertama saat app launch
    service.fullSync();
 
    return service;
  }
 
  Future<SyncResult> sync() async {
    final service = state.valueOrNull;
    if (service == null) {
      return SyncResult(
        status:       SyncStatus.error,
        errorMessage: 'Sync service belum siap',
        timestamp:    DateTime.now(),
      );
    }
 
    final result = await service.fullSync();
 
    // FIX: manual sync juga trigger tick update kalau berhasil
    // (sudah di-handle di statusStream listener di atas, tapi
    // kita pastikan lagi di sini kalau ada race condition)
    if (result.status == SyncStatus.success) {
      ref.read(syncTickProvider.notifier).state++;
    }
 
    return result;
  }
}
 
final syncNotifierProvider =
    AsyncNotifierProvider<SyncNotifier, SyncService?>(SyncNotifier.new);
 
final syncStatusProvider = StreamProvider<SyncResult>((ref) async* {
  final service = ref.watch(syncNotifierProvider).valueOrNull;
  if (service == null) {
    yield SyncResult.idle();
    return;
  }
  yield* service.statusStream;
});