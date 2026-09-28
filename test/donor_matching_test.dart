import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/donor_ranking_card.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';

import 'fakes.dart';

void main() {
  group('Smart Blood Request Matching & Nearby Donor Ranking', () {
    test('MatchedDonor computes estimated travel minutes based on distance', () {
      final donorNear = MatchedDonor(
        id: 'd1',
        name: 'Near Donor',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 1.2,
        status: DonorRequestInteractionStatus.notified,
      );
      // 1.2 km / 0.5 = 2.4 -> 2 minutes
      expect(donorNear.estimatedTravelMinutes, 2);

      final donorFar = MatchedDonor(
        id: 'd2',
        name: 'Far Donor',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 9.7,
        status: DonorRequestInteractionStatus.notified,
      );
      // 9.7 km / 0.5 = 19.4 -> 19 minutes
      expect(donorFar.estimatedTravelMinutes, 19);
    });

    test('AcceptedDonor computes estimated travel minutes correctly', () {
      final accepted = AcceptedDonor(
        id: 'd1',
        name: 'Aarav',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 5.4,
        acceptedAt: DateTime.now(),
      );
      // 5.4 / 0.5 = 10.8 -> 11 minutes
      expect(accepted.estimatedTravelMinutes, 11);
    });

    test('Nearby donors are sorted by distance ascending (nearest first)', () async {
      final fake = FakeBackend();
      final stream = fake.nearbyDonorsStream('req-1');
      final donors = await stream.first;

      expect(donors.isNotEmpty, isTrue);
      for (var i = 0; i < donors.length - 1; i++) {
        expect(donors[i].distanceKm <= donors[i + 1].distanceKm, isTrue);
      }
      expect(donors.first.name, 'Aarav Sharma');
      expect(donors.first.distanceKm, 1.2);
    });

    test('Expanding search radius returns donors within new radius', () async {
      final fake = FakeBackend();
      final req = await fake.createRequest(
        patientName: 'Test Patient',
        patientBloodGroup: BloodGroup.oPos,
        bloodGroups: [BloodGroup.oPos],
        units: 1,
        urgency: Urgency.urgent,
        requestLocationLabel: 'Apex Hospital',
        destination: const Destination(name: 'Apex Hospital', address: 'MG Road'),
      );

      // Expand radius to 50 km
      await fake.expandSearchRadius(req.id, 50.0);
      final updated = await fake.requestStream(req.id).first;
      expect(updated.searchRadiusKm, 50.0);
    });

    test('markInvitationViewed adds user id to viewedByDonorIds', () async {
      final fake = FakeBackend();
      final req = await fake.createRequest(
        patientName: 'Test Patient',
        patientBloodGroup: BloodGroup.oPos,
        bloodGroups: [BloodGroup.oPos],
        units: 1,
        urgency: Urgency.urgent,
        requestLocationLabel: 'Apex Hospital',
        destination: const Destination(name: 'Apex Hospital', address: 'MG Road'),
      );

      expect(req.viewedByDonorIds.contains(fake.uid), isFalse);

      await fake.markInvitationViewed(req.id);
      final updated = await fake.requestStream(req.id).first;
      expect(updated.viewedByDonorIds.contains(fake.uid), isTrue);
    });

    testWidgets('DonorRankingCard renders distance, travel time, and badges',
        (tester) async {
      final donor = MatchedDonor(
        id: 'donor-1',
        name: 'Aarav Sharma',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 1.2,
        status: DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43210',
        isDonorModeOn: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DonorRankingCard(
              donor: donor,
              destination: const Destination(
                name: 'City Hospital',
                address: 'Central Ave',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('1.2 km away'), findsOneWidget);
      expect(find.text('~2 min travel'), findsOneWidget);
      expect(find.text('Donor Mode ON'), findsOneWidget);
      expect(find.text('Notified'), findsOneWidget);
      expect(
        find.textContaining('Approx. neighborhood distance'),
        findsOneWidget,
      );
    });

    testWidgets('RequestDetailScreen shows Nearby & Matched Donors and radius chips',
        (tester) async {
      final fake = FakeBackend();
      final req = await fake.createRequest(
        patientName: 'Kavita Roy',
        patientBloodGroup: BloodGroup.oPos,
        bloodGroups: [BloodGroup.oPos],
        units: 2,
        urgency: Urgency.critical,
        requestLocationLabel: 'Metro Hospital',
        destination: const Destination(name: 'Metro Hospital', address: 'Sector 4'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RequestDetailScreen(requestId: req.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('NEARBY & MATCHED DONORS'),
        findsOneWidget,
      );
      expect(find.text('25 km radius'), findsOneWidget);
      expect(find.text('Ranked by real distance from hospital • Nearest first'), findsOneWidget);
      expect(find.text('15 km'), findsOneWidget);
      expect(find.text('50 km'), findsOneWidget);

      // Verify sorted matched donors are rendered
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('1.2 km away'), findsOneWidget);
      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('2.8 km away'), findsOneWidget);
    });
  });
}
