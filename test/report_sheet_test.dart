import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/report_sheet.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';

import 'fakes.dart';

// "Report a problem" and "Report this chat" file a real report that the
// operators see in the console, instead of only saying thank you.

void main() {
  const me = UserProfile(
    id: 'u1',
    name: 'Dana Donor',
    bloodGroup: BloodGroup.bPos,
    phone: '9876501111',
  );

  Future<FakeBackend> open(
    WidgetTester tester, {
    String? requestId,
    String? userId,
  }) async {
    final backend = FakeBackend(user: me);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReportSheet(
                  context,
                  requestId: requestId,
                  userId: userId,
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
    return backend;
  }

  testWidgets('files the report and thanks the person', (tester) async {
    final backend = await open(tester);
    await tester.enterText(find.byType(TextField), '  The map is blank  ');
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(backend.reports, [('The map is blank', null, null)]);
    expect(find.text('Report sent. Thank you.'), findsOneWidget);
    expect(find.text('Submit report'), findsNothing);
  });

  testWidgets('a report from a chat says who and which request', (
    tester,
  ) async {
    final backend = await open(tester, requestId: 'r1', userId: 'u2');
    await tester.enterText(find.byType(TextField), 'Rude messages');
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(backend.reports, [('Rude messages', 'r1', 'u2')]);
  });

  testWidgets('an empty report is not sent', (tester) async {
    final backend = await open(tester);
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(backend.reports, isEmpty);
    expect(find.text('Describe the problem first.'), findsOneWidget);
  });
}
