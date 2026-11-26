import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late SupabaseClient supabase;
  late SyncService sync;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    supabase = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async => http.Response(
            jsonEncode(<Object>[]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          )),
    );
    sync = SyncService(
      db: database,
      supabase: supabase,
      userId: 'user-1',
      deviceId: 'device-1',
      isOnline: () async => true,
    );
  });

  tearDown(() async {
    sync.dispose();
    await supabase.dispose();
    await database.close();
  });

  test('initial pull only clears the signed-in user local data', () async {
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: const Value('category-user-1'),
            userId: 'user-1',
            name: 'Lama',
          ),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: const Value('category-user-2'),
            userId: 'user-2',
            name: 'Pribadi',
          ),
        );

    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: const Value('tx-user-1'),
            userId: 'user-1',
            date: DateTime(2026, 1, 1),
            totalAmount: const Value(100),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: const Value('tx-user-2'),
            userId: 'user-2',
            date: DateTime(2026, 1, 1),
            totalAmount: const Value(200),
          ),
        );
    await database.into(database.transactionItems).insert(
          TransactionItemsCompanion.insert(
            id: Value('item-user-2'),
            transactionId: 'tx-user-2',
            name: 'Makan',
            subtotal: Value(200),
          ),
        );

    await database.into(database.billSessions).insert(
          BillSessionsCompanion.insert(
            id: const Value('bill-user-2'),
            userId: 'user-2',
            title: 'Makan bersama',
            date: DateTime(2026, 1, 1),
          ),
        );
    await database.into(database.billParticipants).insert(
          BillParticipantsCompanion.insert(
            id: Value('participant-user-2'),
            billSessionId: 'bill-user-2',
            name: 'Teman',
          ),
        );
    await database.into(database.billItems).insert(
          BillItemsCompanion.insert(
            id: Value('bill-item-user-2'),
            billSessionId: 'bill-user-2',
            name: 'Nasi goreng',
            subtotal: Value(200),
          ),
        );
    await database.into(database.billItemParticipants).insert(
          BillItemParticipantsCompanion.insert(
            id: Value('bill-split-user-2'),
            billItemId: 'bill-item-user-2',
            participantId: 'participant-user-2',
            shareAmount: Value(200),
          ),
        );

    final result = await sync.initialPull();

    expect(result.success, isTrue);
    expect(
      (await database.select(database.categories).get())
          .map((row) => row.userId),
      ['user-2'],
    );
    expect(
      (await database.select(database.transactions).get()).map((row) => row.id),
      ['tx-user-2'],
    );
    expect(
      (await database.select(database.transactionItems).get())
          .map((row) => row.id),
      ['item-user-2'],
    );
    expect(
      (await database.select(database.billSessions).get()).map((row) => row.id),
      ['bill-user-2'],
    );
    expect(
        await database.select(database.billParticipants).get(), hasLength(1));
    expect(await database.select(database.billItems).get(), hasLength(1));
    expect(await database.select(database.billItemParticipants).get(),
        hasLength(1));
  });
}
