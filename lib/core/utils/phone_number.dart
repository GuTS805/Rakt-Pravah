import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Supported country information for phone numbers.
class CountryCode {
  const CountryCode({
    required this.name,
    required this.dialCode,
    required this.code,
    required this.flag,
    required this.minLength,
    required this.maxLength,
    required this.hint,
  });

  final String name;
  final String dialCode; // e.g. '+91'
  final String code; // ISO 3166-1 alpha-2, e.g. 'IN'
  final String flag; // Emoji flag, e.g. '🇮🇳'
  final int minLength;
  final int maxLength;
  final String hint; // e.g. '9876543210'

  bool get isExactLength => minLength == maxLength;

  String get displayLabel => '$flag $dialCode';

  /// Default country is India (+91, exactly 10 digits).
  static const defaultCountry = CountryCode(
    name: 'India',
    dialCode: '+91',
    code: 'IN',
    flag: '🇮🇳',
    minLength: 10,
    maxLength: 10,
    hint: '9876543210',
  );

  /// Supported international countries with their mobile dialing rules.
  static const List<CountryCode> supported = [
    defaultCountry,
    CountryCode(
      name: 'United States',
      dialCode: '+1',
      code: 'US',
      flag: '🇺🇸',
      minLength: 10,
      maxLength: 10,
      hint: '2025550123',
    ),
    CountryCode(
      name: 'United Kingdom',
      dialCode: '+44',
      code: 'GB',
      flag: '🇬🇧',
      minLength: 10,
      maxLength: 10,
      hint: '7911123456',
    ),
    CountryCode(
      name: 'United Arab Emirates',
      dialCode: '+971',
      code: 'AE',
      flag: '🇦🇪',
      minLength: 9,
      maxLength: 9,
      hint: '501234567',
    ),
    CountryCode(
      name: 'Saudi Arabia',
      dialCode: '+966',
      code: 'SA',
      flag: '🇸🇦',
      minLength: 9,
      maxLength: 9,
      hint: '512345678',
    ),
    CountryCode(
      name: 'Canada',
      dialCode: '+1',
      code: 'CA',
      flag: '🇨🇦',
      minLength: 10,
      maxLength: 10,
      hint: '4165550123',
    ),
    CountryCode(
      name: 'Australia',
      dialCode: '+61',
      code: 'AU',
      flag: '🇦🇺',
      minLength: 9,
      maxLength: 9,
      hint: '412345678',
    ),
    CountryCode(
      name: 'Singapore',
      dialCode: '+65',
      code: 'SG',
      flag: '🇸🇬',
      minLength: 8,
      maxLength: 8,
      hint: '81234567',
    ),
    CountryCode(
      name: 'Nepal',
      dialCode: '+977',
      code: 'NP',
      flag: '🇳🇵',
      minLength: 10,
      maxLength: 10,
      hint: '9841234567',
    ),
    CountryCode(
      name: 'Bangladesh',
      dialCode: '+880',
      code: 'BD',
      flag: '🇧🇩',
      minLength: 10,
      maxLength: 10,
      hint: '1712345678',
    ),
    CountryCode(
      name: 'Germany',
      dialCode: '+49',
      code: 'DE',
      flag: '🇩🇪',
      minLength: 10,
      maxLength: 11,
      hint: '15123456789',
    ),
    CountryCode(
      name: 'France',
      dialCode: '+33',
      code: 'FR',
      flag: '🇫🇷',
      minLength: 9,
      maxLength: 9,
      hint: '612345678',
    ),
    CountryCode(
      name: 'Japan',
      dialCode: '+81',
      code: 'JP',
      flag: '🇯🇵',
      minLength: 10,
      maxLength: 10,
      hint: '9012345678',
    ),
    CountryCode(
      name: 'Qatar',
      dialCode: '+974',
      code: 'QA',
      flag: '🇶🇦',
      minLength: 8,
      maxLength: 8,
      hint: '33123456',
    ),
    CountryCode(
      name: 'Kuwait',
      dialCode: '+965',
      code: 'KW',
      flag: '🇰🇼',
      minLength: 8,
      maxLength: 8,
      hint: '51234567',
    ),
    CountryCode(
      name: 'Oman',
      dialCode: '+968',
      code: 'OM',
      flag: '🇴🇲',
      minLength: 8,
      maxLength: 8,
      hint: '91234567',
    ),
    CountryCode(
      name: 'Malaysia',
      dialCode: '+60',
      code: 'MY',
      flag: '🇲🇾',
      minLength: 9,
      maxLength: 10,
      hint: '123456789',
    ),
    CountryCode(
      name: 'Philippines',
      dialCode: '+63',
      code: 'PH',
      flag: '🇵🇭',
      minLength: 10,
      maxLength: 10,
      hint: '9171234567',
    ),
    CountryCode(
      name: 'Pakistan',
      dialCode: '+92',
      code: 'PK',
      flag: '🇵🇰',
      minLength: 10,
      maxLength: 10,
      hint: '3001234567',
    ),
    CountryCode(
      name: 'Sri Lanka',
      dialCode: '+94',
      code: 'LK',
      flag: '🇱🇰',
      minLength: 9,
      maxLength: 9,
      hint: '712345678',
    ),
  ];

  /// Finds a supported CountryCode matching [dialCode], or builds a sensible fallback.
  static CountryCode fromDialCode(String? dialCode, [String? countryIso]) {
    if (dialCode == null || dialCode.trim().isEmpty) return defaultCountry;
    final normalized = dialCode.trim().startsWith('+')
        ? dialCode.trim()
        : '+${dialCode.trim()}';

    if (countryIso != null) {
      final match = supported.cast<CountryCode?>().firstWhere(
            (c) => c!.dialCode == normalized && c.code == countryIso.toUpperCase(),
            orElse: () => null,
          );
      if (match != null) return match;
    }

    return supported.firstWhere(
      (c) => c.dialCode == normalized,
      orElse: () => CountryCode(
        name: 'Other',
        dialCode: normalized,
        code: countryIso?.toUpperCase() ?? '',
        flag: '🌐',
        minLength: 6,
        maxLength: 15,
        hint: 'Phone number',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryCode &&
          runtimeType == other.runtimeType &&
          dialCode == other.dialCode &&
          code == other.code;

  @override
  int get hashCode => dialCode.hashCode ^ code.hashCode;
}

/// Phone number formatting, validation, parsing, and international calling utilities.
abstract class PhoneUtils {
  /// Strips all non-digit characters from the input.
  static String cleanDigits(String? value) {
    if (value == null) return '';
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Validates a phone number for the given country.
  ///
  /// For India (+91) or any 10-digit country, returns:
  /// "Please enter a valid 10-digit mobile number."
  /// For other countries with exact length N:
  /// "Please enter a valid N-digit mobile number."
  /// Returns null if the number is valid.
  static String? validate(String? countryDialCode, String? phoneNumber) {
    final country = CountryCode.fromDialCode(countryDialCode);
    final digits = cleanDigits(phoneNumber);

    if (digits.isEmpty) {
      if (country.isExactLength) {
        return 'Please enter a valid ${country.minLength}-digit mobile number.';
      }
      return 'Please enter a valid mobile number.';
    }

    if (country.isExactLength) {
      if (digits.length != country.minLength) {
        return 'Please enter a valid ${country.minLength}-digit mobile number.';
      }
    } else {
      if (digits.length < country.minLength || digits.length > country.maxLength) {
        return 'Please enter a valid ${country.minLength}-${country.maxLength} digit mobile number.';
      }
    }
    return null;
  }

  /// Formats the raw digits nicely for display, e.g.:
  /// 10 digits (India / US) -> 98765 43210
  /// 9 digits -> 501 234 567
  /// 8 digits -> 8123 4567
  static String formatNumber(String raw) {
    final digits = cleanDigits(raw);
    if (digits.length == 10) {
      return '${digits.substring(0, 5)} ${digits.substring(5)}';
    } else if (digits.length == 9) {
      return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    } else if (digits.length == 8) {
      return '${digits.substring(0, 4)} ${digits.substring(4)}';
    }
    return digits;
  }

  /// Formats country code + number for clear display, e.g. "+91 98765 43210".
  static String formatDisplay(String? countryCode, String? phone) {
    if (phone == null || phone.trim().isEmpty) return '';
    final trimmed = phone.trim();

    // If phone already starts with a '+', parse it
    if (trimmed.startsWith('+')) {
      final parsed = parse(trimmed);
      return '${parsed.countryCode} ${formatNumber(parsed.phone)}';
    }

    final code = (countryCode != null && countryCode.trim().isNotEmpty)
        ? (countryCode.trim().startsWith('+')
            ? countryCode.trim()
            : '+${countryCode.trim()}')
        : '+91';
    final digits = cleanDigits(phone);
    if (digits.isEmpty) return '';
    return '$code ${formatNumber(digits)}';
  }

  /// Formats the international phone number for display, e.g. "+91 98765 43210".
  static String formatInternational(String? countryCode, String? phone) =>
      formatDisplay(countryCode, phone);

  /// Produces the complete international phone number for Call/OTP functionality,
  /// e.g. "+919876543210".
  static String toInternational(String? phone, {String? countryCode}) {
    if (phone == null || phone.trim().isEmpty) return '';
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) {
      return '+${cleanDigits(trimmed)}';
    }
    final code = (countryCode != null && countryCode.trim().isNotEmpty)
        ? (countryCode.trim().startsWith('+')
            ? countryCode.trim()
            : '+${countryCode.trim()}')
        : '+91';
    final digits = cleanDigits(trimmed);
    return '$code$digits';
  }

  /// Parses a combined phone string (e.g. "+919876543210" or "+91 98765 43210")
  /// into countryCode and phone.
  static ({String countryCode, String phone}) parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return (countryCode: '+91', phone: '');
    }
    final trimmed = raw.trim();
    if (trimmed.startsWith('+')) {
      // Check known country codes in descending order of length to avoid prefix collisions
      final sorted = List<CountryCode>.from(CountryCode.supported)
        ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
      for (final c in sorted) {
        if (trimmed.startsWith(c.dialCode)) {
          final rest = cleanDigits(trimmed.substring(c.dialCode.length));
          return (countryCode: c.dialCode, phone: rest);
        }
      }
      final match = RegExp(r'^(\+\d{1,4})(.*)$').firstMatch(trimmed);
      if (match != null) {
        return (
          countryCode: match.group(1)!,
          phone: cleanDigits(match.group(2)),
        );
      }
    }
    return (countryCode: '+91', phone: cleanDigits(trimmed));
  }

  /// Places a phone call using the complete international number.
  static Future<void> makePhoneCall(
    BuildContext context,
    String? rawPhone, {
    String? countryCode,
  }) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) return;
    final intlNumber = toInternational(rawPhone, countryCode: countryCode);
    final uri = Uri.parse('tel:$intlNumber');
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place call to $intlNumber')),
      );
    }
  }
}
