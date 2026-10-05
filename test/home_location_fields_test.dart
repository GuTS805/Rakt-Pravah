import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/shared/profile_fields.dart';

void main() {
  group('HomeLocationFields & Location Selection System Tests', () {
    testWidgets('country, state, and city dropdowns initialize and show proper hints', (
      tester,
    ) async {
      final country = TextEditingController(text: 'India');
      final countryCode = TextEditingController(text: 'IN');
      final state = TextEditingController();
      final stateCode = TextEditingController();
      final city = TextEditingController();
      final lat = ValueNotifier<double?>(null);
      final lng = ValueNotifier<double?>(null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  countryCode: countryCode,
                  state: state,
                  stateCode: stateCode,
                  city: city,
                  latitude: lat,
                  longitude: lng,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Country is pre-selected as India
      expect(find.textContaining('India'), findsWidgets);

      // State dropdown exists with 'Select state' prompt
      expect(find.text('Select state'), findsOneWidget);

      // City dropdown exists with 'Select state first' prompt
      expect(find.text('Select state first'), findsOneWidget);
    });

    testWidgets('selecting state enables city dropdown and populates state cities', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final country = TextEditingController(text: 'India');
      final countryCode = TextEditingController(text: 'IN');
      final state = TextEditingController();
      final stateCode = TextEditingController();
      final city = TextEditingController();
      final lat = ValueNotifier<double?>(null);
      final lng = ValueNotifier<double?>(null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  countryCode: countryCode,
                  state: state,
                  stateCode: stateCode,
                  city: city,
                  latitude: lat,
                  longitude: lng,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open state dropdown and select Maharashtra
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maharashtra').last);
      await tester.pumpAndSettle();

      expect(state.text, equals('Maharashtra'));
      expect(stateCode.text, equals('MH'));
      expect(find.text('Select city'), findsOneWidget);

      // Open city dropdown and select Mumbai
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();

      expect(find.text('Mumbai'), findsWidgets);
      await tester.tap(find.text('Mumbai').last);
      await tester.pumpAndSettle();

      expect(city.text, equals('Mumbai'));
      // Coordinates resolved for Mumbai
      expect(lat.value, isNotNull);
      expect(lng.value, isNotNull);
      expect(lat.value, closeTo(19.07, 0.1));
      expect(lng.value, closeTo(72.87, 0.1));
    });

    testWidgets('changing State clears City and resets City dropdown', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final country = TextEditingController(text: 'India');
      final state = TextEditingController(text: 'Maharashtra');
      final city = TextEditingController(text: 'Mumbai');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  state: state,
                  city: city,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(city.text, equals('Mumbai'));

      // Switch state to Uttar Pradesh
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uttar Pradesh').last);
      await tester.pumpAndSettle();

      // State is Uttar Pradesh, and City was automatically cleared!
      expect(state.text, equals('Uttar Pradesh'));
      expect(city.text, isEmpty);
      expect(find.text('Select city'), findsOneWidget);
    });

    testWidgets('changing Country clears State and City', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final country = TextEditingController(text: 'India');
      final countryCode = TextEditingController(text: 'IN');
      final state = TextEditingController(text: 'Maharashtra');
      final stateCode = TextEditingController(text: 'MH');
      final city = TextEditingController(text: 'Mumbai');
      final lat = ValueNotifier<double?>(19.0760);
      final lng = ValueNotifier<double?>(72.8777);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  countryCode: countryCode,
                  state: state,
                  stateCode: stateCode,
                  city: city,
                  latitude: lat,
                  longitude: lng,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change Country to United States
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      // Tap United States
      await tester.tap(find.text('🇺🇸 United States').last);
      await tester.pumpAndSettle();

      // Country updated, state and city cleared
      expect(country.text, equals('United States'));
      expect(countryCode.text, equals('US'));
      expect(state.text, isEmpty);
      expect(stateCode.text, isEmpty);
      expect(city.text, isEmpty);
      expect(lat.value, isNull);
      expect(lng.value, isNull);
    });

    testWidgets('selecting Uttar Pradesh loads all 75+ cities and districts', (
      tester,
    ) async {
      final country = TextEditingController(text: 'India');
      final state = TextEditingController(text: 'Uttar Pradesh');
      final city = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  state: state,
                  city: city,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open city dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();

      // Verify major cities and districts of UP are present in the dataset and UI
      expect(find.text('Agra'), findsWidgets);
      expect(find.text('Aligarh'), findsWidgets);
      expect(find.text('Ayodhya'), findsWidgets);

      // Verify complete UP dataset has all 75+ districts and economic hubs
      final upCities = LocationDataService.getCities('India', 'Uttar Pradesh');
      expect(upCities.length, greaterThanOrEqualTo(75));

      final upNames = upCities.map((c) => c.name).toSet();
      expect(upNames.contains('Lucknow'), isTrue);
      expect(upNames.contains('Kanpur Nagar'), isTrue);
      expect(upNames.contains('Varanasi'), isTrue);
      expect(upNames.contains('Prayagraj'), isTrue);
      expect(upNames.contains('Meerut'), isTrue);
      expect(upNames.contains('Ghaziabad'), isTrue);
      expect(upNames.contains('Noida'), isTrue);
      expect(upNames.contains('Greater Noida'), isTrue);
      expect(upNames.contains('Gorakhpur'), isTrue);
      expect(upNames.contains('Jhansi'), isTrue);
      expect(upNames.contains('Lakhimpur Kheri'), isTrue);
      expect(upNames.contains('Bareilly'), isTrue);
      expect(upNames.contains('Mathura'), isTrue);
      expect(upNames.contains('Moradabad'), isTrue);

      // All cities have valid coordinates
      for (final c in upCities) {
        expect(c.latitude, isNotNull);
        expect(c.longitude, isNotNull);
        expect(c.latitude, greaterThan(20.0));
        expect(c.longitude, greaterThan(70.0));
      }

      await tester.tap(find.text('Agra').last);
      await tester.pumpAndSettle();
      expect(city.text, equals('Agra'));
    });

    testWidgets('selecting Other allows custom city input and administrative fallback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final country = TextEditingController(text: 'India');
      final state = TextEditingController(text: 'Chandigarh');
      final city = TextEditingController();
      final lat = ValueNotifier<double?>(null);
      final lng = ValueNotifier<double?>(null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeLocationFields(
                  country: country,
                  state: state,
                  city: city,
                  latitude: lat,
                  longitude: lng,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open city dropdown and select Other (enter manually)
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Other (enter manually)').last);
      await tester.pumpAndSettle();

      // Custom city text field appears
      expect(find.byKey(const ValueKey('city-custom-text')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('city-custom-text')),
        'Rural Village Sector 4',
      );
      await tester.pumpAndSettle();

      expect(city.text, equals('Rural Village Sector 4'));
      // Coordinates fallback to Chandigarh administrative center
      expect(lat.value, isNotNull);
      expect(lng.value, isNotNull);
      expect(lat.value, closeTo(30.73, 0.1));
      expect(lng.value, closeTo(76.77, 0.1));
    });

    test('LocationDataService handles international resolution and nearest administrative centers', () {
      // US location
      final usRes = LocationDataService.resolve(
        country: 'United States',
        state: 'California',
        city: 'Los Angeles',
      );
      expect(usRes.countryCode, equals('US'));
      expect(usRes.stateCode, equals('CA'));
      expect(usRes.city, equals('Los Angeles'));
      expect(usRes.latitude, closeTo(34.05, 0.1));
      expect(usRes.longitude, closeTo(-118.24, 0.1));

      // Unknown city falls back to state center
      final fallbackRes = LocationDataService.resolve(
        country: 'India',
        state: 'Karnataka',
        city: 'Unknown Remote Hamlet',
      );
      expect(fallbackRes.countryCode, equals('IN'));
      expect(fallbackRes.stateCode, equals('KA'));
      expect(fallbackRes.city, equals('Unknown Remote Hamlet'));
      expect(fallbackRes.hasCoordinates, isTrue);
      expect(fallbackRes.latitude, closeTo(12.97, 3.0));

      // Global country coverage: 100+ countries
      expect(LocationDataService.countries.length, greaterThanOrEqualTo(100));
      expect(LocationDataService.findCountry('India'), isNotNull);
      expect(LocationDataService.findCountry('United Kingdom'), isNotNull);
      expect(LocationDataService.findCountry('United Arab Emirates'), isNotNull);
      expect(LocationDataService.findCountry('Australia'), isNotNull);
      expect(LocationDataService.findCountry('Canada'), isNotNull);
      expect(LocationDataService.findCountry('Germany'), isNotNull);
      expect(LocationDataService.findCountry('France'), isNotNull);
      expect(LocationDataService.findCountry('Japan'), isNotNull);
      expect(LocationDataService.findCountry('Singapore'), isNotNull);
      expect(LocationDataService.findCountry('Brazil'), isNotNull);
      expect(LocationDataService.findCountry('Egypt'), isNotNull);
      expect(LocationDataService.findCountry('South Africa'), isNotNull);
      expect(LocationDataService.findCountry('Saudi Arabia'), isNotNull);
      expect(LocationDataService.findCountry('Nigeria'), isNotNull);
      expect(LocationDataService.findCountry('Kenya'), isNotNull);
    });
  });
}
