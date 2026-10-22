import '../models/receipt_models.dart';
import '../repositories/receipt_repository.dart';
import 'receipt_picker_service.dart';

class ReceiptAttachmentService {
  final ReceiptRepository _repository;

  const ReceiptAttachmentService(this._repository);

  Future<ReceiptAttachment> stageForTransaction({
    required String userId,
    required String transactionId,
    required PickedReceiptImage image,
  }) =>
      _repository.stage(
        userId: userId,
        transactionId: transactionId,
        image: image,
      );
}
