import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'budget_notification_gateway.dart';

class LocalBudgetNotificationGateway implements BudgetNotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialization;

  LocalBudgetNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return Platform.isWindows;
  }

  @override
  Future<void> showBudgetAlert({
    required String budgetId,
    required String categoryName,
    required int thresholdPercent,
  }) async {
    await _ensureInitialized();
    final isLimitReached = thresholdPercent >= 100;
    await _plugin.show(
      _notificationId(budgetId, thresholdPercent),
      isLimitReached ? 'Batas anggaran tercapai' : 'Anggaran hampir habis',
      isLimitReached
          ? 'Pengeluaran kategori $categoryName sudah mencapai batas bulanan.'
          : 'Pengeluaran kategori $categoryName sudah mencapai 80% anggaran.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'category_budget_alerts',
          'Peringatan anggaran',
          channelDescription:
              'Peringatan batas pengeluaran bulanan per kategori',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  Future<void> _ensureInitialized() async {
    try {
      await (_initialization ??= _initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Finansialku',
          appUserModelId: 'FinanceApp.Finansialku',
          guid: '44bcf6e2-c4e4-4c3e-a71f-b337fd0571b4',
        ),
      ),
    );
  }

  int _notificationId(String budgetId, int threshold) {
    final normalized = budgetId.replaceAll('-', '');
    final prefix =
        normalized.length >= 8 ? normalized.substring(0, 8) : normalized;
    final seed = int.tryParse(prefix, radix: 16) ?? budgetId.hashCode;
    return (seed ^ threshold) & 0x7fffffff;
  }
}
