import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/blood_group_picker.dart';
import 'package:rakt_pravah/data/backend.dart' show SignInFailure;
import 'package:rakt_pravah/core/widgets/status_timeline.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/auth/onboarding_screen.dart';
import 'package:rakt_pravah/features/profile/secure_account_screen.dart';
import 'package:rakt_pravah/features/splash/splash_screen.dart';
import 'package:rakt_pravah/shared/segmented_control.dart';

import 'fakes.dart';

/// An auth controller that starts in a chosen state.
class _Auth extends AuthController {
  _Auth(this._start);
  final AuthState _start;
  @override
  AuthState build() => _start;
}

const _user = UserProfile(
  id: 'u1',
  name: 'Uma',
  bloodGroup: BloodGroup.oPos,
  phone: '9876543210',
);

Future<void> _toLastPage(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('Splash', () {
    testWidgets('shows the brand, then restores the saved session', (
      tester,
    ) async {
      final backend = FakeBackend(user: _user);
      // restoreSession() hands back the signed-in user.
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(backend)],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.light(),
                home: const SplashScreen(),
              );
            },
          ),
        ),
      );
      expect(find.text('Rakt Pravah'), findsOneWidget);
      expect(find.text('Emergency blood, coordinated'), findsOneWidget);
      expect(container.read(authControllerProvider).status, AuthStatus.unknown);

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('with no saved session it falls through to sign-in', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(FakeBackend())],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.light(),
                home: const SplashScreen(),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    });
  });

  group('Onboarding', () {
    late ProviderContainer container;

    Future<void> pump(
      WidgetTester tester, {
      LocationResult location = const LocationDenied(),
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(FakeBackend(user: _user)),
            locationServiceProvider.overrideWithValue(
              FakeLocationService(result: location),
            ),
            authControllerProvider.overrideWith(
              () => _Auth(const AuthState(AuthStatus.needsOnboarding, _user)),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.light(),
                home: const OnboardingScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('starts on the first page', (tester) async {
      await pump(tester);
      expect(find.text('Blood when it counts'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('walks through all five pages to Get started', (tester) async {
      await pump(tester);
      for (final title in [
        'How a request works',
        'Donor Mode is yours to control',
        'Private by design',
        'Coordinate and help',
      ]) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('Get started finishes onboarding', (tester) async {
      await pump(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('Skip finishes onboarding straight away', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('the privacy page promises live location is opt-in', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('always opt-in'), findsOneWidget);
    });

    testWidgets('location is optional: refusing it explains where to change it', (
      tester,
    ) async {
      await pump(tester);
      await _toLastPage(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location was not enabled'), findsOneWidget);
      // Still on onboarding: a refusal does not block anything.
      expect(find.text('Coordinate and help'), findsOneWidget);
    });

    testWidgets('allowing location shows no warning', (tester) async {
      await pump(
        tester,
        location: const LocationGranted(GeoPoint(18.5, 73.8), 'Pune'),
      );
      await _toLastPage(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location was not enabled'), findsNothing);
    });
  });

  group('Secure your account', () {
    late GoRouter router;

    Future<FakeBackend> pump(
      WidgetTester tester, {
      FakeBackend? backend,
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final b = backend ?? FakeBackend(user: _user);
      router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (_, _) => const Scaffold(body: Text('PROFILE')),
          ),
          GoRoute(
            path: '/secure',
            builder: (_, _) => const SecureAccountScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(b)],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      router.push('/secure');
      await tester.pumpAndSettle();
      return b;
    }

    testWidgets('explains that the account exists only on this phone', (
      tester,
    ) async {
      await pump(tester);
      expect(find.textContaining('exists only on this phone'), findsOneWidget);
    });

    testWidgets('an invalid email is refused before anything is saved', (
      tester,
    ) async {
      final b = await pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(b.passwords, isEmpty);
    });

    testWidgets('a short password is refused', (tester) async {
      final b = await pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'me@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), '12345');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 6 characters'), findsOneWidget);
      expect(b.passwords, isEmpty);
    });

    testWidgets('the password can be revealed and hidden', (tester) async {
      await pump(tester);
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('a valid email and password are saved and the screen closes', (
      tester,
    ) async {
      final b = await pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'me@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(b.passwords['me@example.com'], 'secret123');
      expect(find.text('PROFILE'), findsOneWidget);
      expect(
        find.text('Done. You can sign in with this email anywhere.'),
        findsOneWidget,
      );
    });

    testWidgets('a rejected email shows the reason and stays on the form', (
      tester,
    ) async {
      final b = await pump(tester, backend: _RefusingBackend(user: _user));
      await tester.enterText(find.byType(TextFormField).at(0), 'taken@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('That email is already in use.'), findsOneWidget);
      expect(find.text('PROFILE'), findsNothing);
      expect(b.passwords, isEmpty);
    });
  });

  group('SegmentedControl', () {
    Future<List<int>> pump(WidgetTester tester, {int selected = 0}) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SegmentedControl(
              segments: const [
                Segment('Invitations'),
                Segment('My requests', badge: 3),
              ],
              selected: selected,
              onChanged: taps.add,
            ),
          ),
        ),
      );
      return taps;
    }

    testWidgets('shows every segment and a badge count', (tester) async {
      await pump(tester);
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('My requests'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('reports which segment was tapped', (tester) async {
      final taps = await pump(tester);
      await tester.tap(find.text('My requests'));
      await tester.tap(find.text('Invitations'));
      expect(taps, [1, 0]);
    });
  });

  group('StatusTimeline', () {
    BloodRequest request(RequestStatus status, {List<StatusEvent>? timeline}) =>
        BloodRequest(
          id: 'r',
          requesterId: 'u',
          requesterName: 'Uma',
          bloodGroups: const [BloodGroup.oPos],
          units: 1,
          urgency: Urgency.urgent,
          status: status,
          createdAt: DateTime(2026, 1, 1),
          destination: const Destination(name: 'H', address: 'A'),
          requestLocationLabel: 'X',
          timeline: timeline ?? const [],
        );

    Future<void> pump(WidgetTester tester, BloodRequest r) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(child: StatusTimeline(request: r)),
            ),
          ),
        );

    testWidgets('lists every step of the happy path', (tester) async {
      await pump(tester, request(RequestStatus.searching));
      for (final s in RequestStatus.lifecycle) {
        expect(find.text(s.label), findsOneWidget, reason: s.label);
      }
      expect(find.text('Cancelled'), findsNothing);
    });

    testWidgets('a cancelled request ends in its own Cancelled step', (
      tester,
    ) async {
      await pump(
        tester,
        request(
          RequestStatus.cancelled,
          timeline: [
            StatusEvent(status: RequestStatus.created, at: DateTime(2026)),
            StatusEvent(status: RequestStatus.searching, at: DateTime(2026)),
            StatusEvent(status: RequestStatus.cancelled, at: DateTime(2026)),
          ],
        ),
      );
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Fulfilled'), findsOneWidget); // still shown, as upcoming
    });

    for (final s in [RequestStatus.expired, RequestStatus.removedByAdmin]) {
      testWidgets('${s.label} also gets a final step', (tester) async {
        await pump(tester, request(s));
        expect(find.text(s.label), findsOneWidget);
      });
    }

    testWidgets('a fulfilled request has no unhappy ending', (tester) async {
      await pump(tester, request(RequestStatus.fulfilled));
      expect(find.text('Cancelled'), findsNothing);
      expect(find.text('Expired'), findsNothing);
    });
  });

  group('Blood group pickers', () {
    testWidgets('the single picker offers all eight groups and reports a pick', (
      tester,
    ) async {
      BloodGroup? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BloodGroupPicker(selected: null, onChanged: (g) => picked = g),
          ),
        ),
      );
      for (final g in BloodGroup.values) {
        expect(find.text(g.label), findsOneWidget, reason: g.label);
      }
      await tester.tap(find.text('AB-'));
      expect(picked, BloodGroup.abNeg);
    });

    testWidgets(
      'the multi picker only offers groups that can safely give to the patient',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: BloodGroupMultiPicker(
                patient: BloodGroup.aPos,
                selected: {...donorsCompatibleWith(BloodGroup.aPos)},
                onChanged: (_) {},
              ),
            ),
          ),
        );
        for (final g in donorsCompatibleWith(BloodGroup.aPos)) {
          expect(find.text(g.label), findsOneWidget, reason: g.label);
        }
        for (final g in BloodGroup.values.where(
          (g) => !donorsCompatibleWith(BloodGroup.aPos).contains(g),
        )) {
          expect(find.text(g.label), findsNothing, reason: '${g.label} cannot give to A+');
        }
      },
    );

    testWidgets('unticking a group removes it from the selection', (
      tester,
    ) async {
      Set<BloodGroup>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BloodGroupMultiPicker(
              patient: BloodGroup.aPos,
              selected: {...donorsCompatibleWith(BloodGroup.aPos)},
              onChanged: (s) => result = s,
            ),
          ),
        ),
      );
      await tester.tap(find.text('O-'));
      await tester.pump();
      expect(result, isNot(contains(BloodGroup.oNeg)));
      expect(result, contains(BloodGroup.aPos));
    });

    testWidgets('ticking an unticked group adds it', (tester) async {
      Set<BloodGroup>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BloodGroupMultiPicker(
              patient: BloodGroup.aPos,
              selected: const {BloodGroup.aPos},
              onChanged: (s) => result = s,
            ),
          ),
        ),
      );
      await tester.tap(find.text('O+'));
      await tester.pump();
      expect(result, {BloodGroup.aPos, BloodGroup.oPos});
    });
  });
}

/// A backend whose account-linking is always refused.
class _RefusingBackend extends FakeBackend {
  _RefusingBackend({super.user});

  @override
  Future<UserProfile> addPasswordSignIn({
    required String email,
    required String password,
  }) async => throw const SignInFailure('That email is already in use.');
}
