// lib/features/transactions/services/transaction_service.dart
//
// Business logic: hitung subtotal/total, validasi, dan insert ke DB.
// Layer ini tidak tahu soal UI — hanya menerima data dan memanggil DAO.

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';

const _uuid = Uuid();

// ── Model untuk satu baris item di form ────────────────────
class TransactionItemInput {
  final String id;
  String  name;
  String? categoryId;
  double  unitPrice;
  double  quantity;
  double  discountValue;   // nilainya — bisa Rp atau %
  String  discountType;    // 'flat' atau 'percent'
  String? notes;
 
  TransactionItemInput({
    String? id,
    this.name          = '',
    this.categoryId,
    this.unitPrice     = 0,
    this.quantity      = 1,
    this.discountValue = 0,
    this.discountType  = 'flat',
    this.notes,
  }) : id = id ?? _uuid.v4();
 
  // Hitung diskon dalam Rp berdasarkan tipe
  double get discountAmount {
    if (discountValue <= 0) return 0;
    if (discountType == 'percent') {
      return (unitPrice * quantity) * (discountValue / 100);
    }
    return discountValue;
  }
 
  double get subtotal {
    final gross = unitPrice * quantity;
    final disc  = discountAmount.clamp(0, gross);
    return gross - disc;
  }
 
  TransactionItemInput copyWith({
    String?  name,
    String?  categoryId,
    bool     clearCategory = false,
    double?  unitPrice,
    double?  quantity,
    double?  discountValue,
    String?  discountType,
    String?  notes,
  }) =>
      TransactionItemInput(
        id:            id,
        name:          name          ?? this.name,
        categoryId:    clearCategory ? null : (categoryId ?? this.categoryId),
        unitPrice:     unitPrice     ?? this.unitPrice,
        quantity:      quantity      ?? this.quantity,
        discountValue: discountValue ?? this.discountValue,
        discountType:  discountType  ?? this.discountType,
        notes:         notes         ?? this.notes,
      );
}
 
// ── Model header transaksi ────────────────────────────────
class TransactionInput {
  DateTime date;
  String?  placeName;
  String?  notes;
  List<TransactionItemInput> items;
 
  TransactionInput({
    DateTime? date,
    this.placeName,
    this.notes,
    List<TransactionItemInput>? items,
  })  : date  = date ?? DateTime.now(),
        items = items ?? [TransactionItemInput()];
 
  double get total => items.fold(0, (sum, i) => sum + i.subtotal);
 
  bool get isValid =>
      items.isNotEmpty &&
      items.every((i) => i.name.trim().isNotEmpty && i.unitPrice > 0);
}
 
class ValidationResult {
  final bool    isValid;
  final String? errorMessage;
  const ValidationResult.ok()         : isValid = true,  errorMessage = null;
  const ValidationResult.fail(this.errorMessage) : isValid = false;
}
 
// ── Service ───────────────────────────────────────────────
class TransactionService {
  final TransactionDao _dao;
  final String         _userId;
  final String         _deviceId;
 
  // Expose deviceId supaya bisa diakses dari SyncAwareTransactionService
  String get deviceId => _deviceId;
  String get userId   => _userId;
 
  TransactionService({
    required TransactionDao dao,
    required String         userId,
    required String         deviceId,
  })  : _dao     = dao,
        _userId  = userId,
        _deviceId = deviceId;
 
  ValidationResult validate(TransactionInput input) {
    if (input.items.isEmpty) {
      return const ValidationResult.fail('Tambahkan minimal satu item.');
    }
    for (final item in input.items) {
      if (item.name.trim().isEmpty) {
        return const ValidationResult.fail('Nama item tidak boleh kosong.');
      }
      if (item.unitPrice <= 0) {
        return const ValidationResult.fail('Harga satuan harus lebih dari 0.');
      }
      if (item.quantity <= 0) {
        return const ValidationResult.fail('Jumlah harus lebih dari 0.');
      }
      if (item.discountValue < 0) {
        return const ValidationResult.fail('Diskon tidak boleh negatif.');
      }
      if (item.discountType == 'percent' && item.discountValue > 100) {
        return const ValidationResult.fail(
            'Diskon persen tidak boleh lebih dari 100%.');
      }
      if (item.discountAmount > item.unitPrice * item.quantity) {
        return ValidationResult.fail(
            'Diskon item "${item.name}" melebihi subtotal-nya.');
      }
    }
    return const ValidationResult.ok();
  }
 
  Future<String> saveTransaction(TransactionInput input) async {
    final validation = validate(input);
    if (!validation.isValid) throw Exception(validation.errorMessage);
 
    final txId = _uuid.v4();
 
    final header = TransactionsCompanion(
      id:          Value(txId),
      userId:      Value(_userId),
      date:        Value(input.date),
      placeName:   Value(input.placeName),
      notes:       Value(input.notes),
      totalAmount: Value(input.total),
      deviceId:    Value(_deviceId),
      createdAt:   Value(DateTime.now()),
      updatedAt:   Value(DateTime.now()),
    );
 
    final items = input.items.map((i) => TransactionItemsCompanion(
      id:             Value(_uuid.v4()),
      transactionId:  Value(txId),
      categoryId:     Value(i.categoryId),
      name:           Value(i.name.trim()),
      unitPrice:      Value(i.unitPrice),
      quantity:       Value(i.quantity),
      // Simpan discountAmount (sudah dalam Rp) ke kolom discount_amount
      discountAmount: Value(i.discountAmount),
      subtotal:       Value(i.subtotal),
      notes:          Value(i.notes),
      createdAt:      Value(DateTime.now()),
      updatedAt:      Value(DateTime.now()),
    )).toList();
 
    await _dao.insertFull(header: header, items: items);
    return txId;
  }
 
  Future<void> updateTransaction(String txId, TransactionInput input) async {
    final validation = validate(input);
    if (!validation.isValid) throw Exception(validation.errorMessage);
 
    await _dao.deleteItemsByTxId(txId);
 
    final items = input.items.map((i) => TransactionItemsCompanion(
      id:             Value(_uuid.v4()),
      transactionId:  Value(txId),
      categoryId:     Value(i.categoryId),
      name:           Value(i.name.trim()),
      unitPrice:      Value(i.unitPrice),
      quantity:       Value(i.quantity),
      discountAmount: Value(i.discountAmount),
      subtotal:       Value(i.subtotal),
      notes:          Value(i.notes),
      createdAt:      Value(DateTime.now()),
      updatedAt:      Value(DateTime.now()),
    )).toList();
 
    await _dao.updateHeaderAndItems(
      txId:   txId,
      header: TransactionsCompanion(
        placeName:   Value(input.placeName),
        notes:       Value(input.notes),
        date:        Value(input.date),
        totalAmount: Value(input.total),
        updatedAt:   Value(DateTime.now()),
      ),
      items: items,
    );
  }
 
  Future<void> deleteTransaction(String txId) =>
      _dao.deleteTransaction(txId);
 
  // ── Format helpers ───────────────────────────────────────
  static String formatCurrency(double amount) {
    final parts =
        amount.toStringAsFixed(0).split('').reversed.toList();
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write('.');
      buffer.write(parts[i]);
    }
    return 'Rp ${buffer.toString().split('').reversed.join()}';
  }
 
  static String formatDate(DateTime date) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }
 
  static String formatMonth(int year, int month) {
    const months = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return '${months[month]} $year';
  }
}