import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/core/services/donor_gate.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/backend.dart';
import 'package:rakt_pravah/data/backend_error.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/home/donor_status_card.dart';
import 'package:rakt_pravah/core/widgets/invitation_card.dart';
import 'package:rakt_pravah/core/widgets/profile_card.dart';
import 'package:rakt_pravah/core/widgets/request_card.dart';
import 'package:rakt_pravah/features/auth/login_screen.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';
import 'package:rakt_pravah/features/requests/requests_screen.dart';
import 'package:rakt_pravah/features/shell/app_shell.dart';
import 'package:rakt_pravah/features/auth/verify_phone_screen.dart';
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
  bool phoneVerified = true,
}) => UserProfile(
  id: 'u1',
  name: name,
  bloodGroup: group,
  phone: '9876543210',
  phoneVerified: phoneVerified,
  dateOfBirth: age == null
      ? null
      : DateTime.now().subtract(Duration(days: age * 366)),
  gender: gender,
  city: city,
);

Invitation _invitation({
  String id = 'r9',
  InvitationStatus status = InvitationStatus.pending,
  RequestStatus requestStatus = RequestStatus.searching,
}) => Invitation(
  id: id,
  requestId: id,
  requesterId: 'RDTEnCpXsUTImKqDY8iEY93Lgwg2',
  requesterName: 'Ravi Kumar',
  bloodGroups: const [BloodGroup.oPos],
  units: 1,
  urgency: Urgency.critical,
  distanceKm: 2.4,
  requestStatus: requestStatus,
  status: status,
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
      GoRoute(
        path: Routes.verifyPhone,
        builder: (_, _) => const VerifyPhoneScreen(),
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
  group('request and invitation cards', () {
    Future<void> show(
      WidgetTester tester,
      Widget card, {
      FakeBackend? backend,
    }) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(
          backend: backend ?? FakeBackend(user: _user()),
          user: _user(),
          screen: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: card),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
    }

    Finder inPhoto(Finder f) =>
        find.descendant(of: find.byKey(ProfileCard.photoKey), matching: f);
    Finder inDetails(Finder f) =>
        find.descendant(of: find.byKey(ProfileCard.detailsKey), matching: f);

    testWidgets('the requester is a round photo on the left of the name', (
      tester,
    ) async {
      await show(tester, RequestCard(request: _request()));

      final photo = tester.getRect(find.byKey(ProfileCard.photoKey));
      expect(photo.width, photo.height, reason: 'it is a circle');
      expect(
        tester.getRect(find.text('Alok Sharma')).left,
        greaterThan(photo.right),
      );
    });

    testWidgets('without a photo the requester shows their initials', (
      tester,
    ) async {
      await show(tester, RequestCard(request: _request()));

      expect(inDetails(find.text('Alok Sharma')), findsOneWidget);
      expect(inPhoto(find.text('AS')), findsOneWidget);
    });

    testWidgets('a request you sent shows the patient, the id and the rest', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user())
        ..patientNames['r1'] = 'Sita Devi';
      await show(tester, RequestCard(request: _request()), backend: backend);

      expect(inDetails(find.text('Requesting for Sita Devi')), findsOneWidget);
      expect(inDetails(find.text('ID RP-U1')), findsOneWidget);
      expect(inDetails(find.text('City Hospital')), findsOneWidget);
      expect(inDetails(find.text('MG Road')), findsOneWidget);
      expect(inDetails(find.text('Critical')), findsOneWidget);
      expect(inDetails(find.text('Searching')), findsOneWidget);
    });

    testWidgets('an invitation shows who is asking and their id', (
      tester,
    ) async {
      await show(tester, InvitationCard(invitation: _invitation()));

      expect(inDetails(find.text('Ravi Kumar')), findsOneWidget);
      expect(inDetails(find.text('ID RP-RDTENC')), findsOneWidget);
      expect(inDetails(find.text('City Hospital')), findsOneWidget);
      expect(inDetails(find.text('2.4 km')), findsOneWidget);
    });

    testWidgets('the patient name is held back until you accept', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user())
        ..patientNames['r9'] = 'Sita Devi';
      await show(
        tester,
        InvitationCard(invitation: _invitation()),
        backend: backend,
      );

      expect(
        find.text('Sita Devi'),
        findsNothing,
        reason: 'a donor who has not accepted is not allowed to read it',
      );
      expect(find.text('Name shown after you accept'), findsOneWidget);
    });

    testWidgets('once you accept, the patient name appears', (tester) async {
      final backend = FakeBackend(user: _user())
        ..patientNames['r9'] = 'Sita Devi';
      await show(
        tester,
        InvitationCard(
          invitation: _invitation(status: InvitationStatus.accepted),
        ),
        backend: backend,
      );

      expect(inDetails(find.text('Requesting for Sita Devi')), findsOneWidget);
      expect(find.text('Name shown after you accept'), findsNothing);
      expect(find.text('You accepted this request'), findsOneWidget);
    });

    testWidgets('accept and decline run across the whole card', (tester) async {
      await show(
        tester,
        InvitationCard(
          invitation: _invitation(),
          onAccept: () {},
          onDecline: () {},
        ),
      );

      final card = tester.getSize(find.byType(ProfileCard)).width;
      final accept = tester.getRect(find.text('Accept'));
      final decline = tester.getRect(find.text('Decline'));
      expect(decline.left, lessThan(accept.left));
      expect(
        accept.right - decline.left,
        greaterThan(card * 0.4),
        reason: 'the buttons run across the card',
      );
    });
  });

  group('requests page', () {
    testWidgets('invitations are on the left and my requests on the right', (
      tester,
    ) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(
          backend: FakeBackend(user: _user()),
          user: _user(),
          screen: const RequestsScreen(),
        ),
      );
      await _pumpFrames(tester);

      final invitations = tester.getCenter(find.text('Invitations')).dx;
      final mine = tester.getCenter(find.text('My requests')).dx;
      expect(invitations, lessThan(mine));
    });

    testWidgets('it still opens on my requests', (tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(
          backend: FakeBackend(user: _user(), requests: [_request()]),
          user: _user(),
          screen: const RequestsScreen(),
        ),
      );
      await _pumpFrames(tester);

      expect(find.byType(RequestCard), findsOneWidget);

      await tester.tap(find.text('Invitations'));
      await _pumpFrames(tester);
      expect(find.byType(RequestCard), findsNothing);
      expect(find.text('Donor Mode is off'), findsOneWidget);
    });

    testWidgets('requests and invitations both arrive as cards', (
      tester,
    ) async {
      _useTallPhone(tester);
      final backend = FakeBackend(
        user: _user(),
        requests: [_request()],
        invitations: [_invitation()],
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
        ),
      );
      await tester.pumpWidget(
        _app(backend: backend, user: _user(), screen: const RequestsScreen()),
      );
      await _pumpFrames(tester);

      expect(find.byType(ProfileCard), findsOneWidget);
      await tester.tap(find.text('Invitations'));
      await _pumpFrames(tester);
      expect(find.byType(InvitationCard), findsOneWidget);
      expect(find.byType(ProfileCard), findsOneWidget);
    });
  });

  group('requests in progress', () {
    Future<int> processingFor(FakeBackend backend) async {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(backend),
          currentUserProvider.overrideWithValue(_user()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(myRequestsProvider.future);
      await container.read(invitationsProvider.future);
      return container.read(processingCountProvider);
    }

    test('counts what you asked for that is not finished', () async {
      final backend = FakeBackend(
        user: _user(),
        requests: [
          _request(id: 'a'),
          _request(id: 'b', status: RequestStatus.coordinating),
          _request(id: 'c', status: RequestStatus.fulfilled),
          _request(id: 'd', status: RequestStatus.cancelled),
        ],
      );
      expect(await processingFor(backend), 2);
    });

    test('counts donations you agreed to that are not finished', () async {
      final backend = FakeBackend(
        user: _user(),
        invitations: [
          _invitation(id: 'a', status: InvitationStatus.accepted),
          _invitation(
            id: 'b',
            status: InvitationStatus.accepted,
            requestStatus: RequestStatus.fulfilled,
          ),
          _invitation(id: 'c'),
        ],
      );
      expect(
        await processingFor(backend),
        1,
        reason:
            'a finished donation and an unanswered invitation are not '
            'in progress',
      );
    });

    test('adds the two together', () async {
      final backend = FakeBackend(
        user: _user(),
        requests: [_request()],
        invitations: [_invitation(status: InvitationStatus.accepted)],
      );
      expect(await processingFor(backend), 2);
    });

    test('is zero when nothing is going on', () async {
      expect(await processingFor(FakeBackend(user: _user())), 0);
    });

    testWidgets('the Requests tab shows the number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              currentIndex: 0,
              onTap: (_) {},
              requestsBadge: 3,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the Requests badge is blue and the Donate badge is red', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              currentIndex: 0,
              onTap: (_) {},
              requestsBadge: 2,
              donateBadge: 5,
            ),
          ),
        ),
      );

      final colors = tester.element(find.byType(AppBottomNavigation)).colors;
      Color? badgeColor(String count) {
        final box = tester.widget<Container>(
          find
              .ancestor(of: find.text(count), matching: find.byType(Container))
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(
        badgeColor('2'),
        colors.info,
        reason: 'requests in progress are underway, not waiting on you',
      );
      expect(
        badgeColor('5'),
        colors.brand,
        reason: 'a pending invitation is waiting for you to act',
      );
    });

    testWidgets('the Requests tab shows nothing when nothing is in progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('0'), findsNothing);
    });
  });

  group('invitations follow the donor settings', () {
    Future<(ProviderContainer, FakeBackend)> start() async {
      final backend = FakeBackend(
        user: _user(),
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
          maxDistanceKm: 15,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(backend),
          currentUserProvider.overrideWithValue(_user()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(invitationsProvider, (_, _) {});
      await container.read(invitationsProvider.future);
      return (container, backend);
    }

    test('a new range rebuilds the invitation query', () async {
      final (container, backend) = await start();
      final before = backend.invitationsStreamReads;

      backend.emitDonor(
        container.read(donorProfileValueProvider).copyWith(maxDistanceKm: 30),
      );
      await container.pump();

      expect(backend.invitationsStreamReads, before + 1);
    });

    test('an unrelated donor change does not', () async {
      final (container, backend) = await start();
      final before = backend.invitationsStreamReads;

      backend.emitDonor(
        container.read(donorProfileValueProvider).copyWith(notifyPush: false),
      );
      await container.pump();

      expect(backend.invitationsStreamReads, before);
    });
  });

  group('request detail', () {
    testWidgets('a request open to every group still lays out on a phone', (
      tester,
    ) async {
      // An ordinary phone, 411 logical pixels wide.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeBackend(
        user: _user(),
        requests: [_request(groups: BloodGroup.values.toList())],
      )..patientNames['r1'] = 'Sita Devi';
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: _user(),
          screen: const RequestDetailScreen(requestId: 'r1'),
        ),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final units = tester.getSize(find.text('2 units'));
      expect(units.width, greaterThan(50), reason: 'not one letter per line');
      expect(units.height, lessThan(40));
    });
  });

  group('invitation detail', () {
    testWidgets('a request open to every group still lays out on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inv = Invitation(
        id: 'r9',
        requestId: 'r9',
        requesterId: 'RDTEnCpXsUTImKqDY8iEY93Lgwg2',
        requesterName: 'Ravi Kumar',
        bloodGroups: BloodGroup.values.toList(),
        units: 1,
        urgency: Urgency.urgent,
        distanceKm: 2.0,
        status: InvitationStatus.pending,
        destinationName: 'City Hospital',
        destinationArea: 'MG Road',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 5)),
        patientBloodGroup: BloodGroup.abPos,
      );
      await tester.pumpWidget(
        _app(
          backend: FakeBackend(user: _user(), invitations: [inv]),
          user: _user(),
          screen: const InvitationDetailScreen(invitationId: 'r9'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final units = tester.getSize(find.text('1 unit'));
      expect(units.width, greaterThan(50), reason: 'not one letter per line');
      expect(units.height, lessThan(40));
    });
  });

  group('phone verification', () {
    Future<void> openHome(
      WidgetTester tester,
      FakeBackend backend, {
      UserProfile? user,
    }) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        _app(backend: backend, user: user ?? _user(phoneVerified: false), screen: const HomeScreen()),
      );
      await _pumpFrames(tester);
    }

    Future<bool?> tryDonorCheck(
      WidgetTester tester,
      FakeBackend backend,
      UserProfile user,
    ) async {
      bool? allowed;
      await tester.pumpWidget(
        _app(
          backend: backend,
          user: user,
          screen: Consumer(
            builder: (context, ref, _) {
              ref.watch(canActProvider); // the app shell does this
              return Scaffold(
                body: TextButton(
                  onPressed: () => allowed = requireDonorProfile(context, ref),
                  child: const Text('try'),
                ),
              );
            },
          ),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.text('try'));
      await _pumpFrames(tester);
      return allowed;
    }

    testWidgets('a verified account sees no banner and can request', (
      tester,
    ) async {
      await openHome(
        tester,
        FakeBackend(user: _user(phoneVerified: true)),
        user: _user(phoneVerified: true),
      );

      expect(find.text('Verify your phone number'), findsNothing);
      await tester.tap(find.text('Create blood request'));
      await _pumpFrames(tester);
      expect(find.text('CREATE REQUEST SCREEN'), findsOneWidget);
    });

    testWidgets('an unverified account is asked to verify before requesting', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);

      expect(find.text('Verify your phone number'), findsOneWidget);
      await tester.tap(find.text('Create blood request'));
      await _pumpFrames(tester);

      expect(find.text('CREATE REQUEST SCREEN'), findsNothing);
      expect(find.text('Verify phone number'), findsOneWidget);
    });

    testWidgets('the texted code verifies the number and unlocks requesting', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);

      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      // The number given at registration is already filled in.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '9876543210',
      );

      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);
      expect(backend.phoneCodesSentTo, ['+919876543210']);
      expect(find.textContaining('+91 98765 43210'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify'));
      await _pumpFrames(tester);

      expect(find.text('Phone number verified.'), findsOneWidget);
      expect(backend.currentUser!.phoneVerified, isTrue);
      expect(find.text('Verify your phone number'), findsNothing);

      await tester.tap(find.text('Create blood request'));
      await _pumpFrames(tester);
      expect(find.text('CREATE REQUEST SCREEN'), findsOneWidget);
    });

    testWidgets('a wrong code is explained and nothing is verified', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Verify'));
      await _pumpFrames(tester);

      expect(find.textContaining('That code is wrong'), findsOneWidget);
      expect(backend.currentUser!.phoneVerified, isFalse);
      expect(find.text('Verify phone number'), findsOneWidget);
    });

    testWidgets('a short code is caught before it is checked', (tester) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Verify'));
      await _pumpFrames(tester);

      expect(find.text('Enter the 6-digit code from the SMS.'), findsOneWidget);
    });

    testWidgets('a code that cannot be sent says why', (tester) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))
        ..emitCanAct(false)
        ..sendPhoneCodeError = const PhoneVerificationFailure(
          'Phone verification isn\'t switched on for this app yet.',
        );
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      expect(
        find.text('Phone verification isn\'t switched on for this app yet.'),
        findsOneWidget,
      );
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('a mistyped number can be corrected before resending', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      await tester.tap(find.text('Change number'));
      await _pumpFrames(tester);
      await tester.enterText(find.byType(TextFormField), '9123456789');
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      expect(backend.phoneCodesSentTo, ['+919876543210', '+919123456789']);
    });

    testWidgets('resending waits 30 seconds', (tester) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      expect(find.text('Resend code in 30s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.tap(find.text('Resend code'));
      await _pumpFrames(tester);

      expect(backend.phoneCodesSentTo, hasLength(2));
    });

    testWidgets('when Android reads the SMS itself, no code is needed', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))
        ..emitCanAct(false)
        ..verifyWithoutCode = true;
      await openHome(tester, backend);
      await tester.tap(find.text('Verify your phone number'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Send code'));
      await _pumpFrames(tester);

      expect(find.text('Phone number verified.'), findsOneWidget);
      expect(backend.currentUser!.phoneVerified, isTrue);
    });

    testWidgets('an unverified account cannot turn Donor Mode on or accept', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user(phoneVerified: false))..emitCanAct(false);
      final allowed = await tryDonorCheck(tester, backend, _user(phoneVerified: false));

      expect(allowed, isFalse);
      expect(find.text('Verify phone number'), findsOneWidget);
    });

    testWidgets('a verified account the console switched off is told so', (
      tester,
    ) async {
      final user = _user(phoneVerified: true);
      final backend = FakeBackend(user: user)..emitCanAct(false);
      final allowed = await tryDonorCheck(tester, backend, user);

      expect(allowed, isFalse);
      expect(find.textContaining('switched off'), findsOneWidget);
      expect(find.text('Verify phone number'), findsNothing);
    });

    testWidgets('once verified the same donor check passes', (tester) async {
      final user = _user(phoneVerified: true);
      final allowed = await tryDonorCheck(tester, FakeBackend(user: user), user);

      expect(allowed, isTrue);
    });
  });

  group('signing in', () {
    Future<FakeBackend> signIn(
      WidgetTester tester, {
      required String password,
    }) async {
      final backend = FakeBackend()..passwords['alok@example.com'] = 'hunter22';
      await tester.pumpWidget(
        _app(backend: backend, screen: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'alok@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, password);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a wrong password is refused', (tester) async {
      final backend = await signIn(tester, password: 'not-it');

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(
        backend.currentUser,
        isNull,
        reason: 'nobody is signed in after a failed attempt',
      );
    });

    testWidgets('the right password signs in', (tester) async {
      final backend = await signIn(tester, password: 'hunter22');

      expect(find.text('Wrong email or password.'), findsNothing);
      expect(backend.currentUser?.email, 'alok@example.com');
    });

    testWidgets('a reset link never says whether the account exists', (
      tester,
    ) async {
      final backend = FakeBackend();
      await tester.pumpWidget(
        _app(backend: backend, screen: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'stranger@example.com',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(backend.passwordResetEmails, ['stranger@example.com']);
      expect(
        find.textContaining('If stranger@example.com has an account'),
        findsOneWidget,
      );
    });

    testWidgets('a reset link that could not be sent says so', (tester) async {
      final backend = FakeBackend()..passwordResetError = Exception('offline');
      await tester.pumpWidget(
        _app(backend: backend, screen: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address first.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).first,
        'stranger@example.com',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address first.'), findsNothing);
      expect(find.textContaining("Couldn't send the reset link"), findsOneWidget);
      expect(find.textContaining('has an account'), findsNothing);
    });
  });

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

    /// Answers the health questions with No and confirms.
    Future<void> confirmAccept(WidgetTester tester) async {
      final noChips = find.text('No');
      final count = noChips.evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(noChips.at(i));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept & help').last);
      await tester.pumpAndSettle();
    }

    testWidgets('losing the race says someone else accepted', (tester) async {
      final backend = await openInvitation(tester);
      backend.invitationResponseError = StateError('This request is no longer available.');
      await confirmAccept(tester);

      expect(find.text('Someone else already accepted this request.'), findsOneWidget);
      expect(find.text('COORDINATION SCREEN'), findsNothing);
    });

    testWidgets('a slow or unreachable server is not blamed on another donor', (tester) async {
      final backend = await openInvitation(tester);
      const reason = 'No connection. Check your internet and try again.';
      backend.invitationResponseError = const BackendUnavailable(reason);
      await confirmAccept(tester);

      expect(find.text(reason), findsOneWidget);
      expect(find.textContaining('Someone else'), findsNothing);
      expect(find.text('Accept & help'), findsOneWidget, reason: 'stays on the request so it can be retried');
    });

    testWidgets('any other failure also stays put with a plain message', (tester) async {
      final backend = await openInvitation(tester);
      backend.invitationResponseError = Exception('boom');
      await confirmAccept(tester);

      expect(find.text("Couldn't accept the request. Try again."), findsOneWidget);
      expect(find.textContaining('Someone else'), findsNothing);
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
