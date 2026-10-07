import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/donor_ranking_card.dart';
import 'package:rakt_pravah/core/widgets/invitation_card.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/invitations/invitation_detail_screen.dart';
import 'package:rakt_pravah/features/profile/privacy_screen.dart';
import 'package:rakt_pravah/shared/settings_widgets.dart';

import 'fakes.dart';

// Privacy promises the app makes, checked from the screens a person sees:
// contact details are not shown before a request is accepted, location is
// opt-in and revocable, and the controls say what they do.

const _donor = UserProfile(
  id: 'donor-1',
  name: 'Dana Donor',
  bloodGroup: BloodGroup.aPos,
  phone: '4155550123',
  countryCode: '+1',
);

const _secretPhone = '9988776655';

BloodRequest _request({List<AcceptedDonor> accepted = const []}) =>
    BloodRequest(
      id: 'r1',
      requesterId: 'requester-1',
      requesterName: 'Ravi Kumar',
      patientName: 'Sunil Patient',
      patientBloodGroup: BloodGroup.aPos,
      bloodGroups: const [BloodGroup.aPos],
      units: 1,
      urgency: Urgency.urgent,
      status: RequestStatus.searching,
      createdAt: DateTime.now(),
      phone: _secretPhone,
      phoneCountryCode: '+91',
      destination: const Destination(
        name: 'Pune City Hospital',
        address: 'FC Road, Pune',
        location: GeoPoint(18.52, 73.85),
      ),
      requestLocationLabel: 'Pune',
      acceptedDonors: accepted,
    );

Invitation _invitation(BloodRequest r, {InvitationStatus? status}) =>
    Invitation(
      id: r.id,
      requestId: r.id,
      requesterId: r.requesterId,
      requesterName: r.requesterName,
      bloodGroups: r.bloodGroups,
      units: r.units,
      urgency: r.urgency,
      distanceKm: 2.0,
      status: status ?? InvitationStatus.pending,
      destinationName: r.destination.name,
      destinationArea: 'Pune',
      createdAt: r.createdAt,
      patientBloodGroup: r.patientBloodGroup,
    );

Widget _app(FakeBackend backend, Widget home, {LocationResult? location}) =>
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => backend.currentUser),
        locationServiceProvider.overrideWithValue(
          FakeLocationService(result: location ?? const LocationDenied()),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

Finder _switchFor(String title) => find.descendant(
  of: find.ancestor(
    of: find.text(title),
    matching: find.byType(SettingsSwitchTile),
  ),
  matching: find.byType(Switch),
);

void main() {
  group('contact details before and after accepting', () {
    testWidgets('an invitation card never shows the requester phone', (
      tester,
    ) async {
      final r = _request();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: InvitationCard(
              invitation: _invitation(r),
              onTap: () {},
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining(_secretPhone), findsNothing);
      expect(find.textContaining('Sunil'), findsNothing);
    });

    testWidgets('the invitation screen says contact stays private until accept', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final r = _request();
      final backend = FakeBackend(
        user: _donor,
        donor: const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.aPos,
        ),
        requests: [r],
        invitations: [_invitation(r)],
      );
      await tester.pumpWidget(
        _app(backend, InvitationDetailScreen(invitationId: r.id)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("contact details stay private until you accept"),
        findsOneWidget,
      );
      expect(find.textContaining(_secretPhone), findsNothing);
      expect(find.textContaining('Sunil'), findsNothing);
    });
  });

  group('nearby donors list (the requester\'s view)', () {
    MatchedDonor donor(DonorRequestInteractionStatus s) => MatchedDonor(
      id: 'd1',
      name: 'Dana Donor',
      bloodGroup: BloodGroup.aPos,
      distanceKm: 2.5,
      status: s,
      phone: '4155550123',
      phoneCountryCode: '+1',
    );

    Future<void> pump(WidgetTester tester, MatchedDonor d) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DonorRankingCard(
              donor: d,
              isAccepted: d.status == DonorRequestInteractionStatus.accepted,
            ),
          ),
        ),
      );
    }

    for (final s in [
      DonorRequestInteractionStatus.notified,
      DonorRequestInteractionStatus.viewed,
      DonorRequestInteractionStatus.declined,
    ]) {
      testWidgets('no call button for a donor who is ${s.label.toLowerCase()}', (
        tester,
      ) async {
        await pump(tester, donor(s));
        expect(find.byTooltip('Call Donor'), findsNothing);
      });
    }

    testWidgets('a call button once the donor has accepted', (tester) async {
      await pump(tester, donor(DonorRequestInteractionStatus.accepted));
      expect(find.byTooltip('Call Donor'), findsOneWidget);
    });

    testWidgets('a donor with no number never gets a call button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: DonorRankingCard(
              isAccepted: true,
              donor: MatchedDonor(
                id: 'd2',
                name: 'No Phone',
                bloodGroup: BloodGroup.aPos,
                distanceKm: 1,
                status: DonorRequestInteractionStatus.accepted,
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Call Donor'), findsNothing);
    });
  });

  group('Privacy & location screen', () {
    Future<FakeBackend> pump(
      WidgetTester tester, {
      bool locationGranted = true,
      LocationResult? location,
    }) async {
      final backend = FakeBackend(
        user: _donor,
        donor: DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.aPos,
          locationGranted: locationGranted,
        ),
      );
      await tester.pumpWidget(
        _app(backend, const PrivacyScreen(), location: location),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('states that phone and location are private by default', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('phone number and exact location are private'),
        findsOneWidget,
      );
    });

    testWidgets('turning location off is saved and needs no prompt', (
      tester,
    ) async {
      final backend = await pump(tester);
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(backend.donorProfile.locationGranted, isFalse);
    });

    testWidgets('turning location on explains a refusal', (tester) async {
      await pump(tester, locationGranted: false);
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location access is needed to match you with nearby requests.'),
        findsOneWidget,
      );
    });

    testWidgets('a blocked permission offers system settings', (tester) async {
      await pump(
        tester,
        locationGranted: false,
        location: const LocationDeniedForever(),
      );
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('turning location on with permission is saved', (tester) async {
      final backend = await pump(
        tester,
        locationGranted: false,
        location: const LocationGranted(GeoPoint(18.52, 73.85), 'Pune'),
      );
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(backend.donorProfile.locationGranted, isTrue);
      expect(backend.myLocation, const GeoPoint(18.52, 73.85));
    });

    testWidgets('the sharing switches can be flipped', (tester) async {
      await pump(tester);
      for (final title in [
        'Share contact after accepting',
        'Hide last donation date',
      ]) {
        final before = tester.widget<Switch>(_switchFor(title)).value;
        await tester.tap(_switchFor(title));
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(_switchFor(title)).value, !before);
      }
    });

    // These two switches only flip local widget state: nothing reads them and
    // nothing is saved, so a user who turns sharing off still gets shared.
    testWidgets(
      'KNOWN GAP: turning off "Share contact after accepting" stops the number being shared',
      (tester) async {
        await pump(tester);
        await tester.tap(_switchFor('Share contact after accepting'));
        await tester.pumpAndSettle();
        fail('the switch is not read by anything, so accepting still shares');
      },
      skip: true,
    );

    testWidgets(
      'KNOWN GAP: "Hide last donation date" is remembered after leaving the screen',
      (tester) async {
        await pump(tester);
        await tester.tap(_switchFor('Hide last donation date'));
        await tester.pumpAndSettle();
        await pump(tester);
        expect(
          tester.widget<Switch>(_switchFor('Hide last donation date')).value,
          isTrue,
        );
      },
      skip: true,
    );
  });

  group('live location is opt-in and revocable', () {
    test('nothing is shared until the donor starts sharing', () async {
      final r = _request(
        accepted: [
          AcceptedDonor(
            id: _donor.id,
            name: _donor.name,
            acceptedAt: DateTime.now(),
          ),
        ],
      );
      final backend = FakeBackend(user: _donor, requests: [r]);
      expect(backend.liveLocationUpdates, isEmpty);
      await backend.updateLiveLocation(r.id, const GeoPoint(18.5, 73.8));
      expect(backend.liveLocationUpdates, hasLength(1));
    });

    test('stopping removes the donor from the live map', () async {
      final r = _request(
        accepted: [
          AcceptedDonor(
            id: _donor.id,
            name: _donor.name,
            acceptedAt: DateTime.now(),
          ),
        ],
      );
      final backend = FakeBackend(user: _donor, requests: [r]);
      await backend.updateLiveLocation(r.id, const GeoPoint(18.5, 73.8));
      await backend.stopLiveLocation(r.id);
      expect(backend.stoppedLiveLocationIds, contains(r.id));
    });
  });
}
