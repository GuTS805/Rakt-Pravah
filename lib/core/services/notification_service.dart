import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, debugPrint;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/backend.dart';
import '../../firebase_options.dart';

/// Top-level background message handler for Firebase Cloud Messaging.
/// Must be outside of any class and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('[NotificationService] Background handler init error: $e');
  }
}

/// Production notification service supporting:
/// - Real push notifications via Firebase Cloud Messaging (FCM)
/// - Local heads-up alerts when app is in foreground
/// - Deep-linking to blood request / invitation across all app states:
///   🟢 App Open (Foreground notification banner + stream update)
///   🟡 App Background (System push notification -> tap opens request)
///   🔴 App Closed / Killed (System push notification -> tap opens request)
/// - Multi-device FCM token registration & rotation
/// - Donor Mode toggling (registers token when ON, unregisters when OFF)
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _channelId = 'bloodlink_alerts';

  static const _channel = AndroidNotificationChannel(
    _channelId,
    'Urgent Blood Requests & Updates',
    description: 'Real-time emergency blood requests and donor updates',
    importance: Importance.max,
    playSound: true,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  FirebaseMessaging? get _fcm =>
      Firebase.apps.isNotEmpty ? FirebaseMessaging.instance : null;
  bool _ready = false;
  String? _currentToken;
  String? _pendingPayload;
  void Function(String payload)? _onTap;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Tapped notification callback (assigned by notificationWatcherProvider).
  /// If a notification was clicked while the app was closed/launching,
  /// the pending payload is immediately delivered once onTap is set.
  void Function(String payload)? get onTap => _onTap;
  set onTap(void Function(String payload)? handler) {
    _onTap = handler;
    if (handler != null && _pendingPayload != null) {
      final payload = _pendingPayload!;
      _pendingPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handler(payload);
      });
    }
  }

  /// Current cached FCM token for this device.
  String? get currentToken => _currentToken;

  /// Stream of FCM token refreshes.
  Stream<String> get onTokenRefresh =>
      _fcm?.onTokenRefresh ?? const Stream.empty();

  Future<void> init() async {
    if (_ready) return;

    // 1. Initialize local notification display for heads-up alerts
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: ios,
        linux: linux,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _dispatchPayload(payload);
        }
      },
    );

    // Create high-importance Android Notification Channel
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
    }

    // 2. Initialize Firebase Cloud Messaging (FCM)
    try {
      final fcm = _fcm;
      if (fcm != null) {
        // Configure foreground presentation options on Apple platforms
        await fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Register top-level background handler
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        // 🟢 APP OPEN (Foreground): Display in-app heads-up notification
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notification = message.notification;
          final data = message.data;
          final title =
              notification?.title ??
              data['title'] ??
              '🩸 Urgent Blood Request';
          final body =
              notification?.body ??
              data['body'] ??
              'A matching patient urgently needs blood near you.';
          final payload = _extractPayload(message);

          show(
            id: message.messageId.hashCode,
            title: title,
            body: body,
            payload: payload,
          );
        });

        // 🟡 APP IN BACKGROUND: User tapped system push notification
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          final payload = _extractPayload(message);
          if (payload != null && payload.isNotEmpty) {
            _dispatchPayload(payload);
          }
        });

        // 🔴 APP CLOSED / KILLED: User launched app by tapping system push notification
        final initialMessage = await fcm.getInitialMessage();
        if (initialMessage != null) {
          final payload = _extractPayload(initialMessage);
          if (payload != null && payload.isNotEmpty) {
            _dispatchPayload(payload);
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] FCM init warning: $e');
    }

    _ready = true;
  }

  /// Requests notification permission from the system.
  Future<NotificationSettings?> requestPermission() async {
    // Platform-specific local notification permissions
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // Firebase Messaging permission
    final fcm = _fcm;
    if (fcm != null) {
      return await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    }
    return null;
  }

  /// Retrieves the current device's FCM registration token.
  Future<String?> getFcmToken({String? vapidKey}) async {
    final fcm = _fcm;
    if (fcm == null) return null;
    try {
      if (kIsWeb) {
        return await fcm.getToken(
          vapidKey:
              vapidKey ??
              'BKq9d48k34u9fW74aZ173X7P9QvL9347589k34jf98u234', // standard web push key fallback
        );
      }
      return await fcm.getToken();
    } catch (e) {
      debugPrint('[NotificationService] Failed to retrieve FCM token: $e');
      return null;
    }
  }

  /// Synchronizes device token with the backend based on Donor Mode status.
  /// When Donor Mode is ON: Requests permissions, generates token, stores token in backend.
  /// When Donor Mode is OFF: Unregisters device token from backend.
  Future<void> syncDeviceToken(
    Backend backend, {
    required bool isDonorOn,
  }) async {
    try {
      if (isDonorOn) {
        await requestPermission();
        final token = await getFcmToken();
        if (token != null && token.isNotEmpty) {
          _currentToken = token;
          await backend.registerFcmToken(token);

          // Setup token refresh listener if not already listening
          _tokenRefreshSub ??= onTokenRefresh.listen((newToken) async {
            _currentToken = newToken;
            await backend.registerFcmToken(newToken);
          });
        }
      } else {
        if (_currentToken != null) {
          await backend.unregisterFcmToken(_currentToken!);
          _currentToken = null;
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error syncing FCM token: $e');
    }
  }

  /// Removes device token from backend upon logout.
  Future<void> unregisterCurrentToken(Backend backend) async {
    try {
      if (_currentToken != null) {
        await backend.unregisterFcmToken(_currentToken!);
        _currentToken = null;
      }
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
    } catch (e) {
      debugPrint('[NotificationService] Error unregistering token: $e');
    }
  }

  /// Shows a local heads-up notification (used for in-app alert when app is open).
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Urgent Blood Requests & Updates',
        channelDescription: 'Real-time emergency blood requests and donor updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
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

  void _dispatchPayload(String payload) {
    if (_onTap != null) {
      _onTap!(payload);
    } else {
      _pendingPayload = payload;
    }
  }

  String? _extractPayload(RemoteMessage message) {
    final data = message.data;
    if (data.containsKey('payload') && data['payload'].toString().isNotEmpty) {
      return data['payload'].toString();
    }
    final type = data['type']?.toString();
    final requestId =
        data['requestId']?.toString() ?? data['id']?.toString();
    if (type != null && requestId != null && requestId.isNotEmpty) {
      return '$type:$requestId';
    }
    if (requestId != null && requestId.isNotEmpty) {
      return 'invitation:$requestId';
    }
    return null;
  }
}
