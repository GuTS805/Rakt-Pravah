import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/phone_number_field.dart';
import 'package:rakt_pravah/data/models/models.dart';

import 'fakes.dart';

void main() {
  group('CountryCode & PhoneUtils Unit Tests', () {
    test('default country is India (+91, exactly 10 digits)', () {
      expect(CountryCode.defaultCountry.dialCode, equals('+91'));
      expect(CountryCode.defaultCountry.code, equals('IN'));
      expect(CountryCode.defaultCountry.flag, equals('🇮🇳'));
      expect(CountryCode.defaultCountry.minLength, equals(10));
      expect(CountryCode.defaultCountry.maxLength, equals(10));
      expect(CountryCode.defaultCountry.isExactLength, isTrue);
    });

    test('lookup country codes by dial code', () {
      final india = CountryCode.fromDialCode('+91');
      expect(india.name, equals('India'));

      final us = CountryCode.fromDialCode('+1');
      expect(us.dialCode, equals('+1'));

      final sg = CountryCode.fromDialCode('+65');
      expect(sg.name, equals('Singapore'));
      expect(sg.minLength, equals(8));
      expect(sg.maxLength, equals(8));

      final fallback = CountryCode.fromDialCode('+999');
      expect(fallback.dialCode, equals('+999'));
    });

    test('cleanDigits strips non-digits', () {
      expect(PhoneUtils.cleanDigits('+91 (987) 654-3210'), equals('919876543210'));
      expect(PhoneUtils.cleanDigits('abc 123 xyz 456'), equals('123456'));
      expect(PhoneUtils.cleanDigits(null), equals(''));
    });

    test('PhoneUtils.validate enforces exact 10 digits for India (+91)', () {
      expect(PhoneUtils.validate('+91', '9876543210'), isNull);

      const expectedError = 'Please enter a valid 10-digit mobile number.';
      expect(PhoneUtils.validate('+91', ''), equals(expectedError));
      expect(PhoneUtils.validate('+91', null), equals(expectedError));
      expect(PhoneUtils.validate('+91', '987654321'), equals(expectedError)); // 9 digits
      expect(PhoneUtils.validate('+91', '98765432100'), equals(expectedError)); // 11 digits
      expect(PhoneUtils.validate('+91', 'abcdefghij'), equals(expectedError));
    });

    test('PhoneUtils.validate handles other supported country rules', () {
      // Singapore: 8 digits
      expect(PhoneUtils.validate('+65', '81234567'), isNull);
      expect(
        PhoneUtils.validate('+65', '8123456'),
        equals('Please enter a valid 8-digit mobile number.'),
      );

      // UAE: 9 digits
      expect(PhoneUtils.validate('+971', '501234567'), isNull);
      expect(
        PhoneUtils.validate('+971', '50123456'),
        equals('Please enter a valid 9-digit mobile number.'),
      );

      // Germany: 10-11 digits
      expect(PhoneUtils.validate('+49', '1512345678'), isNull);
      expect(PhoneUtils.validate('+49', '15123456789'), isNull);
      expect(
        PhoneUtils.validate('+49', '151234567'),
        equals('Please enter a valid 10-11 digit mobile number.'),
      );
    });

    test('formatNumber and formatDisplay format clearly', () {
      expect(PhoneUtils.formatNumber('9876543210'), equals('98765 43210'));
      expect(PhoneUtils.formatNumber('501234567'), equals('501 234 567'));
      expect(PhoneUtils.formatNumber('81234567'), equals('8123 4567'));

      expect(
        PhoneUtils.formatDisplay('+91', '9876543210'),
        equals('+91 98765 43210'),
      );
      expect(
        PhoneUtils.formatDisplay('+91', '+919876543210'),
        equals('+91 98765 43210'),
      );
      expect(
        PhoneUtils.formatDisplay(null, '+91 98765 43210'),
        equals('+91 98765 43210'),
      );
    });

    test('toInternational creates complete international dial string for Call/OTP', () {
      expect(
        PhoneUtils.toInternational('9876543210', countryCode: '+91'),
        equals('+919876543210'),
      );
      expect(
        PhoneUtils.toInternational('+919876543210'),
        equals('+919876543210'),
      );
      expect(
        PhoneUtils.toInternational('81234567', countryCode: '+65'),
        equals('+6581234567'),
      );
      expect(
        PhoneUtils.toInternational('  +91 98765 43210  '),
        equals('+919876543210'),
      );
    });

    test('parse splits international phone into countryCode and phone', () {
      final res1 = PhoneUtils.parse('+919876543210');
      expect(res1.countryCode, equals('+91'));
      expect(res1.phone, equals('9876543210'));

      final res2 = PhoneUtils.parse('+91 98765 43210');
      expect(res2.countryCode, equals('+91'));
      expect(res2.phone, equals('9876543210'));

      final res3 = PhoneUtils.parse('9876543210');
      expect(res3.countryCode, equals('+91'));
      expect(res3.phone, equals('9876543210'));
    });
  });

  group('PhoneNumberField Widget Tests', () {
    testWidgets('renders country code dropdown with India (+91) and vertical divider', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PhoneNumberField(phoneController: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check for country dropdown and default India (+91)
      expect(find.byKey(const ValueKey('country-code-dropdown')), findsOneWidget);
      expect(find.text('🇮🇳'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);

      // Check for phone input field
      expect(find.byKey(const ValueKey('phone-input-field')), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget); // Hint text
    });

    testWidgets('accepts only numeric digits (0-9) and rejects letters / special chars', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PhoneNumberField(phoneController: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type alphanumeric and special characters
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '987abc#*654',
      );
      await tester.pumpAndSettle();

      // Letters and symbols should have been stripped by digitsOnly
      expect(controller.text, equals('987654'));
    });

    testWidgets('limits to 10 digits for India (+91)', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PhoneNumberField(phoneController: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to enter 12 digits
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '987654321012',
      );
      await tester.pumpAndSettle();

      // Exactly 10 digits allowed
      expect(controller.text, equals('9876543210'));
    });

    testWidgets('shows validation error when less than 10 digits for India (+91)', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Form(
              key: formKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PhoneNumberField(phoneController: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Validate when empty
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid 10-digit mobile number.'),
        findsOneWidget,
      );

      // 2. Validate with 9 digits
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '987654321',
      );
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid 10-digit mobile number.'),
        findsOneWidget,
      );

      // 3. Validate with exact 10 digits
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '9876543210',
      );
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid 10-digit mobile number.'),
        findsNothing,
      );
    });

    testWidgets('can select another country code and validate accordingly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();
      CountryCode? changedCountry;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Form(
              key: formKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PhoneNumberField(
                  phoneController: controller,
                  onCountryChanged: (c) => changedCountry = c,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap dropdown to open menu
      await tester.tap(find.byKey(const ValueKey('country-code-dropdown')));
      await tester.pumpAndSettle();

      // Select United Arab Emirates (+971, 9 digits)
      final uaeItem = find.text('United Arab Emirates').last;
      await tester.ensureVisible(uaeItem);
      await tester.tap(uaeItem);
      await tester.pumpAndSettle();

      expect(changedCountry?.dialCode, equals('+971'));
      expect(find.text('🇦🇪'), findsOneWidget);
      expect(find.text('+971'), findsOneWidget);

      // Enter 8 digits (UAE requires 9 digits)
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '50123456',
      );
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid 9-digit mobile number.'),
        findsOneWidget,
      );

      // Enter exact 9 digits
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '501234567',
      );
      formKey.currentState!.validate();
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid 9-digit mobile number.'),
        findsNothing,
      );
    });
  });

  group('Backend Phone Number Validation & Separate Storage Tests', () {
    test('backend rejects invalid phone during register', () async {
      final backend = FakeBackend();

      // 9 digits for India
      expect(
        () => backend.register(
          email: 'test@example.com',
          password: 'password123',
          name: 'Test User',
          phone: '987654321', // 9 digits!
          countryCode: '+91',
          bloodGroup: BloodGroup.oPos,
          dateOfBirth: DateTime(1995, 1, 1),
          gender: Gender.male,
          country: 'India',
          state: 'Delhi',
          city: 'New Delhi',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'Please enter a valid 10-digit mobile number.',
        )),
      );
    });

    test('backend stores country code and phone number separately and exposes helpers', () async {
      final backend = FakeBackend();

      final user = await backend.register(
        email: 'test@example.com',
        password: 'password123',
        name: 'Test User',
        phone: '9876543210',
        countryCode: '+91',
        bloodGroup: BloodGroup.oPos,
        dateOfBirth: DateTime(1995, 1, 1),
        gender: Gender.male,
        country: 'India',
        state: 'Delhi',
        city: 'New Delhi',
      );

      // Verified separate storage in UserProfile
      expect(user.countryCode, equals('+91'));
      expect(user.phone, equals('9876543210'));

      // Display formatted number
      expect(user.displayPhone, equals('+91 98765 43210'));

      // Complete international number for Call/OTP
      expect(user.internationalPhone, equals('+919876543210'));

      // Update profile with new phone
      await backend.updateProfile(
        name: 'Updated User',
        bloodGroup: BloodGroup.aPos,
        phone: '9123456789',
        countryCode: '+91',
        dateOfBirth: DateTime(1995, 1, 1),
        gender: Gender.male,
        country: 'India',
        state: 'Delhi',
        city: 'New Delhi',
      );

      final updated = backend.currentUser!;
      expect(updated.countryCode, equals('+91'));
      expect(updated.phone, equals('9123456789'));
      expect(updated.displayPhone, equals('+91 91234 56789'));
      expect(updated.internationalPhone, equals('+919123456789'));
    });

    test('backend rejects invalid phone during createRequest and stores separately on success', () async {
      final backend = FakeBackend();

      // Reject invalid phone on backend (9 digits for +91)
      expect(
        () => backend.createRequest(
          patientName: 'John Doe',
          patientBloodGroup: BloodGroup.bPos,
          bloodGroups: [BloodGroup.bPos],
          units: 1,
          urgency: Urgency.urgent,
          requestLocationLabel: 'Delhi',
          destination: const Destination(name: 'AIIMS', address: 'Delhi'),
          phoneCountryCode: '+91',
          phone: '987654321', // 9 digits
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'Please enter a valid 10-digit mobile number.',
        )),
      );

      // Successfully create request with valid 10 digits
      final req = await backend.createRequest(
        patientName: 'John Doe',
        patientBloodGroup: BloodGroup.bPos,
        bloodGroups: [BloodGroup.bPos],
        units: 1,
        urgency: Urgency.urgent,
        requestLocationLabel: 'Delhi',
        destination: const Destination(name: 'AIIMS', address: 'Delhi'),
        phoneCountryCode: '+91',
        phone: '9876543210',
      );

      expect(req.phoneCountryCode, equals('+91'));
      expect(req.phone, equals('9876543210'));
      expect(req.fullPhoneNumber, equals('+919876543210'));
    });
  });
}
