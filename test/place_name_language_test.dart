import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:rakt_pravah/core/services/location_service.dart';

// What a OnePlus phone set to English (India) got back for a spot in Kalyan:
// the same place five times, the first two in Devanagari. Asking the
// geocoder for an English locale made no difference.

void main() {
  const hindi = Placemark(locality: 'कल्याण', administrativeArea: 'महाराष्ट्र');
  const english = Placemark(
    locality: 'Kalyan',
    administrativeArea: 'Maharashtra',
  );

  test('the English answer is used when one comes back', () {
    final p = LocationService.pickPlacemark([hindi, hindi, english, english]);
    expect(p?.locality, 'Kalyan');
    expect(p?.administrativeArea, 'Maharashtra');
  });

  test('accented Latin names count as English', () {
    const pune = Placemark(locality: 'Pune', administrativeArea: 'Maharashtra');
    const zurich = Placemark(locality: 'Zürich', administrativeArea: 'Zürich');
    expect(LocationService.pickPlacemark([zurich, pune])?.locality, 'Zürich');
  });

  test('with only the local script, that is still better than nothing', () {
    expect(LocationService.pickPlacemark([hindi])?.locality, 'कल्याण');
  });

  test('no answer is no placemark', () {
    expect(LocationService.pickPlacemark(const []), isNull);
  });

  test('an answer with no names is skipped for one that has them', () {
    const blank = Placemark(street: '12');
    expect(LocationService.pickPlacemark([blank, english])?.locality, 'Kalyan');
  });
}
