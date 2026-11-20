import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/notification_service.dart';
import 'package:rakt_pravah/core/services/notification_watcher_provider.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// Every alert now comes from the server, so a phone must stay registered for
// as long as someone is signed in on it, whether or not they donate, and must
// stop receiving that account's pushes once they sign out.

const _user = UserProfile(
  id: 'u1',
  name: 'Dana',
  bloodGroup: BloodGroup.aPos,
  phone: '4155550123',
);

const _off = DonorProfile(
  availability: DonorAvailability.off,
  bloodGroup: BloodGroup.aPos,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a requester with Donor Mode off is registered for pushes', () async {
    final service = NotificationService.instance;
    final backend = FakeBackend(user: _user, donor: _off);
    await service.unregisterCurrentToken(backend);
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => _user),
      ],
    );
    addTearDown(container.dispose);
    container.listen(notificationWatcherProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.syncedEnabled, isTrue);
  });

  test('signing out takes the phone off the account', () async {
    final service = NotificationService.instance;
    final backend = FakeBackend(user: _user, donor: _off);
    final container = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);
    service.debugCurrentToken = 'phone-token';

    await container.read(authControllerProvider.notifier).logout();

    expect(backend.unregisteredFcmTokens, ['phone-token']);
    expect(service.currentToken, isNull);
    expect(backend.currentUser, isNull);
  });

  group('what a tap opens', () {
    final service = NotificationService.instance;

    test('a new request opens the request for the donor', () {
      expect(
        service.payloadFor({'type': 'invitation', 'requestId': 'R1'}),
        'invitation:R1',
      );
    });

    test('a chat message opens the chat, for either side', () {
      for (final type in ['request', 'chat']) {
        expect(
          service.payloadFor({'type': type, 'requestId': 'R1', 'kind': 'chat'}),
          'chat:R1',
        );
      }
    });

    test('a donor accepting opens the request for the requester', () {
      expect(
        service.payloadFor({
          'type': 'request',
          'requestId': 'R1',
          'kind': 'request',
        }),
        'request:R1',
      );
    });
  });
}
