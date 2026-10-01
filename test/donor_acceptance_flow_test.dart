import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/live_location_screen.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'Donor acceptance updates status to Donor Accepted and displays profile',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final req = BloodRequest(
        id: 'req-1',
        requesterId: 'requester-1',
        requesterName: 'Vikram',
        bloodGroups: const [BloodGroup.aPos],
        units: 1,
        urgency: Urgency.urgent,
        status: RequestStatus.searching,
        createdAt: DateTime.now(),
        destination: const Destination(
          name: 'Apollo Hospital',
          address: 'GS Road, Guwahati',
          location: GeoPoint(26.1445, 91.7362),
        ),
        requestLocationLabel: 'Guwahati, Assam',
        bloodType: 'Platelets',
      );

      const donorUser = UserProfile(
        id: 'donor-1',
        name: 'Rahul Sharma',
        bloodGroup: BloodGroup.aPos,
        phone: '+91 98765 43210',
      );
      final fakeBackend = FakeBackend(user: donorUser, requests: [req]);

      // 1. Respond to invitation -> status becomes donorAccepted
      await fakeBackend.respondToInvitation('req-1', InvitationStatus.accepted);

      final updatedRequests = await fakeBackend.myRequestsStream.first;
      final updatedReq = updatedRequests.first;

      // Requirement 1: Status is donorAccepted
      expect(updatedReq.status, RequestStatus.donorAccepted);
      expect(updatedReq.acceptedDonors.length, 1);
      final donor = updatedReq.acceptedDonors.first;
      expect(donor.name, 'Rahul Sharma');
      expect(donor.bloodType, 'Platelets');
      expect(donor.isVerified, isTrue);

      // Pump RequestDetailScreen to check Accepted Donor Profile
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(fakeBackend),
            requestProvider('req-1')
                .overrideWith((ref) => Stream.value(updatedReq)),
            patientNameProvider('req-1')
                .overrideWith((ref) => Stream.value('Rahul')),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const RequestDetailScreen(requestId: 'req-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Requirement 3: Accepted Donor Profile fields
      expect(find.text('Selected Donor · Primary Contact'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Platelets'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Available · Donor Mode ON'), findsOneWidget);
      expect(find.textContaining('km away'), findsWidgets);
      expect(find.textContaining('min travel'), findsWidgets);

      // Requirement 3 Action Buttons: Track Donor, Call, Chat
      expect(find.text('Track Donor (Live)'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);

      // Requirement 6: Donor Journey Status
      expect(find.text('Donor Journey Status'), findsOneWidget);
      expect(find.text('Accepted'), findsWidgets);
      expect(find.text('On the Way'), findsOneWidget);
      expect(find.text('Near Hospital'), findsOneWidget);
      expect(find.text('Reached'), findsOneWidget);
      expect(find.text('Donation Completed'), findsOneWidget);

      // Privacy rule check: home address or ID is NOT displayed
      expect(find.textContaining('Permanent address'), findsNothing);
      expect(find.textContaining('Aadhaar'), findsNothing);
      expect(find.textContaining('Privacy rule:'), findsOneWidget);
    },
  );

  testWidgets(
    'Multiple accepted donors are sorted nearest first with alternative selection',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final req = BloodRequest(
        id: 'req-multi',
        requesterId: 'requester-1',
        requesterName: 'Vikram',
        bloodGroups: const [BloodGroup.oPos],
        units: 2,
        urgency: Urgency.urgent,
        status: RequestStatus.donorAccepted,
        createdAt: now,
        destination: const Destination(
          name: 'City General Hospital',
          address: 'Banjara Hills, Hyderabad',
          location: GeoPoint(17.4156, 78.4357),
        ),
        requestLocationLabel: 'Hyderabad, Telangana',
        acceptedDonors: [
          AcceptedDonor(
            id: 'donor-far',
            name: 'Far Donor Amit',
            bloodGroup: BloodGroup.oPos,
            bloodType: 'Blood',
            distanceKm: 8.5,
            phone: '+91 99999 11111',
            acceptedAt: now.subtract(const Duration(minutes: 5)),
          ),
          AcceptedDonor(
            id: 'donor-near',
            name: 'Near Donor Suman',
            bloodGroup: BloodGroup.oPos,
            bloodType: 'Blood',
            distanceKm: 1.8,
            phone: '+91 99999 22222',
            acceptedAt: now.subtract(const Duration(minutes: 3)),
          ),
        ],
      );

      final fakeBackend = FakeBackend(requests: [req]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(fakeBackend),
            requestProvider('req-multi')
                .overrideWith((ref) => Stream.value(req)),
            patientNameProvider('req-multi')
                .overrideWith((ref) => Stream.value('Sunil')),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const RequestDetailScreen(requestId: 'req-multi'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Requirement 7: Suman (1.8 km) should be primary because nearest first
      expect(find.text('2 accepted · nearest first'), findsOneWidget);
      expect(find.text('Near Donor Suman'), findsOneWidget);

      // Requirement 8: Amit (8.5 km) is listed under Alternative Donors
      expect(find.text('Alternative Donors (1 available)'), findsOneWidget);
      expect(find.text('Far Donor Amit'), findsOneWidget);

      // Tap Select on Amit to make him primary
      final selectButton = find.widgetWithText(ElevatedButton, 'Select');
      expect(selectButton, findsOneWidget);
      await tester.tap(selectButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Amit is now primary, Suman is alternative
      expect(find.text('Selected Donor · Primary Contact'), findsOneWidget);
    },
  );

  testWidgets(
    'Live location session closes and stops sharing when request is completed/cancelled',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final req = BloodRequest(
        id: 'req-fulfilled',
        requesterId: 'requester-1',
        requesterName: 'Vikram',
        bloodGroups: const [BloodGroup.aPos],
        units: 1,
        urgency: Urgency.urgent,
        status: RequestStatus.fulfilled,
        createdAt: DateTime.now(),
        destination: const Destination(
          name: 'Apollo Hospital',
          address: 'GS Road, Guwahati',
          location: GeoPoint(26.1445, 91.7362),
        ),
        requestLocationLabel: 'Guwahati, Assam',
        acceptedDonors: [
          AcceptedDonor(
            id: 'donor-1',
            name: 'Rahul',
            bloodGroup: BloodGroup.aPos,
            acceptedAt: DateTime.now(),
          ),
        ],
      );

      final fakeBackend = FakeBackend(requests: [req]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(fakeBackend),
            requestProvider('req-fulfilled')
                .overrideWith((ref) => Stream.value(req)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const LiveLocationScreen(requestId: 'req-fulfilled'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Requirement 9: Active tracking session closed message is displayed
      expect(find.text('Donation Completed'), findsOneWidget);
      expect(
        find.textContaining(
          'Live-location sharing has stopped to protect donor and requester privacy',
        ),
        findsOneWidget,
      );
      expect(find.text('Back to Request'), findsOneWidget);
    },
  );
}
