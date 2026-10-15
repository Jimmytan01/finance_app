import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/sync/sync_service.dart';
import 'package:finance_app/features/transactions/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('TransactionInput model', () {
    test('accepts a valid transaction', () {
      final model = TransactionInput(
        items: [
          TransactionItemInput(name: 'Kopi', unitPrice: 12000, quantity: 1),
        ],
      );

      expect(model.isValid, isTrue);
      expect(model.total, 12000);
    });

    test('rejects an invalid transaction', () {
      final model = TransactionInput(
        items: [
          TransactionItemInput(name: ' ', unitPrice: 12000, quantity: 1),
        ],
      );

      expect(model.isValid, isFalse);
    });
  });

  group('SyncService API', () {
    late AppDatabase database;
    late SupabaseClient supabase;
    late SyncService syncService;
    late List<http.Request> requests;
    late http.Response Function(http.Request) responseFor;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      requests = [];
      responseFor = (request) => http.Response(
            '',
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
      final httpClient = MockClient((request) async {
        requests.add(request);
        return responseFor(request);
      });
      supabase = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: httpClient,
      );
      syncService = SyncService(
        db: database,
        supabase: supabase,
        userId: 'user-1',
        deviceId: 'device-1',
      );
    });

    tearDown(() async {
      syncService.dispose();
      await supabase.dispose();
      await database.close();
    });

    test('pushes a queued transaction to the API successfully', () async {
      await _enqueueTransaction(database);

      final pushed = await syncService.pushPendingQueue();

      expect(pushed, 1);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/transactions');
      expect(jsonDecode(requests.single.body), {
        'id': 'tx-1',
        'user_id': 'user-1',
        'total_amount': 12000,
      });
      expect(await SyncQueueDao(database).getPending(), isEmpty);
    });

    test('returns zero when the API has no transactions', () async {
      responseFor = (request) => http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );

      final pulled = await syncService.pullDelta();

      expect(pulled, 0);
      expect(
        requests.map((request) => request.url.path),
        contains('/rest/v1/transactions'),
      );
    });

    test('keeps a queued transaction for retry after HTTP failure', () async {
      await _enqueueTransaction(database);
      responseFor = (request) => http.Response(
            '{"message":"server unavailable","code":"500"}',
            500,
            request: request,
            headers: {'content-type': 'application/json'},
          );

      final pushed = await syncService.pushPendingQueue();
      final pending = await SyncQueueDao(database).getPending();

      expect(pushed, 0);
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 1);
    });

    test('ignores malformed JSON returned by the API', () async {
      responseFor = (request) => http.Response(
            request.url.path.endsWith('/categories') ? '{broken' : '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );

      final pulled = await syncService.pullDelta();

      expect(pulled, 0);
      expect(requests, isNotEmpty);
    });
  });
}

Future<void> _enqueueTransaction(AppDatabase database) {
  return SyncQueueDao(database).enqueue(
    SyncQueueCompanion(
      targetTable: const Value('transactions'),
      recordId: const Value('tx-1'),
      operation: const Value('insert'),
      payload: const Value(
        '{"id":"tx-1","user_id":"user-1","total_amount":12000}',
      ),
      queuedAt: Value(DateTime.utc(2026, 1, 1)),
      retryCount: const Value(0),
    ),
  );
}
