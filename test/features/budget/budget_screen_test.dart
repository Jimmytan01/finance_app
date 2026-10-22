import 'dart:async';

import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/providers/budget_providers.dart';
import 'package:finance_app/features/budget/screens/budget_screen.dart';
import 'package:finance_app/features/transactions/providers/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading while budgets are being read', (tester) async {
    final response = Completer<List<BudgetSummary>>();
    await tester.pumpWidget(_app([
      budgetListProvider
          .overrideWith(() => _BudgetNotifier(() => response.future)),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the empty budget state', (tester) async {
    await tester.pumpWidget(_app([
      budgetListProvider.overrideWith(() => _BudgetNotifier(() async => [])),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada anggaran untuk bulan ini'), findsOneWidget);
  });

  testWidgets('shows loaded budget progress and in-app threshold alert',
      (tester) async {
    await tester.pumpWidget(_app([
      budgetListProvider
          .overrideWith(() => _BudgetNotifier(() async => [_budget()])),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Makanan'), findsWidgets);
    expect(find.text('Anggaran hampir habis'), findsOneWidget);
    expect(find.text('80% terpakai'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error and retries loading budgets', (tester) async {
    final notifier = _BudgetNotifier(() async => []);
    notifier.failFirstBuild = true;
    await tester.pumpWidget(_app([
      budgetListProvider.overrideWith(() => notifier),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Gagal memuat anggaran'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(notifier.buildCalls, 2);
    expect(find.text('Belum ada anggaran untuk bulan ini'), findsOneWidget);
  });

  testWidgets('validates a positive budget amount', (tester) async {
    await tester.pumpWidget(_app([
      budgetListProvider.overrideWith(() => _BudgetNotifier(() async => [])),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simpan Anggaran'));
    await tester.pump();

    expect(find.text('Anggaran harus lebih besar dari nol'), findsOneWidget);
  });

  testWidgets('shows submit loading and blocks double tap', (tester) async {
    final notifier = _BudgetNotifier(() async => []);
    notifier.saveResponse = Completer<bool>();
    await tester.pumpWidget(_app([
      budgetListProvider.overrideWith(() => notifier),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount')), '100000');
    await tester.tap(find.text('Simpan Anggaran'));
    await tester.pump();

    expect(notifier.saveCalls, 1);
    expect(find.text('Menyimpan...'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    notifier.saveResponse!.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps in-app alert visible when system notifications are off',
      (tester) async {
    await tester.pumpWidget(_app([
      budgetListProvider.overrideWith(() =>
          _BudgetNotifier(() async => [_budget(notificationsEnabled: false)])),
      categoriesProvider.overrideWith((ref) async => [_category()]),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Anggaran hampir habis'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}

Widget _app(List overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: const MaterialApp(home: BudgetScreen()),
    );

Category _category() => Category(
      id: 'food',
      userId: 'user-1',
      name: 'Makanan',
      icon: 'restaurant',
      color: '#EF9F27',
      isDefault: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

BudgetSummary _budget({bool notificationsEnabled = true}) => BudgetSummary(
      id: 'budget-1',
      userId: 'user-1',
      categoryId: 'food',
      categoryName: 'Makanan',
      year: 2026,
      month: 10,
      limitAmount: 100000,
      spentAmount: 80000,
      notificationsEnabled: notificationsEnabled,
      progress: BudgetProgress.fromAmounts(
        limitAmount: 100000,
        spentAmount: 80000,
      ),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _BudgetNotifier extends BudgetListNotifier {
  _BudgetNotifier(this.loader);

  final Future<List<BudgetSummary>> Function() loader;
  int buildCalls = 0;
  bool failFirstBuild = false;
  Completer<bool>? saveResponse;
  int saveCalls = 0;

  @override
  Future<List<BudgetSummary>> build() async {
    buildCalls++;
    if (failFirstBuild && buildCalls == 1) throw StateError('offline');
    return loader();
  }

  @override
  Future<bool> save(BudgetInput input) async {
    if (state.isLoading) return false;
    saveCalls++;
    final previous = state;
    state =
        const AsyncLoading<List<BudgetSummary>>().copyWithPrevious(previous);
    final granted = await (saveResponse?.future ?? Future.value(true));
    state = AsyncData(await loader());
    return granted;
  }
}
