import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/chat_screen.dart';
import 'package:rakt_pravah/features/notifications/notifications_screen.dart';
import 'package:rakt_pravah/features/profile/history_screen.dart';

import 'fakes.dart';

// The screens that tell a person what is happening: notifications, request
// and donation history, and the private chat between requester and donor.

const _me = UserProfile(
  id: 'me',
  name: 'Maya Requester',
  bloodGroup: BloodGroup.oPos,
  phone: '9876543210',
);

BloodRequest _request({
  String id = 'r1',
  RequestStatus status = RequestStatus.searching,
  String requesterId = 'me',
  String requesterName = 'Maya Requester',
  List<BloodGroup> groups = const [BloodGroup.aPos, BloodGroup.oPos],
  List<AcceptedDonor> donors = const [],
  int contacted = 0,
}) => BloodRequest(
  id: id,
  requesterId: requesterId,
  requesterName: requesterName,
  patientName: 'Patient',
  patientBloodGroup: BloodGroup.aPos,
  bloodGroups: groups,
  units: 1,
  urgency: Urgency.urgent,
  status: status,
  createdAt: DateTime.now(),
  donorsContacted: contacted,
  destination: const Destination(name: 'City Hospital', address: 'Pune'),
  requestLocationLabel: 'Pune',
  acceptedDonors: donors,
);

Invitation _invitation({
  String id = 'inv1',
  InvitationStatus status = InvitationStatus.pending,
  double? km = 3.5,
}) => Invitation(
  id: id,
  requestId: id,
  requesterId: 'someone',
  requesterName: 'Sam',
  bloodGroups: const [BloodGroup.oPos],
  units: 2,
  urgency: Urgency.critical,
  distanceKm: km,
  status: status,
  destinationName: 'Ruby Hall',
  destinationArea: 'Pune',
  createdAt: DateTime.now(),
);

Widget _host(
  FakeBackend backend,
  Widget screen, {
  List<Override> overrides = const [],
  Map<String, String> routes = const {},
}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      for (final e in routes.entries)
        GoRoute(
          path: e.key,
          builder: (_, _) => Scaffold(body: Text(e.value)),
        ),
    ],
  );
  return ProviderScope(
    overrides: [
      backendProvider.overrideWithValue(backend),
      currentUserProvider.overrideWith((ref) => backend.currentUser),
      ...overrides,
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void main() {
  group('Notifications', () {
    Future<void> pump(
      WidgetTester tester, {
      List<BloodRequest> requests = const [],
      List<Invitation> invitations = const [],
      Map<String, String> routes = const {},
    }) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _host(
          FakeBackend(user: _me, requests: requests, invitations: invitations),
          const NotificationsScreen(),
          routes: routes,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says you are caught up when there is nothing', (tester) async {
      await pump(tester);
      expect(find.text('You\'re all caught up'), findsOneWidget);
    });

    testWidgets('a request still searching reports how many were contacted', (
      tester,
    ) async {
      await pump(tester, requests: [_request(contacted: 7)]);
      expect(find.text('Searching for donors'), findsOneWidget);
      expect(
        find.text('7 donors contacted for your A+/O+ request.'),
        findsOneWidget,
      );
    });

    testWidgets('an accepted request names the donor who accepted', (
      tester,
    ) async {
      await pump(
        tester,
        requests: [
          _request(
            status: RequestStatus.donorAccepted,
            donors: [
              AcceptedDonor(
                id: 'd1',
                name: 'Dana Donor',
                acceptedAt: DateTime.now(),
              ),
            ],
          ),
        ],
      );
      expect(
        find.text('Your blood request has been accepted by a donor'),
        findsOneWidget,
      );
      expect(find.textContaining('Dana Donor has accepted'), findsOneWidget);
    });

    testWidgets('a finished request makes no notification', (tester) async {
      await pump(
        tester,
        requests: [
          _request(status: RequestStatus.fulfilled),
          _request(id: 'r2', status: RequestStatus.cancelled),
        ],
      );
      expect(find.text('You\'re all caught up'), findsOneWidget);
    });

    testWidgets('a pending invitation shows the distance, groups and units', (
      tester,
    ) async {
      await pump(tester, invitations: [_invitation()]);
      expect(find.text('New donor invitation'), findsOneWidget);
      expect(find.text('O+ · 2 units · 3.5 km away.'), findsOneWidget);
    });

    testWidgets('without a distance the hospital is named instead', (
      tester,
    ) async {
      await pump(tester, invitations: [_invitation(km: null)]);
      expect(find.text('O+ · 2 units · Ruby Hall.'), findsOneWidget);
    });

    testWidgets('an invitation already accepted is not a new notification', (
      tester,
    ) async {
      await pump(
        tester,
        invitations: [_invitation(status: InvitationStatus.accepted)],
      );
      expect(find.text('New donor invitation'), findsNothing);
    });

    testWidgets('tapping an invitation opens it', (tester) async {
      await pump(
        tester,
        invitations: [_invitation()],
        routes: {'/invitations/inv1': 'INVITATION PAGE'},
      );
      await tester.tap(find.text('New donor invitation'));
      await tester.pumpAndSettle();
      expect(find.text('INVITATION PAGE'), findsOneWidget);
    });

    testWidgets('tapping a request update opens that request', (tester) async {
      await pump(
        tester,
        requests: [_request()],
        routes: {'/requests/r1': 'REQUEST PAGE'},
      );
      await tester.tap(find.text('Searching for donors'));
      await tester.pumpAndSettle();
      expect(find.text('REQUEST PAGE'), findsOneWidget);
    });

    testWidgets('the newest update comes first', (tester) async {
      await pump(
        tester,
        requests: [_request()],
        invitations: [_invitation()],
      );
      final invite = tester.getTopLeft(find.text('New donor invitation')).dy;
      final search = tester.getTopLeft(find.text('Searching for donors')).dy;
      expect(invite, lessThan(search));
    });
  });

  group('History', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool donations,
      List<BloodRequest> requests = const [],
      List<Invitation> invitations = const [],
    }) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _host(
          FakeBackend(user: _me, requests: requests, invitations: invitations),
          HistoryScreen(donations: donations),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the request history is titled and empty at first', (
      tester,
    ) async {
      await pump(tester, donations: false);
      expect(find.text('Request history'), findsOneWidget);
      expect(find.text('No requests yet'), findsOneWidget);
    });

    testWidgets('past requests are listed, finished ones included', (
      tester,
    ) async {
      await pump(
        tester,
        donations: false,
        requests: [
          _request(id: 'a'),
          _request(id: 'b', status: RequestStatus.fulfilled),
        ],
      );
      expect(find.text('No requests yet'), findsNothing);
      expect(find.text('Fulfilled'), findsWidgets);
    });

    testWidgets('the donation history is titled and empty at first', (
      tester,
    ) async {
      await pump(tester, donations: true);
      expect(find.text('Donation history'), findsOneWidget);
      expect(find.text('No donations yet'), findsOneWidget);
    });

    testWidgets('only requests you accepted count as donations', (
      tester,
    ) async {
      await pump(
        tester,
        donations: true,
        invitations: [
          _invitation(id: 'a', status: InvitationStatus.accepted),
          _invitation(id: 'b', status: InvitationStatus.declined),
          _invitation(id: 'c'),
        ],
      );
      expect(find.text('Ruby Hall'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });

  group('Chat', () {
    ChatMessage msg(
      String id,
      String from,
      String text, {
      bool pending = false,
      bool failed = false,
    }) => ChatMessage(
      id: id,
      requestId: 'r1',
      senderId: from,
      senderName: from,
      text: text,
      sentAt: DateTime.now(),
      pending: pending,
      failed: failed,
    );

    Future<FakeBackend> pump(
      WidgetTester tester, {
      required UserProfile as_,
      List<ChatMessage> messages = const [],
      BloodRequest? request,
    }) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final r =
          request ??
          _request(
            donors: [
              AcceptedDonor(
                id: 'donor-1',
                name: 'Dana Donor',
                acceptedAt: DateTime.now(),
              ),
            ],
          );
      final backend = FakeBackend(user: as_, requests: [r]);
      await tester.pumpWidget(
        _host(
          backend,
          const ChatScreen(requestId: 'r1'),
          overrides: [
            chatProvider('r1').overrideWith((ref) => Stream.value(messages)),
            requestProvider('r1').overrideWith((ref) => Stream.value(r)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    const donor = UserProfile(
      id: 'donor-1',
      name: 'Dana Donor',
      bloodGroup: BloodGroup.aPos,
      phone: '4155550123',
    );

    testWidgets('an empty conversation invites the first message', (
      tester,
    ) async {
      await pump(tester, as_: _me);
      expect(find.text('Start the conversation'), findsOneWidget);
    });

    testWidgets('the requester sees the donor\'s name in the header', (
      tester,
    ) async {
      await pump(tester, as_: _me);
      expect(find.text('Dana Donor'), findsOneWidget);
      expect(find.text('Direct chat'), findsOneWidget);
    });

    testWidgets('the donor sees the requester\'s name in the header', (
      tester,
    ) async {
      await pump(tester, as_: donor);
      expect(find.text('Maya Requester'), findsOneWidget);
    });

    testWidgets('messages from both sides are shown', (tester) async {
      await pump(
        tester,
        as_: _me,
        messages: [
          msg('1', 'me', 'Are you on your way?'),
          msg('2', 'donor-1', 'Yes, 10 minutes'),
        ],
      );
      expect(find.text('Are you on your way?'), findsOneWidget);
      expect(find.text('Yes, 10 minutes'), findsOneWidget);
      expect(find.text('Start the conversation'), findsNothing);
    });

    testWidgets('my own messages sit on the right, theirs on the left', (
      tester,
    ) async {
      await pump(
        tester,
        as_: _me,
        messages: [msg('1', 'me', 'mine'), msg('2', 'donor-1', 'theirs')],
      );
      final mine = tester.getTopRight(find.text('mine')).dx;
      final theirs = tester.getTopLeft(find.text('theirs')).dx;
      expect(mine, greaterThan(tester.view.physicalSize.width / 2));
      expect(theirs, lessThan(tester.view.physicalSize.width / 2));
    });

    testWidgets('a message still sending shows a clock, a failed one an error', (
      tester,
    ) async {
      await pump(
        tester,
        as_: _me,
        messages: [
          msg('1', 'me', 'sending', pending: true),
          msg('2', 'me', 'broken', failed: true),
          msg('3', 'me', 'sent'),
        ],
      );
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    });

    testWidgets('sending trims the text, clears the box and calls the backend', (
      tester,
    ) async {
      final backend = await pump(tester, as_: _me);
      await tester.enterText(find.byType(TextField), '  hello there  ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(backend.sentMessages, ['hello there']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    });

    testWidgets('pressing enter on the keyboard sends too', (tester) async {
      final backend = await pump(tester, as_: _me);
      await tester.enterText(find.byType(TextField), 'on enter');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(backend.sentMessages, ['on enter']);
    });

    testWidgets('an empty or blank message is never sent', (tester) async {
      final backend = await pump(tester, as_: _me);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.enterText(find.byType(TextField), '    ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(backend.sentMessages, isEmpty);
    });
  });
}
