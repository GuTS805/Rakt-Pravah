import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/badges.dart';
import 'package:rakt_pravah/core/widgets/profile_photo_sheet.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/profile/profile_screen.dart';

import 'fakes.dart';

// The "Verified" mark sits under the name, so a long name keeps the whole row
// instead of being cut to make room for a badge beside it.

UserProfile _user({String? email, String name = 'Photo Tester'}) => UserProfile(
  id: 'u1',
  name: name,
  bloodGroup: BloodGroup.oPos,
  phone: '9876511111',
  email: email,
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openProfile(WidgetTester tester, UserProfile user) async {
  _phone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(FakeBackend(user: user)),
        currentUserProvider.overrideWithValue(user),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('profile header', () {
    testWidgets('a verified user is marked verified below their name', (
      tester,
    ) async {
      await _openProfile(tester, _user(email: 'a@example.com'));

      final name = tester.getRect(find.text('Photo Tester'));
      final badge = tester.getRect(find.byType(VerificationBadge));
      expect(badge.top, greaterThanOrEqualTo(name.bottom));
      expect(badge.left, closeTo(name.left, 1));
    });

    testWidgets('a long name is no longer cut short by the badge', (
      tester,
    ) async {
      await _openProfile(
        tester,
        _user(email: 'a@example.com', name: 'Photo Tester'),
      );

      expect(find.text('Photo Tester'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('someone who is not verified gets no mark', (tester) async {
      await _openProfile(tester, _user());

      expect(find.text('Verified Donor'), findsNothing);
      expect(find.text('Pending Verification'), findsNothing);
    });
  });

  group('photo preview', () {
    testWidgets('the note under the photo fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPhotoPreviewDialog(
                    context: context,
                    photoBase64: 'AAAA',
                    initials: 'PT',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.textContaining('Square cropped'), findsOneWidget);
    });
  });
}
