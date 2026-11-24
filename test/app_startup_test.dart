import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/router/app_router.dart';
import 'package:rakt_pravah/core/router/routes.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/splash/splash_screen.dart';
import 'package:rakt_pravah/main.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'the splash covers the page while sign-in is restored, then the app opens '
    'without the address ever moving to a splash page',
    (tester) async {
      final user = UserProfile(
        id: 'u1',
        name: 'Donor',
        bloodGroup: BloodGroup.oPos,
        phone: '9876543210',
        email: 'donor@test.org',
      );
      late ProviderContainer container;
      final seen = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(FakeBackend(user: user)),
            currentTimeProvider.overrideWith(
              (ref) => Stream.value(DateTime.now()),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const RaktPravahApp();
            },
          ),
        ),
      );
      final router = container.read(routerProvider);
      router.routeInformationProvider.addListener(
        () => seen.add(router.routeInformationProvider.value.uri.path),
      );

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        isNot(Routes.splash),
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SplashScreen), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, Routes.home);
      expect(seen, isNot(contains(Routes.splash)));
    },
  );
}
