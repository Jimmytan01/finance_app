import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v1 transaction data survives upgrade to schema v2', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE transactions (
              id TEXT NOT NULL PRIMARY KEY,
              user_id TEXT NOT NULL,
              date INTEGER NOT NULL,
              place_name TEXT,
              notes TEXT,
              total_amount REAL NOT NULL DEFAULT 0.0,
              device_id TEXT,
              synced_at INTEGER,
              created_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          sqlite.execute('PRAGMA user_version = 1');
          sqlite.execute('''
            INSERT INTO transactions
              (id, user_id, date, total_amount, created_at, updated_at)
            VALUES
              ('legacy-tx', 'user-1', 1791590400000, 25000,
               1791590400000, 1791590400000)
          ''');
        },
      ),
    );
    addTearDown(database.close);

    final saved = await database.select(database.transactions).getSingle();
    final budgets = await database.select(database.categoryBudgets).get();

    expect(saved.id, 'legacy-tx');
    expect(saved.userId, 'user-1');
    expect(saved.totalAmount, 25000);
    expect(budgets, isEmpty);
  });
}
