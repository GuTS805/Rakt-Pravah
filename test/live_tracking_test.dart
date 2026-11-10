import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/live_location_screen.dart';
import 'package:rakt_pravah/features/coordination/live_tracking_map.dart';
import 'package:rakt_pravah/features/coordination/live_tracking_sheet.dart';

import 'fakes.dart';

void main() {
  group('Live Blood Donation Location Tracking', () {
    test('DonorTransitStatus step indexes and progression are correct', () {
      expect(DonorTransitStatus.accepted.stepIndex, 0);
      expect(DonorTransitStatus.onTheWay.stepIndex, 1);
      expect(DonorTransitStatus.nearHospital.stepIndex, 2);
      expect(DonorTransitStatus.reached.stepIndex, 3);

      expect(DonorTransitStatus.accepted.label, 'Accepted');
      expect(DonorTransitStatus.onTheWay.label, 'On the Way');
      expect(DonorTransitStatus.nearHospital.label, 'Near Hospital');
      expect(DonorTransitStatus.reached.label, 'Reached');
    });

    test(
      'Two-way live location updates store donor and requester pings',
      () async {
        final fake = FakeBackend();
        final req = await fake.createRequest(
          patientName: 'Asha Sharma',
          patientBloodGroup: BloodGroup.bPos,
          bloodGroups: [BloodGroup.bPos],
          units: 1,
          urgency: Urgency.urgent,
          requestLocationLabel: 'Apollo Hospital',
          destination: const Destination(
            name: 'Apollo Hospital',
            address: 'Main Rd',
          ),
        );

        // Donor updates location
        const donorPoint = GeoPoint(28.6140, 77.2095);
        await fake.updateLiveLocation(
          req.id,
          donorPoint,
          transitStatus: DonorTransitStatus.onTheWay,
        );

        var updated = await fake.requestStream(req.id).first;
        expect(updated.donorLiveLocations[fake.uid], isNotNull);
        expect(updated.donorLiveLocations[fake.uid]!.point.lat, 28.6140);
        expect(
          updated.donorLiveLocations[fake.uid]!.transitStatus,
          DonorTransitStatus.onTheWay,
        );

        // Requester updates location
        const requesterPoint = GeoPoint(28.6150, 77.2100);
        await fake.updateLiveLocation(
          req.id,
          requesterPoint,
          isRequester: true,
        );

        updated = await fake.requestStream(req.id).first;
        expect(updated.requesterLiveLocation, isNotNull);
        expect(updated.requesterLiveLocation!.point.lat, 28.6150);

        // Advance transit status
        await fake.updateDonorTransitStatus(
          req.id,
          DonorTransitStatus.nearHospital,
        );
        updated = await fake.requestStream(req.id).first;
        expect(
          updated.donorLiveLocations[fake.uid]!.transitStatus,
          DonorTransitStatus.nearHospital,
        );

        // Stop live location
        await fake.stopLiveLocation(req.id);
        updated = await fake.requestStream(req.id).first;
        expect(updated.donorLiveLocations.containsKey(fake.uid), isFalse);
      },
    );

    testWidgets('LiveTrackingSheet renders 4-step progress, ETA, and actions', (
      tester,
    ) async {
      final req = BloodRequest(
        id: 'req-track',
        requesterId: 'req-1',
        requesterName: 'Vikram Mehta',
        bloodGroups: [BloodGroup.oPos],
        units: 1,
        urgency: Urgency.critical,
        status: RequestStatus.coordinating,
        createdAt: DateTime.now(),
        destination: const Destination(
          name: 'Max Healthcare',
          address: 'Ring Rd',
        ),
        requestLocationLabel: 'Max Healthcare',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LiveTrackingSheet(
              request: req,
              partnerName: 'Aarav Sharma',
              partnerPhone: '+91 98765 43210',
              partnerBloodGroup: BloodGroup.oPos,
              isDonor: false,
              transitStatus: DonorTransitStatus.onTheWay,
              distanceKm: 2.4,
              isSharingLocation: true,
              onToggleSharing: () {},
              onUpdateTransitStatus: (_) {},
            ),
          ),
        ),
      );

      // Verify ETA and Distance
      expect(find.text('5 mins'), findsOneWidget); // 2.4 / 0.5 = 4.8 -> 5 mins
      expect(find.textContaining('2.4 km away'), findsOneWidget);
      expect(find.text('LIVE TRACKING'), findsOneWidget);

      // Verify 4-step progress labels
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('On the Way'), findsOneWidget);
      expect(find.text('Near Hospital'), findsOneWidget);
      expect(find.text('Reached'), findsOneWidget);

      // Verify Action buttons
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
    });

    testWidgets("without the donor's position, no distance or time is made up", (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LiveTrackingSheet(
              request: BloodRequest(
                id: 'req-track',
                requesterId: 'req-1',
                requesterName: 'Vikram Mehta',
                bloodGroups: const [BloodGroup.oPos],
                units: 1,
                urgency: Urgency.critical,
                status: RequestStatus.coordinating,
                createdAt: DateTime.now(),
                destination: const Destination(
                  name: 'Max Healthcare',
                  address: 'Ring Rd',
                ),
                requestLocationLabel: 'Max Healthcare',
              ),
              partnerName: 'Aarav Sharma',
              isDonor: false,
              transitStatus: DonorTransitStatus.onTheWay,
              distanceKm: null,
              isSharingLocation: true,
              onToggleSharing: () {},
              onUpdateTransitStatus: (_) {},
            ),
          ),
        ),
      );

      expect(find.text("Waiting for the donor's location"), findsOneWidget);
      expect(find.textContaining('km away'), findsNothing);
      expect(find.textContaining('mins'), findsNothing);
    });

    testWidgets(
      "a donor who hasn't set off sees the patient, the number, no arrival time",
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: LiveTrackingSheet(
                request: BloodRequest(
                  id: 'req-track',
                  requesterId: 'req-1',
                  requesterName: 'Priya Sharma',
                  patientBloodGroup: BloodGroup.bPos,
                  bloodGroups: const [BloodGroup.bPos],
                  units: 1,
                  urgency: Urgency.critical,
                  status: RequestStatus.donorAccepted,
                  createdAt: DateTime.now(),
                  destination: const Destination(
                    name: 'Fortis Hospital',
                    address: 'Shivaji Chowk',
                  ),
                  requestLocationLabel: 'Kalyan, Maharashtra',
                ),
                patientName: 'Meena Sharma',
                partnerName: 'Priya Sharma',
                partnerPhone: '9999999993',
                partnerPhoneCountryCode: '+91',
                isDonor: true,
                transitStatus: DonorTransitStatus.accepted,
                distanceKm: 8.6,
                isSharingLocation: true,
                onToggleSharing: () {},
                onUpdateTransitStatus: (_) {},
              ),
            ),
          ),
        );

        expect(find.textContaining('Patient Meena Sharma (B+)'), findsOneWidget);
        expect(find.textContaining('Needed'), findsNothing);
        expect(find.text('+91 99999 99993'), findsOneWidget);
        expect(find.text('8.6 km from the hospital'), findsOneWidget);
        expect(find.textContaining('Arriving by'), findsNothing);
        expect(find.textContaining('mins'), findsNothing);
      },
    );

    testWidgets('a donor has no demo simulation button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LiveTrackingSheet(
              request: BloodRequest(
                id: 'req-track',
                requesterId: 'req-1',
                requesterName: 'Vikram Mehta',
                bloodGroups: const [BloodGroup.oPos],
                units: 1,
                urgency: Urgency.critical,
                status: RequestStatus.coordinating,
                createdAt: DateTime.now(),
                destination: const Destination(
                  name: 'Max Healthcare',
                  address: 'Ring Rd',
                ),
                requestLocationLabel: 'Max Healthcare',
              ),
              partnerName: 'Vikram Mehta',
              isDonor: true,
              transitStatus: DonorTransitStatus.onTheWay,
              distanceKm: 3,
              isSharingLocation: true,
              onToggleSharing: () {},
              onUpdateTransitStatus: (_) {},
            ),
          ),
        ),
      );

      expect(find.textContaining('Simulat'), findsNothing);
      expect(find.text('Sharing live location with requester'), findsOneWidget);
    });

    testWidgets(
      'LiveLocationScreen renders live map and bottom tracking sheet',
      (tester) async {
        final fake = FakeBackend(
          user: const UserProfile(
            id: 'donor-1',
            name: 'Aarav Sharma',
            bloodGroup: BloodGroup.oPos,
            phone: '+91 98765 43210',
          ),
        );

        final req = await fake.createRequest(
          patientName: 'Ravi Kumar',
          patientBloodGroup: BloodGroup.oPos,
          bloodGroups: [BloodGroup.oPos],
          units: 1,
          urgency: Urgency.urgent,
          requestLocationLabel: 'City Hospital',
          destination: const Destination(
            name: 'City Hospital',
            address: 'Station Rd',
            location: GeoPoint(28.6139, 77.2090),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [backendProvider.overrideWithValue(fake)],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: LiveLocationScreen(requestId: req.id),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Live Donation Tracking'), findsOneWidget);
        expect(find.text('Max Healthcare'), findsNothing);
        expect(find.text('City Hospital'), findsOneWidget);
        expect(
          find.text('Call'),
          findsNothing,
        ); // requester has no phone by default
        expect(find.text('Chat'), findsOneWidget);
        expect(find.text('Directions'), findsOneWidget);
        // The sheet sits under the card, not over it (it used to hide the
        // card's Google Maps buttons).
        expect(
          tester.getRect(find.byType(LiveTrackingMap)).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(LiveTrackingSheet)).top,
          ),
        );
      },
    );
  });
}
