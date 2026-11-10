import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/phone_number.dart';

export '../utils/phone_number.dart' show CountryCode, PhoneUtils;

/// A phone number input with an integrated Country Code dropdown, vertical divider,
/// and digits-only text input.
///
/// Example layout:
///   🇮🇳 +91 ▾ | 9876543210
///
/// Features:
/// - Defaults to India (+91, exactly 10 digits).
/// - Accepts only digits (0–9), rejecting letters and special characters.
/// - Validates strictly based on the selected country's rules.
/// - Dynamic max length enforcement per selected country.
/// - Shows error: "Please enter a valid 10-digit mobile number." for India (+91).
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.phoneController,
    this.initialCountryCode = '+91',
    this.onCountryChanged,
    this.focusNode,
    this.validator,
    this.enabled = true,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController phoneController;
  final String initialCountryCode;
  final ValueChanged<CountryCode>? onCountryChanged;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;

  @override
  State<PhoneNumberField> createState() => PhoneNumberFieldState();
}

class PhoneNumberFieldState extends State<PhoneNumberField> {
  late CountryCode _selectedCountry;

  CountryCode get selectedCountry => _selectedCountry;

  @override
  void initState() {
    super.initState();
    _selectedCountry = CountryCode.fromDialCode(widget.initialCountryCode);
  }

  @override
  void didUpdateWidget(covariant PhoneNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCountryCode != widget.initialCountryCode) {
      setState(() {
        _selectedCountry = CountryCode.fromDialCode(widget.initialCountryCode);
      });
    }
  }

  void _onCountrySelected(CountryCode? country) {
    if (country == null || country == _selectedCountry) return;
    setState(() {
      _selectedCountry = country;
      // If current digits exceed new country's max length, truncate
      final digits = PhoneUtils.cleanDigits(widget.phoneController.text);
      if (digits.length > country.maxLength) {
        widget.phoneController.text = digits.substring(0, country.maxLength);
      }
    });
    widget.onCountryChanged?.call(country);
  }

  final _codeFocus = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = context.text;

    return TextFormField(
      key: const ValueKey('phone-input-field'),
      controller: widget.phoneController,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      style: textTheme.bodyLarge?.copyWith(
        color: widget.enabled ? c.textPrimary : c.textTertiary,
        letterSpacing: 0.5,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
      ],
      onChanged: widget.onChanged,
      validator: (v) {
        if (widget.validator != null) {
          return widget.validator!(v);
        }
        return PhoneUtils.validate(_selectedCountry.dialCode, v);
      },
      decoration: InputDecoration(
        hintText: _selectedCountry.hint,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 0,
          minHeight: 0,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<CountryCode>(
                  // The keyboard's Next lands on the number, not on this.
                  focusNode: _codeFocus,
                  key: const ValueKey('country-code-dropdown'),
                  value: _selectedCountry,
                  isDense: true,
                  menuMaxHeight: 360,
                  menuWidth: 280,
                  borderRadius: AppRadius.cardMd,
                  dropdownColor: c.surface,
                  icon: Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 20,
                    color: c.textSecondary,
                  ),
                  onChanged: widget.enabled ? _onCountrySelected : null,
                  selectedItemBuilder: (context) {
                    return CountryCode.supported.map((country) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            country.flag,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            country.dialCode,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                  items: CountryCode.supported.map((country) {
                    return DropdownMenuItem<CountryCode>(
                      value: country,
                      child: Row(
                        children: [
                          Text(
                            country.flag,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            country.dialCode,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              country.name,
                              style: textTheme.bodyMedium?.copyWith(
                                color: c.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Vertical Divider "|"
              Container(
                height: 22,
                width: 1.2,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: c.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
