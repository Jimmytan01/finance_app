import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/transactions/models/receipt_models.dart';
import '../../features/transactions/repositories/receipt_repository.dart';

const receiptStorageBucket = 'transaction-receipts';

class ReceiptSyncResult {
  final int uploaded;
  final int deleted;
  final int failed;
  final String? errorMessage;

  const ReceiptSyncResult({
    this.uploaded = 0,
    this.deleted = 0,
    this.failed = 0,
    this.errorMessage,
  });
}

class ReceiptStorageException implements Exception {
  final String message;
  const ReceiptStorageException(this.message);

  @override
  String toString() => message;
}

class ReceiptStorageSyncService {
  final ReceiptRepository _repository;
  final SupabaseClient _supabase;
  final String _userId;
  Future<ReceiptSyncResult>? _activeSync;
  RealtimeChannel? _channel;

  ReceiptStorageSyncService({
    required ReceiptRepository repository,
    required SupabaseClient supabase,
    required String userId,
  })  : _repository = repository,
        _supabase = supabase,
        _userId = userId;

  void subscribeRealtime({required void Function() onChanged}) {
    _channel = _supabase
        .channel('transaction-receipts-$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transaction_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId,
          ),
          callback: (_) {
            unawaited(_pullRemoteMetadata().then((_) {
              try {
                onChanged();
              } catch (_) {
                // Ignore refresh callbacks after a provider has been disposed.
              }
            }).catchError((Object _) {}));
          },
        )
        .subscribe();
  }

  void unsubscribeRealtime() {
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    unawaited(_supabase.removeChannel(channel));
  }

  Future<ReceiptSyncResult> syncPending() {
    final active = _activeSync;
    if (active != null) return active;
    late final Future<ReceiptSyncResult> pending;
    pending = _syncPending()
        .catchError((Object error) => ReceiptSyncResult(
              failed: 1,
              errorMessage: error.toString(),
            ))
        .whenComplete(() {
      if (identical(_activeSync, pending)) _activeSync = null;
    });
    _activeSync = pending;
    return pending;
  }

  Future<String> downloadToCache(String receiptId) async {
    final receipt = await _repository.getById(receiptId);
    if (receipt == null || receipt.isDeleted || receipt.storagePath == null) {
      throw const ReceiptStorageException('Bukti struk tidak tersedia.');
    }
    try {
      final bytes = await _supabase.storage
          .from(receiptStorageBucket)
          .download(receipt.storagePath!);
      return await _repository.cacheDownloaded(receiptId, bytes);
    } catch (error) {
      throw ReceiptStorageException('Gagal mengunduh bukti struk: $error');
    }
  }

  Future<ReceiptSyncResult> _syncPending() async {
    var uploaded = 0;
    var deleted = 0;
    var failed = 0;
    final errors = <String>[];
    for (final task in await _repository.getPendingTasks()) {
      try {
        switch (task.operation) {
          case ReceiptQueueOperation.upload:
            await _upload(task.receiptId);
            uploaded++;
          case ReceiptQueueOperation.delete:
            await _delete(task.receiptId);
            deleted++;
        }
      } catch (error) {
        failed++;
        errors.add(error.toString());
        if (task.operation == ReceiptQueueOperation.upload) {
          await _repository.markUploadFailed(task.receiptId, error);
        } else {
          await _repository.markDeleteFailed(task.receiptId, error);
        }
      }
    }

    try {
      await _pullRemoteMetadata();
    } catch (error) {
      failed++;
      errors.add(error.toString());
    }
    return ReceiptSyncResult(
      uploaded: uploaded,
      deleted: deleted,
      failed: failed,
      errorMessage: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  Future<void> _upload(String receiptId) async {
    final receipt = await _repository.getById(receiptId);
    final localPath = receipt?.localPath;
    if (receipt == null || receipt.isDeleted || localPath == null) {
      throw const ReceiptStorageException('File struk lokal tidak ditemukan.');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw const ReceiptStorageException('File struk lokal sudah tidak ada.');
    }
    final storagePath = receipt.storagePath ?? _storagePath(receipt);
    final bytes = await file.readAsBytes();
    await _supabase.storage.from(receiptStorageBucket).uploadBinary(
          storagePath,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: receipt.mimeType ?? 'image/jpeg',
            upsert: true,
          ),
        );
    await _upsertMetadata(
      receipt: receipt,
      storagePath: storagePath,
      isDeleted: false,
    );
    await _repository.markUploaded(receiptId, storagePath);
  }

  Future<void> _delete(String receiptId) async {
    final receipt = await _repository.getById(receiptId);
    if (receipt == null) {
      throw const ReceiptStorageException(
          'Metadata struk lokal tidak ditemukan.');
    }
    final storagePath = receipt.storagePath;
    if (storagePath != null) {
      await _supabase.storage.from(receiptStorageBucket).remove([storagePath]);
    }
    await _upsertMetadata(
      receipt: receipt,
      storagePath: storagePath,
      isDeleted: true,
    );
    await _repository.markDeleted(receiptId);
  }

  Future<void> _upsertMetadata({
    required ReceiptAttachment receipt,
    required String? storagePath,
    required bool isDeleted,
  }) async {
    await _supabase.from('transaction_receipts').upsert(
      {
        'id': receipt.id,
        'user_id': receipt.userId,
        'transaction_id': receipt.transactionId,
        'storage_path': storagePath,
        'mime_type': receipt.mimeType,
        'is_deleted': isDeleted,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'id',
    );
  }

  Future<void> _pullRemoteMetadata() async {
    final remote = await _supabase
        .from('transaction_receipts')
        .select()
        .eq('user_id', _userId);
    for (final row in remote) {
      await _repository.mergeRemote(Map<String, dynamic>.from(row));
    }
  }

  String _storagePath(ReceiptAttachment receipt) {
    final localPath = receipt.localPath!;
    final extension =
        p.extension(localPath).replaceFirst('.', '').toLowerCase();
    final safeExtension =
        const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension)
            ? extension
            : 'jpg';
    return '${receipt.userId}/${receipt.transactionId}/${receipt.id}.$safeExtension';
  }
}
