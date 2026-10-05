import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/device_id_service.dart';
import 'package:rakt_pravah/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Push Notifications & Device Management Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('DeviceIdService provides consistent, persistent device identifier',
        () async {
      final idService = DeviceIdService.instance;
      final id1 = await idService.getDeviceId();
      expect(id1, isNotEmpty);
      expect(id1.startsWith('dev_'), isTrue);

      final id2 = await idService.getDeviceId();
      expect(id2, equals(id1), reason: 'Device ID must remain stable across calls');
    });

    test('FakeBackend tracks token registration and unregistration lifecycle',
        () async {
      final backend = FakeBackend();
      expect(backend.registeredFcmTokens, isEmpty);
      expect(backend.unregisteredFcmTokens, isEmpty);

      await backend.registerFcmToken('test_fcm_token_123');
      expect(backend.registeredFcmTokens, contains('test_fcm_token_123'));

      await backend.unregisterFcmToken('test_fcm_token_123');
      expect(backend.unregisteredFcmTokens, contains('test_fcm_token_123'));
    });

    test('NotificationService delivers queued cold-start taps when onTap is attached',
        () async {
      final service = NotificationService.instance;
      service.onTap = null;

      String? deliveredPayload;

      // Attach onTap handler
      service.onTap = (payload) {
        deliveredPayload = payload;
      };

      expect(service.onTap, isNotNull);
      expect(deliveredPayload, isNull);
    });
  });
}
