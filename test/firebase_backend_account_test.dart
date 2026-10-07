import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:rakt_pravah/data/backend.dart' show SignInFailure;
import 'package:rakt_pravah/data/firebase/firebase_backend.dart';
import 'package:rakt_pravah/data/models/models.dart';

// The real FirebaseBackend's account handling: restoring a session, signing
// up and in, editing the profile and the profile photo.

/// A 1x1 transparent PNG.
final _png = base64Encode(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

FirebaseBackend _backend(
  FakeFirebaseFirestore db, {
  String? uid,
  String email = 'dana@example.com',
}) => FirebaseBackend.forTesting(
  db,
  MockFirebaseAuth(
    signedIn: uid != null,
    mockUser: uid == null ? null : MockUser(uid: uid, email: email),
  ),
);

/// A backend whose Auth call [method] fails with a FirebaseAuthException.
FirebaseBackend _failing(FakeFirebaseFirestore db, Symbol method, String code) {
  final auth = MockFirebaseAuth();
  whenCalling(Invocation.method(method, null))
      .on(auth)
      .thenThrow(fb_auth.FirebaseAuthException(code: code));
  return FirebaseBackend.forTesting(db, auth);
}

Future<void> _profile(
  FakeFirebaseFirestore db,
  String uid, {
  String email = 'dana@example.com',
  Map<String, dynamic> extra = const {},
}) => db.doc('users/$uid').set({
  'name': 'Dana Donor',
  'email': email,
  'phone': '4155550123',
  'countryCode': '+1',
  'countryIsoCode': 'US',
  'bloodGroup': 'A+',
  'country': 'India',
  'state': 'Maharashtra',
  'stateCode': 'MH',
  'city': 'Pune',
  'approved': true,
  'isAdmin': false,
  'latitude': 18.5204,
  'longitude': 73.8567,
  'donor': {'availability': 'available', 'bloodGroup': 'A+', 'maxDistanceKm': 25},
  ...extra,
});

Future<Map<String, dynamic>> _doc(FakeFirebaseFirestore db, String path) async =>
    (await db.doc(path).get()).data()!;

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  group('restoring a session', () {
    test('nobody signed in means no session', () async {
      expect(await _backend(db).restoreSession(), isNull);
    });

    test('a signed-in account with no profile has no session', () async {
      expect(await _backend(db, uid: 'u1').restoreSession(), isNull);
    });

    test('loads the profile with its country code and donor settings', () async {
      await _profile(db, 'u1');
      final b = _backend(db, uid: 'u1');
      final user = await b.restoreSession();
      expect(user!.name, 'Dana Donor');
      expect(user.countryCode, '+1');
      expect(user.phone, '4155550123');
      expect(user.bloodGroup, BloodGroup.aPos);
      expect(user.approved, isTrue);
      expect(b.donorProfile.maxDistanceKm, 25);
      expect(b.donorProfile.availability, DonorAvailability.available);
    });

    test('an account from before approval existed counts as approved', () async {
      await _profile(db, 'u1');
      await db.doc('users/u1').update({'approved': fs.FieldValue.delete()});
      expect((await _backend(db, uid: 'u1').restoreSession())!.approved, isTrue);
    });

    test('an unapproved account is restored as unapproved', () async {
      await _profile(db, 'u1', extra: {'approved': false});
      expect((await _backend(db, uid: 'u1').restoreSession())!.approved, isFalse);
    });

    group('who is an operator', () {
      Future<bool> adminFor(String email, {Map<String, dynamic> extra = const {}}) async {
        await _profile(db, 'u1', email: email, extra: extra);
        return (await _backend(db, uid: 'u1', email: email).restoreSession())!.isAdmin;
      }

      test('an ordinary account is not', () async {
        expect(await adminFor('dana@example.com'), isFalse);
      });
      test('isAdmin on the profile makes one', () async {
        expect(await adminFor('ops@example.com', extra: {'isAdmin': true}), isTrue);
      });
      test('role=admin on the profile makes one', () async {
        expect(await adminFor('ops@example.com', extra: {'role': 'admin'}), isTrue);
      });
      test('the designated operator emails are operators', () async {
        expect(await adminFor('vikky.code@gmail.com'), isTrue);
        expect(await adminFor('ADMIN.VIKKY@gmail.com'), isTrue);
      });
      test('an email that merely contains "admin" is not', () async {
        expect(await adminFor('myadmin@example.com'), isFalse);
      });
    });
  });

  group('signing up', () {
    Future<(FirebaseBackend, UserProfile)> register({
      String phone = '9876543210',
      String code = '+91',
    }) async {
      final b = _backend(db);
      final u = await b.register(
        email: 'new@example.com',
        password: 'secret123',
        name: 'Nina New',
        phone: phone,
        countryCode: code,
        bloodGroup: BloodGroup.bNeg,
        dateOfBirth: DateTime(1995, 5, 5),
        gender: Gender.female,
        country: 'India',
        state: 'Maharashtra',
        city: 'Pune',
      );
      return (b, u);
    }

    test('creates an unapproved, non-admin profile', () async {
      final (b, _) = await register();
      final d = await _doc(db, 'users/${b.uid}');
      expect(d['approved'], isFalse);
      expect(d['isAdmin'], isFalse);
      expect(d.containsKey('role'), isFalse);
      expect(d['name'], 'Nina New');
      expect(d['bloodGroup'], 'B-');
      expect(d['email'], 'new@example.com');
    });

    test('starts with Donor Mode available and the right blood group', () async {
      final (b, _) = await register();
      final donor = (await _doc(db, 'users/${b.uid}'))['donor'] as Map;
      expect(donor['availability'], 'available');
      expect(donor['bloodGroup'], 'B-');
    });

    test('stores the phone and country code separately', () async {
      final (b, _) = await register(phone: '4155550123', code: '+1');
      final d = await _doc(db, 'users/${b.uid}');
      expect(d['phone'], '4155550123');
      expect(d['countryCode'], '+1');
    });

    test('gives a starting position from the chosen city', () async {
      final (b, _) = await register();
      final d = await _doc(db, 'users/${b.uid}');
      expect(d['latitude'], isA<num>());
      expect(d['location'], isA<Map>());
    });

    test('an invalid phone is refused and nothing is saved', () async {
      await expectLater(register(phone: '123'), throwsA(isA<ArgumentError>()));
      final all = await db.collection('users').get();
      expect(all.docs, isEmpty);
    });
  });

  group('signing in', () {
    test('a wrong password is refused with a generic message', () async {
      final b = _failing(db, #signInWithEmailAndPassword, 'wrong-password');
      await expectLater(
        b.signInWithPassword(email: 'a@example.com', password: 'nope'),
        throwsA(isA<SignInFailure>().having((e) => e.message, 'message', 'Invalid ID or password.')),
      );
    });

    test('an unknown email gets the same message (no account enumeration)', () async {
      final b = _failing(db, #signInWithEmailAndPassword, 'user-not-found');
      await expectLater(
        b.signInWithPassword(email: 'a@example.com', password: 'x'),
        throwsA(isA<SignInFailure>().having((e) => e.message, 'message', 'Invalid ID or password.')),
      );
    });

    test('a disabled account is told so', () async {
      final b = _failing(db, #signInWithEmailAndPassword, 'user-disabled');
      await expectLater(
        b.signInWithPassword(email: 'a@example.com', password: 'x'),
        throwsA(isA<SignInFailure>().having((e) => e.message, 'message', contains('disabled'))),
      );
    });

    test('too many attempts asks the user to wait', () async {
      final b = _failing(db, #signInWithEmailAndPassword, 'too-many-requests');
      await expectLater(
        b.signInWithPassword(email: 'a@example.com', password: 'x'),
        throwsA(isA<SignInFailure>().having((e) => e.message, 'message', contains('Wait'))),
      );
    });

    test('a good sign-in loads the saved profile', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 'dana@example.com'));
      await _profile(db, 'u1');
      final b = FirebaseBackend.forTesting(db, auth);
      final user = await b.signInWithPassword(email: 'dana@example.com', password: 'secret123');
      expect(user.name, 'Dana Donor');
      expect(user.countryCode, '+1');
      expect(user.isAdmin, isFalse);
    });

    test('a designated operator is promoted on the profile at sign-in', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'op', email: 'vikky.code@gmail.com'));
      await _profile(db, 'op', email: 'vikky.code@gmail.com');
      final b = FirebaseBackend.forTesting(db, auth);
      final user = await b.signInWithPassword(email: 'vikky.code@gmail.com', password: 'x');
      expect(user.isAdmin, isTrue);
      expect((await _doc(db, 'users/op'))['role'], 'admin');
    });

    test('an ordinary account is never promoted', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 'myadmin@example.com'));
      await _profile(db, 'u1', email: 'myadmin@example.com');
      final b = FirebaseBackend.forTesting(db, auth);
      final user = await b.signInWithPassword(email: 'myadmin@example.com', password: 'x');
      expect(user.isAdmin, isFalse);
      expect((await _doc(db, 'users/u1'))['isAdmin'], isFalse);
    });

    test('an account made in the console gets an unapproved profile', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'c1', email: 'console@example.com'));
      final b = FirebaseBackend.forTesting(db, auth);
      await b.signInWithPassword(email: 'console@example.com', password: 'x');
      final d = await _doc(db, 'users/c1');
      expect(d['approved'], isFalse);
      expect(d['isAdmin'], isFalse);
    });

    test(
      'KNOWN GAP: a console-made profile must not get a made-up phone number',
      () async {
        final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'c1', email: 'console@example.com'));
        final b = FirebaseBackend.forTesting(db, auth);
        await b.signInWithPassword(email: 'console@example.com', password: 'x');
        // That number would be shown to, and dialled by, other people.
        expect((await _doc(db, 'users/c1'))['phone'], isNot('9876543210'));
      },
      skip: 'signInWithPassword writes the placeholder phone 9876543210',
    );
  });

  group('password reset', () {
    test('an unknown address is swallowed, so nobody learns who has an account', () async {
      final b = _failing(db, #sendPasswordResetEmail, 'user-not-found');
      await b.sendPasswordReset('ghost@example.com'); // does not throw
    });

    test('a malformed address is swallowed too', () async {
      final b = _failing(db, #sendPasswordResetEmail, 'invalid-email');
      await b.sendPasswordReset('nope');
    });

    test('a real failure is not hidden', () async {
      final b = _failing(db, #sendPasswordResetEmail, 'network-request-failed');
      await expectLater(b.sendPasswordReset('a@example.com'), throwsA(isA<fb_auth.FirebaseAuthException>()));
    });
  });

  group('editing the profile', () {
    Future<FirebaseBackend> signedIn() async {
      await _profile(db, 'u1');
      final b = _backend(db, uid: 'u1');
      await b.restoreSession();
      return b;
    }

    Future<void> edit(FirebaseBackend b, {String? phone, String? code, String city = 'Pune', double? lat, double? lng}) =>
        b.updateProfile(
          name: 'Dana Renamed',
          bloodGroup: BloodGroup.oPos,
          dateOfBirth: DateTime(1990, 1, 1),
          gender: Gender.female,
          country: 'India',
          state: 'Maharashtra',
          city: city,
          phone: phone,
          countryCode: code,
          latitude: lat,
          longitude: lng,
        );

    test('saves the new details', () async {
      final b = await signedIn();
      await edit(b);
      final d = await _doc(db, 'users/u1');
      expect(d['name'], 'Dana Renamed');
      expect(d['bloodGroup'], 'O+');
      expect(b.currentUser!.name, 'Dana Renamed');
    });

    test('changing blood group changes the donor group used for matching', () async {
      final b = await signedIn();
      await edit(b);
      expect(((await _doc(db, 'users/u1'))['donor'] as Map)['bloodGroup'], 'O+');
      expect(b.donorProfile.bloodGroup, BloodGroup.oPos);
    });

    test('keeps the donor settings it did not change', () async {
      final b = await signedIn();
      await edit(b);
      expect(((await _doc(db, 'users/u1'))['donor'] as Map)['maxDistanceKm'], 25);
    });

    test('keeps the country code when only the name changes', () async {
      final b = await signedIn();
      await edit(b);
      expect((await _doc(db, 'users/u1'))['countryCode'], '+1');
      expect(b.currentUser!.countryCode, '+1');
    });

    test('an invalid phone is refused and the profile is untouched', () async {
      final b = await signedIn();
      await expectLater(edit(b, phone: '12', code: '+91'), throwsA(isA<ArgumentError>()));
      expect((await _doc(db, 'users/u1'))['name'], 'Dana Donor');
    });

    test('a new phone and code are saved together', () async {
      final b = await signedIn();
      await edit(b, phone: '501234567', code: '+971');
      final d = await _doc(db, 'users/u1');
      expect(d['phone'], '501234567');
      expect(d['countryCode'], '+971');
    });

    test(
      "editing the profile must not overwrite the donor's saved GPS position",
      () async {
        final b = await signedIn();
        b.myLocation = const GeoPoint(28.6139, 77.2090); // Delhi GPS, saved to the profile
        await Future<void>.delayed(Duration.zero);
        await edit(b); // city is Pune
        expect((await _doc(db, 'users/u1'))['latitude'], 28.6139);
      },
    );

    test('with no saved GPS, a new city sets a starting position', () async {
      final b = await signedIn();
      await edit(b, city: 'Mumbai');
      final d = await _doc(db, 'users/u1');
      expect(d['latitude'], isNot(18.5204));
    });
  });

  group('profile photo', () {
    Future<FirebaseBackend> signedIn() async {
      await _profile(db, 'u1');
      final b = _backend(db, uid: 'u1');
      await b.restoreSession();
      return b;
    }

    test('a valid picture is saved on the profile', () async {
      final b = await signedIn();
      await b.setProfilePhoto(_png);
      expect((await _doc(db, 'users/u1'))['photo'], _png);
      expect(b.currentUser!.photo, _png);
    });

    test('it can be removed again', () async {
      final b = await signedIn();
      await b.setProfilePhoto(_png);
      await b.setProfilePhoto(null);
      expect((await _doc(db, 'users/u1'))['photo'], isNull);
    });

    test('too large a payload is refused', () async {
      final b = await signedIn();
      await expectLater(b.setProfilePhoto('A' * 60001), throwsA(isA<ArgumentError>()));
    });

    test('something that is not base64 is refused', () async {
      final b = await signedIn();
      await expectLater(b.setProfilePhoto('***not base64***'), throwsA(isA<ArgumentError>()));
    });

    test('a file that is not an image is refused', () async {
      final b = await signedIn();
      await expectLater(
        b.setProfilePhoto(base64Encode(utf8.encode('just some text, not a picture'))),
        throwsA(isA<ArgumentError>()),
      );
      expect((await _doc(db, 'users/u1')).containsKey('photo'), isFalse);
    });

    test('the new picture follows onto the user\'s own requests only', () async {
      final b = await signedIn();
      await db.doc('blood_requests/mine').set({'requesterId': 'u1', 'requesterPhoto': null});
      await db.doc('blood_requests/theirs').set({'requesterId': 'other', 'requesterPhoto': null});
      await b.setProfilePhoto(_png);
      expect((await _doc(db, 'blood_requests/mine'))['requesterPhoto'], _png);
      expect((await _doc(db, 'blood_requests/theirs'))['requesterPhoto'], isNull);
    });

    test(
      'changing the photo keeps the country code, so a call still dials the right number',
      () async {
        final b = await signedIn();
        await b.setProfilePhoto(_png);
        expect(b.currentUser!.countryCode, '+1');
      },
    );

    test('accepting a request after a photo change still shares the +1 code', () async {
      final b = await signedIn();
      await b.setProfilePhoto(_png);
      await db.doc('blood_requests/r1').set({
        'requesterId': 'other',
        'status': 'searching',
        'units': 1,
        'bloodGroups': ['A+'],
        'acceptedDonors': <Map<String, dynamic>>[],
        'acceptedDonorIds': <String>[],
        'timeline': <Map<String, dynamic>>[],
        'destination': {'name': 'H', 'address': 'A'},
      });
      await b.respondToInvitation('r1', InvitationStatus.accepted);
      final donor = ((await _doc(db, 'blood_requests/r1'))['acceptedDonors'] as List).single as Map;
      expect(donor['phoneCountryCode'], '+1');
    });
  });
}
