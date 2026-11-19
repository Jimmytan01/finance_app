import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Small local logger for diagnostics in debug and release builds.
///
/// Records are kept as JSON Lines in the application support directory. The
/// active log is capped and rotated so diagnostics cannot grow indefinitely.
class AppLogger {
  AppLogger._();

  static const int _maxFileBytes = 1024 * 1024;
  static const int _backupCount = 3;
  static const int _maxPendingRecords = 200;

  static File? _activeFile;
  static Future<void>? _initialization;
  static Future<void> _writeQueue = Future<void>.value();
  static final List<String> _pendingRecords = <String>[];

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final logDirectory = Directory(path.join(supportDirectory.path, 'logs'));
      await logDirectory.create(recursive: true);
      _activeFile = File(path.join(logDirectory.path, 'finance_app.log'));

      final pending = List<String>.of(_pendingRecords);
      _pendingRecords.clear();
      for (final record in pending) {
        _enqueueWrite(record);
      }
    } catch (error) {
      // Logging must never prevent the app from starting.
      if (kDebugMode) {
        debugPrint('[logger] Could not initialize log file: $error');
      }
    }
  }

  static void info(String message, {String scope = 'app'}) {
    _record('INFO', message, scope: scope);
  }

  static void warning(String message, {String scope = 'app'}) {
    _record('WARNING', message, scope: scope);
  }

  static void error(
    String message, {
    String scope = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _record(
      'ERROR',
      message,
      scope: scope,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _record(
    String level,
    String message, {
    required String scope,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = jsonEncode(<String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'scope': scope,
      'message': message,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    });

    if (kDebugMode) debugPrint(record);

    if (_activeFile == null) {
      if (_pendingRecords.length == _maxPendingRecords) {
        _pendingRecords.removeAt(0);
      }
      _pendingRecords.add(record);
      return;
    }

    _enqueueWrite(record);
  }

  static void _enqueueWrite(String record) {
    _writeQueue = _writeQueue
        .then((_) => _appendRecord(record))
        .catchError((Object error) {
      if (kDebugMode) debugPrint('[logger] Could not write log record: $error');
    });
  }

  static Future<void> _appendRecord(String record) async {
    final activeFile = _activeFile;
    if (activeFile == null) return;

    final recordBytes = utf8.encode(record).length + 1;
    if (await activeFile.exists() &&
        await activeFile.length() + recordBytes > _maxFileBytes) {
      await _rotateFiles(activeFile);
    }

    await activeFile.writeAsString(
      '$record\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<void> _rotateFiles(File activeFile) async {
    for (var index = _backupCount; index >= 1; index--) {
      final current = File('${activeFile.path}.$index');
      if (!await current.exists()) continue;

      if (index == _backupCount) {
        await current.delete();
      } else {
        final next = File('${activeFile.path}.${index + 1}');
        if (await next.exists()) await next.delete();
        await current.rename(next.path);
      }
    }

    if (await activeFile.exists()) {
      await activeFile.rename('${activeFile.path}.1');
    }
  }

  /// Builds one text file containing the active log and its rotated backups.
  static Future<File> createExportFile() async {
    await initialize();
    await _writeQueue;

    final activeFile = _activeFile;
    if (activeFile == null) {
      throw StateError('File log tidak tersedia di perangkat ini.');
    }

    final logFiles = <File>[
      for (var index = _backupCount; index >= 1; index--)
        File('${activeFile.path}.$index'),
      activeFile,
    ];
    final output = StringBuffer();
    var hasRecords = false;

    for (final logFile in logFiles) {
      if (!await logFile.exists()) continue;
      hasRecords = true;
      output
        ..writeln('===== ${path.basename(logFile.path)} =====')
        ..writeln(await logFile.readAsString());
    }

    if (!hasRecords) {
      output.writeln('Belum ada log aplikasi yang tercatat.');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final exportFile = File(path.join(
      temporaryDirectory.path,
      'finance_app_logs_$timestamp.txt',
    ));
    await exportFile.writeAsString(output.toString(), flush: true);
    return exportFile;
  }
}
