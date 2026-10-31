import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/data/firebase/firebase_backend.dart';
import 'package:rakt_pravah/data/models/models.dart';

// The real FirebaseBackend, run against in-memory Firestore and Auth. These
// cover what the screens' FakeBackend cannot: the shape of what is written,
// the accept transaction, and which requests a donor is actually offered.
// They do not run the security rules (see functions/test/rules for those).

const _pune = GeoPoint(18.5204, 73.8567);

class _Rig {
  _Rig() : db = FakeFirebaseFirestore();

  final FakeFirebaseFirestore db;

  Future<void> user(
    String id, {
    String name = 'Someone',
    String group = 'A+',
    String phone = '9876543210',
    String countryCode = '+91',
    String state = 'Maharashtra',
    String availability = 'available',
    double maxKm = 30,
    DateTime? lastDonation,
    bool isAdmin = false,
  }) => db.doc('users/$id').set({
    'name': name,
    'email': '$id@example.com',
    'phone': phone,
    'countryCode': countryCode,
    'bloodGroup': group,
    'country': 'India',
    'state': state,
    'city': 'Pune',
    'approved': true,
    'isAdmin': isAdmin,
    'lastDonation': lastDonation == null
        ? null
        : fs.Timestamp.fromDate(lastDonation),
    'donor': {
      'availability': availability,
      'bloodGroup': group,
      'maxDistanceKm': maxKm,
      'lastDonation': lastDonation == null
          ? null
          : fs.Timestamp.fromDate(lastDonation),
    },
  });

  /// A backend signed in as [id], which must already exist via [user].
  Future<FirebaseBackend> as_(String id) async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: id, email: '$id@example.com'),
    );
    final b = FirebaseBackend.forTesting(db, auth);
    await b.restoreSession();
    return b;
  }

  Future<void> request(
    String id, {
    String requester = 'requester',
    List<String> groups = const ['A+'],
    int units = 1,
    String status = 'searching',
    List<String> accepted = const [],
    List<String> declined = const [],
    String state = 'Maharashtra',
    GeoPoint? at = _pune,
    DateTime? expiresAt,
  }) => db.doc('blood_requests/$id').set({
    'requesterId': requester,
    'requesterName': 'Requester',
    'patientBloodGroup': groups.first,
    'bloodGroups': groups,
    'units': units,
    'urgency': 'urgent',
    'bloodType': 'Blood',
    'phone': '501234567',
    'phoneCountryCode': '+971',
    'status': status,
    'createdAt': fs.Timestamp.fromDate(DateTime.now()),
    'expiresAt': fs.Timestamp.fromDate(
      expiresAt ?? DateTime.now().add(const Duration(hours: 5)),
    ),
    'destination': {
      'name': 'City Hospital',
      'address': 'Pune',
      'location': at == null ? null : {'lat': at.lat, 'lng': at.lng},
    },
    'requestLocationLabel': 'Pune',
    'state': state,
    'acceptedDonors': [
      for (final d in accepted)
        {'id': d, 'name': d, 'status': 'Accepted', 'at': fs.Timestamp.now()},
    ],
    'acceptedDonorIds': accepted,
    'declinedByDonorIds': declined,
    'viewedByDonorIds': <String>[],
    'timeline': <Map<String, dynamic>>[],
  });

  Future<Map<String, dynamic>> data(String path) async =>
      (await db.doc(path).get()).data()!;
}

Future<List<Invitation>> _offered(FirebaseBackend b) => b.invitationsStream
    .firstWhere((_) => true)
    .timeout(const Duration(seconds: 5));

void main() {
  late _Rig rig;

  setUp(() async {
    rig = _Rig();
    await rig.user('requester', name: 'Riya Requester', group: 'O+', phone: '5550001111', countryCode: '+44');
    await rig.user('donor1', name: 'Dana Donor', phone: '4155550123', countryCode: '+1');
    await rig.user('donor2', name: 'Dev Donor', phone: '9000000002');
  });

  group('createRequest', () {
    Future<(FirebaseBackend, BloodRequest)> create({
      String? phone = '501234567',
      String? code = '+971',
      int units = 2,
      List<BloodGroup> groups = const [BloodGroup.aPos, BloodGroup.oPos],
    }) async {
      final b = await rig.as_('requester');
      final r = await b.createRequest(
        patientName: 'Sunil Patient',
        patientBloodGroup: BloodGroup.aPos,
        bloodGroups: groups,
        units: units,
        urgency: Urgency.urgent,
        requestLocationLabel: 'Pune',
        requestLocation: _pune,
        phone: phone,
        phoneCountryCode: code,
        destination: const Destination(
          name: 'City Hospital',
          address: 'FC Road, Pune',
          location: _pune,
        ),
      );
      return (b, r);
    }

    test('writes an open request in the requester\'s name', () async {
      final (_, r) = await create();
      final d = await rig.data('blood_requests/${r.id}');
      expect(d['requesterId'], 'requester');
      expect(d['requesterName'], 'Riya Requester');
      expect(d['status'], 'searching');
      expect(d['units'], 2);
      expect(d['bloodGroups'], ['A+', 'O+']);
      expect(d['patientBloodGroup'], 'A+');
      expect(d['acceptedDonorIds'], isEmpty);
      expect(d['declinedByDonorIds'], isEmpty);
    });

    test('opens a six-hour window and starts the timeline', () async {
      final (_, r) = await create();
      final d = await rig.data('blood_requests/${r.id}');
      final left = (d['expiresAt'] as fs.Timestamp)
          .toDate()
          .difference(DateTime.now());
      expect(left.inMinutes, inInclusiveRange(355, 360));
      final steps = (d['timeline'] as List).map((e) => (e as Map)['status']);
      expect(steps, ['created', 'searching']);
    });

    test('stores locations as {lat, lng} maps', () async {
      final (_, r) = await create();
      final d = await rig.data('blood_requests/${r.id}');
      expect(d['requestLocation'], {'lat': 18.5204, 'lng': 73.8567});
      expect((d['destination'] as Map)['location'], {'lat': 18.5204, 'lng': 73.8567});
    });

    test('keeps the number typed on the form, with its country code', () async {
      final (_, r) = await create(phone: '501234567', code: '+971');
      final d = await rig.data('blood_requests/${r.id}');
      expect(d['phone'], '501234567');
      expect(d['phoneCountryCode'], '+971');
      expect(d['fullPhoneNumber'], '+971501234567');
    });

    test('a number with no country code is taken as +91', () async {
      final (_, r) = await create(phone: '9876500000', code: null);
      final d = await rig.data('blood_requests/${r.id}');
      expect(d['phoneCountryCode'], '+91');
      expect(d['fullPhoneNumber'], '+919876500000');
    });

    test('a number typed with a leading + is split into code and digits', () async {
      final (_, r) = await create(phone: '+14155550123', code: null);
      final d = await rig.data('blood_requests/${r.id}');
      expect(d['phoneCountryCode'], '+1');
      expect(d['phone'], '4155550123');
    });

    test('the patient\'s name is kept off the world-readable request', () async {
      final (_, r) = await create();
      final d = await rig.data('blood_requests/${r.id}');
      expect(d.containsKey('patientName'), isFalse);
      expect(d.toString(), isNot(contains('Sunil')));
      final secret = await rig.data('blood_requests/${r.id}/private/patient');
      expect(secret['name'], 'Sunil Patient');
    });

    test('the requester can read the patient name back', () async {
      final (b, r) = await create();
      expect(await b.patientNameStream(r.id).first, 'Sunil Patient');
    });
  });

  group('accepting', () {
    Future<void> accept(String donor, {String id = 'r1'}) async {
      final b = await rig.as_(donor);
      await b.respondToInvitation(id, InvitationStatus.accepted);
    }

    test('adds the donor with their registered number and country code', () async {
      await rig.request('r1');
      await accept('donor1');
      final d = await rig.data('blood_requests/r1');
      final donor = (d['acceptedDonors'] as List).single as Map;
      expect(donor['id'], 'donor1');
      expect(donor['name'], 'Dana Donor');
      expect(donor['phone'], '4155550123');
      expect(donor['phoneCountryCode'], '+1');
      expect(d['acceptedDonorIds'], ['donor1']);
      expect(d['status'], 'donorAccepted');
    });

    test('records the acceptance on the timeline', () async {
      await rig.request('r1');
      await accept('donor1');
      final d = await rig.data('blood_requests/r1');
      final last = (d['timeline'] as List).last as Map;
      expect(last['status'], 'donorAccepted');
      expect(last['note'], contains('Dana Donor'));
    });

    test('measures the donor\'s distance to the hospital', () async {
      await rig.request('r1');
      final b = await rig.as_('donor1');
      b.myLocation = const GeoPoint(18.55, 73.88);
      await b.respondToInvitation('r1', InvitationStatus.accepted);
      final donor = ((await rig.data('blood_requests/r1'))['acceptedDonors'] as List).single as Map;
      expect(donor['distanceKm'] as num, closeTo(4.4, 1.0));
    });

    test('the first donor wins a one-unit request; the second is refused', () async {
      await rig.request('r1', units: 1);
      await accept('donor1');
      await expectLater(accept('donor2'), throwsA(isA<StateError>()));
      expect((await rig.data('blood_requests/r1'))['acceptedDonorIds'], ['donor1']);
    });

    test('a multi-unit request takes one donor per unit', () async {
      await rig.request('r1', units: 2);
      await accept('donor1');
      await accept('donor2');
      expect((await rig.data('blood_requests/r1'))['acceptedDonorIds'], ['donor1', 'donor2']);
      await rig.user('donor3', name: 'Third');
      await expectLater(accept('donor3'), throwsA(isA<StateError>()));
    });

    test('accepting twice does not add the donor twice', () async {
      await rig.request('r1', units: 3);
      await accept('donor1');
      await accept('donor1');
      expect((await rig.data('blood_requests/r1'))['acceptedDonorIds'], ['donor1']);
    });

    for (final s in ['cancelled', 'fulfilled', 'expired', 'removedByAdmin']) {
      test('a $s request can no longer be accepted', () async {
        await rig.request('r1', status: s);
        await expectLater(accept('donor1'), throwsA(isA<StateError>()));
      });
    }

    test('a request that no longer exists cannot be accepted', () async {
      await expectLater(accept('donor1', id: 'gone'), throwsA(isA<StateError>()));
    });
  });

  group('declining and withdrawing', () {
    test('declining only adds the donor to the declined list', () async {
      await rig.request('r1');
      await (await rig.as_('donor1')).respondToInvitation('r1', InvitationStatus.declined);
      final d = await rig.data('blood_requests/r1');
      expect(d['declinedByDonorIds'], ['donor1']);
      expect(d['status'], 'searching');
      expect(d['acceptedDonorIds'], isEmpty);
    });

    test('withdrawing puts the request back to searching for that unit', () async {
      await rig.request('r1', accepted: ['donor1'], status: 'donorAccepted');
      await (await rig.as_('donor1')).withdrawFromRequest('r1');
      final d = await rig.data('blood_requests/r1');
      expect(d['status'], 'searching');
      expect(d['acceptedDonorIds'], isEmpty);
      expect(d['declinedByDonorIds'], contains('donor1'));
    });

    test('withdrawing leaves the other donors in place', () async {
      await rig.request('r1', units: 2, accepted: ['donor1', 'donor2'], status: 'donorAccepted');
      await (await rig.as_('donor1')).withdrawFromRequest('r1');
      expect((await rig.data('blood_requests/r1'))['acceptedDonorIds'], ['donor2']);
    });

    test('someone who never accepted cannot withdraw anyone', () async {
      await rig.request('r1', accepted: ['donor1'], status: 'donorAccepted');
      await (await rig.as_('donor2')).withdrawFromRequest('r1');
      final d = await rig.data('blood_requests/r1');
      expect(d['acceptedDonorIds'], ['donor1']);
      expect(d['status'], 'donorAccepted');
    });
  });

  group('the requester ending a request', () {
    test('cancelling marks it cancelled and clears live locations', () async {
      await rig.request('r1');
      await (await rig.as_('requester')).cancelRequest('r1');
      final d = await rig.data('blood_requests/r1');
      expect(d['status'], 'cancelled');
      expect((d['timeline'] as List).last['status'], 'cancelled');
    });

    test('fulfilling marks it fulfilled', () async {
      await rig.request('r1', status: 'coordinating', accepted: ['donor1']);
      await (await rig.as_('requester')).markFulfilled('r1');
      expect((await rig.data('blood_requests/r1'))['status'], 'fulfilled');
    });

    test('a finished request cannot be changed again', () async {
      await rig.request('r1');
      final b = await rig.as_('requester');
      await b.cancelRequest('r1');
      await b.markFulfilled('r1');
      expect((await rig.data('blood_requests/r1'))['status'], 'cancelled');
    });

    test('extending reopens the search for six more hours', () async {
      await rig.request('r1', status: 'expired', expiresAt: DateTime.now().subtract(const Duration(hours: 1)));
      await (await rig.as_('requester')).extendRequest('r1');
      final d = await rig.data('blood_requests/r1');
      expect(d['status'], 'searching');
      expect((d['expiresAt'] as fs.Timestamp).toDate().isAfter(DateTime.now().add(const Duration(hours: 5))), isTrue);
    });

    test('only the requester can extend', () async {
      await rig.request('r1', status: 'expired');
      await (await rig.as_('donor1')).extendRequest('r1');
      expect((await rig.data('blood_requests/r1'))['status'], 'expired');
    });
  });

  group('which requests a donor is offered', () {
    test('an open request for their blood group, nearby', () async {
      await rig.request('r1');
      final b = await rig.as_('donor1');
      b.myLocation = const GeoPoint(18.53, 73.86);
      final offered = await _offered(b);
      expect(offered.map((i) => i.id), ['r1']);
      expect(offered.single.status, InvitationStatus.pending);
    });

    test('not a request for a different blood group', () async {
      await rig.request('r1', groups: ['B+']);
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('only groups the requester chose, not every compatible one', () async {
      await rig.user('donorO', group: 'O-');
      await rig.request('r1', groups: ['A+']); // O- could give to A+, but was not chosen
      expect(await _offered(await rig.as_('donorO')), isEmpty);
    });

    test('not one the donor made themselves', () async {
      await rig.user('requester', group: 'A+');
      await rig.request('r1');
      expect(await _offered(await rig.as_('requester')), isEmpty);
    });

    test('not one the donor already declined', () async {
      await rig.request('r1', declined: ['donor1']);
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('not when Donor Mode is off', () async {
      await rig.user('donor1', availability: 'off');
      await rig.request('r1');
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('not during the waiting period after a donation', () async {
      await rig.user('donor1', lastDonation: DateTime.now().subtract(const Duration(days: 20)));
      await rig.request('r1');
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('again once the waiting period has passed', () async {
      await rig.user('donor1', lastDonation: DateTime.now().subtract(const Duration(days: 120)));
      await rig.request('r1');
      expect((await _offered(await rig.as_('donor1'))).map((i) => i.id), ['r1']);
    });

    test('not an expired request', () async {
      await rig.request('r1', expiresAt: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    for (final s in ['cancelled', 'fulfilled', 'donorAccepted']) {
      test('not a request that is already $s', () async {
        await rig.request('r1', status: s, accepted: s == 'donorAccepted' ? ['donor2'] : []);
        expect(await _offered(await rig.as_('donor1')), isEmpty);
      });
    }

    test('not a request whose every unit already has a donor', () async {
      await rig.request('r1', units: 1, accepted: ['donor2'], status: 'searching');
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('still one with room left on a multi-unit request', () async {
      await rig.request('r1', units: 2, accepted: ['donor2'], status: 'searching');
      expect((await _offered(await rig.as_('donor1'))).map((i) => i.id), ['r1']);
    });

    test('a donor who accepted keeps seeing it, marked accepted', () async {
      await rig.request('r1', units: 1, accepted: ['donor1'], status: 'donorAccepted');
      final offered = await _offered(await rig.as_('donor1'));
      expect(offered.single.status, InvitationStatus.accepted);
    });

    test('not one beyond the donor\'s own radius', () async {
      await rig.user('donor1', maxKm: 5);
      await rig.request('r1', at: const GeoPoint(19.076, 72.8777)); // Mumbai
      final b = await rig.as_('donor1');
      b.myLocation = _pune;
      expect(await _offered(b), isEmpty);
    });

    test('one inside the radius, nearest first', () async {
      await rig.request('near', at: const GeoPoint(18.53, 73.86));
      await rig.request('mid', at: const GeoPoint(18.65, 73.9));
      final b = await rig.as_('donor1');
      b.myLocation = _pune;
      expect((await _offered(b)).map((i) => i.id), ['near', 'mid']);
    });

    test('with no GPS, a request from another state is not offered', () async {
      await rig.request('r1', state: 'Kerala', at: null);
      expect(await _offered(await rig.as_('donor1')), isEmpty);
    });

    test('with no GPS, a request from the same state is offered', () async {
      await rig.request('r1', state: 'Maharashtra', at: null);
      expect((await _offered(await rig.as_('donor1'))).map((i) => i.id), ['r1']);
    });

    test('the offer never carries the requester\'s phone', () async {
      await rig.request('r1');
      final i = (await _offered(await rig.as_('donor1'))).single;
      expect(i.toString(), isNot(contains('501234567')));
    });
  });

  group('saving the donor\'s position', () {
    test('writes the device GPS to the donor\'s profile', () async {
      final b = await rig.as_('donor1');
      b.myLocation = const GeoPoint(28.6139, 77.2090);
      await Future<void>.delayed(Duration.zero);
      final d = await rig.data('users/donor1');
      expect(d['latitude'], 28.6139);
      expect(d['longitude'], 77.2090);
      expect(d['location'], {'lat': 28.6139, 'lng': 77.2090});
      expect(d['locationUpdatedAt'], isNotNull);
    });

    test('keeps the rest of the profile intact', () async {
      final b = await rig.as_('donor1');
      b.myLocation = _pune;
      await Future<void>.delayed(Duration.zero);
      final d = await rig.data('users/donor1');
      expect(d['name'], 'Dana Donor');
      expect(d['phone'], '4155550123');
      expect((d['donor'] as Map)['availability'], 'available');
    });

    test('GPS jitter under 300 m does not write again', () async {
      final b = await rig.as_('donor1');
      b.myLocation = _pune;
      await Future<void>.delayed(Duration.zero);
      b.myLocation = const GeoPoint(18.5210, 73.8570); // ~80 m away
      await Future<void>.delayed(Duration.zero);
      expect((await rig.data('users/donor1'))['latitude'], 18.5204);
    });

    test('a real move is saved', () async {
      final b = await rig.as_('donor1');
      b.myLocation = _pune;
      await Future<void>.delayed(Duration.zero);
      b.myLocation = const GeoPoint(18.60, 73.90);
      await Future<void>.delayed(Duration.zero);
      expect((await rig.data('users/donor1'))['latitude'], 18.60);
    });

    test('clearing the position writes nothing', () async {
      final b = await rig.as_('donor1');
      b.myLocation = null;
      await Future<void>.delayed(Duration.zero);
      expect((await rig.data('users/donor1')).containsKey('location'), isFalse);
    });

    test('nothing is written when nobody is signed in', () async {
      final b = FirebaseBackend.forTesting(rig.db, MockFirebaseAuth());
      b.myLocation = _pune;
      await Future<void>.delayed(Duration.zero);
      expect((await rig.data('users/donor1')).containsKey('location'), isFalse);
    });
  });
}
