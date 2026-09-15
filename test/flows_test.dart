import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bloodlink/core/router/routes.dart';
import 'package:bloodlink/core/theme/app_theme.dart';
import 'package:bloodlink/data/models/models.dart';
import 'package:bloodlink/data/providers.dart';
import 'package:bloodlink/features/home/donor_status_card.dart';
import 'package:bloodlink/features/home/home_screen.dart';

import 'fakes.dart';

// Real screens, driven against an in-memory backend. These are the tests that
// replace poking at a physical device for everything: the verification gate,
// the donation cooldown, and what Home actually shows in each state.

UserProfile _user({
  bool verified = false,
  String name = 'Alok Sharma',
  BloodGroup group = BloodGroup.oPos,
  String? city,
}) =>
    UserProfile(
      id: 'u1',
      name: name,
      bloodGroup: group,
      phone: '9876543210',
      email: verified ? 'alok@example.com' : null,
      emailVerified: verified,
      city: city,
    );

BloodRequest _request({
  String id = 'r1',
  RequestStatus status = RequestStatus.searching,
  List<BloodGroup>? groups,
  int units = 2,
}) =>
    BloodRequest(
      id: id,
      requesterId: 'u1',
      requesterName: 'Alok Sharma',
      bloodGroups: groups ?? [BloodGroup.oPos],
      units: units,
      urgency: Urgency.critical,
      status: status,
      createdAt: DateTime.now(),
      destination:
          const Destination(name: 'City Hospital', address: 'MG Road'),
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
        path: Routes.verifyEmail,
        builder: (_, _) => const Scaffold(body: Text('VERIFY EMAIL SCREEN')),
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
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
    ),
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
  group('verification gate', () {
    testWidgets('an unverified user cannot switch Donor Mode on',
        (tester) async {
      final backend = FakeBackend(user: _user());
      await tester.pumpWidget(_app(
        backend: backend,
        user: _user(),
        screen: const Scaffold(body: DonorStatusCard()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY EMAIL SCREEN'), findsOneWidget,
          reason: 'the gate should route to verification');
      expect(backend.setDonorProfileCalls, isEmpty,
          reason: 'Donor Mode must not be enabled before verification');
    });

    testWidgets('a verified user can switch Donor Mode on', (tester) async {
      final user = _user(verified: true);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(_app(
        backend: backend,
        user: user,
        screen: const Scaffold(body: DonorStatusCard()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY EMAIL SCREEN'), findsNothing);
      expect(backend.setDonorProfileCalls, hasLength(1));
      expect(backend.setDonorProfileCalls.single.availability,
          DonorAvailability.available);
    });

    testWidgets('switching Donor Mode off is never gated', (tester) async {
      final user = _user();
      final backend = FakeBackend(
        user: user,
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
        ),
      );
      await tester.pumpWidget(_app(
        backend: backend,
        user: user,
        screen: const Scaffold(body: DonorStatusCard()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY EMAIL SCREEN'), findsNothing,
          reason: 'turning off is a safety action, never blocked');
      expect(backend.setDonorProfileCalls.single.availability,
          DonorAvailability.off);
    });
  });

  group('donation cooldown in the UI', () {
    testWidgets('a donor inside the 90-day window cannot re-enable',
        (tester) async {
      final user = _user(verified: true);
      final backend = FakeBackend(
        user: user,
        donor: DonorProfile(
          availability: DonorAvailability.off,
          bloodGroup: BloodGroup.oPos,
          lastDonation: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      await tester.pumpWidget(_app(
        backend: backend,
        user: user,
        screen: const Scaffold(body: DonorStatusCard()),
      ));
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.onChanged, isNull,
          reason: 'the switch must be frozen during cooldown');
      expect(find.textContaining('Eligible in'), findsOneWidget);
      expect(find.textContaining('Resting after your last donation'),
          findsOneWidget);
    });

    testWidgets('a donor past the cooldown can enable again', (tester) async {
      final user = _user(verified: true);
      final backend = FakeBackend(
        user: user,
        donor: DonorProfile(
          availability: DonorAvailability.off,
          bloodGroup: BloodGroup.oPos,
          lastDonation: DateTime.now().subtract(const Duration(days: 120)),
        ),
      );
      await tester.pumpWidget(_app(
        backend: backend,
        user: user,
        screen: const Scaffold(body: DonorStatusCard()),
      ));
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.onChanged, isNotNull);
      expect(find.textContaining('Eligible in'), findsNothing);
    });
  });

  group('home screen', () {
    testWidgets('idle state leads with the emergency card', (tester) async {
      final user = _user(verified: true);
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('A little help'), findsOneWidget);
      expect(find.text('Need blood now?'), findsOneWidget);
      expect(find.text('Create blood request'), findsOneWidget);
    });

    testWidgets('an active request takes over the headline', (tester) async {
      final user = _user(verified: true);
      _useTallPhone(tester);
      final backend = FakeBackend(user: user, requests: [_request()]);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await _pumpFrames(tester);

      expect(find.text('Your request is live.'), findsOneWidget);
      expect(find.textContaining('A little help'), findsNothing);
      expect(find.text('Your active request'), findsOneWidget);
      expect(find.textContaining('Searching for nearby donors'), findsOneWidget);
    });

    testWidgets('a fulfilled request is not treated as active', (tester) async {
      final user = _user(verified: true);
      final backend = FakeBackend(
        user: user,
        requests: [_request(status: RequestStatus.fulfilled)],
      );
      _useTallPhone(tester);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Your active request'), findsNothing);
      expect(find.textContaining('A little help'), findsOneWidget,
          reason: 'a finished request should return Home to its idle state');
    });

    testWidgets('the stats strip reports real counts and blood group',
        (tester) async {
      final user = _user(verified: true, group: BloodGroup.bNeg);
      final backend = FakeBackend(
        user: user,
        requests: [_request(id: 'r1'), _request(id: 'r2')],
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.bNeg,
          totalDonations: 3,
        ),
      );
      _useTallPhone(tester);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await _pumpFrames(tester);

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Donations'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Your type'), findsOneWidget);
      expect(find.text('B-'), findsWidgets);
    });

    testWidgets('Home reacts live when a request arrives', (tester) async {
      final user = _user(verified: true);
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Your active request'), findsNothing);

      backend.emitRequests([_request()]);
      await _pumpFrames(tester);

      expect(find.text('Your active request'), findsOneWidget,
          reason: 'the stream should drive the UI without a manual refresh');
    });

    testWidgets('an unverified user is gated out of creating a request',
        (tester) async {
      final user = _user();
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create blood request'));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY EMAIL SCREEN'), findsOneWidget);
      expect(find.text('CREATE REQUEST SCREEN'), findsNothing);
    });

    testWidgets('a verified user reaches the create request screen',
        (tester) async {
      final user = _user(verified: true);
      _useTallPhone(tester);
      final backend = FakeBackend(user: user);
      await tester.pumpWidget(
          _app(backend: backend, user: user, screen: const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create blood request'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE REQUEST SCREEN'), findsOneWidget);
    });
  });
}
