import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/coordination_screen.dart';
import 'package:rakt_pravah/features/invitations/invitation_detail_screen.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';

import 'fakes.dart';

void main() {
  group('Mutual Connection & Contact Sharing Flow', () {
    const requester = UserProfile(
      id: 'requester-1',
      name: 'Vikram Sen',
      bloodGroup: BloodGroup.bPos,
      phone: '+91 98765 11111',
      city: 'Guwahati',
      state: 'Assam',
    );

    const donor = UserProfile(
      id: 'donor-1',
      name: 'Rahul Sharma',
      bloodGroup: BloodGroup.aPos,
      phone: '+91 98765 43210',
      city: 'Guwahati',
      state: 'Assam',
    );

    final req = BloodRequest(
      id: 'req-connect-1',
      requesterId: 'requester-1',
      requesterName: 'Vikram Sen',
      patientName: 'Sunil Sen',
      patientBloodGroup: BloodGroup.aPos,
      bloodGroups: const [BloodGroup.aPos],
      bloodType: 'Platelets',
      units: 1,
      urgency: Urgency.urgent,
      status: RequestStatus.searching,
      createdAt: DateTime.now(),
      phone: '+91 98765 11111',
      notes: 'Patient in ICU 3rd floor, ask for ward 304',
      destination: const Destination(
        name: 'Apollo Hospital',
        address: 'GS Road, Guwahati, Assam 781005',
        wardOrContact: 'ICU Ward 304',
        location: GeoPoint(26.1445, 91.7362),
      ),
      requestLocationLabel: 'Guwahati, Assam',
    );

    testWidgets(
      'Before acceptance, private requester contact info is NOT revealed to donor',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final invitation = Invitation(
          id: 'inv-1',
          requestId: req.id,
          requesterId: req.requesterId,
          requesterName: req.requesterName,
          bloodGroups: req.bloodGroups,
          units: req.units,
          urgency: req.urgency,
          distanceKm: 3.2,
          status: InvitationStatus.pending,
          destinationName: req.destination.name,
          destinationArea: 'Guwahati',
          createdAt: DateTime.now(),
          patientBloodGroup: req.patientBloodGroup,
        );

        final fakeBackend = FakeBackend(
          user: donor,
          invitations: [invitation],
          requests: [req],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(fakeBackend),
              invitationsProvider.overrideWith(
                (ref) => Stream.value([invitation]),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const InvitationDetailScreen(invitationId: 'inv-1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Before acceptance: Phone number is completely hidden
        expect(find.text('+91 98765 11111'), findsNothing);
        expect(find.text('Vikram Sen'), findsNothing);
        expect(find.text('Sunil Sen'), findsNothing);
        expect(
          find.text('Patient in ICU 3rd floor, ask for ward 304'),
          findsNothing,
        );

        // Privacy guarantee note is shown
        expect(
          find.textContaining(
            'The requester\'s contact details stay private until you accept',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'After donor accepts, Donor can see Requester/Patient details on CoordinationScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final acceptedReq = req.copyWith(
          status: RequestStatus.donorAccepted,
          acceptedDonors: [
            AcceptedDonor(
              id: donor.id,
              name: donor.name,
              bloodGroup: donor.bloodGroup,
              bloodType: req.bloodType,
              phone: donor.phone,
              distanceKm: 3.2,
              status: 'Accepted',
              transitStatus: DonorTransitStatus.accepted,
              isVerified: true,
              isDonorModeOn: true,
              acceptedAt: DateTime.now(),
            ),
          ],
        );

        // Logged in as donor
        final fakeBackend = FakeBackend(user: donor, requests: [acceptedReq]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(fakeBackend),
              currentUserProvider.overrideWith((ref) => donor),
              requestProvider(acceptedReq.id)
                  .overrideWith((ref) => Stream.value(acceptedReq)),
              patientNameProvider(acceptedReq.id)
                  .overrideWith((ref) => Stream.value('Sunil Sen')),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: CoordinationScreen(requestId: acceptedReq.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mutual connection banner
        expect(find.text('Mutual Connection Active'), findsOneWidget);

        // Donor can see Requester/Patient:
        // 1. Requester name
        expect(find.text('Vikram Sen'), findsOneWidget);
        expect(find.text('Requester'), findsOneWidget);

        // 2. Patient name
        expect(find.text('Sunil Sen'), findsOneWidget);

        // 3. Required blood group & Blood type
        expect(find.text('A+'), findsWidgets);
        expect(find.text('Platelets'), findsOneWidget);

        // 4. Units required
        expect(find.text('1 unit required'), findsOneWidget);

        // 5. Urgency
        expect(find.text('Urgent'), findsOneWidget);

        // 6. Hospital name & address & location
        expect(find.text('Apollo Hospital'), findsWidgets);
        expect(find.text('GS Road, Guwahati, Assam 781005'), findsWidgets);
        expect(find.text('Guwahati, Assam'), findsOneWidget);

        // 7. Requester's phone number
        expect(find.text('+91 98765 11111'), findsOneWidget);
        expect(find.text('Shared on Accept'), findsOneWidget);

        // 8. Additional notes
        expect(
          find.text('Patient in ICU 3rd floor, ask for ward 304'),
          findsOneWidget,
        );

        // 9. Call button, Chat button, Navigate button
        expect(find.widgetWithText(ElevatedButton, 'Call'), findsOneWidget);
        expect(find.text('Chat'), findsWidgets);
        expect(find.text('Navigate'), findsOneWidget);
      },
    );

    testWidgets(
      'After donor accepts, Requester can see Donor details on RequestDetailScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final acceptedReq = req.copyWith(
          status: RequestStatus.donorAccepted,
          acceptedDonors: [
            AcceptedDonor(
              id: donor.id,
              name: donor.name,
              bloodGroup: donor.bloodGroup,
              bloodType: req.bloodType,
              phone: donor.phone,
              distanceKm: 2.8,
              status: 'Accepted',
              transitStatus: DonorTransitStatus.accepted,
              isVerified: true,
              isDonorModeOn: true,
              acceptedAt: DateTime.now(),
            ),
          ],
        );

        // Logged in as requester
        final fakeBackend = FakeBackend(
          user: requester,
          requests: [acceptedReq],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(fakeBackend),
              currentUserProvider.overrideWith((ref) => requester),
              requestProvider(acceptedReq.id)
                  .overrideWith((ref) => Stream.value(acceptedReq)),
              patientNameProvider(acceptedReq.id)
                  .overrideWith((ref) => Stream.value('Sunil Sen')),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: RequestDetailScreen(requestId: acceptedReq.id),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Requester can see Donor:
        // 1. Name
        expect(find.text('Rahul Sharma'), findsOneWidget);

        // 2. Blood group & blood type
        expect(find.text('A+'), findsWidgets);
        expect(find.text('Platelets'), findsOneWidget);

        // 3. Verification status & Availability status
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Available · Donor Mode ON'), findsOneWidget);

        // 4. Phone number (revealed after acceptance)
        expect(find.text('+91 98765 43210'), findsOneWidget);

        // 5. Distance and travel ETA
        expect(find.textContaining('km away'), findsWidgets);
        expect(find.textContaining('min travel'), findsWidgets);

        // 6. Action buttons: Call, Chat, Track Live
        expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Chat'), findsOneWidget);
        expect(find.text('Track Donor (Live)'), findsOneWidget);
      },
    );

    testWidgets(
      'Full Lifecycle: Request -> Accept -> Connected -> Donation Completed -> Closed',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final completedReq = req.copyWith(
          status: RequestStatus.fulfilled,
          acceptedDonors: [
            AcceptedDonor(
              id: donor.id,
              name: donor.name,
              bloodGroup: donor.bloodGroup,
              phone: donor.phone,
              distanceKm: 2.8,
              acceptedAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ],
        );

        final fakeBackend = FakeBackend(user: donor, requests: [completedReq]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(fakeBackend),
              currentUserProvider.overrideWith((ref) => donor),
              requestProvider(completedReq.id)
                  .overrideWith((ref) => Stream.value(completedReq)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: CoordinationScreen(requestId: completedReq.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Closed session message
        expect(
          find.text('Donation Completed · Connection Closed'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Blood donation was completed. Tracking & coordination closed.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
