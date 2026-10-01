import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/auth/login_screen.dart';
import 'package:rakt_pravah/features/auth/register_screen.dart';
import 'package:rakt_pravah/shared/brand_mark.dart';

import 'fakes.dart';

// The logo and the heading above the sign-in and sign-up forms sit in the
// middle of the screen, with the logo large enough to read as the brand.

void main() {
  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(FakeBackend())],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  double middle(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;

  testWidgets('the sign-in logo and heading are centred', (tester) async {
    await open(tester, const LoginScreen());

    final mid = middle(tester);
    expect(tester.getCenter(find.byType(BrandMark)).dx, closeTo(mid, 1));
    expect(tester.getCenter(find.text('Welcome back')).dx, closeTo(mid, 1));
    expect(
      tester.getCenter(find.text('Sign in to your account')).dx,
      closeTo(mid, 1),
    );
  });

  testWidgets('the sign-in logo is larger than the old 48', (tester) async {
    await open(tester, const LoginScreen());

    expect(
      tester.getSize(find.byType(BrandMark)).width,
      greaterThanOrEqualTo(72),
    );
  });

  testWidgets('the sign-up page has a centred logo and intro', (tester) async {
    await open(tester, const RegisterScreen());

    final mid = middle(tester);
    expect(tester.getCenter(find.byType(BrandMark)).dx, closeTo(mid, 1));
    expect(
      tester
          .getCenter(
            find.text('A few details so donors near you can help fast.'),
          )
          .dx,
      closeTo(mid, 1),
    );
    expect(
      tester.getSize(find.byType(BrandMark)).width,
      greaterThanOrEqualTo(72),
    );
  });
}
