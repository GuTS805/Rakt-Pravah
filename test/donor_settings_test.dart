import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/donate/donate_screen.dart';
import 'package:rakt_pravah/features/donate/donor_settings_screen.dart';
import 'package:rakt_pravah/shared/settings_widgets.dart';

import 'fakes.dart';

// What a donor can change about how and when they are asked to help, and what
// the Donate tab tells them. Every control must end up on the donor profile,
// because the server matches requests from that profile.

UserProfile _user({int age = 30}) => UserProfile(
  id: 'u1',
  name: 'Dana Donor',
  bloodGroup: BloodGroup.aPos,
  phone: '9876543210',
  dateOfBirth: DateTime.now().subtract(Duration(days: age * 366)),
  gender: Gender.female,
);

DonorProfile _donor({
  DonorAvailability availability = DonorAvailability.available,
  bool notifyPush = true,
  bool notifyCritical = false,
  bool locationGranted = true,
  double km = 30,
  DateTime? lastDonation,
}) => DonorProfile(
  availability: availability,
  bloodGroup: BloodGroup.aPos,
  notifyPush: notifyPush,
  notifyCritical: notifyCritical,
  locationGranted: locationGranted,
  maxDistanceKm: km,
  lastDonation: lastDonation,
);

Future<FakeBackend> _pump(
  WidgetTester tester,
  Widget screen, {
  DonorProfile? donor,
  LocationResult location = const LocationDenied(),
  List<Invitation> invitations = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final user = _user();
  final backend = FakeBackend(
    user: user,
    donor: donor ?? _donor(),
    invitations: invitations,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWith((ref) => user),
        locationServiceProvider.overrideWithValue(
          FakeLocationService(result: location),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

Finder _switchFor(String title) => find.descendant(
  of: find.ancestor(
    of: find.text(title),
    matching: find.byType(SettingsSwitchTile),
  ),
  matching: find.byType(Switch),
);

void main() {
  group('Donor settings', () {
    testWidgets('lists availability, notifications, radius and location', (
      tester,
    ) async {
      await _pump(tester, const DonorSettingsScreen());
      expect(find.text('AVAILABILITY'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('MATCH RADIUS'), findsOneWidget);
      expect(find.text('Location access'), findsOneWidget);
    });

    testWidgets('switching push off is saved on the donor profile', (
      tester,
    ) async {
      final backend = await _pump(tester, const DonorSettingsScreen());
      await tester.tap(_switchFor('Push notifications'));
      await tester.pumpAndSettle();
      expect(backend.setDonorProfileCalls.last.notifyPush, isFalse);
      expect(backend.donorProfile.notifyPush, isFalse);
    });

    testWidgets('critical-only is saved on the donor profile', (tester) async {
      final backend = await _pump(tester, const DonorSettingsScreen());
      await tester.tap(_switchFor('Critical requests only'));
      await tester.pumpAndSettle();
      expect(backend.donorProfile.notifyCritical, isTrue);
    });

    testWidgets('the radius slider ranges 2-40 km and is saved', (
      tester,
    ) async {
      final backend = await _pump(
        tester,
        const DonorSettingsScreen(),
        donor: _donor(km: 30),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 2);
      expect(slider.max, 40);
      expect(slider.value, 30);

      await tester.drag(find.byType(Slider), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(backend.donorProfile.maxDistanceKm, lessThan(30));
      expect(backend.donorProfile.maxDistanceKm, greaterThanOrEqualTo(2));
    });

    testWidgets('turning location off needs no permission prompt', (
      tester,
    ) async {
      final backend = await _pump(tester, const DonorSettingsScreen());
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(backend.donorProfile.locationGranted, isFalse);
    });

    testWidgets('turning location on explains a refusal', (tester) async {
      await _pump(
        tester,
        const DonorSettingsScreen(),
        donor: _donor(locationGranted: false),
      );
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location access is needed to match you by distance.'),
        findsOneWidget,
      );
    });

    testWidgets('a permanently blocked location points to system settings', (
      tester,
    ) async {
      await _pump(
        tester,
        const DonorSettingsScreen(),
        donor: _donor(locationGranted: false),
        location: const LocationDeniedForever(),
      );
      await tester.tap(_switchFor('Location access'));
      await tester.pumpAndSettle();
      expect(find.textContaining('blocked'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('a donor in the waiting period is told when they can return', (
      tester,
    ) async {
      await _pump(
        tester,
        const DonorSettingsScreen(),
        donor: _donor(
          availability: DonorAvailability.off,
          lastDonation: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      expect(find.textContaining('Thanks for donating'), findsOneWidget);
      expect(find.textContaining('Next eligible donation date'), findsOneWidget);
      expect(find.textContaining('Time remaining'), findsOneWidget);
    });

    testWidgets('a donor with no recent donation sees no waiting notice', (
      tester,
    ) async {
      await _pump(tester, const DonorSettingsScreen());
      expect(find.textContaining('Thanks for donating'), findsNothing);
    });

    testWidgets('an account under 18 cannot turn availability on', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final minor = _user(age: 16);
      final backend = FakeBackend(
        user: minor,
        donor: _donor(availability: DonorAvailability.off),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            currentUserProvider.overrideWith((ref) => minor),
            locationServiceProvider.overrideWithValue(FakeLocationService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DonorSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(DonorAvailability.available.label));
      await tester.pumpAndSettle();
      expect(backend.setDonorProfileCalls, isEmpty);
      expect(find.textContaining('18'), findsWidgets);
    });
  });

  group('Donate tab', () {
    testWidgets('summarises blood group, radius and location access', (
      tester,
    ) async {
      await _pump(tester, const DonateScreen());
      expect(find.text('Your blood group'), findsOneWidget);
      expect(find.text('A+'), findsWidgets);
      expect(find.text('Match radius'), findsOneWidget);
      expect(find.text('30 km'), findsOneWidget);
      expect(find.text('Granted'), findsOneWidget);
    });

    testWidgets('says so when location is not granted', (tester) async {
      await _pump(
        tester,
        const DonateScreen(),
        donor: _donor(locationGranted: false),
      );
      expect(find.text('Not granted'), findsOneWidget);
    });

    testWidgets('an available donor with no requests is told there are none', (
      tester,
    ) async {
      await _pump(tester, const DonateScreen());
      expect(find.text('No matching requests right now'), findsOneWidget);
    });

    testWidgets('a donor who is off is told how to start receiving requests', (
      tester,
    ) async {
      await _pump(
        tester,
        const DonateScreen(),
        donor: _donor(availability: DonorAvailability.off),
      );
      expect(
        find.text('Turn on Donor Mode above to start receiving requests near you.'),
        findsOneWidget,
      );
    });
  });
}
