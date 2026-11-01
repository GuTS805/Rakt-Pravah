import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/utils/maps_links.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/features/coordination/live_tracking_map.dart';
import 'package:rakt_pravah/features/coordination/map_panel.dart';

// The app has no map of its own: it shows where things are and opens Google
// Maps for the route and the donor's live position.

const _hospital = Destination(
  name: 'City Hospital',
  address: 'Station Rd',
  location: GeoPoint(28.6139, 77.2090),
);
// About 2.2 km north of the hospital.
const _donor = GeoPoint(28.6339, 77.2090);

void main() {
  late List<Uri> opened;
  setUp(() {
    opened = [];
    final original = openMapsLink;
    openMapsLink = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openMapsLink = original);
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  test('links point at Google Maps', () {
    expect(
      MapsLinks.directions(_hospital).toString(),
      'https://www.google.com/maps/dir/?api=1&destination=28.6139,77.209&travelmode=driving',
    );
    expect(
      MapsLinks.directions(
        const Destination(name: 'AIIMS', address: 'Ansari Nagar'),
      ).queryParameters['destination'],
      'AIIMS, Ansari Nagar',
    );
    expect(
      MapsLinks.place(_donor).toString(),
      'https://www.google.com/maps/search/?api=1&query=28.6339,77.209',
    );
  });

  test('distance is measured in km', () {
    expect(distanceKm(_donor, _hospital.location!), closeTo(2.22, 0.01));
  });

  testWidgets('the coordination panel opens the route and the donor', (
    tester,
  ) async {
    await pump(
      tester,
      const MapPanel(destination: _hospital, trackedLocations: [_donor]),
    );

    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('The donor is 2.2 km away'), findsOneWidget);

    await tester.tap(find.text('Directions'));
    await tester.tap(find.text('Donor on map'));
    await tester.pump();
    expect(opened, [
      MapsLinks.directions(_hospital),
      MapsLinks.place(_donor),
    ]);
  });

  testWidgets('without a live position there is no donor button', (
    tester,
  ) async {
    await pump(tester, const MapPanel(destination: _hospital));
    expect(find.text('Donor on map'), findsNothing);
    expect(find.text('Directions'), findsOneWidget);
  });

  testWidgets('live tracking shows who is coming and how far', (tester) async {
    await pump(
      tester,
      const LiveTrackingMap(
        destination: _hospital,
        donorLocation: _donor,
        donorName: 'Dana Donor',
        donorBloodGroup: BloodGroup.bPos,
      ),
    );

    expect(find.text('Dana Donor'), findsOneWidget);
    expect(find.text('2.2 km from the hospital'), findsOneWidget);
    await tester.tap(find.text('Donor on map'));
    await tester.pump();
    expect(opened, [MapsLinks.place(_donor)]);
  });

  testWidgets('live tracking waits for a position rather than guessing', (
    tester,
  ) async {
    await pump(
      tester,
      const LiveTrackingMap(destination: _hospital, donorName: 'Dana Donor'),
    );
    expect(find.text('Waiting for the donor’s location'), findsOneWidget);
    expect(find.text('Donor on map'), findsNothing);
  });
}
