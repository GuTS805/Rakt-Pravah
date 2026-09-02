import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloodlink/core/theme/app_theme.dart';
import 'package:bloodlink/data/models/blood_compatibility.dart';
import 'package:bloodlink/data/models/enums.dart';
import 'package:bloodlink/shared/brand_mark.dart';

// A full app boot now needs a live Firebase project (Auth + Firestore) via
// main()'s Firebase.initializeApp() call, which isn't available in a plain
// widget test without emulator setup — that belongs in an integration test,
// not here. These cover what's safe to test without a backend: pure widgets
// and pure logic.

void main() {
  testWidgets('BrandMark renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: BrandMark(size: 48)),
      ),
    );
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
      expect(recipientsFor(BloodGroup.aPos),
          containsAll([BloodGroup.aPos, BloodGroup.abPos]));
      expect(recipientsFor(BloodGroup.aPos).length, 2);
    });

    test('AB+ patient can receive from every group (universal recipient)', () {
      expect(donorsCompatibleWith(BloodGroup.abPos),
          containsAll(BloodGroup.values));
    });

    test('O- patient can only receive from O- (inverse of universal donor)',
        () {
      expect(donorsCompatibleWith(BloodGroup.oNeg), [BloodGroup.oNeg]);
    });

    test('donorsCompatibleWith is the true inverse of recipientsFor', () {
      for (final donor in BloodGroup.values) {
        for (final recipient in recipientsFor(donor)) {
          expect(donorsCompatibleWith(recipient), contains(donor));
        }
      }
    });
  });
}
