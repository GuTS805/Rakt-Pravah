import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/notification_service.dart';
import 'package:rakt_pravah/core/services/notification_watcher_provider.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// Registering the push token writes to the donor's profile. The app used to
// re-register on every profile update, so each registration caused the next
// one, without end: on a slow connection every pending call held a thread and
// the phone killed the app within seconds.

const _user = UserProfile(
  id: 'u1',
  name: 'Dana',
  bloodGroup: BloodGroup.aPos,
  phone: '4155550123',
);

const _on = DonorProfile(
  availability: DonorAvailability.available,
  bloodGroup: BloodGroup.aPos,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the same Donor Mode state is synced once, however often it is asked', () async {
    final service = NotificationService.instance;
    final backend = FakeBackend(user: _user, donor: _on);
    final before = service.syncRuns;
    await Future.wait([
      for (var i = 0; i < 20; i++) service.syncDeviceToken(backend, isDonorOn: true),
    ]);
    await service.syncDeviceToken(backend, isDonorOn: true);
    expect(service.syncRuns - before, lessThanOrEqualTo(1));
  });

  test('a change that arrives during a sync is not lost', () async {
    final service = NotificationService.instance;
    final backend = FakeBackend(user: _user, donor: _on);
    await service.syncDeviceToken(backend, isDonorOn: true);
    final before = service.syncRuns;
    final first = service.syncDeviceToken(backend, isDonorOn: false);
    final second = service.syncDeviceToken(backend, isDonorOn: true);
    await Future.wait([first, second]);
    await service.syncDeviceToken(backend, isDonorOn: true);
    // Off and back on again: whatever ran, it ends synced to "on" and the
    // last call, matching that, does nothing more.
    final after = service.syncRuns;
    await service.syncDeviceToken(backend, isDonorOn: true);
    expect(service.syncRuns, after);
    expect(after - before, lessThanOrEqualTo(2));
  });

  test('profile updates that leave Donor Mode alone do not re-sync', () async {
    final service = NotificationService.instance;
    final backend = FakeBackend(user: _user, donor: _on);
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => _user),
      ],
    );
    addTearDown(container.dispose);
    container.listen(notificationWatcherProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final before = service.syncRuns;

    // What a token registration looks like from here: the profile changes,
    // Donor Mode does not.
    for (var i = 0; i < 25; i++) {
      backend.emitDonor(_on.copyWith(maxDistanceKm: 10.0 + i));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(service.syncRuns, before);
  });
}
