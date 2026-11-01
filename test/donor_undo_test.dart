import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/home/donor_status_card.dart';

import 'fakes.dart';

// The 90 days between donations protect the donor, so the waiting period
// can't be skipped. A donation recorded by mistake can be undone, but only
// for a day.

void main() {
  const me = UserProfile(
    id: 'u1',
    name: 'Dana Donor',
    bloodGroup: BloodGroup.bPos,
    phone: '9876501111',
    phoneVerified: true,
  );

  Future<FakeBackend> open(WidgetTester tester, Duration sinceDonation) async {
    final now = DateTime(2026, 11, 2, 12);
    final backend = FakeBackend(
      user: me,
      donor: DonorProfile(
        availability: DonorAvailability.off,
        bloodGroup: BloodGroup.bPos,
        lastDonation: now.subtract(sinceDonation),
        totalDonations: 3,
      ),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          currentTimeProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DonorStatusCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return backend;
  }

  testWidgets('a donation recorded today can be undone', (tester) async {
    final backend = await open(tester, const Duration(hours: 2));

    await tester.tap(find.text("Undo: I didn't donate"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.donorProfile.lastDonation, isNull);
    expect(backend.donorProfile.totalDonations, 2);
    expect(backend.donorProfile.availability, DonorAvailability.available);
    expect(find.text('Donation removed. Donor Mode is ON.'), findsOneWidget);
  });

  testWidgets('after a day the waiting period cannot be skipped', (
    tester,
  ) async {
    await open(tester, const Duration(days: 2));

    expect(find.text("Undo: I didn't donate"), findsNothing);
    expect(find.textContaining('Reset waiting period'), findsNothing);
  });
}
