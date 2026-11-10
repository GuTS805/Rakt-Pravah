import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/home/donor_status_card.dart';

import 'fakes.dart';

// The Donor Mode card must not promise requests the donor can't get: the
// matcher skips donors without a verified phone, and an alert can't show
// on a phone where notifications are off.

void main() {
  UserProfile me({required bool verified}) => UserProfile(
    id: 'u1',
    name: 'Dana Donor',
    bloodGroup: BloodGroup.bPos,
    phone: '9876501111',
    phoneVerified: verified,
  );

  Future<void> open(
    WidgetTester tester, {
    bool verified = true,
    bool? notificationsAllowed = true,
  }) async {
    final user = me(verified: verified);
    final backend = FakeBackend(
      user: user,
      donor: const DonorProfile(
        availability: DonorAvailability.available,
        bloodGroup: BloodGroup.bPos,
      ),
    )..emitCanAct(verified);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          currentUserProvider.overrideWithValue(user),
          notificationsAllowedProvider.overrideWith(
            (ref) async => notificationsAllowed,
          ),
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
  }

  testWidgets('a verified donor with notifications on is told requests come', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.text('You can receive matching requests nearby.'),
      findsOneWidget,
    );
    expect(find.textContaining('Notifications are off'), findsNothing);
  });

  testWidgets('a donor without a verified phone is told to verify it', (
    tester,
  ) async {
    await open(tester, verified: false);
    expect(
      find.text('You can receive matching requests nearby.'),
      findsNothing,
    );
    expect(
      find.text('Verify your phone number to start receiving requests.'),
      findsOneWidget,
    );
  });

  testWidgets('notifications switched off are pointed out, with a fix', (
    tester,
  ) async {
    await open(tester, notificationsAllowed: false);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('no warning when the setting is not known', (tester) async {
    await open(tester, notificationsAllowed: null);
    expect(find.textContaining('Notifications are off'), findsNothing);
  });

  testWidgets('the card no longer shows a ticking clock', (tester) async {
    await open(tester);
    expect(find.textContaining('Local time'), findsNothing);
  });
}
