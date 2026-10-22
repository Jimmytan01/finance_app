import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v2 budgets survive migration to receipt schema v3', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE category_budgets (
              id TEXT NOT NULL PRIMARY KEY,
              user_id TEXT NOT NULL,
              category_id TEXT NOT NULL,
              year INTEGER NOT NULL,
              month INTEGER NOT NULL,
              limit_amount REAL NOT NULL,
              notifications_enabled INTEGER NOT NULL DEFAULT 1,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          sqlite.execute('PRAGMA user_version = 2');
          sqlite.execute('''
            INSERT INTO category_budgets
              (id, user_id, category_id, year, month, limit_amount,
               notifications_enabled, is_deleted, created_at, updated_at)
            VALUES ('budget-1', 'user-1', 'food', 2026, 10, 100000,
                    1, 0, 1791590400000, 1791590400000)
          ''');
        },
      ),
    );
    addTearDown(database.close);

    final budget = await database.select(database.categoryBudgets).getSingle();
    final receipts = await database.select(database.transactionReceipts).get();
    final queue = await database.select(database.receiptUploadQueue).get();

    expect(budget.id, 'budget-1');
    expect(receipts, isEmpty);
    expect(queue, isEmpty);
  });
}
