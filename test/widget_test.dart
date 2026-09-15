import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloodlink/core/theme/app_theme.dart';
import 'package:bloodlink/core/utils/formatters.dart';
import 'package:bloodlink/core/widgets/badges.dart';
import 'package:bloodlink/data/models/models.dart';
import 'package:bloodlink/shared/brand_mark.dart';

// A full app boot now needs a live Firebase project (Auth + Firestore) via
// main()'s Firebase.initializeApp() call, which isn't available in a plain
// widget test without emulator setup — that belongs in an integration test,
// not here. These cover what's safe to test without a backend: pure widgets
// and pure logic.
//
// Screens are deliberately absent: they read `backendProvider`, which is typed
// to the concrete FirebaseBackend, so faking it needs an interface extracted
// first.

/// Wraps a widget with the theme its descendants need — `context.colors` is a
/// theme extension, so a bare MaterialApp null-checks and crashes.
Widget _themed(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

DonorProfile _donor({
  DateTime? lastDonation,
  DonorAvailability? availability,
}) => DonorProfile(
  availability: availability ?? DonorAvailability.available,
  bloodGroup: BloodGroup.oPos,
  lastDonation: lastDonation,
);

void main() {
  testWidgets('BrandMark renders without error', (tester) async {
    await tester.pumpWidget(_themed(const BrandMark(size: 48)));
    expect(find.byType(BrandMark), findsOneWidget);
  });

  group('blood compatibility', () {
    test('O- is a universal donor', () {
      expect(recipientsFor(BloodGroup.oNeg), containsAll(BloodGroup.values));
    });

    test('AB+ can only give to AB+', () {
      expect(recipientsFor(BloodGroup.abPos), [BloodGroup.abPos]);
    });

    test('A+ can give to A+ and AB+ only', () {
      expect(
        recipientsFor(BloodGroup.aPos),
        containsAll([BloodGroup.aPos, BloodGroup.abPos]),
      );
      expect(recipientsFor(BloodGroup.aPos).length, 2);
    });

    test('AB+ patient can receive from every group (universal recipient)', () {
      expect(
        donorsCompatibleWith(BloodGroup.abPos),
        containsAll(BloodGroup.values),
      );
    });

    test(
      'O- patient can only receive from O- (inverse of universal donor)',
      () {
        expect(donorsCompatibleWith(BloodGroup.oNeg), [BloodGroup.oNeg]);
      },
    );

    test('donorsCompatibleWith is the true inverse of recipientsFor', () {
      for (final donor in BloodGroup.values) {
        for (final recipient in recipientsFor(donor)) {
          expect(donorsCompatibleWith(recipient), contains(donor));
        }
      }
    });

    test('Rh- donors can give to their Rh+ counterpart but not vice versa', () {
      expect(recipientsFor(BloodGroup.oNeg), contains(BloodGroup.oPos));
      expect(recipientsFor(BloodGroup.oPos), isNot(contains(BloodGroup.oNeg)));
      expect(recipientsFor(BloodGroup.bNeg), contains(BloodGroup.bPos));
      expect(recipientsFor(BloodGroup.bPos), isNot(contains(BloodGroup.bNeg)));
    });

    test('every group can donate to itself', () {
      for (final g in BloodGroup.values) {
        expect(recipientsFor(g), contains(g), reason: '$g should accept $g');
      }
    });
  });

  // The 90-day gap between whole-blood donations is a medical safety rule, so
  // it gets tested at its boundaries rather than trusted.
  group('donation cooldown', () {
    test('a donor who has never donated is never in cooldown', () {
      final donor = _donor();
      expect(donor.isInCooldown, isFalse);
      expect(donor.cooldownEndsAt, isNull);
      expect(donor.cooldownRemaining, Duration.zero);
    });

    test('donating today puts the donor in cooldown', () {
      expect(_donor(lastDonation: DateTime.now()).isInCooldown, isTrue);
    });

    test('still in cooldown one day before the 90 days elapse', () {
      final donor = _donor(
        lastDonation: DateTime.now().subtract(const Duration(days: 89)),
      );
      expect(donor.isInCooldown, isTrue);
    });

    test('out of cooldown once 90 days have passed', () {
      final donor = _donor(
        lastDonation: DateTime.now().subtract(
          const Duration(days: 90, minutes: 1),
        ),
      );
      expect(donor.isInCooldown, isFalse);
      expect(donor.cooldownRemaining, Duration.zero);
    });

    test('cooldown ends exactly 90 days after the donation', () {
      final donated = DateTime(2026, 1, 1, 9, 30);
      final donor = _donor(lastDonation: donated);
      expect(donor.cooldownEndsAt, donated.add(const Duration(days: 90)));
    });

    test('remaining time never goes negative', () {
      final donor = _donor(
        lastDonation: DateTime.now().subtract(const Duration(days: 400)),
      );
      expect(donor.cooldownRemaining, Duration.zero);
      expect(donor.cooldownRemaining.isNegative, isFalse);
    });

    test('remaining time shrinks as the cooldown elapses', () {
      final fresh = _donor(lastDonation: DateTime.now());
      final older = _donor(
        lastDonation: DateTime.now().subtract(const Duration(days: 60)),
      );
      expect(older.cooldownRemaining, lessThan(fresh.cooldownRemaining));
    });

    test('cooldown is independent of availability', () {
      final paused = _donor(
        lastDonation: DateTime.now(),
        availability: DonorAvailability.paused,
      );
      expect(paused.isInCooldown, isTrue);
    });

    test('copyWith preserves the donation date that drives cooldown', () {
      final donated = DateTime.now().subtract(const Duration(days: 10));
      final donor = _donor(lastDonation: donated)
          .copyWith(availability: DonorAvailability.off);
      expect(donor.lastDonation, donated);
      expect(donor.isInCooldown, isTrue);
    });
  });

  group('donor availability', () {
    test('isOn is true for available and paused, false only for off', () {
      expect(_donor(availability: DonorAvailability.available).isOn, isTrue);
      expect(_donor(availability: DonorAvailability.paused).isOn, isTrue);
      expect(_donor(availability: DonorAvailability.off).isOn, isFalse);
    });
  });

  group('request state machine', () {
    test('terminal states are exactly the four that end a request', () {
      final terminal = RequestStatus.values.where((s) => s.isTerminal).toSet();
      expect(terminal, {
        RequestStatus.fulfilled,
        RequestStatus.cancelled,
        RequestStatus.expired,
        RequestStatus.removedByAdmin,
      });
    });

    test('isActive is the exact inverse of isTerminal', () {
      for (final s in RequestStatus.values) {
        expect(s.isActive, !s.isTerminal, reason: '$s');
      }
    });

    test('the lifecycle is the happy path only — no failure states', () {
      expect(RequestStatus.lifecycle, [
        RequestStatus.created,
        RequestStatus.searching,
        RequestStatus.donorAccepted,
        RequestStatus.coordinating,
        RequestStatus.fulfilled,
      ]);
      expect(RequestStatus.lifecycle, isNot(contains(RequestStatus.cancelled)));
      expect(RequestStatus.lifecycle, isNot(contains(RequestStatus.expired)));
    });

    test('fulfilled is the only terminal state inside the lifecycle', () {
      final terminalInLifecycle = RequestStatus.lifecycle.where(
        (s) => s.isTerminal,
      );
      expect(terminalInLifecycle, [RequestStatus.fulfilled]);
    });
  });

  group('blood group labels', () {
    test('every group round-trips through its label', () {
      for (final g in BloodGroup.values) {
        expect(BloodGroup.fromLabel(g.label), g);
      }
    });

    test('labels are unique', () {
      final labels = BloodGroup.values.map((g) => g.label).toSet();
      expect(labels.length, BloodGroup.values.length);
    });
  });

  group('user initials', () {
    UserProfile user(String name) => UserProfile(
      id: 'u1',
      name: name,
      bloodGroup: BloodGroup.oPos,
      phone: '9876543210',
    );

    test('uses first and last name', () {
      expect(user('Alok Sharma').initials, 'AS');
    });

    test('a single name yields one letter', () {
      expect(user('Alok').initials, 'A');
    });

    test('middle names are skipped in favour of first and last', () {
      expect(user('Alok Kumar Sharma').initials, 'AS');
    });

    test('extra whitespace does not break it', () {
      expect(user('   Alok    Sharma  ').initials, 'AS');
    });

    test('an empty name falls back rather than crashing', () {
      expect(user('   ').initials, '?');
    });
  });

  group('email verification state', () {
    UserProfile user({bool verified = false, String? email}) => UserProfile(
      id: 'u1',
      name: 'Alok Sharma',
      bloodGroup: BloodGroup.oPos,
      phone: '9876543210',
      email: email,
      emailVerified: verified,
    );

    test('defaults to unverified — verification is never assumed', () {
      expect(user().emailVerified, isFalse);
    });

    test('an email on file does not by itself mean verified', () {
      expect(user(email: 'a@b.com').emailVerified, isFalse);
    });
  });

  group('place name for the location chip', () {
    test('keeps only the first segment of a geocoded label', () {
      expect(
        Fmt.placeName('Indiranagar, Bengaluru, Karnataka', null),
        'Indiranagar',
      );
    });

    test('rejects raw coordinates in favour of the profile city', () {
      expect(Fmt.placeName('12.9716, 77.5946', 'Bengaluru'), 'Bengaluru');
    });

    test('rejects negative and whole-number coordinates too', () {
      expect(Fmt.placeName('-33.86, 151.20', 'Sydney'), 'Sydney');
      expect(Fmt.placeName('12, 77', 'Bengaluru'), 'Bengaluru');
    });

    test('returns null when neither source is a real place', () {
      expect(Fmt.placeName('12.9716, 77.5946', null), isNull);
      expect(Fmt.placeName(null, null), isNull);
      expect(Fmt.placeName('', '  '), isNull);
    });

    test('falls back to the city when there is no geocoded label', () {
      expect(Fmt.placeName(null, 'Bengaluru'), 'Bengaluru');
    });

    test('a single-segment label is used as-is', () {
      expect(Fmt.placeName('Dubai', 'Bengaluru'), 'Dubai');
    });
  });

  group('formatters', () {
    test('units is singular only for one', () {
      expect(Fmt.units(1), '1 unit');
      expect(Fmt.units(2), '2 units');
      expect(Fmt.units(0), '0 units');
    });

    test('remaining is empty for no deadline and Expired for past ones', () {
      expect(Fmt.remaining(null), '');
      expect(
        Fmt.remaining(DateTime.now().subtract(const Duration(minutes: 5))),
        'Expired',
      );
    });

    test('remaining counts down in the largest sensible unit', () {
      expect(
        Fmt.remaining(DateTime.now().add(const Duration(minutes: 31))),
        endsWith('min left'),
      );
      expect(
        Fmt.remaining(DateTime.now().add(const Duration(hours: 5))),
        endsWith('h left'),
      );
      expect(
        Fmt.remaining(DateTime.now().add(const Duration(days: 3))),
        endsWith('d left'),
      );
    });

    test('relative reads as just now for a fresh timestamp', () {
      expect(Fmt.relative(DateTime.now()), 'just now');
      expect(
        Fmt.relative(DateTime.now().subtract(const Duration(minutes: 6))),
        '6 min ago',
      );
    });

    test('clock pads to two digits', () {
      expect(Fmt.clock(DateTime(2026, 1, 1, 9, 5)), '09:05');
      expect(Fmt.clock(DateTime(2026, 1, 1, 14, 32)), '14:32');
    });

    test('shortDate renders day and month name', () {
      expect(Fmt.shortDate(DateTime(2026, 8, 12)), '12 Aug');
      expect(Fmt.shortDate(DateTime(2026, 1, 1)), '1 Jan');
    });
  });

  group('multi-group requests', () {
    BloodRequest request(List<BloodGroup> groups) => BloodRequest(
      id: 'r1',
      requesterId: 'u1',
      requesterName: 'Alok Sharma',
      bloodGroups: groups,
      units: 2,
      urgency: Urgency.critical,
      status: RequestStatus.searching,
      createdAt: DateTime(2026, 1, 1),
      destination: const Destination(name: 'City Hospital', address: 'MG Rd'),
      requestLocationLabel: 'Bengaluru',
    );

    test('copyWith keeps identity fields and updates the rest', () {
      final original = request([BloodGroup.oPos]);
      final updated = original.copyWith(
        status: RequestStatus.fulfilled,
        acceptedDonorName: 'Aman',
      );
      expect(updated.id, original.id);
      expect(updated.requesterId, original.requesterId);
      expect(updated.createdAt, original.createdAt);
      expect(updated.status, RequestStatus.fulfilled);
      expect(updated.acceptedDonorName, 'Aman');
      expect(
        original.status,
        RequestStatus.searching,
        reason: 'copyWith must not mutate the original',
      );
    });

    test('hasAcceptedDonor tracks the donor id, not the name', () {
      expect(request([BloodGroup.oPos]).hasAcceptedDonor, isFalse);
      expect(
        request([BloodGroup.oPos])
            .copyWith(acceptedDonorId: 'd1')
            .hasAcceptedDonor,
        isTrue,
      );
    });

    test('a request can accept every group a patient is compatible with', () {
      final groups = donorsCompatibleWith(BloodGroup.abPos);
      expect(request(groups).bloodGroups.length, BloodGroup.values.length);
    });
  });

  group('BloodGroupBadges', () {
    testWidgets('renders one badge per group when uncapped', (tester) async {
      await tester.pumpWidget(
        _themed(const BloodGroupBadges([BloodGroup.oPos, BloodGroup.oNeg])),
      );
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('O-'), findsOneWidget);
    });

    testWidgets('folds the overflow into a +N chip', (tester) async {
      await tester.pumpWidget(
        _themed(
          const BloodGroupBadges([
            BloodGroup.oPos,
            BloodGroup.oNeg,
            BloodGroup.aPos,
            BloodGroup.bPos,
          ], maxVisible: 2),
        ),
      );
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('O-'), findsOneWidget);
      expect(find.text('A+'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('shows no +N chip when the cap is not exceeded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(const BloodGroupBadges([BloodGroup.oPos], maxVisible: 3)),
      );
      expect(find.text('O+'), findsOneWidget);
      expect(
        find.textContaining('+'),
        findsOneWidget,
        reason: 'only the O+ badge itself contains a plus',
      );
    });
  });
}
