import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';

import 'fakes.dart';

// Signing out and into another account on the same phone must not keep
// showing (or writing back) the previous person's donor data and requests.

class _CountingBackend extends FakeBackend {
  _CountingBackend({super.user});

  int donorSubscriptions = 0;
  int requestSubscriptions = 0;

  @override
  Stream<DonorProfile> get donorStream {
    donorSubscriptions++;
    return super.donorStream;
  }

  @override
  Stream<List<BloodRequest>> get myRequestsStream {
    requestSubscriptions++;
    return super.myRequestsStream;
  }
}

const _ravi = UserProfile(
  id: 'ravi',
  name: 'Ravi',
  bloodGroup: BloodGroup.bPos,
  phone: '9999999991',
);
const _priya = UserProfile(
  id: 'priya',
  name: 'Priya',
  bloodGroup: BloodGroup.aPos,
  phone: '9999999992',
);

void main() {
  test('a different account gets fresh donor and request streams', () async {
    final backend = _CountingBackend(user: _ravi);
    final who = StateProvider<UserProfile?>((ref) => _ravi);
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => ref.watch(who)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(donorProfileProvider, (_, _) {});
    container.listen(myRequestsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(backend.donorSubscriptions, 1);
    expect(backend.requestSubscriptions, 1);

    // Sign out, then into Priya's account.
    backend.currentUser = null;
    container.read(who.notifier).state = null;
    await Future<void>.delayed(Duration.zero);
    backend.currentUser = _priya;
    container.read(who.notifier).state = _priya;
    await Future<void>.delayed(Duration.zero);

    expect(backend.donorSubscriptions, 2);
    expect(backend.requestSubscriptions, 2);
  });

  test('signed out, no one\'s donor data is streamed', () async {
    final backend = _CountingBackend();
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);
    container.listen(donorProfileProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(backend.donorSubscriptions, 0);
  });
}
