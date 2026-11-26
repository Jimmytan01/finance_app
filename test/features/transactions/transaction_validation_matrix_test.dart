import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/transactions/repositories/transaction_repository.dart';
import 'package:finance_app/features/transactions/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = TransactionService(
    repository: _UnusedTransactionRepository(),
    userId: 'user-1',
    deviceId: 'device-1',
  );

  group('Transaction validation boundary matrix', () {
    for (var index = 0; index < 26; index++) {
      final percent = index * 4;
      test('accepts a $percent% discount', () {
        final item = TransactionItemInput(
          name: 'Item $percent',
          unitPrice: 1000.0 + percent,
          quantity: 1.5,
          discountType: 'percent',
          discountValue: percent.toDouble(),
        );

        expect(
            service.validate(TransactionInput(items: [item])).isValid, isTrue);
        expect(item.subtotal,
            closeTo(item.unitPrice * 1.5 * (1 - percent / 100), 0.001));
      });
    }

    for (var index = 0; index < 24; index++) {
      final discount = index.toDouble();
      test('accepts flat discount Rp $discount below subtotal', () {
        final item = TransactionItemInput(
          name: 'Item Rp $discount',
          unitPrice: 100,
          quantity: 1,
          discountType: 'flat',
          discountValue: discount,
        );

        expect(
            service.validate(TransactionInput(items: [item])).isValid, isTrue);
        expect(item.subtotal, 100 - discount);
      });
    }

    for (var value = 101; value <= 115; value++) {
      final percent = value.toDouble();
      test('rejects a $percent% discount above the limit', () {
        final result = service.validate(TransactionInput(items: [
          TransactionItemInput(
            name: 'Item invalid',
            unitPrice: 100,
            discountType: 'percent',
            discountValue: percent,
          ),
        ]));

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('100%'));
      });
    }

    for (var value = 1; value <= 15; value++) {
      final discount = -value.toDouble();
      test('rejects negative flat discount $discount', () {
        final result = service.validate(TransactionInput(items: [
          TransactionItemInput(
            name: 'Item invalid',
            unitPrice: 100,
            discountValue: discount,
          ),
        ]));

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('negatif'));
      });
    }

    for (var value = 0; value >= -14; value--) {
      final price = value.toDouble();
      test('rejects unit price $price', () {
        final result = service.validate(TransactionInput(items: [
          TransactionItemInput(name: 'Item invalid', unitPrice: price),
        ]));

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('Harga satuan'));
      });
    }

    for (var value = 0; value >= -14; value--) {
      final quantity = value.toDouble();
      test('rejects quantity $quantity', () {
        final result = service.validate(TransactionInput(items: [
          TransactionItemInput(
            name: 'Item invalid',
            unitPrice: 100,
            quantity: quantity,
          ),
        ]));

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('Jumlah'));
      });
    }

    for (var value = 101; value <= 115; value++) {
      final discount = value.toDouble();
      test('rejects flat discount Rp $discount above subtotal', () {
        final result = service.validate(TransactionInput(items: [
          TransactionItemInput(
            name: 'Item invalid',
            unitPrice: 100,
            discountType: 'flat',
            discountValue: discount,
          ),
        ]));

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('melebihi subtotal'));
      });
    }
  });

  group('Transaction currency formatting', () {
    const currencyCases = <(double, String)>[
      (0, 'Rp 0'),
      (1, 'Rp 1'),
      (10, 'Rp 10'),
      (99, 'Rp 99'),
      (100, 'Rp 100'),
      (999, 'Rp 999'),
      (1000, 'Rp 1.000'),
      (1001, 'Rp 1.001'),
      (9999, 'Rp 9.999'),
      (10000, 'Rp 10.000'),
      (999999, 'Rp 999.999'),
      (1000000, 'Rp 1.000.000'),
      (1234567, 'Rp 1.234.567'),
      (123456789, 'Rp 123.456.789'),
      (-1, 'Rp -1'),
      (-10, 'Rp -10'),
      (-100, 'Rp -100'),
      (-999, 'Rp -999'),
      (-1000, 'Rp -1.000'),
      (-1234567, 'Rp -1.234.567'),
      (1.49, 'Rp 1'),
      (1.5, 'Rp 2'),
    ];

    for (final (amount, expected) in currencyCases) {
      test('formats Rp $amount as $expected', () {
        expect(TransactionService.formatCurrency(amount), expected);
      });
    }
  });
}

class _UnusedTransactionRepository implements TransactionRepository {
  @override
  Future<List<Transaction>> getByMonth(String userId, int year, int month) =>
      throw UnimplementedError();

  @override
  Future<List<CategorySummary>> getMonthlyCategorySummary(
          String userId, int year, int month) =>
      throw UnimplementedError();

  @override
  Future<List<Category>> getCategories(String userId) =>
      throw UnimplementedError();

  @override
  Future<List<TransactionItem>> getItemsByTxId(String txId) =>
      throw UnimplementedError();

  @override
  Future<void> insertFull({
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteItemsByTxId(String txId) => throw UnimplementedError();

  @override
  Future<void> updateHeaderAndItems({
    required String txId,
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteTransaction(String txId) => throw UnimplementedError();
}
