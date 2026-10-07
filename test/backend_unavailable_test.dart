import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/backend_error.dart';
import 'package:rakt_pravah/data/firebase/firebase_backend.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/home/donor_status_card.dart';

import 'fakes.dart';

// What a person sees when the server won't take a change: a reason, not a
// spinner that never ends.

const _donor = DonorProfile(
  availability: DonorAvailability.available,
  bloodGroup: BloodGroup.aPos,
);

Future<FirebaseBackend> _backendWhereWritesFail(String code) async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/u1').set({'name': 'Dana', 'donor': {'availability': 'available'}});
  whenCalling(Invocation.method(#set, null))
      .on(db.doc('users/u1'))
      .thenThrow(fs.FirebaseException(plugin: 'cloud_firestore', code: code, message: 'boom'));
  final b = FirebaseBackend.forTesting(
    db,
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', email: 'dana@example.com')),
  );
  return b;
}

class _Rejecting extends FakeBackend {
  _Rejecting(this._error, {super.user, super.donor});
  final Object _error;
  @override
  Future<DonorProfile> setDonorProfile(DonorProfile next) async => throw _error;
}

Future<void> _pumpCard(WidgetTester tester, FakeBackend backend) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [backendProvider.overrideWithValue(backend)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DonorStatusCard()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('a write the server refuses', () {
    test('a missing database is called out by name', () async {
      final b = await _backendWhereWritesFail('not-found');
      await expectLater(
        b.setDonorProfile(_donor),
        throwsA(
          isA<BackendUnavailable>().having(
            (e) => e.message,
            'message',
            contains('database is not set up'),
          ),
        ),
      );
    });

    test('an unreachable server says to check the connection', () async {
      final b = await _backendWhereWritesFail('unavailable');
      await expectLater(
        b.setDonorProfile(_donor),
        throwsA(
          isA<BackendUnavailable>().having(
            (e) => e.message,
            'message',
            contains('[unavailable]'),
          ),
        ),
      );
    });

    test('security rules turning the change down are named as such', () async {
      final b = await _backendWhereWritesFail('permission-denied');
      await expectLater(
        b.setDonorProfile(_donor),
        throwsA(
          isA<BackendUnavailable>().having((e) => e.message, 'message', contains('security rules')),
        ),
      );
    });

    test('recording a donation reports the same way', () async {
      final b = await _backendWhereWritesFail('not-found');
      await expectLater(b.recordDonation(DateTime(2026, 1, 1)), throwsA(isA<BackendUnavailable>()));
    });

    test('resetting the cooldown reports the same way', () async {
      final b = await _backendWhereWritesFail('not-found');
      await expectLater(b.resetDonationCooldown(), throwsA(isA<BackendUnavailable>()));
    });

    test('a healthy server still saves the change', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u1').set({'name': 'Dana'});
      final b = FirebaseBackend.forTesting(
        db,
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', email: 'dana@example.com')),
      );
      await b.setDonorProfile(_donor.copyWith(availability: DonorAvailability.off));
      expect(((await db.doc('users/u1').get()).data()!['donor'] as Map)['availability'], 'off');
    });
  });

  group('Donor Mode switch', () {
    const user = UserProfile(id: 'u1', name: 'Dana', bloodGroup: BloodGroup.aPos, phone: '4155550123');

    testWidgets('shows the backend\'s reason and stops spinning when the change fails', (
      tester,
    ) async {
      const reason = 'The Firestore database is not set up for this Firebase project.';
      await _pumpCard(tester, _Rejecting(const BackendUnavailable(reason), user: user, donor: _donor));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(reason), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('falls back to a generic message for any other failure', (tester) async {
      await _pumpCard(tester, _Rejecting(StateError("x"), user: user, donor: _donor));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Couldn\'t update Donor Mode. Try again.'), findsOneWidget);
    });
  });
}
