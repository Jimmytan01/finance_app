import 'dart:async';

import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/transactions/providers/transaction_providers.dart';
import 'package:finance_app/features/transactions/screens/transaction_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _demoState = String.fromEnvironment(
  'TRANSACTION_DEMO_STATE',
  defaultValue: 'loading',
);

Future<void> main() async {
  runApp(
    ProviderScope(
      overrides: [
        monthlyTransactionsProvider.overrideWith((ref) async {
          switch (_demoState) {
            case 'loading':
              await Completer<List<Transaction>>().future;
            case 'error':
              throw StateError('Transaction demo error');
          }
          return [];
        }),
        monthlyCategorySummaryProvider.overrideWith((ref) async => []),
        monthlyTotalProvider.overrideWith((ref) async => 0),
      ],
      child: const _TransactionDemoApp(),
    ),
  );
}

class _TransactionDemoApp extends StatelessWidget {
  const _TransactionDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finansialku',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF5C6BC0),
      ),
      home: Scaffold(
        body: const TransactionListScreen(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Riwayat',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Laporan',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_outlined),
              selectedIcon: Icon(Icons.receipt),
              label: 'Tagihan',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}
