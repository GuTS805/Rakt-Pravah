import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rakt_pravah/admin/admin_backend.dart';
import 'package:rakt_pravah/admin/admin_providers.dart';
import 'package:rakt_pravah/admin/admin_screens.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';

AdminRequest _mockReq({
  String id = 'req-1',
  String requester = 'Rahul Verma',
  RequestStatus status = RequestStatus.searching,
  Urgency urgency = Urgency.critical,
  String? donor,
}) =>
    AdminRequest(
      id: id,
      requesterId: 'u1',
      requesterName: requester,
      bloodGroups: [BloodGroup.oNeg, BloodGroup.oPos],
      units: 2,
      urgency: urgency,
      status: status,
      createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
      destinationName: 'Apollo Hospital Bengaluru',
      locationLabel: 'Bannerghatta Road, Bengaluru',
      acceptedDonorIds: donor == null ? const [] : const ['d1'],
      acceptedDonorName: donor,
      declinedCount: 3,
    );

AdminUser _mockUser({
  String id = 'u1',
  String name = 'Priya Sharma',
  bool isAdmin = false,
  bool isActive = true,
  DonorAvailability? donor = DonorAvailability.available,
  int donations = 5,
}) =>
    AdminUser(
      id: id,
      name: name,
      phone: '+91 98765 43210',
      bloodGroup: BloodGroup.oNeg,
      isAdmin: isAdmin,
      isActive: isActive,
      emailVerified: true,
      email: 'priya@example.com',
      donorAvailability: donor,
      totalDonations: donations,
      city: 'Bengaluru',
      lastDonation: DateTime.now().subtract(const Duration(days: 30)),
    );

Widget _testWrapper(Widget screen) {
  final reqs = [
    _mockReq(id: 'r1', urgency: Urgency.critical),
    _mockReq(id: 'r2', urgency: Urgency.urgent, donor: 'Amit Kumar'),
  ];
  final users = [
    _mockUser(id: 'u1', name: 'Priya Sharma', donations: 5),
    _mockUser(
      id: 'u2',
      name: 'Rohan Mehra',
      isAdmin: true,
      donor: DonorAvailability.off,
      donations: 1,
    ),
  ];

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(
        const UserProfile(
          id: 'admin-root',
          name: 'Chief Admin',
          bloodGroup: BloodGroup.oPos,
          phone: '9999999999',
          isAdmin: true,
        ),
      ),
      adminRequestsProvider.overrideWith((ref) => Stream.value(reqs)),
      adminUsersProvider.overrideWith((ref) => Stream.value(users)),
      adminReportsProvider.overrideWith((ref) => Stream.value(const [])),
      adminAuditProvider.overrideWith((ref) => Stream.value(const [])),
      adminStatsProvider.overrideWithValue(AdminStats.from(reqs)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: screen),
    ),
  );
}

void main() {
  const viewports = <String, Size>{
    '320px (iPhone SE 1st gen)': Size(320, 568),
    '360px (Standard Android)': Size(360, 800),
    '375px (iPhone SE 2nd gen)': Size(375, 667),
    '390px (iPhone 13/14)': Size(390, 844),
    '414px (iPhone XR/Plus)': Size(414, 896),
    '430px (iPhone Pro Max)': Size(430, 932),
    '768px (iPad Mini)': Size(768, 1024),
    '1024px (iPad Pro / Small Laptop)': Size(1024, 768),
    'Desktop (1440px)': Size(1440, 900),
  };

  group('Admin Panel Responsive Testing Across Viewports', () {
    for (final entry in viewports.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets('Dashboard renders with no overflow at $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testWrapper(const AdminDashboardScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });

      testWidgets('Emergency Monitoring renders with no overflow at $name',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testWrapper(const AdminEmergencyScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });

      testWidgets('User Management renders with no overflow at $name',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testWrapper(const AdminUsersScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });

      testWidgets('Donor Network renders with no overflow at $name',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testWrapper(const AdminDonorsScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });

      testWidgets('Reports & Export renders with no overflow at $name',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testWrapper(const AdminReportsScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });
    }
  });
}
