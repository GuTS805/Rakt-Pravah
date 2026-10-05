import 'package:flutter/material.dart';

import '../core/location/location_data.dart';
import '../core/location/searchable_location_picker.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'segmented_control.dart';

export '../core/location/location_data.dart';
export '../core/location/searchable_location_picker.dart';
export '../core/utils/indian_locations.dart'
    show indianStates, indianCitiesByState;
export '../core/widgets/phone_number_field.dart';

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

/// Country, state and city selection with complete dynamic dropdowns,
/// instant search, clear/reset cascade, and coordinate resolution.
class HomeLocationFields extends StatefulWidget {
  const HomeLocationFields({
    super.key,
    required this.country,
    required this.state,
    required this.city,
    this.countryCode,
    this.stateCode,
    this.latitude,
    this.longitude,
    this.onLocationChanged,
  });

  final TextEditingController country;
  final TextEditingController state;
  final TextEditingController city;
  final TextEditingController? countryCode;
  final TextEditingController? stateCode;
  final ValueNotifier<double?>? latitude;
  final ValueNotifier<double?>? longitude;
  final ValueChanged<SelectedLocation>? onLocationChanged;

  @override
  State<HomeLocationFields> createState() => _HomeLocationFieldsState();
}

class _HomeLocationFieldsState extends State<HomeLocationFields> {
  late final TextEditingController _customCityController;
  bool _isOtherCity = false;

  String? _required(String? v, String what) =>
      (v ?? '').trim().isEmpty ? 'Enter your $what' : null;

  @override
  void initState() {
    super.initState();
    if (widget.country.text.trim().isEmpty) {
      widget.country.text = 'India';
      widget.countryCode?.text = 'IN';
    }

    final countryVal = widget.country.text.trim();
    final stateVal = widget.state.text.trim();
    final cityVal = widget.city.text.trim();

    final cities = LocationDataService.getCities(countryVal, stateVal);
    final cityNames = cities.map((c) => c.name).toSet();

    if (cityVal.isNotEmpty && !cityNames.contains(cityVal)) {
      _isOtherCity = true;
      _customCityController = TextEditingController(text: cityVal);
    } else {
      _customCityController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _customCityController.dispose();
    super.dispose();
  }

  void _onCountryChanged(String newCountry) {
    if (widget.country.text == newCountry) return;
    setState(() {
      widget.country.text = newCountry;
      final countryObj = LocationDataService.findCountry(newCountry);
      widget.countryCode?.text = countryObj?.code ?? '';

      // Clear state and city when country changes
      widget.state.clear();
      widget.stateCode?.clear();
      widget.city.clear();
      _customCityController.clear();
      _isOtherCity = false;
      widget.latitude?.value = null;
      widget.longitude?.value = null;
    });
    _notifyLocation();
  }

  void _onStateChanged(String newState) {
    if (widget.state.text == newState) return;
    setState(() {
      widget.state.text = newState;
      final stateObj = LocationDataService.findState(widget.country.text, newState);
      widget.stateCode?.text = stateObj?.code ?? '';

      // Clear city when state changes
      widget.city.clear();
      _customCityController.clear();
      _isOtherCity = false;
      widget.latitude?.value = stateObj?.latitude;
      widget.longitude?.value = stateObj?.longitude;
    });
    _notifyLocation();
  }

  void _onCityChanged(String? newCity) {
    setState(() {
      if (newCity == 'Other') {
        _isOtherCity = true;
        widget.city.text = _customCityController.text.trim();
      } else {
        _isOtherCity = false;
        _customCityController.clear();
        widget.city.text = newCity ?? '';
      }
    });
    _resolveCoordinates();
  }

  void _resolveCoordinates() {
    final country = widget.country.text.trim();
    final state = widget.state.text.trim();
    final city = widget.city.text.trim();

    if (country.isEmpty) return;

    final resolved = LocationDataService.resolve(
      country: country,
      state: state.isNotEmpty ? state : null,
      city: city.isNotEmpty ? city : null,
    );

    widget.countryCode?.text = resolved.countryCode;
    widget.stateCode?.text = resolved.stateCode;
    widget.latitude?.value = resolved.latitude;
    widget.longitude?.value = resolved.longitude;

    _notifyLocation(resolved);
  }

  void _notifyLocation([SelectedLocation? loc]) {
    final location = loc ??
        LocationDataService.resolve(
          country: widget.country.text.trim(),
          state: widget.state.text.trim(),
          city: widget.city.text.trim(),
        );
    widget.onLocationChanged?.call(location);
  }

  Future<void> _openCountrySearch(BuildContext context) async {
    final picked = await showModalBottomSheet<CountryLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchPickerSheet<CountryLocation>(
        title: 'Select Country',
        searchHint: 'Search country name or code...',
        items: LocationDataService.countries,
        itemTitle: (c) => c.name,
        itemSubtitle: (c) => '${c.flag} ${c.code} · ${c.dialCode}',
        selectedItem: LocationDataService.findCountry(widget.country.text),
      ),
    );
    if (picked != null) {
      _onCountryChanged(picked.name);
    }
  }

  Future<void> _openStateSearch(BuildContext context) async {
    final country = widget.country.text.trim();
    final states = LocationDataService.getStates(country);
    if (states.isEmpty) return;

    final picked = await showModalBottomSheet<StateLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchPickerSheet<StateLocation>(
        title: 'Select State or Province',
        searchHint: 'Search state or district...',
        items: states,
        itemTitle: (s) => s.name,
        itemSubtitle: (s) => 'Code: ${s.code} · ${s.cities.length} cities/districts',
        selectedItem: LocationDataService.findState(country, widget.state.text),
      ),
    );
    if (picked != null) {
      _onStateChanged(picked.name);
    }
  }

  Future<void> _openCitySearch(BuildContext context) async {
    final country = widget.country.text.trim();
    final state = widget.state.text.trim();
    final cities = LocationDataService.getCities(country, state);

    final picked = await showModalBottomSheet<CityLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchPickerSheet<CityLocation>(
        title: 'Select City / District',
        searchHint: 'Search city or district in $state...',
        items: cities,
        itemTitle: (c) => c.name,
        itemSubtitle: (c) =>
            '${c.latitude.toStringAsFixed(2)}°N, ${c.longitude.toStringAsFixed(2)}°E',
        selectedItem: LocationDataService.findCity(country, state, widget.city.text),
        allowCustom: true,
        onCustomSelected: (customText) {
          setState(() {
            _isOtherCity = true;
            _customCityController.text = customText;
            widget.city.text = customText;
          });
          _resolveCoordinates();
        },
      ),
    );
    if (picked != null) {
      _onCityChanged(picked.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final countryValue = widget.country.text.trim();
    final stateValue = widget.state.text.trim();
    final cityValue = widget.city.text.trim();

    final allCountries = LocationDataService.countries;
    final countryNames = allCountries.map((c) => c.name).toList();

    final availableStates = LocationDataService.getStates(countryValue);
    final stateNames = availableStates.map((s) => s.name).toList();

    final availableCities = LocationDataService.getCities(countryValue, stateValue);
    final cityNames = availableCities.map((c) => c.name).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Country'),
        DropdownButtonFormField<String>(
          key: ValueKey('country-dropdown-$countryValue'),
          initialValue: countryNames.contains(countryValue) ? countryValue : null,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: InputDecoration(
            hintText: 'Select country',
            prefixIcon: const Icon(Icons.public_outlined),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search countries',
              onPressed: () => _openCountrySearch(context),
            ),
          ),
          items: [
            for (final c in allCountries)
              DropdownMenuItem(
                value: c.name,
                child: Text('${c.flag.isNotEmpty ? "${c.flag} " : ""}${c.name}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) _onCountryChanged(v);
          },
          validator: (v) => _required(v, 'country'),
        ),
        const SizedBox(height: AppSpacing.lg),
        const FieldLabel('State / Province'),
        if (availableStates.isNotEmpty || countryValue.isEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey('state-list-$countryValue-$stateValue'),
            initialValue: stateNames.contains(stateValue) ? stateValue : null,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: InputDecoration(
              hintText: countryValue.isEmpty ? 'Select country first' : 'Select state',
              prefixIcon: const Icon(Icons.map_outlined),
              suffixIcon: countryValue.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: 'Search states/districts',
                      onPressed: () => _openStateSearch(context),
                    ),
            ),
            items: countryValue.isEmpty
                ? []
                : [
                    for (final s in stateNames)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
            onChanged: countryValue.isEmpty
                ? null
                : (v) {
                    if (v != null) _onStateChanged(v);
                  },
            validator: (v) => v == null || v.isEmpty ? 'Select your state' : null,
          )
        else
          TextFormField(
            key: const ValueKey('state-text'),
            controller: widget.state,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'State or region',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            validator: (v) => _required(v, 'state'),
            onChanged: (_) {
              setState(() {
                widget.city.clear();
                _customCityController.clear();
                _isOtherCity = false;
              });
              _resolveCoordinates();
            },
          ),
        const SizedBox(height: AppSpacing.lg),
        const FieldLabel('City / District'),
        if (availableCities.isNotEmpty || stateValue.isEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(
              'city-list-$countryValue-$stateValue-${_isOtherCity ? "other" : cityValue}',
            ),
            initialValue: _isOtherCity
                ? 'Other'
                : (cityNames.contains(cityValue) ? cityValue : null),
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: InputDecoration(
              hintText: stateValue.isEmpty ? 'Select state first' : 'Select city',
              prefixIcon: const Icon(Icons.location_city_outlined),
              suffixIcon: stateValue.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: 'Search city/district',
                      onPressed: () => _openCitySearch(context),
                    ),
            ),
            items: stateValue.isEmpty
                ? []
                : [
                    for (final c in cityNames)
                      DropdownMenuItem(value: c, child: Text(c)),
                    const DropdownMenuItem(
                      value: 'Other',
                      child: Text('Other (enter manually)'),
                    ),
                  ],
            onChanged: stateValue.isEmpty
                ? null
                : (v) => _onCityChanged(v),
            validator: (v) {
              if (stateValue.isEmpty) return 'Select your state first';
              if (v == null || v.isEmpty) return 'Select your city';
              if (v == 'Other' && widget.city.text.trim().isEmpty) {
                return 'Enter your city';
              }
              return null;
            },
          ),
          if (_isOtherCity) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('city-custom-text'),
              controller: _customCityController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Enter city or town name',
                prefixIcon: const Icon(Icons.edit_location_outlined),
                suffixIcon: TextButton(
                  onPressed: () => _openCitySearch(context),
                  child: const Text('Pick Center'),
                ),
              ),
              validator: (v) => _required(v, 'city'),
              onChanged: (v) {
                widget.city.text = v.trim();
                _resolveCoordinates();
              },
            ),
          ],
        ] else
          TextFormField(
            key: const ValueKey('city-text'),
            controller: widget.city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. City name',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            validator: (v) => _required(v, 'city'),
            onChanged: (_) => _resolveCoordinates(),
          ),
      ],
    );
  }
}
