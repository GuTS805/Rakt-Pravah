import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bloodlink/main.dart';

void main() {
  testWidgets('BloodLink boots to splash then routes to login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BloodLinkApp()));
    await tester.pump();

    // Splash shows the product name while startup resolves the route.
    expect(find.text('BloodLink'), findsOneWidget);

    // Let the startup timer fire so the router redirects to Login.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
  });
}
