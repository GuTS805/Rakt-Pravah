import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/home/donor_status_card.dart';
import 'package:rakt_pravah/features/home/home_screen.dart';
import 'package:rakt_pravah/features/invitations/invitation_detail_screen.dart';

import 'fakes.dart';

// Real screens, driven against an in-memory backend. These are the tests that
// replace poking at a physical device for everything: the donor checks, the
// donation cooldown, and what Home actually shows in each state.

/// A complete adult profile unless told otherwise. [age] of null leaves the
/// birth date out, like an account created before registration asked for it.
UserProfile _user({
  int? age = 30,
  Gender? gender = Gender.male,
  String name = 'Alok Sharma',
  BloodGroup group = BloodGroup.oPos,
  String? city,
}) => UserProfile(
  id: 'u1',
  name: name,
  bloodGroup: group,
  phone: '9876543210',
  dateOfBirth: age == null
      ? null
      : DateTime.now().subtract(Duration(days: age * 366)),
  gender: gender,
  city: city,
);

Invitation _invitation({String id = 'r9'}) => Invitation(
  id: id,
  requestId: id,
  bloodGroups: const [BloodGroup.oPos],
  units: 1,
  urgency: Urgency.critical,
  distanceKm: 2.4,
  status: InvitationStatus.pending,
  destinationName: 'City Hospital',
  destinationArea: 'MG Road',
  createdAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 5)),
  patientBloodGroup: BloodGroup.oPos,
);

BloodRequest _request({
  String id = 'r1',
  RequestStatus status = RequestStatus.searching,
  List<BloodGroup>? groups,
  int units = 2,
}) => BloodRequest(
  id: id,
  requesterId: 'u1',
  requesterName: 'Alok Sharma',
  bloodGroups: groups ?? [BloodGroup.oPos],
  units: units,
  urgency: Urgency.critical,
  status: status,
  createdAt: DateTime.now(),
  destination: const Destination(name: 'City Hospital', address: 'MG Road'),
  requestLocationLabel: 'Bengaluru',
);

/// Boots a screen with the fake backend wired in, plus a router carrying just
/// enough routes for the gate to have somewhere to send people.
Widget _app({
  required FakeBackend backend,
  required Widget screen,
  UserProfile? user,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: Routes.profileEdit,
        builder: (_, _) => const Scaffold(body: Text('PROFILE EDIT SCREEN')),
      ),
      GoRoute(
        path: '/requests/:id/coordination',
        builder: (_, _) => const Scaffold(body: Text('COORDINATION SCREEN')),
      ),
      GoRoute(
        path: Routes.createRequest,
        builder: (_, _) => const Scaffold(body: Text('CREATE REQUEST SCREEN')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      backendProvider.overrideWithValue(backend),
      currentUserProvider.overrideWithValue(user),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

/// A request in `searching` shows an indeterminate progress spinner, which
/// never stops animating — `pumpAndSettle` would wait forever. Pump a couple
/// of frames instead: enough for the streams to deliver and the UI to rebuild.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// The default 800x600 test surface cuts Home off partway down, and a ListView
/// never builds its off-screen children — so anything below the fold is simply
/// absent from the tree and unfindable. A tall phone-shaped viewport keeps the
/// whole screen in play.
void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('donor checks', () {
    testWidgets('an account without a birth date is sent to its profile', (
      tester,
    ) async {
      final user = _user(age: null);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE EDIT SCREEN'), findsOneWidget);
      expect(backend.setDonorProfileCalls, isEmpty);
    });

    testWidgets('someone under 18 cannot switch Donor Mode on', (tester) async {
      final user = _user(age: 16);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.textContaining('must be 18 to 65'), findsOneWidget);
      expect(backend.setDonorProfileCalls, isEmpty);
    });

    testWidgets('an adult with a complete profile can switch Donor Mode on', (
      tester,
    ) async {
      final user = _user();
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE EDIT SCREEN'), findsNothing);
      expect(backend.setDonorProfileCalls, hasLength(1));
      expect(
        backend.setDonorProfileCalls.single.availability,
        DonorAvailability.available,
      );
    });

    testWidgets('switching Donor Mode off is never blocked', (tester) async {
      final user = _user(age: null, gender: null);
      final backend = FakeBackend(
        user: user,
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
        ),
      );
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        find.text('PROFILE EDIT SCREEN'),
        findsNothing,
        reason: 'turning off is a safety action, never blocked',
      );
      expect(
        backend.setDonorProfileCalls.single.availability,
        DonorAvailability.off,
      );
    });
  });

  group('accepting a request', () {
    Future<FakeBackend> openInvitation(
      WidgetTester tester, {
      Gender gender = Gender.male,
    }) async {
      _useTallPhone(tester);
      final user = _user(gender: gender);
      final backend = FakeBackend(user: user, invitations: [_invitation()]);
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const InvitationDetailScreen(invitationId: 'r9'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept & help'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('asks the health questions before accepting', (tester) async {
      final backend = await openInvitation(tester);

      expect(find.text('Before you accept'), findsOneWidget);
      expect(find.textContaining('HIV'), findsOneWidget);
      expect(
        backend.invitationResponses,
        isEmpty,
        reason: 'nothing is accepted until the questions are answered',
      );
    });

    testWidgets('men are not asked about pregnancy', (tester) async {
      await openInvitation(tester);
      expect(find.textContaining('pregnant'), findsNothing);
    });

    testWidgets('women are asked about pregnancy', (tester) async {
      await openInvitation(tester, gender: Gender.female);
      expect(find.textContaining('pregnant'), findsOneWidget);
    });

    testWidgets('any yes answer stops the acceptance', (tester) async {
      final backend = await openInvitation(tester);

      final noChips = find.text('No');
      final count = noChips.evaluate().length;
      for (var i = 1; i < count; i++) {
        await tester.tap(noChips.at(i));
      }
      await tester.tap(find.text('Yes').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('3 months between donations'), findsOneWidget);
      await tester.tap(find.text('I can\'t donate this time'));
      await tester.pumpAndSettle();

      expect(backend.invitationResponses, isEmpty);
    });

    testWidgets('all no answers accept and open coordination', (tester) async {
      final backend = await openInvitation(tester);

      final noChips = find.text('No');
      final count = noChips.evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(noChips.at(i));
      }
      await tester.pumpAndSettle();
      // The sheet's own button, not the screen's one underneath it.
      await tester.tap(find.text('Accept & help').last);
      await tester.pumpAndSettle();

      expect(backend.invitationResponses, [('r9', InvitationStatus.accepted)]);
      expect(find.text('COORDINATION SCREEN'), findsOneWidget);
    });
  });

  group('donation cooldown in the UI', () {
    testWidgets('a donor inside the 90-day window cannot re-enable', (
      tester,
    ) async {
      final user = _user();
      final backend = FakeBackend(
        user: user,
        donor: DonorProfile(
          availability: DonorAvailability.off,
          bloodGroup: BloodGroup.oPos,
          lastDonation: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(
        toggle.onChanged,
        isNull,
        reason: 'the switch must be frozen during cooldown',
      );
      expect(find.textContaining('Eligible in'), findsOneWidget);
      expect(
        find.textContaining('Resting after your last donation'),
        findsOneWidget,
      );
    });

    testWidgets('a donor past the cooldown can enable again', (tester) async {
      final user = _user();
      final backend = FakeBackend(
        user: user,
        donor: DonorProfile(
          availability: DonorAvailability.off,
          bloodGroup: BloodGroup.oPos,
          lastDonation: DateTime.now().subtract(const Duration(days: 120)),
        ),
      );
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: const Scaffold(body: DonorStatusCard()),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.onChanged, isNotNull);
      expect(find.textContaining('Eligible in'), findsNothing);
    });
  });

  group('home screen', () {
    testWidgets('idle state leads with the emergency card', (tester) async {
      final user = _user();
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('A little help'), findsOneWidget);
      expect(find.text('Need blood now?'), findsOneWidget);
      expect(find.text('Create blood request'), findsOneWidget);
    });

    testWidgets('an active request takes over the headline', (tester) async {
      final user = _user();
      _useTallPhone(tester);
      final backend = FakeBackend(user: user, requests: [_request()]);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await _pumpFrames(tester);

      expect(find.text('Your request is live.'), findsOneWidget);
      expect(find.textContaining('A little help'), findsNothing);
      expect(find.text('Your active request'), findsOneWidget);
      expect(
        find.textContaining('Searching for nearby donors'),
        findsOneWidget,
      );
    });

    testWidgets('a fulfilled request is not treated as active', (tester) async {
      final user = _user();
      final backend = FakeBackend(
        user: user,
        requests: [_request(status: RequestStatus.fulfilled)],
      );
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your active request'), findsNothing);
      expect(
        find.textContaining('A little help'),
        findsOneWidget,
        reason: 'a finished request should return Home to its idle state',
      );
    });

    testWidgets('the stats strip reports real counts and blood group', (
      tester,
    ) async {
      final user = _user(group: BloodGroup.bNeg);
      final backend = FakeBackend(
        user: user,
        requests: [
          _request(id: 'r1'),
          _request(id: 'r2'),
        ],
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.bNeg,
          totalDonations: 3,
        ),
      );
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await _pumpFrames(tester);

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Donations'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Your type'), findsOneWidget);
      expect(find.text('B-'), findsWidgets);
    });

    testWidgets('Home reacts live when a request arrives', (tester) async {
      final user = _user();
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your active request'), findsNothing);

      backend.emitRequests([_request()]);
      await _pumpFrames(tester);

      expect(
        find.text('Your active request'),
        findsOneWidget,
        reason: 'the stream should drive the UI without a manual refresh',
      );
    });

    testWidgets('anyone can start a request, even without donor details', (
      tester,
    ) async {
      final user = _user(age: null, gender: null);
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
        _app(backend: backend, user: user, screen: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create blood request'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE REQUEST SCREEN'), findsOneWidget);
    });
  });
}
