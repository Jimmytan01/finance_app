import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/sync/sync_aware_bill_service.dart';
import '../../transactions/providers/transaction_providers.dart';
import '../services/bill_service.dart';
 
// ─────────────────────────────────────────────────────────────
// BillService provider — sekarang sync-aware
// ─────────────────────────────────────────────────────────────
 
final billServiceProvider = Provider<SyncAwareBillService>((ref) {
  final sync = ref.watch(syncNotifierProvider).valueOrNull;
 
  return SyncAwareBillService(
    billDao:     ref.watch(billDaoProvider),
    txDao:       ref.watch(transactionDaoProvider),
    userId:      ref.watch(currentUserIdProvider),
    deviceId:    ref.watch(currentDeviceIdProvider),
    syncService: sync, // null kalau belum login / offline → tetap simpan lokal
  );
});
 
// ─────────────────────────────────────────────────────────────
// Form state notifier
// ─────────────────────────────────────────────────────────────
 
class BillFormNotifier extends Notifier<BillFormState> {
  String? editingSessionId;
 
  @override
  BillFormState build() => BillFormState(
        title:        '',
        date:         DateTime.now(),
        participants: [],
        items:        [],
        currentStep:  0,
      );
 
  void nextStep() {
    if (state.currentStep < 2) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }
 
  void prevStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }
 
  void goToStep(int step) => state = state.copyWith(currentStep: step);
 
  void setTitle(String v)   => state = state.copyWith(title: v);
  void setDate(DateTime d)  => state = state.copyWith(date: d);
  void setPlace(String? v)  => state = state.copyWith(
        placeName:  v,
        clearPlace: v == null || v.isEmpty,
      );
 
  void addParticipant(BillParticipantInput p) =>
      state = state.copyWith(participants: [...state.participants, p]);
 
  void updateParticipant(int idx, BillParticipantInput updated) {
    final list = [...state.participants]..[idx] = updated;
    state = state.copyWith(participants: list);
  }
 
  void removeParticipant(int idx) {
    final removed = state.participants[idx];
    final newList = [...state.participants]..removeAt(idx);
    final updatedItems = state.items.map((item) {
      final newShares = Map<String, double>.from(item.shares)
        ..remove(removed.id);
      return item.copyWith(shares: newShares);
    }).toList();
    state = state.copyWith(participants: newList, items: updatedItems);
  }
 
  void addItem(BillItemInput item) =>
      state = state.copyWith(items: [...state.items, item]);
 
  void updateItem(int idx, BillItemInput updated) {
    final list = [...state.items]..[idx] = updated;
    state = state.copyWith(items: list);
  }
 
  void removeItem(int idx) {
    final list = [...state.items]..removeAt(idx);
    state = state.copyWith(items: list);
  }
 
  void splitItemEqually(int itemIdx) {
    if (state.participants.isEmpty) return;
    final item      = state.items[itemIdx];
    final perPerson = item.quantity / state.participants.length;
    final shares    = {for (final p in state.participants) p.id: perPerson};
    updateItem(itemIdx, item.copyWith(shares: shares));
  }
 
  void toggleParticipantOnItem(int itemIdx, String participantId) {
    final item      = state.items[itemIdx];
    final newShares = Map<String, double>.from(item.shares);
    if (newShares.containsKey(participantId)) {
      newShares.remove(participantId);
    } else {
      newShares[participantId] = 0;
    }
    if (newShares.isEmpty) {
      updateItem(itemIdx, item.copyWith(shares: newShares));
      return;
    }
    final perPerson    = item.quantity / newShares.length;
    final redistributed = {for (final id in newShares.keys) id: perPerson};
    updateItem(itemIdx, item.copyWith(shares: redistributed));
  }
 
  void setShareQty(int itemIdx, String participantId, double qty) {
    final item      = state.items[itemIdx];
    final newShares = Map<String, double>.from(item.shares);
    if (qty <= 0) {
      newShares.remove(participantId);
    } else {
      newShares[participantId] = qty;
    }
    updateItem(itemIdx, item.copyWith(shares: newShares));
  }
 
  void setDiscountType(String type)  =>
      state = state.copyWith(discountType: type);
  void setDiscountValue(double val)  =>
      state = state.copyWith(discountValue: val);
  void setTaxPercent(double val)     =>
      state = state.copyWith(taxPercent: val);
 
  void reset() {
    editingSessionId = null;
    state = BillFormState(
      title:        '',
      date:         DateTime.now(),
      participants: [],
      items:        [],
      currentStep:  0,
    );
  }
 
  Future<void> loadFromSession(BillSessionDetail detail) async {
    editingSessionId = detail.session.id;
 
    final participants = detail.participants
        .map((p) => BillParticipantInput(
              id:     p.id,
              name:   p.name,
              isSelf: p.isSelf,
            ))
        .toList();
 
    final items = detail.items.map((item) {
      final itemSplits = detail.splits
          .where((s) => s.billItemId == item.id)
          .toList();
      final shares = <String, double>{
        for (final s in itemSplits) s.participantId: s.shareQty,
      };
      return BillItemInput(
        id:        item.id,
        name:      item.name,
        unitPrice: item.unitPrice,
        quantity:  item.quantity,
        shares:    shares,
      );
    }).toList();
 
    state = BillFormState(
      title:         detail.session.title,
      date:          detail.session.date,
      placeName:     detail.session.placeName,
      discountType:  detail.session.discountType,
      discountValue: detail.session.discountValue,
      taxPercent:    detail.session.taxPercent,
      participants:  participants,
      items:         items,
      currentStep:   0,
    );
  }
}
 
final billFormProvider =
    NotifierProvider<BillFormNotifier, BillFormState>(BillFormNotifier.new);
 
final billCalcResultProvider =
    StateProvider<BillCalcResult?>((ref) => null);
 
// ─────────────────────────────────────────────────────────────
// Riwayat sesi — watch syncTickProvider supaya refresh setelah sync
// ─────────────────────────────────────────────────────────────
 
final billSessionListProvider =
    FutureProvider.autoDispose<List<BillSession>>((ref) async {
  // Refresh saat ada sync baru dari device lain
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(billDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  return dao.getAllSessions(userId);
});
 
final billSessionDetailProvider = FutureProvider.autoDispose
    .family<BillSessionDetail, String>((ref, sessionId) async {
  ref.watch(syncTickProvider);
 
  final dao = ref.watch(billDaoProvider);
  return dao.getSessionDetail(sessionId);
});