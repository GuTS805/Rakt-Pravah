import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/accepted_donor_profile_card.dart';
import 'package:rakt_pravah/data/models/models.dart';

// The card the requester sees once a donor accepts. On a phone-sized screen
// its header and phone row used to run off the edge.

final _request = BloodRequest(
  id: 'r1',
  requesterId: 'u1',
  requesterName: 'Riya Requester',
  bloodGroups: const [BloodGroup.bPos, BloodGroup.oPos],
  units: 1,
  urgency: Urgency.urgent,
  status: RequestStatus.donorAccepted,
  createdAt: DateTime.now(),
  destination: const Destination(name: 'City Hospital', address: 'Raj Nagar'),
  requestLocationLabel: 'Ghaziabad',
);

final _donor = AcceptedDonor(
  id: 'd1',
  name: 'Dana Donor',
  acceptedAt: DateTime.now(),
  bloodGroup: BloodGroup.bPos,
  phone: '+919876501111',
  distanceKm: 1.6,
);

Future<void> _pump(
  WidgetTester tester, {
  double textScale = 1,
  BloodRequest? request,
}) async {
  // A OnePlus Nord CE 2: 1080 px wide at 2.625 dpr, about 411 dp.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AcceptedDonorProfileCard(
                donor: _donor,
                request: request ?? _request,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('fits a phone-sized screen without overflowing', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Shared on Accept'), findsOneWidget);
    expect(find.textContaining('+91 98765 01111'), findsOneWidget);
  });

  testWidgets('while the donor is coming, it is live', (tester) async {
    await _pump(tester);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Track Donor (Live)'), findsOneWidget);
    expect(find.text('1.6 km away'), findsOneWidget);
  });

  testWidgets('once fulfilled, it is a record of the donation', (
    tester,
  ) async {
    await _pump(
      tester,
      request: _request.copyWith(status: RequestStatus.fulfilled),
    );
    expect(find.text('Donated'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('Track Donor (Live)'), findsNothing);
    expect(find.textContaining('Donor Mode'), findsNothing);
    expect(find.textContaining('km away'), findsNothing);
    // Calling or messaging to say thank you still works.
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('a cancelled request says so', (tester) async {
    await _pump(
      tester,
      request: _request.copyWith(status: RequestStatus.cancelled),
    );
    expect(find.text(RequestStatus.cancelled.label), findsOneWidget);
    expect(find.text('Track Donor (Live)'), findsNothing);
  });

  testWidgets('still fits with large system text', (tester) async {
    await _pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    // The number is never cut short, whatever happens to the tag beside it.
    expect(find.textContaining('+91 98765 01111'), findsOneWidget);
  });
}
