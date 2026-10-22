enum ReceiptSyncState {
  pendingUpload,
  available,
  uploadError,
  pendingDelete,
  deleted,
}

enum ReceiptQueueOperation { upload, delete }

class ReceiptAttachment {
  final String id;
  final String userId;
  final String transactionId;
  final String? localPath;
  final String? storagePath;
  final String? mimeType;
  final ReceiptSyncState syncState;
  final bool isDeleted;

  const ReceiptAttachment({
    required this.id,
    required this.userId,
    required this.transactionId,
    required this.localPath,
    required this.storagePath,
    required this.mimeType,
    required this.syncState,
    required this.isDeleted,
  });
}

class ReceiptUploadTask {
  final String receiptId;
  final ReceiptQueueOperation operation;
  final int retryCount;
  final String? lastError;

  const ReceiptUploadTask({
    required this.receiptId,
    required this.operation,
    required this.retryCount,
    required this.lastError,
  });
}
