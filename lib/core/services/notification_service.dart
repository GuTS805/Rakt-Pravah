import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local, in-process alerts only — there is no push server behind this app
/// (that needs a paid Firebase plan for Cloud Functions), so these fire
/// while the app is running (foreground or backgrounded) but can't wake it
/// once fully closed. Good enough to surface a new nearby request or an
/// accepted donor without the user having to keep the app open and staring.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _channelId = 'bloodlink_alerts';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Set by whoever owns navigation (see `notificationWatcherProvider`) to
  /// route a tapped notification to the right screen.
  void Function(String payload)? onTap;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      settings:
          const InitializationSettings(android: android, iOS: ios, linux: linux),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap?.call(payload);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _ready = true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Requests & updates',
        channelDescription: 'New nearby requests and status changes',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
