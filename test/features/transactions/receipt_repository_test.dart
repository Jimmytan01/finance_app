import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/features/transactions/models/receipt_models.dart';
import 'package:finance_app/features/transactions/repositories/receipt_repository.dart';
import 'package:finance_app/features/transactions/services/receipt_attachment_service.dart';
import 'package:finance_app/features/transactions/services/receipt_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late Directory temporaryDirectory;
  late Directory supportDirectory;
  late ReceiptRepository repository;
  late ReceiptAttachmentService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    temporaryDirectory = await Directory.systemTemp.createTemp('receipt-test-');
    supportDirectory = Directory('${temporaryDirectory.path}/app-support');
    repository = ReceiptRepository(
      database: database,
      supportDirectory: supportDirectory,
    );
    service = ReceiptAttachmentService(repository);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('copies picker cache file into durable app support storage', () async {
    final source =
        await _imageFile(temporaryDirectory, 'receipt.jpg', [1, 2, 3]);

    final receipt = await service.stageForTransaction(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(
        sourcePath: source.path,
        mimeType: 'image/jpeg',
      ),
    );

    expect(receipt.localPath, isNot(source.path));
    expect(await File(receipt.localPath!).readAsBytes(), [1, 2, 3]);
    expect(receipt.syncState, ReceiptSyncState.pendingUpload);
    final queue = await repository.getPendingTasks();
    expect(queue.single.operation, ReceiptQueueOperation.upload);
  });

  test('replacing a receipt leaves one active attachment and queues cleanup',
      () async {
    final firstFile = await _imageFile(temporaryDirectory, 'first.png', [1]);
    final first = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: firstFile.path),
    );
    await repository.markUploaded(first.id, 'user-1/tx-1/${first.id}.png');
    final secondFile = await _imageFile(temporaryDirectory, 'second.jpg', [2]);

    final second = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: secondFile.path),
    );

    expect(second.id, isNot(first.id));
    expect((await repository.getForTransaction('tx-1'))?.id, second.id);
    expect(await File(first.localPath!).exists(), isFalse);
    final queue = await repository.getPendingTasks();
    expect(queue.map((task) => task.receiptId).toSet(), {first.id, second.id});
    expect(
      queue.map((task) => task.operation).toSet(),
      {ReceiptQueueOperation.delete, ReceiptQueueOperation.upload},
    );
    expect(await database.select(database.transactionReceipts).get(),
        hasLength(2));
  });

  test('delete becomes a durable queue tombstone until sync completes',
      () async {
    final source = await _imageFile(temporaryDirectory, 'receipt.jpg', [4, 5]);
    final receipt = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: source.path),
    );

    await repository.markForDelete(receipt.id);

    expect(await repository.getForTransaction('tx-1'), isNull);
    expect(await File(receipt.localPath!).exists(), isTrue);
    final task = (await repository.getPendingTasks()).single;
    expect(task.operation, ReceiptQueueOperation.delete);
  });

  test('successful upload clears retry queue and marks receipt available',
      () async {
    final source = await _imageFile(temporaryDirectory, 'receipt.jpg', [4]);
    final receipt = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: source.path),
    );

    await repository.markUploaded(receipt.id, 'user-1/tx-1/${receipt.id}.jpg');

    final saved = (await repository.getForTransaction('tx-1'))!;
    expect(saved.syncState, ReceiptSyncState.available);
    expect(saved.storagePath, 'user-1/tx-1/${receipt.id}.jpg');
    expect(await repository.getPendingTasks(), isEmpty);
  });

  test('failed upload remains retryable and increments retry count', () async {
    final source = await _imageFile(temporaryDirectory, 'receipt.jpg', [4]);
    final receipt = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: source.path),
    );

    for (var i = 0; i < 6; i++) {
      await repository.markUploadFailed(receipt.id, StateError('offline'));
    }

    final task = (await repository.getPendingTasks()).single;
    expect(task.retryCount, 6);
    expect(task.lastError, contains('offline'));
    expect((await repository.getForTransaction('tx-1'))?.syncState,
        ReceiptSyncState.uploadError);
    expect(await File(receipt.localPath!).exists(), isTrue);
  });

  test('missing picker file does not replace the existing receipt', () async {
    final source = await _imageFile(temporaryDirectory, 'receipt.jpg', [1]);
    final existing = await repository.stage(
      userId: 'user-1',
      transactionId: 'tx-1',
      image: PickedReceiptImage(sourcePath: source.path),
    );

    await expectLater(
      repository.stage(
        userId: 'user-1',
        transactionId: 'tx-1',
        image: const PickedReceiptImage(sourcePath: '/does/not/exist.jpg'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repository.getForTransaction('tx-1'))?.id, existing.id);
  });
}

Future<File> _imageFile(
    Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}
