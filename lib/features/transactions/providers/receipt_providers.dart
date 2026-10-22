import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/sync/receipt_storage_sync_service.dart';
import '../models/receipt_models.dart';
import '../repositories/receipt_repository.dart';
import '../services/receipt_attachment_service.dart';
import '../services/receipt_picker_service.dart';
import 'transaction_providers.dart';

final receiptPickerServiceProvider = Provider<ReceiptPickerService>(
  (ref) => ReceiptPickerService(),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(database: ref.watch(appDatabaseProvider)),
);

final receiptAttachmentServiceProvider = Provider<ReceiptAttachmentService>(
  (ref) => ReceiptAttachmentService(ref.watch(receiptRepositoryProvider)),
);

final receiptStorageSyncServiceProvider =
    Provider<ReceiptStorageSyncService>((ref) {
  return ReceiptStorageSyncService(
    repository: ref.watch(receiptRepositoryProvider),
    supabase: ref.watch(supabaseClientProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

final receiptForTransactionProvider = FutureProvider.autoDispose
    .family<ReceiptAttachment?, String>((ref, transactionId) {
  ref.watch(syncTickProvider);
  return ref.watch(receiptRepositoryProvider).getForTransaction(transactionId);
});

class ReceiptDraftState {
  final PickedReceiptImage? selectedImage;
  final ReceiptAttachment? existing;
  final bool removeExisting;

  const ReceiptDraftState({
    this.selectedImage,
    this.existing,
    this.removeExisting = false,
  });

  bool get hasChanges => selectedImage != null || removeExisting;
}

class ReceiptDraftNotifier extends Notifier<ReceiptDraftState> {
  bool _recoveryStarted = false;

  @override
  ReceiptDraftState build() => const ReceiptDraftState();

  void select(PickedReceiptImage image) {
    state = ReceiptDraftState(
      selectedImage: image,
      existing: state.existing,
    );
  }

  void keepExisting(ReceiptAttachment? receipt) {
    state = ReceiptDraftState(existing: receipt);
  }

  void remove() {
    state = ReceiptDraftState(
      existing: state.existing,
      removeExisting: state.selectedImage == null && state.existing != null,
    );
  }

  void reset() {
    _recoveryStarted = false;
    state = const ReceiptDraftState();
  }

  Future<void> recoverLostImage() async {
    if (_recoveryStarted) return;
    _recoveryStarted = true;
    try {
      final recovered =
          await ref.read(receiptPickerServiceProvider).retrieveLostImage();
      if (recovered != null) select(recovered);
    } catch (_) {
      // Lost picker data should not prevent creating a transaction.
    }
  }
}

final receiptDraftProvider =
    NotifierProvider<ReceiptDraftNotifier, ReceiptDraftState>(
  ReceiptDraftNotifier.new,
);

final receiptSubmitErrorProvider = StateProvider<String?>((ref) => null);

final receiptDownloadLoadingProvider =
    StateProvider.autoDispose.family<bool, String>(
  (ref, transactionId) => false,
);
