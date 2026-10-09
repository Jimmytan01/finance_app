import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/transactions/providers/transaction_providers.dart';
import 'package:finance_app/features/transactions/repositories/transaction_repository.dart';
import 'package:finance_app/features/transactions/screens/add_transaction_screen.dart';
import 'package:finance_app/features/transactions/screens/transaction_list_screen.dart';
import 'package:finance_app/features/transactions/services/transaction_service.dart';

void main() {
  testWidgets('transaction list shows initial loading', (tester) async {
    final response = Completer<List<Transaction>>();
    await tester.pumpWidget(_app(
      const TransactionListScreen(),
      [
        monthlyTransactionsProvider.overrideWith((ref) => response.future),
        monthlyCategorySummaryProvider.overrideWith((ref) async => []),
        monthlyTotalProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    response.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('transaction list shows successfully loaded data', (tester) async {
    await tester.pumpWidget(_app(
      const TransactionListScreen(),
      [
        monthlyTransactionsProvider.overrideWith(
          (ref) async => [_transaction(placeName: 'Warung Nusantara')],
        ),
        monthlyCategorySummaryProvider.overrideWith((ref) async => []),
        monthlyTotalProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Warung Nusantara'), findsOneWidget);
  });

  testWidgets('transaction list shows its empty state', (tester) async {
    await tester.pumpWidget(_app(
      const TransactionListScreen(),
      [
        monthlyTransactionsProvider.overrideWith((ref) async => []),
        monthlyCategorySummaryProvider.overrideWith((ref) async => []),
        monthlyTotalProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada transaksi bulan ini'), findsOneWidget);
  });

  testWidgets('transaction list retries after a load error', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_app(
      const TransactionListScreen(),
      [
        monthlyTransactionsProvider.overrideWith((ref) async {
          if (attempts++ == 0) throw StateError('offline');
          return [];
        }),
        monthlyCategorySummaryProvider.overrideWith((ref) async => []),
        monthlyTotalProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gagal memuat transaksi'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Belum ada transaksi bulan ini'), findsOneWidget);
  });

  testWidgets('add transaction retries after categories fail to load',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_app(
      const AddTransactionScreen(),
      [
        categoriesProvider.overrideWith((ref) async {
          if (attempts++ == 0) throw StateError('offline');
          return [];
        }),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gagal memuat kategori'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Item Pengeluaran'), findsOneWidget);
  });

  testWidgets('add transaction shows a field error for an empty item name',
      (tester) async {
    await tester.pumpWidget(_app(
      const AddTransactionScreen(),
      [categoriesProvider.overrideWith((ref) async => [])],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(3), '12000');
    await tester.pump();
    await tester.tap(find.text('Simpan Transaksi'));
    await tester.pump();

    expect(find.text('Nama item wajib diisi.'), findsOneWidget);
  });

  testWidgets('submit displays loading and disables save while pending',
      (tester) async {
    final saveResponse = Completer<void>();
    final service = _TestTransactionService(() => saveResponse.future);
    await tester.pumpWidget(_app(
      const AddTransactionScreen(),
      [
        categoriesProvider.overrideWith((ref) async => []),
        transactionServiceProvider.overrideWith((ref) => service),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(2), 'Kopi');
    await tester.enterText(find.byType(TextFormField).at(3), '12000');
    await tester.pump();
    await tester.tap(find.text('Simpan Transaksi'));
    await tester.tap(find.text('Simpan Transaksi'));
    await tester.pump();

    expect(find.text('Menyimpan...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(service.saveCalls, 1);
    expect(find.text('null'), findsNothing);

    saveResponse.complete();
    await tester.pumpAndSettle();
  });
}

Widget _app(Widget home, List overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(home: home),
    );

Transaction _transaction({String? placeName}) {
  final now = DateTime(2026, 1, 2);
  return Transaction(
    id: 'tx-1',
    userId: 'user-1',
    date: now,
    placeName: placeName,
    totalAmount: 12000,
    createdAt: now,
    updatedAt: now,
  );
}

class _TestTransactionService extends TransactionService {
  _TestTransactionService(this.onSave)
      : super(
            repository: _UnusedTransactionRepository(),
            userId: 'user-1',
            deviceId: 'test');

  final Future<void> Function() onSave;
  int saveCalls = 0;

  @override
  Future<String> saveTransaction(TransactionInput input) async {
    saveCalls++;
    await onSave();
    return 'tx-1';
  }
}

class _UnusedTransactionRepository extends Fake
    implements TransactionRepository {}
