import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/sync/receipt_storage_sync_service.dart';
import 'package:finance_app/features/transactions/models/receipt_models.dart';
import 'package:finance_app/features/transactions/repositories/receipt_repository.dart';
import 'package:finance_app/features/transactions/services/receipt_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late Directory temporaryDirectory;
  late Directory supportDirectory;
  late ReceiptRepository repository;
  late SupabaseClient supabase;
  late ReceiptStorageSyncService sync;
  late List<http.Request> requests;
  late http.Response Function(http.Request) responseFor;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    temporaryDirectory = await Directory.systemTemp.createTemp('receipt-sync-');
    supportDirectory = Directory('${temporaryDirectory.path}/support');
    repository = ReceiptRepository(
      database: database,
      supportDirectory: supportDirectory,
    );
    requests = [];
    responseFor = _successResponse;
    supabase = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return responseFor(request);
      }),
    );
    sync = ReceiptStorageSyncService(
      repository: repository,
      supabase: supabase,
      userId: 'user-1',
    );
  });

  tearDown(() async {
    await supabase.dispose();
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('uploads private object before metadata and marks receipt available',
      () async {
    final receipt = await _stage(temporaryDirectory, repository);

    final result = await sync.syncPending();

    expect(result.uploaded, 1);
    expect(result.failed, 0);
    final uploaded = requests.firstWhere((request) =>
        request.method == 'POST' &&
        request.url.path.startsWith('/storage/v1/object/'));
    final metadata = requests.firstWhere((request) =>
        request.method == 'POST' &&
        request.url.path == '/rest/v1/transaction_receipts');
    expect(requests.indexOf(uploaded), lessThan(requests.indexOf(metadata)));
    expect(uploaded.url.path, contains('/transaction-receipts/user-1/tx-1/'));
    expect(uploaded.url.path, isNot(contains('/object/public/')));
    final metadataBody = jsonDecode(metadata.body) as Map<String, dynamic>;
    expect(metadataBody['local_path'], isNull);
    expect(metadataBody['storage_path'], contains('${receipt.id}.jpg'));
    expect(metadataBody['is_deleted'], false);
    expect((await repository.getForTransaction('tx-1'))?.syncState,
        ReceiptSyncState.available);
    expect(await repository.getPendingTasks(), isEmpty);
  });

  test('retains upload queue and file on Storage HTTP failure', () async {
    final receipt = await _stage(temporaryDirectory, repository);
    responseFor = (request) {
      if (request.url.path.startsWith('/storage/v1/object/')) {
        return http.Response('{"message":"storage unavailable"}', 503,
            request: request, headers: {'content-type': 'application/json'});
      }
      return _successResponse(request);
    };

    final result = await sync.syncPending();

    expect(result.failed, 1);
    final queue = (await repository.getPendingTasks()).single;
    expect(queue.retryCount, 1);
    expect(queue.operation, ReceiptQueueOperation.upload);
    expect(await File(receipt.localPath!).exists(), isTrue);
    expect(
      requests.where((request) =>
          request.method == 'POST' &&
          request.url.path == '/rest/v1/transaction_receipts'),
      isEmpty,
    );
  });

  test('keeps upload retryable if metadata upsert fails after object upload',
      () async {
    final receipt = await _stage(temporaryDirectory, repository);
    responseFor = (request) {
      if (request.url.path == '/rest/v1/transaction_receipts' &&
          request.method == 'POST') {
        return http.Response('{"message":"metadata unavailable"}', 500,
            request: request, headers: {'content-type': 'application/json'});
      }
      return _successResponse(request);
    };

    final result = await sync.syncPending();

    expect(result.failed, 1);
    expect(
        requests.any(
            (request) => request.url.path.startsWith('/storage/v1/object/')),
        isTrue);
    expect((await repository.getPendingTasks()).single.retryCount, 1);
    expect(await File(receipt.localPath!).exists(), isTrue);
    expect((await repository.getForTransaction('tx-1'))?.syncState,
        ReceiptSyncState.uploadError);
  });

  test('delete failure keeps the tombstone and queue for retry', () async {
    final receipt = await _stage(temporaryDirectory, repository);
    await repository.markUploaded(receipt.id, 'user-1/tx-1/${receipt.id}.jpg');
    await repository.markForDelete(receipt.id);
    responseFor = (request) {
      if (request.method == 'DELETE' &&
          request.url.path == '/storage/v1/object/transaction-receipts') {
        return http.Response('{"message":"storage unavailable"}', 503,
            request: request, headers: {'content-type': 'application/json'});
      }
      return _successResponse(request);
    };

    final result = await sync.syncPending();

    expect(result.failed, 1);
    final queue = (await repository.getPendingTasks()).single;
    expect(queue.operation, ReceiptQueueOperation.delete);
    expect(queue.retryCount, 1);
    expect(await repository.getForTransaction('tx-1'), isNull);
    expect(await File(receipt.localPath!).exists(), isTrue);
  });

  test('removes object before tombstone and local cleanup', () async {
    final receipt = await _stage(temporaryDirectory, repository);
    final storagePath = 'user-1/tx-1/${receipt.id}.jpg';
    await repository.markUploaded(receipt.id, storagePath);
    await repository.markForDelete(receipt.id);

    final result = await sync.syncPending();

    expect(result.deleted, 1);
    final removed = requests.firstWhere((request) =>
        request.method == 'DELETE' &&
        request.url.path == '/storage/v1/object/transaction-receipts');
    final metadata = requests.firstWhere((request) =>
        request.method == 'POST' &&
        request.url.path == '/rest/v1/transaction_receipts');
    expect(requests.indexOf(removed), lessThan(requests.indexOf(metadata)));
    expect((jsonDecode(metadata.body) as Map)['is_deleted'], true);
    expect(await File(receipt.localPath!).exists(), isFalse);
    expect(await repository.getPendingTasks(), isEmpty);
    expect((await repository.getById(receipt.id))?.syncState,
        ReceiptSyncState.deleted);
  });

  test('pulls remote receipt metadata without caching a public URL', () async {
    final now = DateTime.utc(2026, 10, 22).toIso8601String();
    responseFor = (request) {
      if (request.method == 'GET' &&
          request.url.path == '/rest/v1/transaction_receipts') {
        return http.Response(
          jsonEncode([
            {
              'id': 'remote-receipt',
              'user_id': 'user-1',
              'transaction_id': 'tx-remote',
              'storage_path': 'user-1/tx-remote/remote-receipt.jpg',
              'mime_type': 'image/jpeg',
              'is_deleted': false,
              'created_at': now,
              'updated_at': now,
            }
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return _successResponse(request);
    };

    await sync.syncPending();

    final receipt = await repository.getForTransaction('tx-remote');
    expect(receipt?.storagePath, 'user-1/tx-remote/remote-receipt.jpg');
    expect(receipt?.localPath, isNull);
    expect(receipt?.syncState, ReceiptSyncState.available);
    expect(
        requests
            .every((request) => !request.url.path.contains('/object/public/')),
        isTrue);
  });

  test('download failure surfaces an error and stores no local file', () async {
    final now = DateTime.utc(2026, 10, 22).toIso8601String();
    await repository.mergeRemote({
      'id': 'remote-receipt',
      'user_id': 'user-1',
      'transaction_id': 'tx-remote',
      'storage_path': 'user-1/tx-remote/remote-receipt.jpg',
      'mime_type': 'image/jpeg',
      'is_deleted': false,
      'created_at': now,
      'updated_at': now,
    });
    responseFor = (request) => http.Response(
          '{"message":"missing"}',
          404,
          request: request,
          headers: {'content-type': 'application/json'},
        );

    await expectLater(
      sync.downloadToCache('remote-receipt'),
      throwsA(isA<ReceiptStorageException>()),
    );
    expect((await repository.getById('remote-receipt'))?.localPath, isNull);
  });

  test('downloads private object to durable local cache', () async {
    final now = DateTime.utc(2026, 10, 22).toIso8601String();
    await repository.mergeRemote({
      'id': 'remote-receipt',
      'user_id': 'user-1',
      'transaction_id': 'tx-remote',
      'storage_path': 'user-1/tx-remote/remote-receipt.jpg',
      'mime_type': 'image/jpeg',
      'is_deleted': false,
      'created_at': now,
      'updated_at': now,
    });

    final localPath = await sync.downloadToCache('remote-receipt');

    expect(await File(localPath).readAsBytes(), [1, 2, 3]);
    expect((await repository.getById('remote-receipt'))?.localPath, localPath);
    expect(requests.single.url.path,
        '/storage/v1/object/transaction-receipts/user-1/tx-remote/remote-receipt.jpg');
    expect(requests.single.url.path, isNot(contains('/object/public/')));
  });
}

Future<ReceiptAttachment> _stage(
  Directory directory,
  ReceiptRepository repository,
) async {
  final file = File('${directory.path}/picked.jpg');
  await file.writeAsBytes([1, 2, 3, 4]);
  return repository.stage(
    userId: 'user-1',
    transactionId: 'tx-1',
    image: PickedReceiptImage(sourcePath: file.path, mimeType: 'image/jpeg'),
  );
}

http.Response _successResponse(http.Request request) {
  if (request.url.path.startsWith('/storage/v1/object/') &&
      request.method == 'POST') {
    return http.Response(
      jsonEncode({'Key': request.url.path.split('/').skip(4).join('/')}),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
  if (request.url.path.startsWith('/storage/v1/object/') &&
      request.method == 'DELETE') {
    return http.Response('[]', 200,
        request: request, headers: {'content-type': 'application/json'});
  }
  if (request.url.path.startsWith('/storage/v1/object/') &&
      request.method == 'GET') {
    return http.Response.bytes([1, 2, 3], 200,
        request: request, headers: {'content-type': 'image/jpeg'});
  }
  if (request.url.path == '/rest/v1/transaction_receipts' &&
      request.method == 'GET') {
    return http.Response('[]', 200,
        request: request, headers: {'content-type': 'application/json'});
  }
  if (request.url.path == '/rest/v1/transaction_receipts' &&
      request.method == 'POST') {
    return http.Response('', 201, request: request);
  }
  return http.Response('', 200, request: request);
}
