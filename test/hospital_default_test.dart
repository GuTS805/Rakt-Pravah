import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/requests/create_request_screen.dart';

import 'fakes.dart';

// The hospital step used to start from the state and city saved on the
// profile. Someone whose profile says Patna but who is asking from Bengaluru
// then sent donors to a Patna address without noticing, and nobody near the
// real hospital was ever invited.

void main() {
  const patnaUser = UserProfile(
    id: 'u1',
    name: 'Meera Test',
    bloodGroup: BloodGroup.oPos,
    phone: '9876543210',
    city: 'Patna',
    state: 'Bihar',
  );

  Future<void> reachHospitalStep(
    WidgetTester tester, {
    required LocationResult location,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(FakeBackend(user: patnaUser)),
          currentUserProvider.overrideWithValue(patnaUser),
          locationServiceProvider.overrideWithValue(
            FakeLocationService(result: location),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CreateRequestScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Full name as registered at the hospital'),
      'Sita Devi',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-input-field')),
      '9876543210',
    );
    await tester.tap(find.text('AB+'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Where should donors go?'), findsOneWidget);
  }

  testWidgets('the hospital starts in the city the request is made from', (
    tester,
  ) async {
    await reachHospitalStep(
      tester,
      location: const LocationGranted(
        GeoPoint(12.9716, 77.5946),
        'Sivanchetti Gardens, Bengaluru, Karnataka',
      ),
    );

    expect(find.text('Karnataka'), findsOneWidget);
    expect(find.text('Bengaluru'), findsOneWidget);
    expect(find.text('Bihar'), findsNothing);
    expect(find.text('Patna'), findsNothing);
  });

  testWidgets('without a location it falls back to the profile town', (
    tester,
  ) async {
    await reachHospitalStep(tester, location: const LocationDenied());

    expect(find.text('Bihar'), findsOneWidget);
    expect(find.text('Patna'), findsOneWidget);
  });
}
