import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/requests/create_request_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'Create request Step 1 includes Phone, Blood Type, and excludes Routine',
    (tester) async {
      final fakeBackend = FakeBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CreateRequestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Patient Name, Phone number, Blood Type, and Required date exist
      expect(find.text('Patient name'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Blood Type'), findsOneWidget);
      expect(find.text('Blood'), findsWidgets);
      expect(find.text('Required date'), findsOneWidget);

      // Verify Urgency options: Urgent and Critical exist, Routine is removed
      expect(find.text('Urgent'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Routine'), findsNothing);
    },
  );

  testWidgets(
    'Create request Step 2 has State and City dropdowns and removes Home/Other',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeBackend = FakeBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CreateRequestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill Step 1 fields
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Full name as registered at the hospital',
        ),
        'Ravi Kumar',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          '10-digit mobile number for coordination',
        ),
        '9876543210',
      );
      // Pick blood group A+
      await tester.tap(find.text('A+'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Advance to Step 2
      final continueButton = find.text('Continue');
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // In Step 2: "Where is the request?"
      expect(find.text('Where is the request?'), findsOneWidget);
      expect(find.text('Use current location'), findsOneWidget);
      expect(find.text('Select State:'), findsOneWidget);
      expect(find.text('Select City:'), findsOneWidget);

      // Verify "Use my home address" and "Enter a different location" are REMOVED
      expect(find.text('Use my home address'), findsNothing);
      expect(find.text('Enter a different location'), findsNothing);
    },
  );

  testWidgets(
    'Create request Step 3 has State and City dropdowns and removes Ward/contact',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeBackend = FakeBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CreateRequestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Full name as registered at the hospital',
        ),
        'Ravi Kumar',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          '10-digit mobile number for coordination',
        ),
        '9876543210',
      );
      await tester.tap(find.text('A+'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2: Select State & City to advance
      await tester.tap(find.byKey(const ValueKey('state-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assam').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('city-Assam-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guwahati').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // In Step 3: "Where should donors go?"
      expect(find.text('Where should donors go?'), findsOneWidget);
      expect(find.text('Hospital name'), findsOneWidget);
      expect(find.text('Hospital address'), findsOneWidget);
      expect(find.text('Select State:'), findsOneWidget);
      expect(find.text('Select City:'), findsOneWidget);

      // Verify "Ward / contact (optional)" is REMOVED
      expect(find.text('Ward / contact (optional)'), findsNothing);
    },
  );

  testWidgets(
    'Create request Step 4 has Additional Notes (Optional) field above confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeBackend = FakeBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(fakeBackend)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CreateRequestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Patient info
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Full name as registered at the hospital',
        ),
        'Ravi Kumar',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          '10-digit mobile number for coordination',
        ),
        '9876543210',
      );
      await tester.tap(find.text('A+'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2: Location
      await tester.tap(find.byKey(const ValueKey('state-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assam').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('city-Assam-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guwahati').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3: Hospital
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. City General Hospital'),
        'Apollo Hospital',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Street, area, landmark'),
        'GS Road',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 4: Review
      expect(find.text('Additional Notes (Optional)'), findsOneWidget);
      expect(
        find.widgetWithText(
          TextField,
          'Any special instructions, room number, or timing for donors…',
        ),
        findsOneWidget,
      );
      expect(find.text('These details are correct'), findsOneWidget);

      // Enter notes
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Any special instructions, room number, or timing for donors…',
        ),
        'Room 304, 3rd floor ICU',
      );

      // Confirm checkbox
      await tester.tap(find.text('These details are correct'));
      await tester.pumpAndSettle();

      // Submit request
      await tester.tap(find.text('Create request'));
      await tester.pumpAndSettle();

      // Verify backend received the notes
      final requests = await fakeBackend.myRequestsStream.first;
      expect(requests.length, 1);
      expect(requests.first.notes, 'Room 304, 3rd floor ICU');
    },
  );
}
