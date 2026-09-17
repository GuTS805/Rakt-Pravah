import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'segmented_control.dart';

// Profile inputs shared by registration and Edit profile, so both ask for
// the same things the same way.

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: context.text.titleSmall),
  );
}

/// A date of birth picked from a calendar rather than typed, so it can't be
/// entered in an ambiguous order. Shows the resulting age as a check.
class DateOfBirthField extends FormField<DateTime> {
  DateOfBirthField({
    super.key,
    super.initialValue,
    required ValueChanged<DateTime> onChanged,
  }) : super(
         validator: (v) => v == null ? 'Select your date of birth' : null,
         builder: (field) {
           final context = field.context;
           final c = context.colors;
           final value = field.value;
           Future<void> pick() async {
             final now = DateTime.now();
             final picked = await showDatePicker(
               context: context,
               initialDate: value ?? DateTime(now.year - 25, now.month, 1),
               firstDate: DateTime(now.year - 100),
               lastDate: now,
               initialEntryMode: DatePickerEntryMode.calendarOnly,
               helpText: 'Date of birth',
             );
             if (picked != null) {
               field.didChange(picked);
               onChanged(picked);
             }
           }

           return InkWell(
             onTap: pick,
             borderRadius: AppRadius.control,
             child: InputDecorator(
               isEmpty: value == null,
               decoration: InputDecoration(
                 hintText: 'Select date',
                 errorText: field.errorText,
                 suffixIcon: Icon(
                   Icons.calendar_today_rounded,
                   size: 18,
                   color: c.textTertiary,
                 ),
               ),
               child: value == null
                   ? null
                   : Text(
                       '${Fmt.date(value)}  ·  ${ageFrom(value)} years',
                       style: context.text.bodyLarge,
                     ),
             ),
           );
         },
       );
}

class GenderField extends FormField<Gender> {
  GenderField({
    super.key,
    super.initialValue,
    required ValueChanged<Gender> onChanged,
  }) : super(
         validator: (v) => v == null ? 'Select your gender' : null,
         builder: (field) {
           final context = field.context;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               SegmentedControl(
                 segments: [for (final g in Gender.values) Segment(g.label)],
                 selected: field.value == null
                     ? -1
                     : Gender.values.indexOf(field.value!),
                 onChanged: (i) {
                   field.didChange(Gender.values[i]);
                   onChanged(Gender.values[i]);
                 },
               ),
               if (field.errorText != null) ...[
                 const SizedBox(height: AppSpacing.sm),
                 Text(
                   field.errorText!,
                   style: context.text.bodySmall?.copyWith(
                     color: context.colors.danger,
                   ),
                 ),
               ],
             ],
           );
         },
       );
}

/// Country, state and city. For India the state is picked from a list, which
/// keeps names consistent enough to match donors by state later; any other
/// country gets a plain text field.
class HomeLocationFields extends StatefulWidget {
  const HomeLocationFields({
    super.key,
    required this.country,
    required this.state,
    required this.city,
  });

  final TextEditingController country;
  final TextEditingController state;
  final TextEditingController city;

  @override
  State<HomeLocationFields> createState() => _HomeLocationFieldsState();
}

class _HomeLocationFieldsState extends State<HomeLocationFields> {
  bool get _isIndia => widget.country.text.trim().toLowerCase() == 'india';

  String? _required(String? v, String what) =>
      (v ?? '').trim().isEmpty ? 'Enter your $what' : null;

  @override
  Widget build(BuildContext context) {
    final stateValue = widget.state.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Country'),
        TextFormField(
          controller: widget.country,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. India'),
          validator: (v) => _required(v, 'country'),
          // Switching between the state list and free text depends on this.
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        const FieldLabel('State'),
        if (_isIndia)
          DropdownButtonFormField<String>(
            // Rebuilt when the country changes, so a stale value can't linger.
            key: const ValueKey('state-list'),
            initialValue: indianStates.contains(stateValue) ? stateValue : null,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: const InputDecoration(hintText: 'Select state'),
            items: [
              for (final s in indianStates)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => widget.state.text = v ?? '',
            validator: (v) => v == null ? 'Select your state' : null,
          )
        else
          TextFormField(
            key: const ValueKey('state-text'),
            controller: widget.state,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'State or region'),
            validator: (v) => _required(v, 'state'),
          ),
        const SizedBox(height: AppSpacing.lg),
        const FieldLabel('City'),
        TextFormField(
          controller: widget.city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Lucknow'),
          validator: (v) => _required(v, 'city'),
        ),
      ],
    );
  }
}

/// India's 28 states and 8 union territories.
const indianStates = [
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];
