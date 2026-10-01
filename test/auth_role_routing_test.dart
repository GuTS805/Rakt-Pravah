import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/admin/admin_auth.dart';
import 'package:rakt_pravah/admin/admin_backend.dart';
import 'package:rakt_pravah/admin/admin_providers.dart';
import 'package:rakt_pravah/core/router/app_router.dart';
import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/backend.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/auth/login_screen.dart';

import 'fakes.dart';

void main() {
  group('1. User Login Tests', () {
    test(
      'Register user → account created with role=USER and initiates onboarding',
      () async {
        final fakeBackend = FakeBackend();
        final container = ProviderContainer(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
        );
        addTearDown(container.dispose);

        final authController = container.read(authControllerProvider.notifier);
        expect(
          container.read(authControllerProvider).status,
          equals(AuthStatus.unknown),
        );

        // Register new user
        await authController.register(
          email: 'newuser@raktpravah.org',
          password: 'password123',
          name: 'New Citizen Donor',
          phone: '9876543210',
          bloodGroup: BloodGroup.oPos,
          dateOfBirth: DateTime(1998, 5, 20),
          gender: Gender.male,
          country: 'India',
          state: 'Delhi',
          city: 'New Delhi',
        );

        final state = container.read(authControllerProvider);
        expect(state.status, equals(AuthStatus.needsOnboarding));
        expect(state.user, isNotNull);
        expect(state.user!.email, equals('newuser@raktpravah.org'));
        expect(state.user!.name, equals('New Citizen Donor'));
        expect(state.user!.isAdmin, isFalse);
        expect(state.user!.role, equals(UserRole.user));
        expect(state.user!.role.isUser, isTrue);
        expect(state.user!.role.isAdmin, isFalse);

        // Complete onboarding → authenticated
        authController.completeOnboarding();
        final authedState = container.read(authControllerProvider);
        expect(authedState.status, equals(AuthStatus.authenticated));
        expect(authedState.user!.role, equals(UserRole.user));
      },
    );

    testWidgets('User login → navigates to User Home', (tester) async {
      final standardUser = UserProfile(
        id: 'user_123',
        name: 'Standard User',
        bloodGroup: BloodGroup.aPos,
        phone: '9876543210',
        email: 'user@raktpravah.org',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend();
      fakeBackend.passwords['user@raktpravah.org'] = 'correct_pass';
      fakeBackend.registeredUsers['user@raktpravah.org'] = standardUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts unauthenticated on login screen
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.login),
      );

      // Sign in as standard user
      await container
          .read(authControllerProvider.notifier)
          .signInWithPassword(
            email: 'user@raktpravah.org',
            password: 'correct_pass',
          );
      await tester.pumpAndSettle();

      // Redirects to User Home (/home)
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.home),
      );
      expect(container.read(currentUserProvider)?.role, equals(UserRole.user));
    });

    testWidgets('Wrong password → proper error displayed', (tester) async {
      final standardUser = UserProfile(
        id: 'user_123',
        name: 'Standard User',
        bloodGroup: BloodGroup.aPos,
        phone: '9876543210',
        email: 'user@raktpravah.org',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend(user: standardUser);
      fakeBackend.passwords['user@raktpravah.org'] = 'secret_pass';
      fakeBackend.registeredUsers['user@raktpravah.org'] = standardUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              const AuthState(AuthStatus.unauthenticated),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter email and incorrect password
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'user@raktpravah.org',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong_pass');

      // Submit
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      // Proper error message is visible
      expect(find.text('Invalid ID or password.'), findsOneWidget);
    });

    testWidgets('Non-existent account → proper error displayed', (
      tester,
    ) async {
      final fakeBackend = FakeBackend();
      fakeBackend.registeredUsers['existing@raktpravah.org'] =
          const UserProfile(
            id: 'existing_1',
            name: 'Existing',
            bloodGroup: BloodGroup.oPos,
            phone: '9876543210',
            email: 'existing@raktpravah.org',
          );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              const AuthState(AuthStatus.unauthenticated),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter unregistered email
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'unknown@raktpravah.org',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'anypassword');

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid ID or password.'), findsOneWidget);
    });

    testWidgets('Logout → session/token cleared', (tester) async {
      final standardUser = UserProfile(
        id: 'user_123',
        name: 'Standard User',
        bloodGroup: BloodGroup.aPos,
        phone: '9876543210',
        email: 'user@raktpravah.org',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend(user: standardUser);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Start logged in
      final authNotifier = container.read(authControllerProvider.notifier);
      await authNotifier.finishStartup();
      expect(
        container.read(authControllerProvider).status,
        equals(AuthStatus.authenticated),
      );

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.home),
      );

      // Trigger logout
      await authNotifier.logout();
      await tester.pumpAndSettle();

      // State is unauthenticated, user is null, routed back to login
      final postLogoutState = container.read(authControllerProvider);
      expect(postLogoutState.status, equals(AuthStatus.unauthenticated));
      expect(postLogoutState.user, isNull);
      expect(fakeBackend.currentUser, isNull);
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.login),
      );
    });

    testWidgets('User cannot access /admin → redirects to adminNoAccess', (
      tester,
    ) async {
      final standardUser = UserProfile(
        id: 'user_1',
        name: 'Standard User',
        bloodGroup: BloodGroup.aPos,
        phone: '9876543210',
        isAdmin: false,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: standardUser)),
          currentUserProvider.overrideWithValue(standardUser),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              AuthState(AuthStatus.authenticated, standardUser),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt navigating directly to /admin
      router.go(Routes.adminDashboard);
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminNoAccess),
      );
      expect(find.byType(AdminNoAccessScreen), findsOneWidget);
    });

    test('Refresh page → user remains logged in', () async {
      final standardUser = UserProfile(
        id: 'user_persistent',
        name: 'Persistent User',
        bloodGroup: BloodGroup.bPos,
        phone: '9876543210',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend(user: standardUser);
      final container = ProviderContainer(
        overrides: [backendProvider.overrideWithValue(fakeBackend)],
      );
      addTearDown(container.dispose);

      // Simulates app refresh / initialization with active local session
      final authNotifier = container.read(authControllerProvider.notifier);
      await authNotifier.finishStartup();

      final state = container.read(authControllerProvider);
      expect(state.status, equals(AuthStatus.authenticated));
      expect(state.user?.id, equals('user_persistent'));
      expect(state.user?.role, equals(UserRole.user));
    });

    test('Expired session → redirect to login', () async {
      final fakeBackend = FakeBackend();
      fakeBackend.sessionExpired = true; // Session expired/missing on refresh

      final container = ProviderContainer(
        overrides: [backendProvider.overrideWithValue(fakeBackend)],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authControllerProvider.notifier);
      await authNotifier.finishStartup();

      final state = container.read(authControllerProvider);
      expect(state.status, equals(AuthStatus.unauthenticated));
      expect(state.user, isNull);
    });
  });

  group('2. Admin Login Tests', () {
    testWidgets('Admin credentials → Admin Dashboard', (tester) async {
      final adminUser = UserProfile(
        id: 'admin_007',
        name: 'System Administrator',
        bloodGroup: BloodGroup.oNeg,
        phone: '9988776655',
        email: 'admin@raktpravah.org',
        isAdmin: true,
      );
      final fakeBackend = FakeBackend();
      fakeBackend.passwords['admin@raktpravah.org'] = 'admin_secret';
      fakeBackend.registeredUsers['admin@raktpravah.org'] = adminUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sign in with admin credentials
      await container
          .read(authControllerProvider.notifier)
          .signInWithPassword(
            email: 'admin@raktpravah.org',
            password: 'admin_secret',
          );
      await tester.pumpAndSettle();

      // Immediately lands on Admin Dashboard
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminDashboard),
      );
      expect(container.read(currentUserProvider)?.role, equals(UserRole.admin));
      expect(container.read(currentUserProvider)?.isAdmin, isTrue);
    });

    test('Wrong admin credentials → error and rejected sign in', () async {
      final adminUser = UserProfile(
        id: 'admin_007',
        name: 'Admin',
        bloodGroup: BloodGroup.oNeg,
        phone: '9988776655',
        email: 'admin@raktpravah.org',
        isAdmin: true,
      );
      final fakeBackend = FakeBackend(user: adminUser);
      fakeBackend.passwords['admin@raktpravah.org'] = 'correct_admin_pass';
      fakeBackend.registeredUsers['admin@raktpravah.org'] = adminUser;

      final container = ProviderContainer(
        overrides: [backendProvider.overrideWithValue(fakeBackend)],
      );
      addTearDown(container.dispose);

      // Attempt login with wrong password
      expect(
        () => container
            .read(authControllerProvider.notifier)
            .signInWithPassword(
              email: 'admin@raktpravah.org',
              password: 'bad_password',
            ),
        throwsA(isA<SignInFailure>()),
      );

      // Status remains unknown/unauthenticated, not logged in
      expect(
        container.read(authControllerProvider).status,
        equals(AuthStatus.unknown),
      );
    });

    testWidgets('Normal user credentials must not enter admin dashboard', (
      tester,
    ) async {
      final standardUser = UserProfile(
        id: 'user_regular',
        name: 'Regular Donor',
        bloodGroup: BloodGroup.bPos,
        phone: '9876543210',
        email: 'donor@raktpravah.org',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend();
      fakeBackend.passwords['donor@raktpravah.org'] = 'donor_pass';
      fakeBackend.registeredUsers['donor@raktpravah.org'] = standardUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(authControllerProvider.notifier)
          .signInWithPassword(
            email: 'donor@raktpravah.org',
            password: 'donor_pass',
          );
      await tester.pumpAndSettle();

      // Normal user lands at /home, never /admin
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.home),
      );

      // Attempting to manually push to /admin
      router.go(Routes.adminDashboard);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminNoAccess),
      );
    });

    testWidgets('User cannot manually open /admin or any nested admin route', (
      tester,
    ) async {
      final standardUser = UserProfile(
        id: 'user_norm',
        name: 'Norm',
        bloodGroup: BloodGroup.abPos,
        phone: '9876543210',
        isAdmin: false,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: standardUser)),
          currentUserProvider.overrideWithValue(standardUser),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              AuthState(AuthStatus.authenticated, standardUser),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Test multiple nested admin paths
      final nestedAdminRoutes = [
        Routes.adminDashboard,
        Routes.adminUsers,
        Routes.adminDonors,
        Routes.adminRequests,
        Routes.adminAudit,
        Routes.adminSettings,
      ];

      for (final adminRoute in nestedAdminRoutes) {
        router.go(adminRoute);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          equals(Routes.adminNoAccess),
          reason: 'Standard user must not access $adminRoute',
        );
      }
    });

    testWidgets('Admin cannot accidentally be treated as a normal donor', (
      tester,
    ) async {
      final adminUser = UserProfile(
        id: 'admin_op',
        name: 'Operator Admin',
        bloodGroup: BloodGroup.oPos,
        phone: '9998887776',
        isAdmin: true,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: adminUser)),
          currentUserProvider.overrideWithValue(adminUser),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              AuthState(AuthStatus.authenticated, adminUser),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Admin role invariants
      expect(adminUser.isAdmin, isTrue);
      expect(adminUser.role, equals(UserRole.admin));
      expect(adminUser.role.isUser, isFalse);

      // Attempting to visit user donor routes as an admin redirects to Admin Dashboard
      final userDonorRoutes = [
        Routes.home,
        Routes.requests,
        Routes.donate,
        Routes.you,
      ];

      for (final userRoute in userDonorRoutes) {
        router.go(userRoute);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          equals(Routes.adminDashboard),
          reason:
              'Admin navigating to user flow $userRoute must redirect to admin dashboard',
        );
      }
    });

    testWidgets('Admin logout → session completely cleared', (tester) async {
      final adminUser = UserProfile(
        id: 'admin_session',
        name: 'Admin Session',
        bloodGroup: BloodGroup.abNeg,
        phone: '9998887777',
        isAdmin: true,
      );
      final fakeBackend = FakeBackend(user: adminUser);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authControllerProvider.notifier);
      await authNotifier.finishStartup();

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminDashboard),
      );

      // Logout admin
      await authNotifier.logout();
      await tester.pumpAndSettle();

      // Session and providers completely cleared
      expect(
        container.read(authControllerProvider).status,
        equals(AuthStatus.unauthenticated),
      );
      expect(container.read(authControllerProvider).user, isNull);
      expect(container.read(currentUserProvider), isNull);
      expect(container.read(adminBackendProvider), isNull);
      expect(fakeBackend.currentUser, isNull);
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.login),
      );
    });

    test(
      'Refresh → admin session remains authenticated at admin dashboard',
      () async {
        final adminUser = UserProfile(
          id: 'admin_retained',
          name: 'Retained Admin',
          bloodGroup: BloodGroup.aPos,
          phone: '9876543210',
          isAdmin: true,
        );
        final fakeBackend = FakeBackend(user: adminUser);
        final container = ProviderContainer(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
        );
        addTearDown(container.dispose);

        final authNotifier = container.read(authControllerProvider.notifier);
        await authNotifier.finishStartup();

        final state = container.read(authControllerProvider);
        expect(state.status, equals(AuthStatus.authenticated));
        expect(state.user?.isAdmin, isTrue);
        expect(state.user?.role, equals(UserRole.admin));
      },
    );

    test('Backend must verify role=ADMIN, not just hide/show the admin UI', () {
      // 1. Instantiating AdminBackend with isAdmin: false throws AdminUnauthorizedException
      expect(
        () => AdminBackend(
          null,
          actorId: 'attacker',
          actorName: 'Attacker',
          isAdmin: false,
        ),
        throwsA(isA<AdminUnauthorizedException>()),
      );

      // 2. Admin providers yield null/empty streams for non-admins
      final normalUser = UserProfile(
        id: 'non_admin_id',
        name: 'Non Admin',
        bloodGroup: BloodGroup.oPos,
        phone: '1234567890',
        isAdmin: false,
      );

      final container = ProviderContainer(
        overrides: [currentUserProvider.overrideWithValue(normalUser)],
      );
      addTearDown(container.dispose);

      expect(container.read(adminBackendProvider), isNull);
      expect(container.read(adminRequestsProvider).value, isNull);
      expect(container.read(adminUsersProvider).value, isNull);
      expect(container.read(adminReportsProvider).value, isNull);
      expect(container.read(adminAuditProvider).value, isNull);
    });
  });

  group('3. Critical Security & RBAC Routing Matrix', () {
    testWidgets('USER login → role = USER → /home', (tester) async {
      final standardUser = UserProfile(
        id: 'verified_user',
        name: 'Regular User',
        bloodGroup: BloodGroup.oPos,
        phone: '9876543210',
        email: 'user@test.org',
        isAdmin: false,
      );
      final fakeBackend = FakeBackend();
      fakeBackend.passwords['user@test.org'] = 'pass';
      fakeBackend.registeredUsers['user@test.org'] = standardUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(authControllerProvider.notifier)
          .signInWithPassword(email: 'user@test.org', password: 'pass');
      await tester.pumpAndSettle();

      final currentUser = container.read(currentUserProvider);
      expect(currentUser?.role, equals(UserRole.user));
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.home),
      );
    });

    testWidgets('ADMIN login → role = ADMIN → /admin', (tester) async {
      final adminUser = UserProfile(
        id: 'verified_admin',
        name: 'Administrator',
        bloodGroup: BloodGroup.bPos,
        phone: '9876543210',
        email: 'admin@test.org',
        isAdmin: true,
      );
      final fakeBackend = FakeBackend();
      fakeBackend.passwords['admin@test.org'] = 'adminpass';
      fakeBackend.registeredUsers['admin@test.org'] = adminUser;

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(fakeBackend),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(authControllerProvider.notifier)
          .signInWithPassword(email: 'admin@test.org', password: 'adminpass');
      await tester.pumpAndSettle();

      final currentUser = container.read(currentUserProvider);
      expect(currentUser?.role, equals(UserRole.admin));
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminDashboard),
      );
    });

    testWidgets('USER → /admin ❌ Access Denied', (tester) async {
      final standardUser = UserProfile(
        id: 'user_attacker',
        name: 'Attacker User',
        bloodGroup: BloodGroup.aPos,
        phone: '9876543210',
        isAdmin: false,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: standardUser)),
          currentUserProvider.overrideWithValue(standardUser),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              AuthState(AuthStatus.authenticated, standardUser),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /admin
      router.go('/admin');
      await tester.pumpAndSettle();

      // Redirects to Access Denied
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminNoAccess),
      );
      expect(find.text('Access Restricted'), findsOneWidget);
      expect(
        find.textContaining('Administrator privileges are required'),
        findsOneWidget,
      );
    });

    testWidgets('ADMIN → /home ❌ Redirect/appropriate admin flow', (
      tester,
    ) async {
      final adminUser = UserProfile(
        id: 'admin_redirect',
        name: 'Admin User',
        bloodGroup: BloodGroup.oNeg,
        phone: '9876543210',
        isAdmin: true,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: adminUser)),
          currentUserProvider.overrideWithValue(adminUser),
          currentTimeProvider.overrideWith(
            (ref) => Stream.value(DateTime.now()),
          ),
          authControllerProvider.overrideWith(
            () => _MockAuthController(
              AuthState(AuthStatus.authenticated, adminUser),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When admin attempts to navigate to /home
      router.go(Routes.home);
      await tester.pumpAndSettle();

      // Automatically redirected to /admin (AdminDashboard)
      expect(
        router.routeInformationProvider.value.uri.path,
        equals(Routes.adminDashboard),
      );
    });
  });
}

class _MockAuthController extends AuthController {
  _MockAuthController(this._initialState);
  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}
