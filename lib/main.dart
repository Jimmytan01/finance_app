// Entry point aplikasi. Setup Riverpod + tema + routing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env/env.dart';
import 'core/auth/auth_providers.dart';
import 'core/auth/auth_service.dart';
import 'core/sync/sync_aware_service.dart';
import 'core/providers/database_providers.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/bill/screens/bill_list_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/report/screens/report_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/transactions/providers/transaction_providers.dart';
import 'features/transactions/screens/transaction_list_screen.dart';
 
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
 
  // Supabase harus di-init sebelum runApp karena banyak provider
  // yang bergantung pada Supabase.instance.client
  await Supabase.initialize(
    url:       Env.supabaseUrl,
    anonKey:   Env.supabaseAnonKey,
    // authOptions: mengaktifkan session persistence di device
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
 
  runApp(
    ProviderScope(
      overrides: [
        // Override userId dari hardcode ke Supabase auth
        currentUserIdProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          // Kalau offline / belum login, pakai fallback supaya app
          // tetap bisa jalan dalam mode offline-only
          return user?.id ?? 'local-user-offline';
        }),
 
        // Override deviceId dari hardcode ke DB
        currentDeviceIdProvider.overrideWith((ref) {
          // deviceId dibaca async, tapi provider ini sync.
          // Kita return string kosong dulu, SyncNotifier yang
          // akan update setelah deviceId tersedia.
          // Solusi yang lebih proper: pakai FutureProvider untuk deviceId.
          return 'pending-device-id';
        }),
 
        // Override transactionService ke versi yang sync-aware
        transactionServiceProvider.overrideWith((ref) {
          return ref.watch(syncAwareTransactionServiceProvider);
        }),
      ],
      child: const FinanceApp(),
    ),
  );
}
 
class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                      'Finansialku',
      debugShowCheckedModeBanner: false,
      theme:                      _buildTheme(Brightness.light),
      darkTheme:                  _buildTheme(Brightness.dark),
      themeMode:                  ThemeMode.system,
      home:                       const AuthGate(),
    );
  }
 
  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3:    true,
      brightness:      brightness,
      colorSchemeSeed: const Color(0xFF5C6BC0),
      appBarTheme: AppBarTheme(
        centerTitle:            true,
        elevation:              0,
        scrolledUnderElevation: 0,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF1A1A2E)
            : Colors.white,
      ),
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// AuthGate — routing otomatis berdasarkan status login.
// Semua navigasi login/logout terjadi di sini, bukan di screen.
// Kalau auth state berubah (login/logout), widget ini rebuild
// dan routing otomatis ke screen yang tepat.
// ─────────────────────────────────────────────────────────────
 
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
 
    return authAsync.when(
      // Loading awal — cek apakah ada session yang tersimpan
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
 
      error: (_, __) => const LoginScreen(),
 
      data: (authState) {
        // Ada session aktif → masuk ke app
        if (authState.session != null) {
          // Pastikan SyncNotifier sudah aktif
          ref.watch(syncNotifierProvider);
          return const _HomeShell();
        }
 
        // Tidak ada session → tampilkan login
        return const LoginScreen();
      },
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// HomeShell — sama seperti Phase 4, tab keempat diganti Settings
// ─────────────────────────────────────────────────────────────
 
class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override
  State<_HomeShell> createState() => _HomeShellState();
}
 
class _HomeShellState extends State<_HomeShell> {
  int _idx = 0;
 
  static const _screens = [
    TransactionListScreen(),
    HistoryScreen(),
    ReportScreen(),
    BillListScreen(),
    SettingsScreen(),  // Phase 5: ganti placeholder profil
  ];
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex:         _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label:        'Beranda',
          ),
          NavigationDestination(
            icon:         Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label:        'Riwayat',
          ),
          NavigationDestination(
            icon:         Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label:        'Laporan',
          ),
          NavigationDestination(
            icon:         Icon(Icons.receipt_outlined),
            selectedIcon: Icon(Icons.receipt),
            label:        'Split Bill',
          ),
          NavigationDestination(
            icon:         Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label:        'Profil',
          ),
        ],
      ),
    );
  }
}


// ============================================================
//  STRUKTUR FOLDER LENGKAP SETELAH PHASE 2
// ============================================================
//
//  finance_app/
//  ├── lib/
//  │   ├── main.dart                              ← file ini
//  │   │
//  │   ├── core/
//  │   │   ├── database/
//  │   │   │   ├── app_database.dart              ← Phase 1 (+ patch dari dao_patch.dart)
//  │   │   │   └── app_database.g.dart            ← generated, jangan edit
//  │   │   │
//  │   │   └── providers/
//  │   │       └── database_providers.dart        ← Phase 2
//  │   │
//  │   └── features/
//  │       └── transactions/
//  │           ├── services/
//  │           │   └── transaction_service.dart   ← Phase 2
//  │           ├── providers/
//  │           │   └── transaction_providers.dart ← Phase 2
//  │           └── screens/
//  │               ├── transaction_list_screen.dart    ← Phase 2
//  │               ├── add_transaction_screen.dart     ← Phase 2
//  │               └── transaction_detail_screen.dart  ← Phase 2
//  │
//  ├── pubspec.yaml                               ← Phase 1
//  └── supabase/
//      └── migrations/
//          └── 001_initial.sql                    ← Phase 1 (supabase_migration.sql)