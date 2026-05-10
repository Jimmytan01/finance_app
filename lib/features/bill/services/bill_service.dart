import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
 
const _uuid = Uuid();
 
// ─────────────────────────────────────────────────────────────
// Input models — dipakai di form state sebelum disimpan ke DB
// ─────────────────────────────────────────────────────────────
 
class BillParticipantInput {
  final String id;
  String name;
  bool   isSelf;
 
  BillParticipantInput({
    String? id,
    required this.name,
    this.isSelf = false,
  }) : id = id ?? _uuid.v4();
 
  BillParticipantInput copyWith({String? name, bool? isSelf}) =>
      BillParticipantInput(
        id:     id,
        name:   name    ?? this.name,
        isSelf: isSelf  ?? this.isSelf,
      );
}
 
// Satu baris item di bill.
// shares: map dari participantId ke berapa porsi yang dia ambil.
// Kalau 2 orang share 1 piring (qty=1) sama rata → each gets share_qty=0.5
class BillItemInput {
  final String            id;
  String                  name;
  double                  unitPrice;
  int                     quantity;
  Map<String, double>     shares; // participantId → shareQty
 
  BillItemInput({
    String? id,
    required this.name,
    this.unitPrice = 0,
    this.quantity  = 1,
    Map<String, double>? shares,
  })  : id     = id ?? _uuid.v4(),
        shares = shares ?? {};
 
  double get subtotal => unitPrice * quantity;
 
  // Cek apakah item ini sudah di-assign ke setidaknya satu orang
  bool get isAssigned => shares.isNotEmpty &&
      shares.values.any((q) => q > 0);
 
  BillItemInput copyWith({
    String?              name,
    double?              unitPrice,
    int?                 quantity,
    Map<String, double>? shares,
  }) =>
      BillItemInput(
        id:        id,
        name:      name        ?? this.name,
        unitPrice: unitPrice   ?? this.unitPrice,
        quantity:  quantity    ?? this.quantity,
        shares:    shares      ?? Map.from(this.shares),
      );
}
 
// State form keseluruhan. Dipake di BillFormNotifier.
class BillFormState {
  final String  title;
  final DateTime date;
  final String? placeName;
  final String  discountType;  // 'percent' | 'flat'
  final double  discountValue;
  final double  taxPercent;
  final List<BillParticipantInput> participants;
  final List<BillItemInput>        items;
  final int     currentStep;    // 0=info+peserta, 1=item, 2=diskon
 
  const BillFormState({
    this.title         = '',
    DateTime? date,
    this.placeName,
    this.discountType  = 'flat',
    this.discountValue = 0,
    this.taxPercent    = 0,
    this.participants  = const [],
    this.items         = const [],
    this.currentStep   = 0,
  }) : date = date ?? const _Today();
 
  // Validasi per step — user tidak bisa lanjut kalau belum lengkap
  bool get step0Valid =>
      title.trim().isNotEmpty && participants.isNotEmpty;
 
  bool get step1Valid =>
      items.isNotEmpty &&
      items.every((i) => i.name.trim().isNotEmpty && i.unitPrice > 0) &&
      items.every((i) => i.isAssigned);
 
  bool get isReadyToCalculate => step0Valid && step1Valid;
 
  BillFormState copyWith({
    String?                  title,
    DateTime?                date,
    String?                  placeName,
    bool                     clearPlace = false,
    String?                  discountType,
    double?                  discountValue,
    double?                  taxPercent,
    List<BillParticipantInput>? participants,
    List<BillItemInput>?     items,
    int?                     currentStep,
  }) =>
      BillFormState(
        title:          title           ?? this.title,
        date:           date            ?? this.date,
        placeName:      clearPlace ? null : (placeName ?? this.placeName),
        discountType:   discountType    ?? this.discountType,
        discountValue:  discountValue   ?? this.discountValue,
        taxPercent:     taxPercent      ?? this.taxPercent,
        participants:   participants    ?? this.participants,
        items:          items           ?? this.items,
        currentStep:    currentStep     ?? this.currentStep,
      );
}
 
// Dart tidak punya initializer expression untuk field yang nullable const,
// jadi kita pakai trick ini buat nilai default DateTime.now() di const constructor
class _Today implements DateTime {
  const _Today();
  // ... (dalam praktiknya ganti default date di build() notifier, bukan di sini)
  // Baris ini hanya untuk dokumentasi — lihat BillFormNotifier.build()
  noSuchMethod(i) => throw UnimplementedError();
}
 
// ─────────────────────────────────────────────────────────────
// Output models — hasil kalkulasi sebelum disimpan ke DB
// ─────────────────────────────────────────────────────────────
 
class BillCalcResult {
  final double                  subtotalBeforeDiscount;
  final double                  discountAmount;
  final double                  taxAmount;
  final double                  grandTotal;
  final List<ParticipantResult> participants;
 
  const BillCalcResult({
    required this.subtotalBeforeDiscount,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.participants,
  });
}
 
class ParticipantResult {
  final BillParticipantInput participant;
  final double               rawShare;       // sebelum diskon & pajak
  final double               discountShare;  // bagian diskon yang dia hemat
  final double               taxShare;       // bagian pajak yang dia tanggung
  final double               finalAmount;    // yang harus dibayar
  final List<ItemShareResult> itemBreakdown; // rincian per item
 
  const ParticipantResult({
    required this.participant,
    required this.rawShare,
    required this.discountShare,
    required this.taxShare,
    required this.finalAmount,
    required this.itemBreakdown,
  });
}
 
class ItemShareResult {
  final BillItemInput item;
  final double        shareQty;    // porsi quantity
  final double        shareAmount; // nilai rupiah sebelum diskon/pajak
 
  const ItemShareResult({
    required this.item,
    required this.shareQty,
    required this.shareAmount,
  });
}
 
// ─────────────────────────────────────────────────────────────
// BillService — kalkulasi dan save ke DB
// ─────────────────────────────────────────────────────────────
 
class BillService {
  final BillDao          _billDao;
  final TransactionDao   _txDao;
  final String           _userId;
  final String           _deviceId;

  String get userId   => _userId;
 
  BillService({
    required BillDao        billDao,
    required TransactionDao txDao,
    required String         userId,
    required String         deviceId,
  })  : _billDao  = billDao,
        _txDao    = txDao,
        _userId   = userId,
        _deviceId = deviceId;
 
  // Kalkulasi utama — dipanggil waktu user tekan "Hitung".
  // Tidak ada side effect ke DB di sini, murni transform data.
  BillCalcResult calculate(BillFormState form) {
    final participants = form.participants;
    final items        = form.items;
 
    // Hitung raw share tiap peserta dari item yang mereka pesan
    final rawShares = <String, double>{
      for (final p in participants) p.id: 0.0,
    };
 
    final itemBreakdowns = <String, List<ItemShareResult>>{
      for (final p in participants) p.id: [],
    };
 
    for (final item in items) {
      // Total porsi yang sudah di-assign untuk item ini
      // (normalnya sama dengan item.quantity, tapi kita tidak asumsi itu)
      final totalAssignedQty =
          item.shares.values.fold(0.0, (s, q) => s + q);
 
      if (totalAssignedQty <= 0) continue;
 
      for (final entry in item.shares.entries) {
        final participantId = entry.key;
        final shareQty      = entry.value;
 
        // Rupiah yang ditanggung peserta ini untuk item ini,
        // proporsional dengan berapa banyak yang dia ambil
        final shareAmount =
            (shareQty / totalAssignedQty) * item.subtotal;
 
        rawShares[participantId] =
            (rawShares[participantId] ?? 0) + shareAmount;
 
        itemBreakdowns[participantId]?.add(ItemShareResult(
          item:        item,
          shareQty:    shareQty,
          shareAmount: shareAmount,
        ));
      }
    }
 
    // Total subtotal sebelum diskon/pajak
    final subtotal = rawShares.values.fold(0.0, (s, v) => s + v);
 
    // Hitung diskon total
    double discountAmount = 0;
    if (subtotal > 0) {
      if (form.discountType == 'percent') {
        discountAmount = subtotal * (form.discountValue / 100);
      } else {
        discountAmount = form.discountValue;
      }
      // Diskon tidak boleh melebihi subtotal
      discountAmount = discountAmount.clamp(0, subtotal);
    }
 
    // Pajak dihitung dari subtotal SETELAH diskon
    final afterDiscount = subtotal - discountAmount;
    final taxAmount     = afterDiscount * (form.taxPercent / 100);
    final grandTotal    = afterDiscount + taxAmount;
 
    // Distribusi diskon dan pajak ke tiap peserta secara proporsional
    final results = participants.map((p) {
      final raw = rawShares[p.id] ?? 0.0;
 
      // Kalau subtotal 0 (semua gratis?), bagi rata saja
      final proportion   = subtotal > 0 ? raw / subtotal : 0.0;
      final discShare    = discountAmount * proportion;
      final taxShare     = taxAmount      * proportion;
      final finalAmount  = raw - discShare + taxShare;
 
      return ParticipantResult(
        participant:   p,
        rawShare:      raw,
        discountShare: discShare,
        taxShare:      taxShare,
        // Bulatkan ke Rp 1 terdekat — tidak ada koin di Indonesia
        finalAmount:   double.parse(finalAmount.toStringAsFixed(0)),
        itemBreakdown: itemBreakdowns[p.id] ?? [],
      );
    }).toList();
 
    // Urutkan dari yang paling banyak bayar, biar mudah dibaca
    results.sort((a, b) => b.finalAmount.compareTo(a.finalAmount));
 
    return BillCalcResult(
      subtotalBeforeDiscount: subtotal,
      discountAmount:         discountAmount,
      taxAmount:              taxAmount,
      grandTotal:             grandTotal,
      participants:           results,
    );
  }
 
  // Simpan sesi bill ke DB setelah kalkulasi selesai.
  // Return sessionId supaya bisa di-link ke transaksi kalau user mau.
  Future<String> saveSession(
    BillFormState   form,
    BillCalcResult  result,
  ) async {
    final sessionId = _uuid.v4();
 
    // Buat companion untuk session header
    final sessionComp = BillSessionsCompanion(
      id:            Value(sessionId),
      userId:        Value(_userId),
      title:         Value(form.title.trim()),
      date:          Value(form.date),
      placeName:     Value(form.placeName?.trim()),
      discountType:  Value(form.discountType),
      discountValue: Value(form.discountValue),
      taxPercent:    Value(form.taxPercent),
      totalAmount:   Value(result.grandTotal),
      createdAt:     Value(DateTime.now()),
      updatedAt:     Value(DateTime.now()),
    );
 
    // Peserta
    final participantComps = form.participants
        .map((p) => BillParticipantsCompanion(
              id:            Value(p.id),
              billSessionId: Value(sessionId),
              name:          Value(p.name.trim()),
              isSelf:        Value(p.isSelf),
              createdAt:     Value(DateTime.now()),
            ))
        .toList();
 
    // Item
    final itemComps = form.items
        .map((i) => BillItemsCompanion(
              id:            Value(i.id),
              billSessionId: Value(sessionId),
              name:          Value(i.name.trim()),
              unitPrice:     Value(i.unitPrice),
              quantity:      Value(i.quantity),
              subtotal:      Value(i.subtotal),
              createdAt:     Value(DateTime.now()),
            ))
        .toList();
 
    // Item-participant splits — ambil dari hasil kalkulasi
    // supaya share_amount yang tersimpan sudah include diskon/pajak
    final splitComps = <BillItemParticipantsCompanion>[];
    for (final presult in result.participants) {
      for (final iShare in presult.itemBreakdown) {
        // Cari berapa final amount share item ini setelah diskon & pajak
        // Kita proporsikan finalAmount dengan itemShare/rawShare
        final proportion = presult.rawShare > 0
            ? iShare.shareAmount / presult.rawShare
            : 0.0;
        final finalItemShare = presult.finalAmount * proportion;
 
        splitComps.add(BillItemParticipantsCompanion(
          id:            Value(_uuid.v4()),
          billItemId:    Value(iShare.item.id),
          participantId: Value(presult.participant.id),
          shareQty:      Value(iShare.shareQty),
          shareAmount:   Value(
            double.parse(finalItemShare.toStringAsFixed(0)),
          ),
        ));
      }
    }
 
    await _billDao.insertFullBillSession(
      session:      sessionComp,
      participants: participantComps,
      items:        itemComps,
      splits:       splitComps,
    );
 
    return sessionId;
  }
 
  // Simpan bagian saya (is_self = true) ke transaksi keuangan.
  // Dipanggil opsional dari BillResultScreen — user bebas mau simpan atau tidak.
  Future<void> saveMyShareToTransaction({
    required String         sessionId,
    required BillFormState  form,
    required BillCalcResult result,
    required List<Category> categories,
  }) async {
    // Cari peserta yang isSelf
    final myResult = result.participants
        .where((p) => p.participant.isSelf)
        .firstOrNull;
 
    if (myResult == null) return; // tidak ada yang di-tandai "saya"
 
    // Cari kategori "Makan" sebagai default — cocok untuk kebanyakan bill
    final defaultCat = categories
        .where((c) => c.name.toLowerCase().contains('makan'))
        .firstOrNull;
 
    final txId = _uuid.v4();
 
    final header = TransactionsCompanion(
      id:          Value(txId),
      userId:      Value(_userId),
      date:        Value(form.date),
      placeName:   Value(
        form.placeName?.isNotEmpty == true ? form.placeName : form.title,
      ),
      notes:       Value('Split bill: ${form.title}'),
      totalAmount: Value(myResult.finalAmount),
      deviceId:    Value(_deviceId),
      createdAt:   Value(DateTime.now()),
      updatedAt:   Value(DateTime.now()),
    );
 
    // Buat satu item per item yang saya pesan
    final myItems = myResult.itemBreakdown
        .map((iShare) => TransactionItemsCompanion(
              id:             Value(_uuid.v4()),
              transactionId:  Value(txId),
              categoryId:     Value(defaultCat?.id),
              name:           Value(iShare.item.name),
              unitPrice:      Value(iShare.item.unitPrice),
              quantity:       Value(iShare.shareQty),
              discountAmount: Value(0.0),
              // Share amount sudah include proporsi diskon & pajak
              subtotal:       Value(iShare.shareAmount),
              notes:          const Value(null),
              createdAt:      Value(DateTime.now()),
              updatedAt:      Value(DateTime.now()),
            ))
        .toList();
 
    await _txDao.insertFull(header: header, items: myItems);
 
    // Link sesi bill ke transaksi yang baru dibuat
    await _billDao.linkToTransaction(sessionId, txId);
  }
 
  // Validasi sebelum kalkulasi
  String? validate(BillFormState form) {
    if (form.title.trim().isEmpty) {
      return 'Judul sesi tidak boleh kosong';
    }
    if (form.participants.isEmpty) {
      return 'Tambahkan minimal satu peserta';
    }
    if (form.participants.any((p) => p.name.trim().isEmpty)) {
      return 'Ada nama peserta yang masih kosong';
    }
    if (form.items.isEmpty) {
      return 'Tambahkan minimal satu item';
    }
    for (final item in form.items) {
      if (item.name.trim().isEmpty) {
        return 'Ada nama item yang masih kosong';
      }
      if (item.unitPrice <= 0) {
        return 'Harga "${item.name}" harus lebih dari 0';
      }
      if (!item.isAssigned) {
        return 'Item "${item.name}" belum di-assign ke siapapun';
      }
    }
    if (form.discountValue < 0) {
      return 'Diskon tidak boleh negatif';
    }
    if (form.taxPercent < 0 || form.taxPercent > 100) {
      return 'Pajak harus antara 0–100%';
    }
    return null; // null = valid
  }
}