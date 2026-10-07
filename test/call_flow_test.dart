import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/coordination/coordination_screen.dart';
import 'package:rakt_pravah/features/requests/request_detail_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

/// Records every URL the app tries to open instead of launching it.
class _RecordingLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  // The requester typed a +971 number into the request form; the donor
  // registered with a +1 number. Neither is the +91 the app falls back to, so
  // a wrong country code would show up in the dialled number.
  const requester = UserProfile(
    id: 'requester-1',
    name: 'Vikram Sen',
    bloodGroup: BloodGroup.bPos,
    phone: '5550001111',
    countryCode: '+44',
  );
  const donor = UserProfile(
    id: 'donor-1',
    name: 'Rahul Sharma',
    bloodGroup: BloodGroup.aPos,
    phone: '4155550123',
    countryCode: '+1',
  );

  final request = BloodRequest(
    id: 'req-call-1',
    requesterId: requester.id,
    requesterName: requester.name,
    patientName: 'Sunil Sen',
    patientBloodGroup: BloodGroup.aPos,
    bloodGroups: const [BloodGroup.aPos],
    bloodType: 'Blood',
    units: 1,
    urgency: Urgency.urgent,
    status: RequestStatus.donorAccepted,
    createdAt: DateTime.now(),
    // The contact number entered when the request was created.
    phoneCountryCode: '+971',
    phone: '501234567',
    destination: const Destination(
      name: 'Apollo Hospital',
      address: 'GS Road, Guwahati',
      location: GeoPoint(26.1445, 91.7362),
    ),
    requestLocationLabel: 'Guwahati',
    acceptedDonors: [
      AcceptedDonor(
        id: donor.id,
        name: donor.name,
        bloodGroup: donor.bloodGroup,
        // The donor's registered number, copied when they accepted.
        phone: donor.phone,
        phoneCountryCode: donor.countryCode,
        distanceKm: 2.8,
        acceptedAt: DateTime.now(),
      ),
    ],
  );

  late _RecordingLauncher launcher;

  setUp(() {
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  Future<void> pump(WidgetTester tester, UserProfile me, Widget home) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(
            FakeBackend(user: me, requests: [request]),
          ),
          currentUserProvider.overrideWith((ref) => me),
          requestProvider(request.id).overrideWith(
            (ref) => Stream.value(request),
          ),
          patientNameProvider(request.id).overrideWith(
            (ref) => Stream.value('Sunil Sen'),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: home),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('numbers carry their own country code', () {
    test('the request number is the one entered at creation', () {
      expect(request.fullPhoneNumber, '+971501234567');
    });

    test('the donor number is the registered one, with its code', () {
      expect(request.acceptedDonors.single.fullPhoneNumber, '+14155550123');
    });

    test('a donor with no saved code falls back to +91', () {
      final legacy = AcceptedDonor(
        id: 'd',
        name: 'Old',
        phone: '9876543210',
        acceptedAt: DateTime(2026, 1, 1),
      );
      expect(legacy.fullPhoneNumber, '+919876543210');
    });
  });

  testWidgets(
    'donor calling the requester dials the number from the request',
    (tester) async {
      await pump(tester, donor, CoordinationScreen(requestId: request.id));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Call'));
      await tester.pump();

      // Not the donor's own number, and not the requester's profile number.
      expect(launcher.launched, ['tel:+971501234567']);
    },
  );

  testWidgets(
    'requester calling the donor dials the donor\'s registered number',
    (tester) async {
      await pump(tester, requester, RequestDetailScreen(requestId: request.id));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Call'));
      await tester.pump();

      expect(launcher.launched, ['tel:+14155550123']);
    },
  );
}
