import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as permission;

enum ReceiptImageSource { camera, library }

enum ReceiptPermissionStatus { granted, denied, permanentlyDenied }

class PickedReceiptImage {
  final String sourcePath;
  final String? mimeType;

  const PickedReceiptImage({required this.sourcePath, this.mimeType});
}

class ReceiptCameraPermissionException implements Exception {
  final bool permanentlyDenied;

  const ReceiptCameraPermissionException({required this.permanentlyDenied});
}

abstract interface class ReceiptImagePicker {
  Future<PickedReceiptImage?> pick(ReceiptImageSource source);

  Future<PickedReceiptImage?> retrieveLostImage();
}

abstract interface class ReceiptCameraPermissions {
  Future<ReceiptPermissionStatus> requestCamera();

  Future<bool> openAppSettings();
}

class ReceiptPickerService {
  final ReceiptImagePicker _picker;
  final ReceiptCameraPermissions _permissions;
  final TargetPlatform _platform;
  Future<PickedReceiptImage?>? _lostData;

  ReceiptPickerService({
    ReceiptImagePicker? picker,
    ReceiptCameraPermissions? permissions,
    TargetPlatform? platform,
  })  : _picker = picker ?? _PluginReceiptImagePicker(),
        _permissions = permissions ?? _PluginReceiptCameraPermissions(),
        _platform = platform ?? defaultTargetPlatform;

  bool get supportsCamera =>
      _platform == TargetPlatform.android || _platform == TargetPlatform.iOS;

  Future<PickedReceiptImage?> pick(ReceiptImageSource source) async {
    if (source == ReceiptImageSource.camera) {
      if (_platform != TargetPlatform.android &&
          _platform != TargetPlatform.iOS) {
        throw UnsupportedError('Kamera hanya tersedia di Android dan iOS.');
      }
      final status = await _permissions.requestCamera();
      if (status != ReceiptPermissionStatus.granted) {
        throw ReceiptCameraPermissionException(
          permanentlyDenied:
              status == ReceiptPermissionStatus.permanentlyDenied,
        );
      }
    }
    return _picker.pick(source);
  }

  Future<PickedReceiptImage?> retrieveLostImage() {
    if (_platform != TargetPlatform.android) return Future.value(null);
    return _lostData ??= _picker.retrieveLostImage();
  }

  Future<bool> openAppSettings() => _permissions.openAppSettings();
}

class _PluginReceiptImagePicker implements ReceiptImagePicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<PickedReceiptImage?> pick(ReceiptImageSource source) async {
    final file = await _picker.pickImage(
      source: source == ReceiptImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 88,
    );
    return file == null
        ? null
        : PickedReceiptImage(sourcePath: file.path, mimeType: file.mimeType);
  }

  @override
  Future<PickedReceiptImage?> retrieveLostImage() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final file = response.file ?? response.files?.firstOrNull;
    return file == null
        ? null
        : PickedReceiptImage(sourcePath: file.path, mimeType: file.mimeType);
  }
}

class _PluginReceiptCameraPermissions implements ReceiptCameraPermissions {
  @override
  Future<ReceiptPermissionStatus> requestCamera() async {
    final status = await permission.Permission.camera.request();
    if (status.isGranted) return ReceiptPermissionStatus.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return ReceiptPermissionStatus.permanentlyDenied;
    }
    return ReceiptPermissionStatus.denied;
  }

  @override
  Future<bool> openAppSettings() => permission.openAppSettings();
}
