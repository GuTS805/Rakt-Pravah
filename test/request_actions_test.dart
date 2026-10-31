import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/coordination_screen.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';

import 'fakes.dart';

// What the two people on a request can do to it: the requester cancels,
// closes or reopens it, the donor can back out, and a finished request
// offers nothing more.

const _requester = UserProfile(
  id: 'requester-1',
  name: 'Riya Requester',
  bloodGroup: BloodGroup.oPos,
  phone: '9876543210',
);

const _donor = UserProfile(
  id: 'donor-1',
  name: 'Dana Donor',
  bloodGroup: BloodGroup.aPos,
  phone: '4155550123',
  countryCode: '+1',
);

BloodRequest _request(
  RequestStatus status, {
  bool withDonor = false,
}) => BloodRequest(
  id: 'r1',
  requesterId: _requester.id,
  requesterName: _requester.name,
  patientName: 'Sunil',
  patientBloodGroup: BloodGroup.aPos,
  bloodGroups: const [BloodGroup.aPos],
  units: 1,
  urgency: Urgency.urgent,
  status: status,
  createdAt: DateTime.now(),
  phone: '501234567',
  phoneCountryCode: '+971',
  destination: const Destination(
    name: 'City Hospital',
    address: 'FC Road, Pune',
    location: GeoPoint(18.52, 73.85),
  ),
  requestLocationLabel: 'Pune',
  acceptedDonors: withDonor
      ? [
          AcceptedDonor(
            id: _donor.id,
            name: _donor.name,
            phone: _donor.phone,
            phoneCountryCode: _donor.countryCode,
            acceptedAt: DateTime.now(),
          ),
        ]
      : const [],
);

/// The request screens run looping animations, so pumpAndSettle never ends;
/// advance a fixed amount of time instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _FailingWithdraw extends FakeBackend {
  _FailingWithdraw({super.user, super.requests});
  @override
  Future<void> withdrawFromRequest(String id) async => throw StateError('offline');
}

Future<FakeBackend> _pump(
  WidgetTester tester, {
  required UserProfile as_,
  required BloodRequest request,
  required Widget Function(String id) screen,
  FakeBackend? backend,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final b = backend ?? FakeBackend(user: as_, requests: [request]);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => const Scaffold(body: Text('BACK AT START'))),
      GoRoute(path: Routes.donate, builder: (_, _) => const Scaffold(body: Text('DONATE TAB'))),
      GoRoute(path: '/requests/:id', builder: (_, s) => screen(s.pathParameters['id']!)),
      GoRoute(path: '/requests/:id/coordination', builder: (_, s) => screen(s.pathParameters['id']!)),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(b),
        currentUserProvider.overrideWith((ref) => as_),
        requestProvider(request.id).overrideWith((ref) => Stream.value(request)),
        patientNameProvider(request.id).overrideWith((ref) => Stream.value('Sunil')),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  router.push('/requests/${request.id}');
  await _settle(tester);
  return b;
}

Future<FakeBackend> _detail(WidgetTester t, BloodRequest r) =>
    _pump(t, as_: _requester, request: r, screen: (id) => RequestDetailScreen(requestId: id));

Future<FakeBackend> _coord(
  WidgetTester t,
  UserProfile as_,
  BloodRequest r, {
  FakeBackend? backend,
}) => _pump(
  t,
  as_: as_,
  request: r,
  backend: backend,
  screen: (id) => CoordinationScreen(requestId: id),
);

void main() {
  group('request detail (the requester)', () {
    testWidgets('a request still searching can only be cancelled', (tester) async {
      await _detail(tester, _request(RequestStatus.searching));
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('Mark fulfilled'), findsNothing);
      expect(find.text('Open coordination'), findsNothing);
    });

    testWidgets('cancelling asks first; Keep leaves the request alone', (tester) async {
      final b = await _detail(tester, _request(RequestStatus.searching));
      await tester.tap(find.text('Cancel request'));
      await _settle(tester);
      expect(find.text('Cancel this request?'), findsOneWidget);
      expect(find.textContaining('Donors will stop being contacted'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await _settle(tester);
      expect(b.cancelledRequestIds, isEmpty);
    });

    testWidgets('confirming cancels the request', (tester) async {
      final b = await _detail(tester, _request(RequestStatus.searching));
      await tester.tap(find.text('Cancel request'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
      await _settle(tester);
      expect(b.cancelledRequestIds, ['r1']);
    });

    testWidgets('once a donor accepted: open coordination, cancel or fulfil', (tester) async {
      await _detail(tester, _request(RequestStatus.donorAccepted, withDonor: true));
      expect(find.text('Open coordination'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mark fulfilled'), findsOneWidget);
    });

    testWidgets('cancelling after acceptance warns the donor will be told', (tester) async {
      await _detail(tester, _request(RequestStatus.donorAccepted, withDonor: true));
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(find.textContaining('Dana Donor will be told not to come'), findsOneWidget);
    });

    testWidgets('marking fulfilled asks first, then closes the request', (tester) async {
      final b = await _detail(tester, _request(RequestStatus.coordinating, withDonor: true));
      await tester.tap(find.text('Mark fulfilled'));
      await _settle(tester);
      expect(find.text('Mark as fulfilled?'), findsOneWidget);
      expect(b.fulfilledRequestIds, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Mark fulfilled'));
      await _settle(tester);
      expect(b.fulfilledRequestIds, ['r1']);
    });

    testWidgets('an expired request can be searched again', (tester) async {
      final b = await _detail(tester, _request(RequestStatus.expired));
      await tester.tap(find.text('Search again for 6 more hours'));
      await _settle(tester);
      expect(b.extendedRequestIds, ['r1']);
    });

    for (final s in [RequestStatus.fulfilled, RequestStatus.cancelled, RequestStatus.removedByAdmin]) {
      testWidgets('a ${s.label.toLowerCase()} request offers no actions', (tester) async {
        await _detail(tester, _request(s));
        expect(find.text('Cancel request'), findsNothing);
        expect(find.text('Mark fulfilled'), findsNothing);
        expect(find.text('Search again for 6 more hours'), findsNothing);
      });
    }
  });

  group('coordination (requester)', () {
    final accepted = _request(RequestStatus.coordinating, withDonor: true);

    testWidgets('can mark the request fulfilled and is taken back', (tester) async {
      final b = await _coord(tester, _requester, accepted);
      await tester.ensureVisible(find.text('Mark request fulfilled'));
      await tester.tap(find.text('Mark request fulfilled'));
      await _settle(tester);
      expect(b.fulfilledRequestIds, ['r1']);
      expect(find.text('BACK AT START'), findsOneWidget);
    });

    testWidgets('can cancel after confirming', (tester) async {
      final b = await _coord(tester, _requester, accepted);
      await tester.ensureVisible(find.text('Cancel request'));
      await tester.tap(find.text('Cancel request'));
      await _settle(tester);
      expect(find.textContaining('Dana Donor will be told not to come'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
      await _settle(tester);
      expect(b.cancelledRequestIds, ['r1']);
    });

    testWidgets('the requester is not offered "I can\'t make it"', (tester) async {
      await _coord(tester, _requester, accepted);
      expect(find.text('I can\'t make it'), findsNothing);
    });
  });

  group('coordination (donor)', () {
    final accepted = _request(RequestStatus.coordinating, withDonor: true);

    testWidgets('the donor can back out, after confirming', (tester) async {
      final b = await _coord(tester, _donor, accepted);
      await tester.ensureVisible(find.text('I can\'t make it'));
      await tester.tap(find.text('I can\'t make it'));
      await _settle(tester);
      expect(find.text('Can\'t make it?'), findsOneWidget);
      expect(b.withdrawnRequestIds, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'I can\'t make it'));
      await _settle(tester);
      expect(b.withdrawnRequestIds, ['r1']);
      expect(find.text('DONATE TAB'), findsOneWidget);
    });

    testWidgets('Keep leaves the donor on the request', (tester) async {
      final b = await _coord(tester, _donor, accepted);
      await tester.ensureVisible(find.text('I can\'t make it'));
      await tester.tap(find.text('I can\'t make it'));
      await _settle(tester);
      await tester.tap(find.text('Keep'));
      await _settle(tester);
      expect(b.withdrawnRequestIds, isEmpty);
      expect(find.text('Coordination'), findsOneWidget);
    });

    testWidgets('a failure to withdraw is reported and the donor stays', (tester) async {
      final backend = _FailingWithdraw(user: _donor, requests: [accepted]);
      await _coord(tester, _donor, accepted, backend: backend);
      await tester.ensureVisible(find.text('I can\'t make it'));
      await tester.tap(find.text('I can\'t make it'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'I can\'t make it'));
      await _settle(tester);
      expect(find.text('Couldn\'t update. Try again.'), findsOneWidget);
      expect(find.text('DONATE TAB'), findsNothing);
    });

    testWidgets('the donor is not offered fulfil or cancel', (tester) async {
      await _coord(tester, _donor, accepted);
      expect(find.text('Mark request fulfilled'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
    });
  });

  group('coordination on a finished request', () {
    testWidgets('a fulfilled request says thank you and offers nothing', (tester) async {
      await _coord(tester, _donor, _request(RequestStatus.fulfilled, withDonor: true));
      await tester.ensureVisible(find.text('This request is fulfilled. Thank you.'));
      expect(find.text('This request is fulfilled. Thank you.'), findsOneWidget);
      expect(find.text('I can\'t make it'), findsNothing);
    });

    testWidgets('a cancelled request tells the donor not to go', (tester) async {
      await _coord(tester, _donor, _request(RequestStatus.cancelled, withDonor: true));
      await tester.ensureVisible(find.textContaining('No need to go to the hospital'));
      expect(find.textContaining('was cancelled'), findsOneWidget);
      expect(find.text('I can\'t make it'), findsNothing);
    });

    testWidgets('an expired request tells the donor not to go', (tester) async {
      await _coord(tester, _donor, _request(RequestStatus.expired, withDonor: true));
      await tester.ensureVisible(find.textContaining('No need to go to the hospital'));
      expect(find.textContaining('was expired'), findsOneWidget);
    });
  });
}
