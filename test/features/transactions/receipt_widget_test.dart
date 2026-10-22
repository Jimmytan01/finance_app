import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/core/database/app_database.dart';
import 'package:finance_app/core/providers/database_providers.dart';
import 'package:finance_app/core/sync/receipt_storage_sync_service.dart';
import 'package:finance_app/features/budget/providers/budget_alert_providers.dart';
import 'package:finance_app/features/budget/services/budget_alert_service.dart';
import 'package:finance_app/features/transactions/models/receipt_models.dart';
import 'package:finance_app/features/transactions/providers/receipt_providers.dart';
import 'package:finance_app/features/transactions/providers/transaction_providers.dart';
import 'package:finance_app/features/transactions/repositories/transaction_repository.dart';
import 'package:finance_app/features/transactions/screens/add_transaction_screen.dart';
import 'package:finance_app/features/transactions/screens/transaction_detail_screen.dart';
import 'package:finance_app/features/transactions/services/receipt_attachment_service.dart';
import 'package:finance_app/features/transactions/services/receipt_picker_service.dart';
import 'package:finance_app/features/transactions/services/transaction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late String imagePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('receipt-ui-');
    imagePath = '${temporaryDirectory.path}/receipt.png';
    await File(imagePath).writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
    ));
  });

  tearDown(() async => temporaryDirectory.delete(recursive: true));

  testWidgets('offers camera and gallery, then previews a selected photo',
      (tester) async {
    final picker = _PickerAdapter(imagePath);
    await _pumpForm(tester, picker: picker);

    await tester.tap(find.text('Lampirkan foto struk'));
    await tester.pumpAndSettle();
    expect(find.text('Kamera'), findsOneWidget);
    expect(find.text('Galeri / berkas'), findsOneWidget);
    await tester.tap(find.text('Kamera'));
    await tester.pumpAndSettle();

    expect(picker.lastSource, ReceiptImageSource.camera);
    expect(find.text('Foto baru'), findsOneWidget);
  });

  testWidgets('Windows picker offers files and does not offer camera',
      (tester) async {
    await _pumpForm(tester, platform: TargetPlatform.windows);

    await tester.tap(find.text('Lampirkan foto struk'));
    await tester.pumpAndSettle();

    expect(find.text('Galeri / berkas'), findsOneWidget);
    expect(find.text('Kamera'), findsNothing);
  });

  testWidgets('cancelled picker preserves an existing receipt', (tester) async {
    final picker = _PickerAdapter(imagePath)..cancelPick = true;
    final receipt = _receipt(localPath: imagePath);
    await _pumpForm(
      tester,
      picker: picker,
      editTxId: 'tx-1',
      receipt: receipt,
    );

    expect(find.text('Foto tersedia'), findsOneWidget);
    await tester.tap(find.text('Ganti foto struk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri / berkas'));
    await tester.pumpAndSettle();

    expect(find.text('Foto tersedia'), findsOneWidget);
    expect(find.text('Foto baru'), findsNothing);
  });

  testWidgets('permanent camera denial offers an open settings action',
      (tester) async {
    final permissions =
        _FakeCameraPermissions(ReceiptPermissionStatus.permanentlyDenied);
    final picker = _PickerAdapter(imagePath);
    await _pumpForm(tester, picker: picker, permissions: permissions);

    await tester.tap(find.text('Lampirkan foto struk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kamera'));
    await tester.pumpAndSettle();

    expect(find.text('Buka pengaturan'), findsOneWidget);
    await tester.tap(find.text('Buka pengaturan'));
    await tester.pump();
    expect(permissions.settingsCalls, 1);
    expect(find.text('Galeri / berkas'), findsNothing);
  });

  testWidgets('removes and replaces an existing receipt in the draft',
      (tester) async {
    final picker = _PickerAdapter(imagePath);
    await _pumpForm(
      tester,
      picker: picker,
      editTxId: 'tx-1',
      receipt: _receipt(localPath: imagePath),
    );

    await tester.tap(find.byTooltip('Hapus foto struk'));
    await tester.pump();
    expect(
        find.text('Foto akan dihapus saat transaksi disimpan'), findsOneWidget);
    await tester.tap(find.text('Ganti foto struk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri / berkas'));
    await tester.pumpAndSettle();

    expect(find.text('Foto baru'), findsOneWidget);
    expect(
        find.text('Foto akan dihapus saat transaksi disimpan'), findsNothing);
  });

  testWidgets(
      'partial attachment save retry does not save a duplicate transaction',
      (tester) async {
    final picker = _PickerAdapter(imagePath);
    final transactionService = _CountingTransactionService();
    final attachmentService = _FailOnceAttachmentService();
    final container = ProviderContainer(overrides: [
      categoriesProvider.overrideWith((ref) async => []),
      receiptPickerServiceProvider.overrideWithValue(
        _pickerService(picker, platform: TargetPlatform.android),
      ),
      transactionServiceProvider.overrideWith((ref) => transactionService),
      receiptAttachmentServiceProvider.overrideWithValue(attachmentService),
      budgetAlertServiceProvider.overrideWithValue(_NoopBudgetAlertService()),
      syncNowProvider.overrideWith((ref) => () async {}),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AddTransactionScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lampirkan foto struk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri / berkas'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('transaction-item-name-0')), 'Makan siang');
    await tester.enterText(
        find.byKey(const Key('transaction-item-price-0')), '25000');
    await tester.pump();
    await tester.tap(find.text('Simpan Transaksi'));
    await tester.pumpAndSettle();

    expect(transactionService.saveCalls, 1);
    expect(attachmentService.stageCalls, 1);
    expect(find.textContaining('Transaksi tersimpan, tetapi foto struk'),
        findsOneWidget);
    expect(transactionService.saveCalls, 1);
    expect(attachmentService.stageCalls, 1);
    expect(find.text('Coba lagi lampiran struk'), findsOneWidget);

    await tester.tap(find.text('Coba lagi lampiran struk'));
    await tester.pumpAndSettle();

    expect(transactionService.saveCalls, 1);
    expect(attachmentService.stageCalls, 2);
  });

  testWidgets('detail shows pending upload and retries receipt sync',
      (tester) async {
    final sync = _FakeReceiptSyncService();
    final container = _detailContainer(
      receipt: _receipt(
        localPath: imagePath,
        syncState: ReceiptSyncState.uploadError,
      ),
      sync: sync,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: TransactionDetailScreen(txId: 'tx-1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gagal mengunggah struk'), findsOneWidget);
    await tester.tap(find.text('Coba sinkronkan'));
    await tester.pumpAndSettle();

    expect(sync.syncCalls, 1);
  });

  testWidgets('remote receipt displays download loading and caches photo',
      (tester) async {
    final sync = _FakeReceiptSyncService()
      ..downloadResponse = Completer<String>();
    final container = _detailContainer(
      receipt: _receipt(localPath: null),
      sync: sync,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: TransactionDetailScreen(txId: 'tx-1'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unduh foto struk'));
    await tester.pump();
    expect(find.text('Mengunduh...'), findsOneWidget);
    sync.downloadResponse!.complete(imagePath);
    await tester.pumpAndSettle();

    expect(sync.downloadCalls, 1);
  });
}

Future<void> _pumpForm(
  WidgetTester tester, {
  _PickerAdapter? picker,
  ReceiptPermissionStatus permissionStatus = ReceiptPermissionStatus.granted,
  _FakeCameraPermissions? permissions,
  TargetPlatform platform = TargetPlatform.android,
  String? editTxId,
  ReceiptAttachment? receipt,
}) async {
  final service = _pickerService(
    picker ?? _PickerAdapter(''),
    permissions: permissions ?? _FakeCameraPermissions(permissionStatus),
    platform: platform,
  );
  final overrides = <Override>[
    categoriesProvider.overrideWith((ref) async => []),
    receiptPickerServiceProvider.overrideWithValue(service),
  ];
  if (editTxId != null) {
    overrides.add(
      receiptForTransactionProvider(editTxId)
          .overrideWith((ref) async => receipt),
    );
  }
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: AddTransactionScreen(editTxId: editTxId)),
  ));
  await tester.pumpAndSettle();
}

ProviderContainer _detailContainer({
  required ReceiptAttachment receipt,
  required _FakeReceiptSyncService sync,
}) =>
    ProviderContainer(overrides: [
      monthlyTransactionsProvider.overrideWith((ref) async => [_transaction()]),
      transactionItemsProvider('tx-1').overrideWith((ref) async => []),
      categoriesProvider.overrideWith((ref) async => []),
      receiptForTransactionProvider('tx-1')
          .overrideWith((ref) async => receipt),
      receiptStorageSyncServiceProvider.overrideWithValue(sync),
    ]);

ReceiptPickerService _pickerService(
  _PickerAdapter picker, {
  _FakeCameraPermissions? permissions,
  TargetPlatform platform = TargetPlatform.android,
}) =>
    ReceiptPickerService(
      picker: picker,
      permissions: permissions ??
          _FakeCameraPermissions(ReceiptPermissionStatus.granted),
      platform: platform,
    );

class _PickerAdapter implements ReceiptImagePicker {
  _PickerAdapter(this.path);
  final String path;
  bool cancelPick = false;
  ReceiptImageSource? lastSource;

  @override
  Future<PickedReceiptImage?> pick(ReceiptImageSource source) async {
    lastSource = source;
    if (cancelPick) return null;
    return PickedReceiptImage(sourcePath: path, mimeType: 'image/png');
  }

  @override
  Future<PickedReceiptImage?> retrieveLostImage() async => null;
}

class _FakeCameraPermissions implements ReceiptCameraPermissions {
  _FakeCameraPermissions(this.status);
  final ReceiptPermissionStatus status;
  int settingsCalls = 0;

  @override
  Future<bool> openAppSettings() async {
    settingsCalls++;
    return true;
  }

  @override
  Future<ReceiptPermissionStatus> requestCamera() async => status;
}

class _CountingTransactionService extends TransactionService {
  _CountingTransactionService()
      : super(
          repository: _UnusedTransactionRepository(),
          userId: 'user-1',
          deviceId: 'test',
        );
  int saveCalls = 0;

  @override
  Future<String> saveTransaction(TransactionInput input) async {
    saveCalls++;
    return 'tx-1';
  }
}

class _UnusedTransactionRepository extends Fake
    implements TransactionRepository {}

class _FailOnceAttachmentService extends Fake
    implements ReceiptAttachmentService {
  int stageCalls = 0;

  @override
  Future<ReceiptAttachment> stageForTransaction({
    required String userId,
    required String transactionId,
    required PickedReceiptImage image,
  }) async {
    stageCalls++;
    if (stageCalls == 1) throw const FileSystemException('disk full');
    return _receipt(localPath: image.sourcePath);
  }
}

class _NoopBudgetAlertService extends Fake implements BudgetAlertService {
  @override
  Future<void> evaluateForMonth({
    required String userId,
    required int year,
    required int month,
  }) async {}
}

class _FakeReceiptSyncService extends Fake
    implements ReceiptStorageSyncService {
  int syncCalls = 0;
  int downloadCalls = 0;
  Completer<String>? downloadResponse;

  @override
  Future<ReceiptSyncResult> syncPending() async {
    syncCalls++;
    return const ReceiptSyncResult(uploaded: 1);
  }

  @override
  Future<String> downloadToCache(String receiptId) async {
    downloadCalls++;
    return downloadResponse?.future ?? Future.value('cached.jpg');
  }
}

ReceiptAttachment _receipt({
  required String? localPath,
  ReceiptSyncState syncState = ReceiptSyncState.available,
}) =>
    ReceiptAttachment(
      id: 'receipt-1',
      userId: 'user-1',
      transactionId: 'tx-1',
      localPath: localPath,
      storagePath: 'user-1/tx-1/receipt-1.png',
      mimeType: 'image/png',
      syncState: syncState,
      isDeleted: false,
    );

Transaction _transaction() {
  final date = DateTime(2026, 10, 12);
  return Transaction(
    id: 'tx-1',
    userId: 'user-1',
    date: date,
    totalAmount: 25000,
    createdAt: date,
    updatedAt: date,
  );
}
