import '../models/budget_models.dart';
import '../repositories/budget_repository.dart';

class BudgetService {
  final BudgetRepository _repository;

  const BudgetService(this._repository);

  static String? validate(BudgetInput input) {
    if (input.userId.trim().isEmpty) return 'Pengguna tidak valid';
    if (input.categoryId.trim().isEmpty) return 'Pilih kategori';
    if (input.month < 1 || input.month > 12) return 'Bulan tidak valid';
    if (input.year < 1) return 'Tahun tidak valid';
    if (!input.limitAmount.isFinite || input.limitAmount <= 0) {
      return 'Anggaran harus lebih besar dari nol';
    }
    return null;
  }

  Future<void> save(BudgetInput input) async {
    final error = validate(input);
    if (error != null) throw BudgetValidationException(error);
    await _repository.save(input);
  }
}

class BudgetValidationException implements Exception {
  final String message;
  const BudgetValidationException(this.message);

  @override
  String toString() => message;
}
