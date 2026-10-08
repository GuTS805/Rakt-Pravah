import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/admin/admin_backend.dart';
import 'package:rakt_pravah/admin/admin_widgets.dart' show AdminFilterChip;
import 'package:rakt_pravah/admin/admin_providers.dart'
    hide adminHospitalsProvider;
import 'package:rakt_pravah/admin/screens/admin_analytics_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_availability_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_connections_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_donations_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_hospitals_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_live_map_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_notifications_screen.dart';
import 'package:rakt_pravah/admin/screens/admin_verification_screen.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';

// The operators' console screens. AdminBackend talks to Firestore, so the
// screens are fed through providers and actions go to a recording subclass.

/// An AdminBackend that records what the operator asked for.
class _Admin extends AdminBackend {
  _Admin() : super(null, actorId: 'admin1', actorName: 'Operator');

  final verifiedHospitals = <String>[];
  final deletedHospitals = <String>[];
  final addedHospitals = <Map<String, String?>>[];
  final sent = <Map<String, String>>[];

  @override
  Future<void> verifyHospital(String id) async => verifiedHospitals.add(id);

  @override
  Future<void> deleteHospital(String id) async => deletedHospitals.add(id);

  @override
  Future<void> addHospital({
    required String name,
    required String city,
    String? address,
    String? contact,
    String? state,
    String type = 'Hospital',
  }) async => addedHospitals.add({
    'name': name,
    'city': city,
    'address': address,
    'contact': contact,
  });

  @override
  Future<void> sendNotification({
    required String title,
    required String body,
    required String type,
    required String target,
  }) async => sent.add({
    'title': title,
    'body': body,
    'type': type,
    'target': target,
  });
}

AdminRequest _req(
  String id, {
  String requester = 'Riya Requester',
  RequestStatus status = RequestStatus.searching,
  Urgency urgency = Urgency.urgent,
  String? donor,
  BloodGroup group = BloodGroup.oPos,
}) => AdminRequest(
  id: id,
  requesterId: 'u-$id',
  requesterName: requester,
  bloodGroups: [group],
  units: 1,
  urgency: urgency,
  status: status,
  createdAt: DateTime.now(),
  destinationName: 'City Hospital',
  locationLabel: 'Pune',
  acceptedDonorIds: donor == null ? const [] : ['d-$id'],
  acceptedDonorName: donor,
);

AdminUser _user(
  String id,
  String name, {
  BloodGroup group = BloodGroup.oPos,
  DonorAvailability? donor,
  bool verified = false,
  DateTime? lastDonation,
  String city = 'Pune',
}) => AdminUser(
  id: id,
  name: name,
  phone: '98765${id.padLeft(5, '0')}',
  bloodGroup: group,
  isAdmin: false,
  emailVerified: verified,
  city: city,
  donorAvailability: donor,
  lastDonation: lastDonation,
);

AdminHospital _hospital(String id, String name, {bool verified = false}) =>
    AdminHospital(
      id: id,
      name: name,
      city: 'Pune',
      isVerified: verified,
      createdAt: DateTime.now(),
      address: '1 Main Road',
      contact: '020-555-0100',
    );

Future<_Admin> _pump(
  WidgetTester tester,
  Widget screen, {
  List<AdminRequest> requests = const [],
  List<AdminUser> users = const [],
  List<AdminHospital> hospitals = const [],
  List<AdminNotificationEntry> notifications = const [],
}) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final admin = _Admin();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminBackendProvider.overrideWithValue(admin),
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
        adminHospitalsProvider.overrideWith((ref) => Stream.value(hospitals)),
        adminNotificationsProvider.overrideWith(
          (ref) => Stream.value(notifications),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return admin;
}

Finder _text(String s) => find.text(s);

/// A filter chip by its label (the chip text also carries a count).
Finder _chip(String label) => find.byWidgetPredicate(
  (w) => w is AdminFilterChip && w.label == label,
  description: 'filter chip $label',
);

void main() {
  group('Hospitals', () {
    testWidgets('an empty list invites adding the first hospital', (
      tester,
    ) async {
      await _pump(tester, const AdminHospitalsScreen());
      expect(_text('Hospitals'), findsWidgets);
      expect(find.textContaining('No hospitals registered yet'), findsOneWidget);
    });

    testWidgets('counts verified and pending hospitals', (tester) async {
      await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [
          _hospital('1', 'Ruby Hall', verified: true),
          _hospital('2', 'KEM Hospital'),
          _hospital('3', 'Jehangir'),
        ],
      );
      expect(find.text('Ruby Hall'), findsOneWidget);
      expect(find.text('KEM Hospital'), findsOneWidget);
      expect(find.text('Verified'), findsWidgets);
      expect(find.text('Pending'), findsWidgets);
    });

    testWidgets('the Verified filter hides pending hospitals', (tester) async {
      await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [
          _hospital('1', 'Ruby Hall', verified: true),
          _hospital('2', 'KEM Hospital'),
        ],
      );
      await tester.tap(_chip('Verified'));
      await tester.pumpAndSettle();
      expect(find.text('Ruby Hall'), findsOneWidget);
      expect(find.text('KEM Hospital'), findsNothing);
    });

    testWidgets('search narrows the list by name', (tester) async {
      await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [_hospital('1', 'Ruby Hall'), _hospital('2', 'KEM Hospital')],
      );
      await tester.enterText(find.byType(TextField).first, 'kem');
      await tester.pumpAndSettle();
      expect(find.text('KEM Hospital'), findsOneWidget);
      expect(find.text('Ruby Hall'), findsNothing);
    });

    testWidgets('an operator can verify a pending hospital', (tester) async {
      final admin = await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [_hospital('2', 'KEM Hospital')],
      );
      await tester.tap(find.byTooltip('Verify hospital'));
      await tester.pumpAndSettle();
      expect(admin.verifiedHospitals, ['2']);
    });

    testWidgets('a verified hospital has no verify button', (tester) async {
      await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [_hospital('1', 'Ruby Hall', verified: true)],
      );
      expect(find.byTooltip('Verify hospital'), findsNothing);
    });

    testWidgets('deleting asks first, and Cancel keeps the hospital', (
      tester,
    ) async {
      final admin = await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [_hospital('1', 'Ruby Hall')],
      );
      await tester.tap(find.byTooltip('Delete hospital'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Ruby Hall?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(admin.deletedHospitals, isEmpty);
    });

    testWidgets('confirming the delete removes it', (tester) async {
      final admin = await _pump(
        tester,
        const AdminHospitalsScreen(),
        hospitals: [_hospital('1', 'Ruby Hall')],
      );
      await tester.tap(find.byTooltip('Delete hospital'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(admin.deletedHospitals, ['1']);
    });

    testWidgets('adding a hospital needs a name and a city', (tester) async {
      final admin = await _pump(tester, const AdminHospitalsScreen());
      await tester.tap(find.text('Add Hospital'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hospital Name'), 'New Care');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(admin.addedHospitals, isEmpty, reason: 'no city yet');
    });

    testWidgets('a complete hospital is added', (tester) async {
      final admin = await _pump(tester, const AdminHospitalsScreen());
      await tester.tap(find.text('Add Hospital'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hospital Name'), 'New Care');
      await tester.enterText(find.widgetWithText(TextField, 'City'), 'Pune');
      await tester.enterText(find.widgetWithText(TextField, 'Contact Number'), '020123');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(admin.addedHospitals.single['name'], 'New Care');
      expect(admin.addedHospitals.single['city'], 'Pune');
    });
  });

  group('Notifications (operator broadcast)', () {
    AdminNotificationEntry entry(String title, {String type = 'general'}) =>
        AdminNotificationEntry(
          id: title,
          title: title,
          body: 'Body of $title',
          type: type,
          target: 'all',
          sentBy: 'Operator',
          sentAt: DateTime.now(),
        );

    testWidgets('says so when nothing has been sent', (tester) async {
      await _pump(tester, const AdminNotificationsScreen());
      expect(find.text('No notifications have been sent yet.'), findsOneWidget);
    });

    testWidgets('lists sent notifications and tells emergencies apart', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminNotificationsScreen(),
        notifications: [
          entry('Drive on Sunday'),
          entry('Shortage of O-', type: 'emergency'),
        ],
      );
      expect(find.text('Drive on Sunday'), findsOneWidget);
      expect(find.text('Shortage of O-'), findsOneWidget);
      expect(find.text('Emergency'), findsWidgets);
      expect(find.text('General'), findsWidgets);
    });

    testWidgets('the Emergency filter hides general notices', (tester) async {
      await _pump(
        tester,
        const AdminNotificationsScreen(),
        notifications: [
          entry('Drive on Sunday'),
          entry('Shortage of O-', type: 'emergency'),
        ],
      );
      await tester.tap(_chip('Emergency'));
      await tester.pumpAndSettle();
      expect(find.text('Shortage of O-'), findsOneWidget);
      expect(find.text('Drive on Sunday'), findsNothing);
    });

    testWidgets('an operator can send a general notification', (tester) async {
      final admin = await _pump(tester, const AdminNotificationsScreen());
      await tester.tap(find.text('Send Notification').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Camp today');
      await tester.enterText(fields.at(1), 'Free check-up at City Hall');
      await tester.tap(find.text('Send').last);
      await tester.pumpAndSettle();
      expect(admin.sent, hasLength(1));
      expect(admin.sent.single['title'], 'Camp today');
      expect(admin.sent.single['type'], 'general');
      expect(admin.sent.single['target'], 'all');
    });

    testWidgets('an emergency alert is sent as an emergency', (tester) async {
      final admin = await _pump(tester, const AdminNotificationsScreen());
      await tester.tap(find.text('Emergency Alert').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Urgent: B- needed');
      await tester.enterText(fields.at(1), 'Please come to KEM');
      await tester.tap(find.text('Send Emergency Alert'));
      await tester.pumpAndSettle();
      expect(admin.sent.single['type'], 'emergency');
      expect(admin.sent.single['title'], 'Urgent: B- needed');
    });
  });

  group('Donor verification', () {
    final users = [
      _user('1', 'Alice', donor: DonorAvailability.available),
      _user('2', 'Bob', donor: DonorAvailability.off, verified: true),
      _user('3', 'Carol'), // no donor profile
    ];

    testWidgets('counts pending, verified and total donors', (tester) async {
      await _pump(tester, const AdminVerificationScreen(), users: users);
      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.text('Total Donors'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // two donors in total
    });

    testWidgets('people with no donor profile are not listed', (tester) async {
      await _pump(tester, const AdminVerificationScreen(), users: users);
      await tester.tap(_chip('All Donors'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
    });

    testWidgets('the Pending tab shows only unverified donors', (tester) async {
      await _pump(tester, const AdminVerificationScreen(), users: users);
      await tester.tap(_chip('Pending'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('an empty pending queue says so', (tester) async {
      await _pump(
        tester,
        const AdminVerificationScreen(),
        users: [_user('2', 'Bob', donor: DonorAvailability.off, verified: true)],
      );
      await tester.tap(_chip('Pending'));
      await tester.pumpAndSettle();
      expect(find.text('No donors pending verification.'), findsOneWidget);
    });

    testWidgets('search finds a donor by name', (tester) async {
      await _pump(tester, const AdminVerificationScreen(), users: users);
      await tester.tap(_chip('All Donors'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'bob');
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });
  });

  group('Connections', () {
    final reqs = [
      _req('1', requester: 'Riya', donor: 'Dev', status: RequestStatus.coordinating),
      _req('2', requester: 'Sam', donor: 'Dana', status: RequestStatus.fulfilled),
      _req('3', requester: 'Tia'), // nobody accepted yet
    ];

    testWidgets('reports active, coordinating and completed pairs', (
      tester,
    ) async {
      await _pump(tester, const AdminConnectionsScreen(), requests: reqs);
      expect(find.text('Active connections'), findsOneWidget);
      expect(find.text('Coordinating'), findsWidgets);
      expect(find.text('Completed'), findsWidgets);
    });

    testWidgets('the All tab lists only requests that have a donor', (
      tester,
    ) async {
      await _pump(tester, const AdminConnectionsScreen(), requests: reqs);
      await tester.tap(_chip('All'));
      await tester.pumpAndSettle();
      expect(find.text('Riya'), findsWidgets);
      expect(find.text('Sam'), findsWidgets);
      expect(find.text('Tia'), findsNothing);
    });

    testWidgets('the Completed tab shows only finished donations', (
      tester,
    ) async {
      await _pump(tester, const AdminConnectionsScreen(), requests: reqs);
      await tester.tap(_chip('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsWidgets);
      expect(find.text('Riya'), findsNothing);
    });

    testWidgets('an empty view says so', (tester) async {
      await _pump(tester, const AdminConnectionsScreen());
      expect(find.text('No connections match this view.'), findsOneWidget);
    });
  });

  group('Donations', () {
    testWidgets('shows the lifecycle from request to completion', (
      tester,
    ) async {
      await _pump(tester, const AdminDonationsScreen());
      for (final step in ['Request', 'Match', 'Accept', 'Coordinate', 'Complete']) {
        expect(find.text(step), findsWidgets, reason: step);
      }
    });

    testWidgets('counts active, completed and matched donations', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminDonationsScreen(),
        requests: [
          _req('1', donor: 'Dev', status: RequestStatus.donorAccepted),
          _req('2', donor: 'Dana', status: RequestStatus.fulfilled),
          _req('3'),
        ],
      );
      expect(find.text('Active donations'), findsOneWidget);
      expect(find.text('Total matched'), findsOneWidget);
    });
  });

  group('Availability', () {
    testWidgets('has a row for every blood group', (tester) async {
      await _pump(tester, const AdminAvailabilityScreen());
      for (final g in BloodGroup.values) {
        expect(find.text(g.label), findsWidgets, reason: g.label);
      }
      expect(find.text('Component Status Breakdown'), findsOneWidget);
    });

    testWidgets('a group with demand and no donors is a deficit', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminAvailabilityScreen(),
        requests: [_req('1', group: BloodGroup.bNeg)],
        users: [_user('1', 'Alice', donor: DonorAvailability.available)],
      );
      expect(find.text('Deficit'), findsOneWidget);
    });

    testWidgets('a group with more donors than demand is adequate', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminAvailabilityScreen(),
        users: [
          _user('1', 'Alice', donor: DonorAvailability.available),
          _user('2', 'Bob', donor: DonorAvailability.available),
        ],
      );
      expect(find.text('Adequate'), findsOneWidget);
    });

    testWidgets('a donor in the waiting period is not counted as ready', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminAvailabilityScreen(),
        users: [
          _user(
            '1',
            'Alice',
            donor: DonorAvailability.available,
            lastDonation: DateTime.now().subtract(const Duration(days: 5)),
          ),
        ],
      );
      expect(find.text('1 Donors'), findsNothing);
    });
  });

  group('Analytics and live map', () {
    testWidgets('analytics totals users, donors, requests and fulfilled', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminAnalyticsScreen(),
        users: [
          _user('1', 'Alice', donor: DonorAvailability.available),
          _user('2', 'Bob'),
        ],
        requests: [
          _req('1', status: RequestStatus.fulfilled, donor: 'Dev'),
          _req('2'),
          _req('3'),
        ],
      );
      expect(find.text('Total Users'), findsWidgets);
      expect(find.text('Registered Donors'), findsWidgets);
      expect(find.text('Total Requests'), findsWidgets);
      expect(find.text('Fulfilled'), findsWidgets);
      expect(find.text('Request Status Breakdown'), findsOneWidget);
      expect(find.text('Users by City'), findsOneWidget);
    });

    testWidgets('analytics copes with no data at all', (tester) async {
      await _pump(tester, const AdminAnalyticsScreen());
      expect(find.text('Analytics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the live map screen renders with requests and donors', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdminLiveMapScreen(),
        users: [_user('1', 'Alice', donor: DonorAvailability.available)],
        requests: [_req('1'), _req('2', urgency: Urgency.critical)],
      );
      expect(find.text('Live Operational Map'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
