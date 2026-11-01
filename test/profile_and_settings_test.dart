import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/auth/register_screen.dart';
import 'package:rakt_pravah/features/profile/profile_screen.dart';
import 'package:rakt_pravah/features/profile/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// An auth controller that starts signed in.
class _SignedIn extends AuthController {
  _SignedIn(this._user);
  final UserProfile _user;
  @override
  AuthState build() => AuthState(AuthStatus.authenticated, _user);
}

class _DeviceOnly extends FakeBackend {
  _DeviceOnly({super.user});
  @override
  bool get isDeviceOnlyAccount => true;
}

const _user = UserProfile(
  id: 'u1',
  name: 'Dana Donor',
  bloodGroup: BloodGroup.aPos,
  phone: '4155550123',
  countryCode: '+1',
  email: 'dana@example.com',
  city: 'Pune',
  state: 'Maharashtra',
);

late GoRouter _router;

Future<(FakeBackend, ProviderContainer)> _pumpProfile(
  WidgetTester tester, {
  FakeBackend? backend,
  DonorProfile? donor,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final b = backend ??
      FakeBackend(
        user: _user,
        donor: donor ??
            const DonorProfile(
              availability: DonorAvailability.available,
              bloodGroup: BloodGroup.aPos,
              totalDonations: 3,
            ),
      );
  late ProviderContainer container;
  _router = GoRouter(
    initialLocation: Routes.you,
    routes: [
      GoRoute(
        path: Routes.you,
        builder: (context, _) {
          container = ProviderScope.containerOf(context);
          return const ProfileScreen();
        },
      ),
      for (final p in [
        Routes.donorSettings,
        Routes.requestHistory,
        Routes.donationHistory,
        Routes.privacy,
        Routes.profileEdit,
        Routes.settings,
        Routes.secureAccount,
      ])
        GoRoute(path: p, builder: (_, _) => Scaffold(body: Text('PAGE $p'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(b),
        authControllerProvider.overrideWith(() => _SignedIn(_user)),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
  return (b, container);
}

Future<void> _tapRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  group('Profile ("You" tab)', () {
    testWidgets('shows who you are: name, number with country code, place, blood group', (
      tester,
    ) async {
      await _pumpProfile(tester);
      expect(find.text('Dana Donor'), findsOneWidget);
      expect(find.textContaining('415'), findsWidgets);
      expect(find.textContaining('+1'), findsWidgets);
      expect(find.text('A+'), findsWidgets);
    });

    testWidgets('shows the donation count', (tester) async {
      await _pumpProfile(tester);
      expect(find.text('3 completed'), findsOneWidget);
      expect(find.text('3 donations'), findsOneWidget);
    });

    for (final (title, path) in [
      ('Donor settings', Routes.donorSettings),
      ('Request history', Routes.requestHistory),
      ('Donation history', Routes.donationHistory),
      ('Privacy & location', Routes.privacy),
      ('Edit profile', Routes.profileEdit),
      ('Settings', Routes.settings),
    ]) {
      testWidgets('"$title" opens its page', (tester) async {
        await _pumpProfile(tester);
        await _tapRow(tester, title);
        expect(find.text('PAGE $path'), findsOneWidget);
      });
    }

    testWidgets('an email account is not nagged to secure itself', (tester) async {
      await _pumpProfile(tester);
      expect(find.text('Secure your account'), findsNothing);
    });

    testWidgets('a device-only account is offered a way to secure itself', (
      tester,
    ) async {
      await _pumpProfile(tester, backend: _DeviceOnly(user: _user));
      expect(find.text('Secure your account'), findsOneWidget);
      await _tapRow(tester, 'Secure your account');
      expect(find.text('PAGE ${Routes.secureAccount}'), findsOneWidget);
    });

    testWidgets('logging out asks first; Cancel keeps you signed in', (tester) async {
      final (b, container) = await _pumpProfile(tester);
      await _tapRow(tester, 'Log out');
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
      expect(b.currentUser, isNotNull);
    });

    testWidgets('confirming logs you out of the app and the backend', (tester) async {
      final (b, container) = await _pumpProfile(tester);
      await _tapRow(tester, 'Log out');
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(b.currentUser, isNull);
    });

    testWidgets('"Report a problem" sends the report to the operators', (
      tester,
    ) async {
      final (backend, _) = await _pumpProfile(tester);
      await _tapRow(tester, 'Report a problem');
      expect(find.text('Describe the problem…'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Someone is misusing a request');
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Report sent. Thank you.'), findsOneWidget);
      expect(backend.reports, [('Someone is misusing a request', null, null)]);
    });
  });

  group('Settings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> pump(WidgetTester tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(theme: AppTheme.light(), home: const SettingsScreen());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('offers system, light and dark appearance', (tester) async {
      await pump(tester);
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('follows the system until told otherwise', (tester) async {
      final c = await pump(tester);
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('choosing Dark switches the app to dark', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('and Light switches it back', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(c.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('shows the app version', (tester) async {
      await pump(tester);
      expect(find.text('Version'), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
    });
  });

  group('Create account (validation)', () {
    Future<FakeBackend> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final backend = FakeBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(backend)],
          child: MaterialApp(theme: AppTheme.light(), home: const RegisterScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.text('Create account').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('an empty form is refused with a reason for each field', (tester) async {
      final backend = await pump(tester);
      await submit(tester);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 6 characters'), findsOneWidget);
      expect(find.text('Enter your name'), findsOneWidget);
      expect(backend.registeredUsers, isEmpty);
    });

    testWidgets('a blood group must be chosen', (tester) async {
      await pump(tester);
      await submit(tester);
      expect(find.text('Select your blood group'), findsOneWidget);
    });

    testWidgets('a malformed email is refused', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'no-at-sign');
      await submit(tester);
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('a one-letter name is refused', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField).at(2), 'A');
      await submit(tester);
      expect(find.text('Enter your name'), findsOneWidget);
    });
  });
}
