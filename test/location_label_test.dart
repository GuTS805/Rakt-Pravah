import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/data/models/models.dart';

void main() {
  group('nearest listed city (the web has no geocoder)', () {
    test('a point in Ghaziabad is named after Ghaziabad', () {
      expect(
        LocationService.nearestListedCity(const GeoPoint(28.6692, 77.4538)),
        'Ghaziabad, Uttar Pradesh',
      );
    });

    test('a point far from every listed town has no name', () {
      // Middle of the Indian Ocean.
      expect(
        LocationService.nearestListedCity(const GeoPoint(-10.0, 75.0)),
        isNull,
      );
    });
  });
}
