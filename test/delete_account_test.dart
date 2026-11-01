import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/backend.dart';
import 'package:rakt_pravah/data/firebase/firebase_backend.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/profile/delete_account_screen.dart';

import 'fakes.dart';

// Deleting an account from inside the app, which Google Play and the App
// Store both require: the real backend against in-memory Firebase, and the
// screen against the fake backend.

Map<String, dynamic> _request(
  String requesterId,
  String status, {
  List<String> donorIds = const [],
}) => {
  'requesterId': requesterId,
  'requesterName': requesterId == 'u1' ? 'Dana Donor' : 'Riya Requester',
  'requesterPhoto': 'photo',
  'phone': '9876501111',
  'phoneCountryCode': '+91',
  'fullPhoneNumber': '+919876501111',
  'notes': 'Ward 4',
  'bloodGroups': ['B+'],
  'units': 1,
  'urgency': 'urgent',
  'status': status,
  'createdAt': fs.Timestamp.now(),
  'timeline': <Map<String, dynamic>>[],
  'acceptedDonors': [
    for (final id in donorIds)
      {'id': id, 'name': 'Dana Donor', 'at': fs.Timestamp.now()},
  ],
  'acceptedDonorIds': donorIds,
  'declinedByDonorIds': <String>[],
};

void main() {
  group('the backend', () {
    late FakeFirebaseFirestore db;
    late MockUser user;
    // The failures a test makes Auth throw are kept per user and outlive the
    // test, and two MockUsers with the same details count as the same user.
    // A fresh name each time keeps one test's failures out of the next.
    var run = 0;
    late MockFirebaseAuth auth;
    late FirebaseBackend backend;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.doc('users/u1').set({
        'name': 'Dana Donor',
        'email': 'dana@example.com',
        'phone': '9876501111',
        'countryCode': '+91',
        'bloodGroup': 'B+',
      });
      await db.doc('users/u1/devices/d1').set({'user_id': 'u1'});
      await db.doc('users/u1/fcm_tokens/t1').set({'token': 't'});
      await db.doc('push_devices/d1').set({'user_id': 'u1'});
      await db.doc('push_devices/d2').set({'user_id': 'someone-else'});
      // Theirs: one still open, one finished.
      await db.doc('blood_requests/open').set(_request('u1', 'searching'));
      await db
          .doc('blood_requests/open/private/patient')
          .set({'name': 'Sunil', 'phone': '9876501111'});
      await db.doc('blood_requests/done').set(_request('u1', 'fulfilled'));
      // Someone else's they accepted: one under way, one already given.
      await db
          .doc('blood_requests/helping')
          .set(_request('u2', 'donorAccepted', donorIds: ['u1']));
      await db
          .doc('blood_requests/given')
          .set(_request('u2', 'fulfilled', donorIds: ['u1']));

      user = MockUser(
        uid: 'u1',
        email: 'dana@example.com',
        displayName: 'Dana ${run++}',
      );
      auth = MockFirebaseAuth(signedIn: true, mockUser: user);
      backend = FirebaseBackend.forTesting(db, auth);
      await backend.restoreSession();
    });

    Future<Map<String, dynamic>?> read(String path) async =>
        (await db.doc(path).get()).data();

    test('removes the profile, devices and sign-in', () async {
      await backend.deleteAccount(password: 'secret123');

      expect(await read('users/u1'), isNull);
      expect((await db.collection('users/u1/devices').get()).docs, isEmpty);
      expect((await db.collection('users/u1/fcm_tokens').get()).docs, isEmpty);
      expect(await read('push_devices/d1'), isNull);
      expect(await read('push_devices/d2'), isNotNull);
      expect(auth.currentUser, isNull);
      expect(backend.currentUser, isNull);
    });

    test('closes their open requests and takes their details off', () async {
      await backend.deleteAccount(password: 'secret123');

      final open = (await read('blood_requests/open'))!;
      expect(open['status'], 'cancelled');
      expect(open['requesterName'], 'Deleted account');
      expect(open['requesterPhoto'], isNull);
      for (final key in ['phone', 'phoneCountryCode', 'fullPhoneNumber', 'notes']) {
        expect(open.containsKey(key), isFalse, reason: key);
      }
      final patient = (await read('blood_requests/open/private/patient'))!;
      expect(patient['name'], 'Deleted account');
      expect(patient.containsKey('phone'), isFalse);

      final done = (await read('blood_requests/done'))!;
      expect(done['status'], 'fulfilled');
      expect(done['requesterName'], 'Deleted account');
    });

    test('hands back requests they accepted but have not finished', () async {
      await backend.deleteAccount(password: 'secret123');

      final helping = (await read('blood_requests/helping'))!;
      expect(helping['status'], 'searching');
      expect(helping['acceptedDonorIds'], isEmpty);

      // A donation already made stays on the patient's record.
      final given = (await read('blood_requests/given'))!;
      expect(given['status'], 'fulfilled');
      expect(given['acceptedDonorIds'], ['u1']);
    });

    test('a wrong password deletes nothing', () async {
      whenCalling(Invocation.method(#reauthenticateWithCredential, null))
          .on(user)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'wrong-password'));

      await expectLater(
        backend.deleteAccount(password: 'nope'),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (e) => e.message,
            'message',
            'That password is wrong.',
          ),
        ),
      );
      expect(await read('users/u1'), isNotNull);
      expect((await read('blood_requests/open'))!['status'], 'searching');
      expect(auth.currentUser, isNotNull);
    });

    test('a sign-in Firebase refuses to delete is reported', () async {
      whenCalling(Invocation.method(#delete, null))
          .on(user)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'internal-error'));

      await expectLater(
        backend.deleteAccount(password: 'secret123'),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (e) => e.message,
            'message',
            contains('[internal-error]'),
          ),
        ),
      );
    });

    test('a password is needed for an account that has one', () async {
      await expectLater(
        backend.deleteAccount(),
        throwsA(isA<AccountDeletionFailure>()),
      );
      expect(await read('users/u1'), isNotNull);
    });
  });

  group('the screen', () {
    const me = UserProfile(
      id: 'u1',
      name: 'Dana Donor',
      bloodGroup: BloodGroup.bPos,
      phone: '9876501111',
      email: 'dana@example.com',
    );

    Future<FakeBackend> open(WidgetTester tester) async {
      final backend = FakeBackend(user: me);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(backend)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DeleteAccountScreen(),
          ),
        ),
      );
      await tester.pump();
      return backend;
    }

    Future<void> deleteWith(WidgetTester tester, String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('says what is deleted before asking', (tester) async {
      await open(tester);
      expect(find.text('Deleting your account is permanent.'), findsOneWidget);
      expect(find.textContaining('open blood requests are cancelled'),
          findsOneWidget);
    });

    testWidgets('the right password deletes the account', (tester) async {
      final backend = await open(tester);
      await deleteWith(tester, 'secret123');

      expect(backend.accountDeleted, isTrue);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    testWidgets('a wrong password is explained and nothing is deleted', (
      tester,
    ) async {
      final backend = await open(tester);
      await deleteWith(tester, 'nope');

      expect(backend.accountDeleted, isFalse);
      expect(find.text('That password is wrong.'), findsOneWidget);
    });

    testWidgets('an empty password is caught before asking', (tester) async {
      final backend = await open(tester);
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsNothing);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(backend.accountDeleted, isFalse);
    });

    testWidgets('backing out of the question deletes nothing', (tester) async {
      final backend = await open(tester);
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(backend.accountDeleted, isFalse);
    });
  });
}
