import 'package:finance_app/features/transactions/services/receipt_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requests camera permission before taking a picture', () async {
    final picker = _FakeReceiptPicker();
    final permissions = _FakeCameraPermissions(ReceiptPermissionStatus.granted);
    final service = _service(picker, permissions, TargetPlatform.android);

    final image = await service.pick(ReceiptImageSource.camera);

    expect(permissions.requests, 1);
    expect(picker.lastSource, ReceiptImageSource.camera);
    expect(image?.sourcePath, '/tmp/camera.jpg');
  });

  test('does not launch the camera after permission is denied', () async {
    final picker = _FakeReceiptPicker();
    final service = _service(
      picker,
      _FakeCameraPermissions(ReceiptPermissionStatus.denied),
      TargetPlatform.android,
    );

    await expectLater(
      service.pick(ReceiptImageSource.camera),
      throwsA(isA<ReceiptCameraPermissionException>().having(
        (error) => error.permanentlyDenied,
        'permanentlyDenied',
        isFalse,
      )),
    );
    expect(picker.lastSource, isNull);
  });

  test('marks a permanent camera denial so UI can open settings', () async {
    final service = _service(
      _FakeReceiptPicker(),
      _FakeCameraPermissions(ReceiptPermissionStatus.permanentlyDenied),
      TargetPlatform.iOS,
    );

    await expectLater(
      service.pick(ReceiptImageSource.camera),
      throwsA(isA<ReceiptCameraPermissionException>().having(
        (error) => error.permanentlyDenied,
        'permanentlyDenied',
        isTrue,
      )),
    );
    expect(await service.openAppSettings(), isTrue);
  });

  test('uses the gallery without requesting camera permission', () async {
    final picker = _FakeReceiptPicker();
    final permissions = _FakeCameraPermissions(ReceiptPermissionStatus.denied);
    final service = _service(picker, permissions, TargetPlatform.android);

    final image = await service.pick(ReceiptImageSource.library);

    expect(image?.sourcePath, '/tmp/library.png');
    expect(permissions.requests, 0);
    expect(picker.lastSource, ReceiptImageSource.library);
  });

  test('keeps a cancelled picker as null', () async {
    final picker = _FakeReceiptPicker()..cancelPick = true;
    final service = _service(
      picker,
      _FakeCameraPermissions(ReceiptPermissionStatus.granted),
      TargetPlatform.windows,
    );

    expect(await service.pick(ReceiptImageSource.library), isNull);
  });

  test('recovers Android lost data only once', () async {
    final picker = _FakeReceiptPicker()
      ..lostImage = const PickedReceiptImage(sourcePath: '/tmp/recovered.jpg');
    final service = _service(
      picker,
      _FakeCameraPermissions(ReceiptPermissionStatus.granted),
      TargetPlatform.android,
    );

    expect(
        (await service.retrieveLostImage())?.sourcePath, '/tmp/recovered.jpg');
    expect(
        (await service.retrieveLostImage())?.sourcePath, '/tmp/recovered.jpg');
    expect(picker.lostDataRequests, 1);
  });

  test('does not request camera permission on Windows', () async {
    final picker = _FakeReceiptPicker();
    final permissions = _FakeCameraPermissions(ReceiptPermissionStatus.granted);
    final service = _service(picker, permissions, TargetPlatform.windows);

    await expectLater(
      service.pick(ReceiptImageSource.camera),
      throwsA(isA<UnsupportedError>()),
    );
    expect(permissions.requests, 0);
    expect(picker.lastSource, isNull);
  });
}

ReceiptPickerService _service(
  _FakeReceiptPicker picker,
  _FakeCameraPermissions permissions,
  TargetPlatform platform,
) =>
    ReceiptPickerService(
      picker: picker,
      permissions: permissions,
      platform: platform,
    );

class _FakeReceiptPicker implements ReceiptImagePicker {
  ReceiptImageSource? lastSource;
  bool cancelPick = false;
  int lostDataRequests = 0;
  PickedReceiptImage? lostImage;

  @override
  Future<PickedReceiptImage?> pick(ReceiptImageSource source) async {
    lastSource = source;
    if (cancelPick) return null;
    return PickedReceiptImage(
      sourcePath: source == ReceiptImageSource.camera
          ? '/tmp/camera.jpg'
          : '/tmp/library.png',
      mimeType:
          source == ReceiptImageSource.camera ? 'image/jpeg' : 'image/png',
    );
  }

  @override
  Future<PickedReceiptImage?> retrieveLostImage() async {
    lostDataRequests++;
    return lostImage;
  }
}

class _FakeCameraPermissions implements ReceiptCameraPermissions {
  _FakeCameraPermissions(this.status);

  final ReceiptPermissionStatus status;
  int requests = 0;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<ReceiptPermissionStatus> requestCamera() async {
    requests++;
    return status;
  }
}
