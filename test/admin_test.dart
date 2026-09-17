import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloodlink/admin/admin_backend.dart';
import 'package:bloodlink/admin/admin_providers.dart';
import 'package:bloodlink/admin/admin_screens.dart';
import 'package:bloodlink/core/theme/app_theme.dart';
import 'package:bloodlink/data/models/models.dart';
import 'package:bloodlink/data/providers.dart';

// The console is desktop-only and table-driven, so these run on a wide
// surface. AdminBackend itself talks to Firestore; the screens read through
// providers, so the providers are what gets overridden here.

AdminRequest _req({
  String id = 'r1',
  String requester = 'Alok Sharma',
  RequestStatus status = RequestStatus.searching,
  Urgency urgency = Urgency.critical,
  String? donor,
  DateTime? createdAt,
  DateTime? expiresAt,
}) => AdminRequest(
  id: id,
  requesterId: 'u1',
  requesterName: requester,
  bloodGroups: [BloodGroup.oPos],
  units: 2,
  urgency: urgency,
  status: status,
  createdAt: createdAt ?? DateTime.now(),
  destinationName: 'City Hospital',
  locationLabel: 'Bengaluru',
  acceptedDonorIds: donor == null ? const [] : const ['d1'],
  acceptedDonorName: donor,
  expiresAt: expiresAt,
);

AdminUser _user({
  String id = 'u1',
  String name = 'Alok Sharma',
  bool isAdmin = false,
  DonorAvailability? donor,
  DateTime? lastDonation,
  int donations = 0,
  String? email,
}) => AdminUser(
  id: id,
  name: name,
  phone: '9876543210',
  bloodGroup: BloodGroup.oPos,
  isAdmin: isAdmin,
  emailVerified: email != null,
  email: email,
  donorAvailability: donor,
  totalDonations: donations,
  lastDonation: lastDonation,
);

Widget _console({
  required Widget screen,
  List<AdminRequest> requests = const [],
  List<AdminUser> users = const [],
  List<AdminReport> reports = const [],
  List<AuditEntry> audit = const [],
}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(
      const UserProfile(
        id: 'admin1',
        name: 'Operator',
        bloodGroup: BloodGroup.oPos,
        phone: '9000000000',
        isAdmin: true,
      ),
    ),
    adminRequestsProvider.overrideWith((ref) => Stream.value(requests)),
    adminUsersProvider.overrideWith((ref) => Stream.value(users)),
    adminReportsProvider.overrideWith((ref) => Stream.value(reports)),
    adminAuditProvider.overrideWith((ref) => Stream.value(audit)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: screen),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('AdminStats', () {
    test('counts open, unmatched and stale separately', () {
      final stats = AdminStats.from([
        _req(id: 'a'), // searching, unmatched, open
        _req(id: 'b', donor: 'Aman', status: RequestStatus.coordinating),
        _req(id: 'c', status: RequestStatus.fulfilled, donor: 'Aman'),
        _req(
          id: 'd',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ), // open but past expiry
      ]);

      expect(stats.total, 4);
      expect(stats.open, 3, reason: 'fulfilled is terminal');
      expect(stats.unmatched, 2, reason: 'a and d have no donor');
      expect(stats.stale, 1, reason: 'only d is past expiry');
      expect(stats.coordinating, 1);
      expect(stats.fulfilled, 1);
    });

    test('a terminal request is never stale, even if long expired', () {
      final stats = AdminStats.from([
        _req(
          status: RequestStatus.cancelled,
          expiresAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ]);
      expect(stats.stale, 0);
      expect(stats.open, 0);
    });

    test('critical counts only open requests', () {
      final stats = AdminStats.from([
        _req(id: 'a', urgency: Urgency.critical),
        _req(
          id: 'b',
          urgency: Urgency.critical,
          status: RequestStatus.fulfilled,
          donor: 'Aman',
        ),
        _req(id: 'c', urgency: Urgency.routine),
      ]);
      expect(stats.critical, 1);
    });
  });

  group('attention queue', () {
    test('puts stale before unmatched, and critical before routine', () {
      final container = ProviderContainer(
        overrides: [
          adminRequestsProvider.overrideWith(
            (ref) => Stream.value([
              _req(id: 'routine-unmatched', urgency: Urgency.routine),
              _req(
                id: 'stale',
                urgency: Urgency.routine,
                expiresAt: DateTime.now().subtract(const Duration(hours: 2)),
              ),
              _req(id: 'critical-unmatched', urgency: Urgency.critical),
              _req(
                id: 'matched',
                donor: 'Aman',
                status: RequestStatus.coordinating,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Let the stream deliver.
      container.listen(adminRequestsProvider, (_, _) {});
      return Future(() {
        final queue = container.read(adminAttentionQueueProvider);
        expect(queue.map((r) => r.id).toList(), [
          'stale',
          'critical-unmatched',
          'routine-unmatched',
        ]);
        expect(
          queue.any((r) => r.id == 'matched'),
          isFalse,
          reason: 'a request with a donor needs no attention',
        );
      });
    });
  });

  group('AdminRequest flags', () {
    test('isStale needs both an expiry in the past and an open status', () {
      expect(_req(expiresAt: null).isStale, isFalse);
      expect(
        _req(expiresAt: DateTime.now().add(const Duration(hours: 1))).isStale,
        isFalse,
      );
      expect(
        _req(expiresAt: DateTime.now().subtract(const Duration(hours: 1)))
            .isStale,
        isTrue,
      );
    });

    test('isUnmatched is false once a donor accepts', () {
      expect(_req().isUnmatched, isTrue);
      expect(_req(donor: 'Aman').isUnmatched, isFalse);
    });
  });

  group('AdminUser', () {
    test('cooldown mirrors the 90-day donation rule', () {
      expect(
        _user(lastDonation: DateTime.now().subtract(const Duration(days: 10)))
            .isInCooldown,
        isTrue,
      );
      expect(
        _user(lastDonation: DateTime.now().subtract(const Duration(days: 120)))
            .isInCooldown,
        isFalse,
      );
      expect(_user().isInCooldown, isFalse);
    });

    test('donor is on for available and paused, off otherwise', () {
      expect(_user(donor: DonorAvailability.available).isDonorOn, isTrue);
      expect(_user(donor: DonorAvailability.paused).isDonorOn, isTrue);
      expect(_user(donor: DonorAvailability.off).isDonorOn, isFalse);
      expect(_user().isDonorOn, isFalse);
    });
  });

  group('Dashboard', () {
    testWidgets('surfaces the operational counts', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminDashboardScreen(),
          requests: [
            _req(id: 'a'),
            _req(id: 'b', donor: 'Aman', status: RequestStatus.coordinating),
            _req(
              id: 'c',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Open requests'), findsOneWidget);
      expect(find.text('Awaiting a donor'), findsOneWidget);
      expect(find.text('Past expiry'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
    });

    testWidgets('says so plainly when nothing is stuck', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminDashboardScreen(),
          requests: [
            _req(id: 'b', donor: 'Aman', status: RequestStatus.coordinating),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Nothing is stuck'), findsOneWidget);
    });
  });

  group('Requests screen', () {
    testWidgets('filters the table by status', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminRequestsScreen(),
          requests: [
            _req(id: 'a', requester: 'Searching Person'),
            _req(
              id: 'b',
              requester: 'Fulfilled Person',
              status: RequestStatus.fulfilled,
              donor: 'Aman',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Searching Person'), findsOneWidget);
      expect(find.text('Fulfilled Person'), findsOneWidget);

      await tester.tap(find.textContaining('Fulfilled  1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Fulfilled Person'), findsOneWidget);
      expect(find.text('Searching Person'), findsNothing);
    });
  });

  group('Moderation', () {
    testWidgets('lists only requests an operator can still act on', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminModerationScreen(),
          requests: [
            _req(id: 'open', requester: 'Open Person'),
            _req(
              id: 'done',
              requester: 'Finished Person',
              status: RequestStatus.fulfilled,
              donor: 'Aman',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Open Person'), findsWidgets);
      expect(find.text('Remove'), findsWidgets);
      expect(
        find.text('Finished Person'),
        findsNothing,
        reason: 'a closed request cannot be moderated, so it is not listed',
      );
    });

    testWidgets('removal asks for a reason before doing anything', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminModerationScreen(),
          requests: [_req(id: 'open')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();

      expect(find.text('Remove this request?'), findsOneWidget);
      expect(find.widgetWithText(TextField, ''), findsWidgets);
      expect(find.textContaining('recorded in the audit log'), findsOneWidget);
    });
  });

  group('Users screen', () {
    testWidgets('shows donor state, cooldown and donation count', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminUsersScreen(),
          users: [
            _user(
              id: 'u1',
              name: 'Available Donor',
              donor: DonorAvailability.available,
              donations: 4,
            ),
            _user(
              id: 'u2',
              name: 'Resting Donor',
              donor: DonorAvailability.available,
              lastDonation: DateTime.now().subtract(const Duration(days: 5)),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Available Donor'), findsOneWidget);
      expect(find.text('Resting Donor'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Cooldown'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('honest empty states', () {
    testWidgets('Reports explains why it is empty', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_console(screen: const AdminReportsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('no Report screen yet'), findsOneWidget);
    });

    testWidgets('Audit log explains what will appear there', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_console(screen: const AdminAuditScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('No administrative actions'), findsOneWidget);
    });
  });

  group('System Health', () {
    testWidgets('flags an empty donor pool as a problem', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminHealthScreen(),
          requests: [_req()],
          users: [_user(donor: DonorAvailability.off)],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.textContaining('No donors have Donor Mode on'),
        findsOneWidget,
      );
    });

    testWidgets('reports a healthy queue when nothing is overdue', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _console(
          screen: const AdminHealthScreen(),
          requests: [_req(donor: 'Aman', status: RequestStatus.coordinating)],
          users: [_user(donor: DonorAvailability.available)],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('inside its window'), findsOneWidget);
      expect(
        find.textContaining('donor(s) currently available'),
        findsOneWidget,
      );
    });
  });
}
