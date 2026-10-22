import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/sync/sync_service.dart';
import 'package:finance_app/core/sync/sync_aware_budget_service.dart';
import 'package:finance_app/features/budget/models/budget_models.dart';
import 'package:finance_app/features/budget/repositories/budget_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late SupabaseClient supabase;
  late SyncService sync;
  late BudgetRepository repository;
  late SyncAwareBudgetService budgets;
  late List<http.Request> requests;
  late http.Response Function(http.Request) responseFor;
  var online = false;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    requests = [];
    responseFor = (request) => http.Response(
          '',
          201,
          request: request,
          headers: {'content-type': 'application/json'},
        );
    supabase = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return responseFor(request);
      }),
    );
    sync = SyncService(
      db: database,
      supabase: supabase,
      userId: 'user-1',
      deviceId: 'device-1',
      isOnline: () async => online,
    );
    repository = BudgetRepository(database);
    budgets = SyncAwareBudgetService(
      repository: repository,
      syncService: sync,
    );
  });

  tearDown(() async {
    sync.dispose();
    await supabase.dispose();
    await database.close();
  });

  test('stores locally and pushes the budget payload to Supabase', () async {
    await budgets.save(_input());
    final pending = await SyncQueueDao(database).getPending();

    expect(pending, hasLength(1));
    expect(pending.single.targetTable, 'category_budgets');
    final payload = jsonDecode(pending.single.payload) as Map<String, dynamic>;
    expect(payload['user_id'], 'user-1');
    expect(payload['category_id'], 'food');
    expect(payload['limit_amount'], 100000);
    expect(payload['is_deleted'], false);
    expect((await repository.getForMonth('user-1', 2026, 10)), hasLength(1));

    expect(await sync.pushPendingQueue(), 1);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/rest/v1/category_budgets');
    expect(await SyncQueueDao(database).getPending(), isEmpty);
  });

  test('retains a budget queue entry and increments retry after HTTP failure',
      () async {
    await budgets.save(_input());
    responseFor = (request) => http.Response(
          '{"message":"server unavailable"}',
          500,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    expect(await sync.pushPendingQueue(), 0);
    final pending = await SyncQueueDao(database).getPending();

    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 1);
  });

  test('deletes by queuing an upsert tombstone without dropping local state',
      () async {
    await budgets.save(_input());
    final original = (await repository.getForMonth('user-1', 2026, 10)).single;

    await budgets.delete(original.id);

    expect(await repository.getForMonth('user-1', 2026, 10), isEmpty);
    final pending = await SyncQueueDao(database).getPending();
    expect(pending, hasLength(2));
    final tombstone = pending.last;
    expect(tombstone.targetTable, 'category_budgets');
    expect(tombstone.operation, 'update');
    expect((jsonDecode(tombstone.payload) as Map)['is_deleted'], true);
  });

  test('retains existing transaction writes after more than five failures',
      () async {
    await SyncQueueDao(database).enqueue(
      const SyncQueueCompanion(
        targetTable: Value('transactions'),
        recordId: Value('tx-1'),
        operation: Value('insert'),
        payload: Value('{"id":"tx-1","user_id":"user-1"}'),
      ),
    );
    responseFor = (request) => http.Response(
          '{"message":"server unavailable"}',
          500,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    for (var i = 0; i < 6; i++) {
      await sync.pushPendingQueue();
    }
    final pending = await SyncQueueDao(database).getPending();

    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 6);
  });

  test('pulls remote tombstones and hides deleted budgets locally', () async {
    responseFor = (request) => http.Response(
          request.url.path.endsWith('/category_budgets')
              ? jsonEncode([
                  {
                    'id': 'budget-1',
                    'user_id': 'user-1',
                    'category_id': 'food',
                    'year': 2026,
                    'month': 10,
                    'limit_amount': 100000,
                    'notifications_enabled': true,
                    'is_deleted': true,
                    'created_at': '2026-10-01T00:00:00Z',
                    'updated_at': '2026-10-20T00:00:00Z',
                  },
                ])
              : '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    final pulled = await sync.pullDelta();
    final local = await database.select(database.categoryBudgets).get();

    expect(requests.map((request) => request.url.path),
        contains('/rest/v1/category_budgets'));
    expect(pulled, 1);
    expect(local.single.isDeleted, isTrue);
    expect(await repository.getForMonth('user-1', 2026, 10), isEmpty);
  });

  test('does not overwrite an unsynced local budget during pull', () async {
    await budgets.save(_input());
    final local = (await repository.getForMonth('user-1', 2026, 10)).single;
    responseFor = (request) => http.Response(
          request.url.path.endsWith('/category_budgets')
              ? jsonEncode([
                  {
                    'id': local.id,
                    'user_id': 'user-1',
                    'category_id': 'food',
                    'year': 2026,
                    'month': 10,
                    'limit_amount': 1000,
                    'notifications_enabled': true,
                    'is_deleted': false,
                    'created_at': '2026-10-01T00:00:00Z',
                    'updated_at': '2026-10-20T00:00:00Z',
                  },
                ])
              : '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    await sync.pullDelta();

    final afterPull = (await repository.getForMonth('user-1', 2026, 10)).single;
    expect(afterPull.limitAmount, 100000);
  });

  test('includes category budgets in the initial pull', () async {
    online = true;
    responseFor = (request) => http.Response(
          request.url.path.endsWith('/category_budgets')
              ? jsonEncode([
                  {
                    'id': 'budget-2',
                    'user_id': 'user-1',
                    'category_id': 'food',
                    'year': 2026,
                    'month': 10,
                    'limit_amount': 200000,
                    'notifications_enabled': false,
                    'is_deleted': false,
                    'created_at': '2026-10-01T00:00:00Z',
                    'updated_at': '2026-10-20T00:00:00Z',
                  },
                ])
              : '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    final result = await sync.initialPull();

    expect(result.success, isTrue);
    expect(requests.map((request) => request.url.path),
        contains('/rest/v1/category_budgets'));
    expect(await repository.getForMonth('user-1', 2026, 10), hasLength(1));
  });
}

BudgetInput _input() => const BudgetInput(
      userId: 'user-1',
      categoryId: 'food',
      year: 2026,
      month: 10,
      limitAmount: 100000,
      notificationsEnabled: true,
    );
