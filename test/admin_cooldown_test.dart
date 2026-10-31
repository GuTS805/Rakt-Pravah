import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rakt_pravah/admin/admin_providers.dart';
import 'package:rakt_pravah/admin/screens/admin_settings_screen.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('Admin Cooldown Period Configuration', () {
    late FakeBackend fakeBackend;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeBackend = FakeBackend();
    });

    Widget createTestWidget({CooldownConfig? initialConfig}) {
      if (initialConfig != null) {
        fakeBackend.emitCooldownConfig(initialConfig);
      }
      return ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          adminCooldownConfigProvider.overrideWith(
            (ref) => fakeBackend.cooldownConfigStream,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AdminSettingsScreen(),
          ),
        ),
      );
    }

    testWidgets('renders Cooldown Period toggle and Cooldown Duration in Donor Configuration',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Donor Configuration'), findsOneWidget);
      expect(find.text('Cooldown Period'), findsOneWidget);
      expect(
        find.text('Minimum days between donations for donor safety.'),
        findsWidgets,
      );
      expect(find.text('ON'), findsOneWidget);
      expect(find.text('Cooldown Duration: [ 90 days ]'), findsOneWidget);
    });

    testWidgets('toggling Cooldown Period shows confirmation dialog; cancel leaves setting unchanged',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget(
        initialConfig: const CooldownConfig(enabled: true, durationDays: 90),
      ));
      await tester.pumpAndSettle();

      // Find switch for Cooldown Period
      final cooldownSwitch = find.byType(Switch).at(3); // 0: Maint, 1: Reg, 2: Auto-Match, 3: Cooldown
      await tester.tap(cooldownSwitch);
      await tester.pumpAndSettle();

      // Verify confirmation dialog appeared
      expect(find.text('Disable Cooldown Period?'), findsOneWidget);
      expect(
        find.textContaining('Disabling the cooldown period will remove donation cooldown restrictions'),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is gone, cooldown remains enabled
      expect(find.text('Disable Cooldown Period?'), findsNothing);
      expect(fakeBackend.cooldownConfig.enabled, isTrue);
      expect(find.text('ON'), findsOneWidget);
    });

    testWidgets('confirming toggle disables Cooldown Period immediately in backend and UI',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget(
        initialConfig: const CooldownConfig(enabled: true, durationDays: 90),
      ));
      await tester.pumpAndSettle();

      // Find switch for Cooldown Period
      final cooldownSwitch = find.byType(Switch).at(3);
      await tester.tap(cooldownSwitch);
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text('Disable'));
      await tester.pumpAndSettle();

      expect(fakeBackend.cooldownConfig.enabled, isFalse);
      expect(find.text('OFF'), findsOneWidget);
    });

    testWidgets('changing Cooldown Duration shows confirmation dialog; cancel reverts; confirm applies',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget(
        initialConfig: const CooldownConfig(enabled: true, durationDays: 90),
      ));
      await tester.pumpAndSettle();

      // Find first slider (Cooldown Duration)
      final durationSlider = find.byType(Slider).first;

      // Drag to right to change duration
      await tester.drag(durationSlider, const Offset(60, 0));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Update Cooldown Duration?'), findsOneWidget);
      expect(
        find.textContaining('This will immediately affect donor eligibility calculations'),
        findsOneWidget,
      );

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed, duration remains 90
      expect(find.text('Update Cooldown Duration?'), findsNothing);
      expect(fakeBackend.cooldownConfig.durationDays, 90);
      expect(find.text('Cooldown Duration: [ 90 days ]'), findsOneWidget);

      // Drag again and confirm
      await tester.drag(durationSlider, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(find.text('Update Cooldown Duration?'), findsOneWidget);
      await tester.tap(find.text('Update Duration'));
      await tester.pumpAndSettle();

      // Verify duration changed in backend and UI
      expect(fakeBackend.cooldownConfig.durationDays, isNot(90));
      expect(find.text('Cooldown Duration: [ 90 days ]'), findsNothing);
    });

    testWidgets('when Cooldown is OFF, donors remain eligible and Donor Mode is not disabled',
        (tester) async {
      // Set cooldown to OFF
      fakeBackend.emitCooldownConfig(
        const CooldownConfig(enabled: false, durationDays: 90),
      );

      // Enable Donor Mode
      fakeBackend.emitDonor(
        const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
        ),
      );

      // Verify donor state
      expect(fakeBackend.donorProfile.isInCooldown, isFalse);
      expect(fakeBackend.donorProfile.cooldownRemaining, Duration.zero);
      expect(fakeBackend.donorProfile.nextEligibleDonationDate, isNull);

      // Record a donation
      await fakeBackend.recordDonation();

      // With Cooldown OFF, Donor Mode should NOT be automatically disabled
      expect(fakeBackend.donorProfile.availability, DonorAvailability.available);
      expect(fakeBackend.donorProfile.isInCooldown, isFalse);
    });

    testWidgets('when Cooldown is ON, donors enter cooldown and Donor Mode is disabled',
        (tester) async {
      // Set cooldown to ON
      fakeBackend.emitCooldownConfig(
        const CooldownConfig(enabled: true, durationDays: 90),
      );
      fakeBackend.emitDonor(
        const DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: BloodGroup.oPos,
        ),
      );

      // Record a donation
      await fakeBackend.recordDonation();

      // With Cooldown ON, Donor Mode should automatically be disabled
      expect(fakeBackend.donorProfile.availability, DonorAvailability.off);
      expect(fakeBackend.donorProfile.isInCooldown, isTrue);
      expect(fakeBackend.donorProfile.cooldownRemaining, isNotNull);
      expect(fakeBackend.donorProfile.nextEligibleDonationDate, isNotNull);

      // If admin toggles cooldown OFF, eligibility and donor mode are restored
      fakeBackend.emitCooldownConfig(
        const CooldownConfig(enabled: false, durationDays: 90),
      );
      expect(fakeBackend.donorProfile.availability, DonorAvailability.available);
      expect(fakeBackend.donorProfile.isInCooldown, isFalse);
    });

    testWidgets('cooldown setting persists across page refresh / widget reload',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Initial screen load
      await tester.pumpWidget(createTestWidget(
        initialConfig: const CooldownConfig(enabled: true, durationDays: 90),
      ));
      await tester.pumpAndSettle();

      // 2. Toggle to OFF and confirm
      final cooldownSwitch = find.byType(Switch).at(3);
      await tester.tap(cooldownSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable'));
      await tester.pumpAndSettle();

      expect(find.text('OFF'), findsOneWidget);

      // 3. Simulate page refresh by re-mounting a brand new widget tree without initialConfig override
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 4. Verify setting remains OFF after refresh
      expect(find.text('OFF'), findsOneWidget);
      expect(fakeBackend.cooldownConfig.enabled, isFalse);
    });
  });
}
