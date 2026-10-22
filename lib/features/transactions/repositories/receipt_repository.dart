import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../models/receipt_models.dart';
import '../services/receipt_picker_service.dart';

class ReceiptRepository {
  final AppDatabase _db;
  final Directory? _supportDirectory;

  ReceiptRepository(
      {required AppDatabase database, Directory? supportDirectory})
      : _db = database,
        _supportDirectory = supportDirectory;

  Future<ReceiptAttachment?> getForTransaction(String transactionId) async {
    final row = await (_db.select(_db.transactionReceipts)
          ..where((receipt) =>
              receipt.transactionId.equals(transactionId) &
              receipt.isDeleted.equals(false)))
        .getSingleOrNull();
    return row == null ? null : _model(row);
  }

  Future<ReceiptAttachment?> getById(String receiptId) async {
    final row = await (_db.select(_db.transactionReceipts)
          ..where((receipt) => receipt.id.equals(receiptId)))
        .getSingleOrNull();
    return row == null ? null : _model(row);
  }

  Future<ReceiptAttachment> stage({
    required String userId,
    required String transactionId,
    required PickedReceiptImage image,
  }) async {
    final id = const Uuid().v4();
    final supportDirectory =
        _supportDirectory ?? await getApplicationSupportDirectory();
    final extension = _safeExtension(image.sourcePath);
    final receiptDirectory = Directory(
      p.join(supportDirectory.path, 'receipts'),
    );
    await receiptDirectory.create(recursive: true);
    final destination = p.join(receiptDirectory.path, '$id.$extension');
    final source = File(image.sourcePath);
    await source.copy(destination);

    final now = DateTime.now();
    final oldFiles = <String>[];
    try {
      await _db.transaction(() async {
        final previous = await (_db.select(_db.transactionReceipts)
              ..where((receipt) =>
                  receipt.transactionId.equals(transactionId) &
                  receipt.isDeleted.equals(false)))
            .get();
        for (final receipt in previous) {
          if (receipt.localPath != null) oldFiles.add(receipt.localPath!);
          await (_db.update(_db.transactionReceipts)
                ..where((value) => value.id.equals(receipt.id)))
              .write(TransactionReceiptsCompanion(
            isDeleted: const Value(true),
            syncState: const Value('pendingDelete'),
            updatedAt: Value(now),
          ));
          await _enqueue(
            receipt.id,
            ReceiptQueueOperation.delete,
            queuedAt: now,
          );
        }

        await _db.into(_db.transactionReceipts).insert(
              TransactionReceiptsCompanion.insert(
                id: id,
                userId: userId,
                transactionId: transactionId,
                localPath: Value(destination),
                mimeType: Value(image.mimeType ?? _mimeType(extension)),
                syncState: ReceiptSyncState.pendingUpload.name,
                isDeleted: const Value(false),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await _enqueue(id, ReceiptQueueOperation.upload, queuedAt: now);
      });
    } catch (_) {
      await _deleteFile(destination);
      rethrow;
    }

    for (final oldPath in oldFiles) {
      if (oldPath != destination) await _deleteFile(oldPath);
    }
    return (await getById(id))!;
  }

  Future<List<ReceiptUploadTask>> getPendingTasks() async {
    final rows = await (_db.select(_db.receiptUploadQueue)
          ..orderBy([(queue) => OrderingTerm.asc(queue.queuedAt)]))
        .get();
    return rows
        .map((row) => ReceiptUploadTask(
              receiptId: row.receiptId,
              operation: ReceiptQueueOperation.values.byName(row.operation),
              retryCount: row.retryCount,
              lastError: row.lastError,
            ))
        .toList();
  }

  Future<void> mergeRemote(Map<String, dynamic> data) async {
    final id = data['id'] as String;
    final queued = await (_db.select(_db.receiptUploadQueue)
          ..where((row) => row.receiptId.equals(id)))
        .getSingleOrNull();
    if (queued != null) return;

    final existing = await (_db.select(_db.transactionReceipts)
          ..where((receipt) => receipt.id.equals(id)))
        .getSingleOrNull();
    final deleted = data['is_deleted'] as bool? ?? false;
    final localPath = deleted ? null : existing?.localPath;
    final values = TransactionReceiptsCompanion(
      id: Value(id),
      userId: Value(data['user_id'] as String),
      transactionId: Value(data['transaction_id'] as String),
      localPath: Value(localPath),
      storagePath: Value(data['storage_path'] as String?),
      mimeType: Value(data['mime_type'] as String?),
      syncState: Value(
        (deleted ? ReceiptSyncState.deleted : ReceiptSyncState.available).name,
      ),
      isDeleted: Value(deleted),
      createdAt: Value(DateTime.parse(data['created_at'] as String).toLocal()),
      updatedAt: Value(DateTime.parse(data['updated_at'] as String).toLocal()),
    );
    if (existing == null) {
      await _db.into(_db.transactionReceipts).insert(values);
    } else {
      await (_db.update(_db.transactionReceipts)
            ..where((receipt) => receipt.id.equals(id)))
          .write(values);
    }
    if (deleted && existing?.localPath != null) {
      await _deleteFile(existing!.localPath!);
    }
  }

  Future<String> cacheDownloaded(String receiptId, Uint8List bytes) async {
    final receipt = await getById(receiptId);
    if (receipt == null || receipt.isDeleted || receipt.storagePath == null) {
      throw StateError('Bukti struk tidak tersedia untuk diunduh.');
    }
    final supportDirectory =
        _supportDirectory ?? await getApplicationSupportDirectory();
    final cacheDirectory = Directory(p.join(supportDirectory.path, 'receipts'));
    await cacheDirectory.create(recursive: true);
    final extension = _safeExtension(receipt.storagePath!);
    final localPath = p.join(cacheDirectory.path, '$receiptId.$extension');
    await File(localPath).writeAsBytes(bytes, flush: true);
    await (_db.update(_db.transactionReceipts)
          ..where((row) => row.id.equals(receiptId)))
        .write(TransactionReceiptsCompanion(
      localPath: Value(localPath),
      syncState: Value(ReceiptSyncState.available.name),
      updatedAt: Value(DateTime.now()),
    ));
    return localPath;
  }

  Future<void> markUploaded(String receiptId, String storagePath) async {
    await _db.transaction(() async {
      await (_db.update(_db.transactionReceipts)
            ..where((receipt) => receipt.id.equals(receiptId)))
          .write(TransactionReceiptsCompanion(
        storagePath: Value(storagePath),
        syncState: Value(ReceiptSyncState.available.name),
        isDeleted: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));
      await (_db.delete(_db.receiptUploadQueue)
            ..where((queue) => queue.receiptId.equals(receiptId)))
          .go();
    });
  }

  Future<void> markForDelete(String receiptId) async {
    await _db.transaction(() async {
      await (_db.update(_db.transactionReceipts)
            ..where((receipt) => receipt.id.equals(receiptId)))
          .write(TransactionReceiptsCompanion(
        isDeleted: const Value(true),
        syncState: Value(ReceiptSyncState.pendingDelete.name),
        updatedAt: Value(DateTime.now()),
      ));
      await _enqueue(receiptId, ReceiptQueueOperation.delete);
    });
  }

  Future<void> markUploadFailed(String receiptId, Object error) async {
    await _markFailed(receiptId, error, ReceiptSyncState.uploadError);
  }

  Future<void> markDeleteFailed(String receiptId, Object error) async {
    await _markFailed(receiptId, error, ReceiptSyncState.pendingDelete);
  }

  Future<void> markDeleted(String receiptId) async {
    final receipt = await getById(receiptId);
    await _db.transaction(() async {
      await (_db.update(_db.transactionReceipts)
            ..where((row) => row.id.equals(receiptId)))
          .write(TransactionReceiptsCompanion(
        localPath: const Value(null),
        syncState: Value(ReceiptSyncState.deleted.name),
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
      await (_db.delete(_db.receiptUploadQueue)
            ..where((queue) => queue.receiptId.equals(receiptId)))
          .go();
    });
    final localPath = receipt?.localPath;
    if (localPath != null) await _deleteFile(localPath);
  }

  Future<void> _markFailed(
    String receiptId,
    Object error,
    ReceiptSyncState state,
  ) async {
    final queue = await (_db.select(_db.receiptUploadQueue)
          ..where((row) => row.receiptId.equals(receiptId)))
        .getSingleOrNull();
    if (queue == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.receiptUploadQueue)
            ..where((row) => row.receiptId.equals(receiptId)))
          .write(ReceiptUploadQueueCompanion(
        retryCount: Value(queue.retryCount + 1),
        lastError: Value(error.toString()),
        queuedAt: Value(DateTime.now()),
      ));
      await (_db.update(_db.transactionReceipts)
            ..where((row) => row.id.equals(receiptId)))
          .write(TransactionReceiptsCompanion(
        syncState: Value(state.name),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<void> _enqueue(
    String receiptId,
    ReceiptQueueOperation operation, {
    DateTime? queuedAt,
  }) async {
    final existing = await (_db.select(_db.receiptUploadQueue)
          ..where((row) => row.receiptId.equals(receiptId)))
        .getSingleOrNull();
    final timestamp = queuedAt ?? DateTime.now();
    if (existing == null) {
      await _db.into(_db.receiptUploadQueue).insert(
            ReceiptUploadQueueCompanion.insert(
              receiptId: receiptId,
              operation: operation.name,
              retryCount: const Value(0),
              lastError: const Value(null),
              queuedAt: Value(timestamp),
            ),
          );
    } else {
      await (_db.update(_db.receiptUploadQueue)
            ..where((row) => row.receiptId.equals(receiptId)))
          .write(ReceiptUploadQueueCompanion(
        operation: Value(operation.name),
        retryCount: const Value(0),
        lastError: const Value(null),
        queuedAt: Value(timestamp),
      ));
    }
  }

  ReceiptAttachment _model(TransactionReceipt row) => ReceiptAttachment(
        id: row.id,
        userId: row.userId,
        transactionId: row.transactionId,
        localPath: row.localPath,
        storagePath: row.storagePath,
        mimeType: row.mimeType,
        syncState: ReceiptSyncState.values.byName(row.syncState),
        isDeleted: row.isDeleted,
      );

  String _safeExtension(String sourcePath) {
    final extension =
        p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension)
        ? extension
        : 'jpg';
  }

  String _mimeType(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        _ => 'image/jpeg',
      };

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A stale local copy must not roll back a saved receipt/queue update.
    }
  }
}
