import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/indian_locations.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// A short, fast multi-step request flow (spec §10–12). Each step is small,
/// validated, and reversible; the final Review step submits once and guards
/// against duplicate submissions.
class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  ConsumerState<CreateRequestScreen> createState() =>
      _CreateRequestScreenState();
}

enum _LocationSource { current, stateCity }

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  static const _steps = ['Patient', 'Location', 'Hospital', 'Review'];
  int _step = 0;
  bool _submitting = false;

  // Step 1. The patient is often not the person filling this in, so their
  // blood group and phone are asked for directly instead of borrowing the requester's.
  final _patientName = TextEditingController();
  final _patientPhone = TextEditingController();
  String _bloodType = 'Blood';
  DateTime _requiredDate = DateTime.now();
  BloodGroup? _patientGroup;
  // Donor groups the request is open to: every group that can safely give to
  // the patient, narrowed by the requester if the hospital asks for fewer.
  Set<BloodGroup> _groups = {};
  int _units = 1;
  Urgency _urgency = Urgency.urgent;

  Future<void> _pickRequiredDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _requiredDate.isBefore(now) ? now : _requiredDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _requiredDate = picked);
    }
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // Step 2. Location selection via live GPS or State/City dropdowns.
  final _location = TextEditingController();
  final _customCityController = TextEditingController();
  String? _selectedState;
  String? _selectedCity;
  _LocationSource _source = _LocationSource.current;
  bool _locating = false;
  GeoPoint? _requestPoint;

  // Step 3
  final _destName = TextEditingController();
  final _destAddress = TextEditingController();
  final _destCustomCityController = TextEditingController();
  String? _destState;
  String? _destCity;

  // Step 4. Wrong details send donors to the wrong place, so they're
  // confirmed explicitly rather than assumed.
  final _notes = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user?.state != null && indianStates.contains(user!.state)) {
        _selectedState = user.state;
        if (user.city != null && user.city!.isNotEmpty) {
          final cities = indianCitiesByState[user.state] ?? const [];
          if (cities.contains(user.city)) {
            _selectedCity = user.city;
          } else {
            _selectedCity = 'Other';
            _customCityController.text = user.city!;
          }
          _location.text = '${user.city}, ${user.state}';
          _source = _LocationSource.stateCity;
        }
      }
      _useDeviceLocation();
    });
  }

  Future<void> _useDeviceLocation() async {
    setState(() => _locating = true);
    final notifier = ref.read(deviceLocationProvider.notifier);
    var state = ref.read(deviceLocationProvider);
    if (!state.isGranted) {
      state = await notifier.request();
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (state.isGranted) {
        _source = _LocationSource.current;
        _requestPoint = state.point;
        _location.text = state.label ?? 'Current location';
      } else if (_source == _LocationSource.current) {
        _requestPoint = null;
        if (_selectedState != null && _selectedCity != null) {
          _source = _LocationSource.stateCity;
          _location.text = _selectedCity == 'Other'
              ? (_customCityController.text.trim().isEmpty
                  ? _selectedState!
                  : '${_customCityController.text.trim()}, $_selectedState')
              : '$_selectedCity, $_selectedState';
        } else {
          _location.text = '';
        }
      }
    });
  }

  @override
  void dispose() {
    _patientName.dispose();
    _patientPhone.dispose();
    _location.dispose();
    _customCityController.dispose();
    _destName.dispose();
    _destAddress.dispose();
    _destCustomCityController.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canAdvance {
    switch (_step) {
      case 0:
        final digits = _patientPhone.text.replaceAll(RegExp(r'\D'), '');
        return _patientName.text.trim().length >= 2 &&
            digits.length >= 10 &&
            _patientGroup != null &&
            _groups.isNotEmpty &&
            _units >= 1;
      case 1:
        if (_source == _LocationSource.current &&
            (_requestPoint != null || _location.text.trim().isNotEmpty)) {
          return true;
        }
        return _selectedState != null &&
            (_selectedCity != null &&
                (_selectedCity != 'Other' ||
                    _customCityController.text.trim().isNotEmpty));
      case 2:
        return _destName.text.trim().isNotEmpty &&
            _destAddress.text.trim().isNotEmpty &&
            _destState != null &&
            (_destCity != null &&
                (_destCity != 'Other' ||
                    _destCustomCityController.text.trim().isNotEmpty));
      default:
        return _confirmed;
    }
  }

  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      setState(() => _step -= 1);
    }
  }

  Future<void> _next() async {
    if (_step < _steps.length - 1) {
      if (_step == 1) {
        _destState ??= _selectedState;
        if (_destCity == null && _selectedCity != null) {
          _destCity = _selectedCity;
          if (_selectedCity == 'Other') {
            _destCustomCityController.text = _customCityController.text;
          }
        }
      }
      setState(() => _step += 1);
    } else {
      await _submit();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return; // guard duplicate submission
    setState(() => _submitting = true);
    try {
      // Best-effort forward-geocode of the typed destination address to a
      // real coordinate, so the coordination map shows an actual pin instead
      // of a fabricated position. If it fails, the map falls back honestly to
      // a city-center default rather than faking precision.
      final resolvedDestCity = _destCity == 'Other'
          ? _destCustomCityController.text.trim()
          : (_destCity ?? '');
      final fullDestAddress = [
        _destAddress.text.trim(),
        if (resolvedDestCity.isNotEmpty) resolvedDestCity,
        if (_destState != null && _destState!.isNotEmpty) _destState!,
      ].where((part) => part.isNotEmpty).join(', ');

      final locationService = ref.read(locationServiceProvider);
      final destPoint = await locationService.forwardGeocode(
        '${_destName.text.trim()}, $fullDestAddress',
      );
      // A typed or state/city location has no coordinates yet; look them up the
      // same way so donors can still be sorted by distance.
      final requestPoint =
          _requestPoint ??
          await locationService.forwardGeocode(_location.text.trim());

      final phoneText = _patientPhone.text.trim();
      final contactText = phoneText.isNotEmpty ? 'Contact: $phoneText' : null;

      final req = await ref
          .read(backendProvider)
          .createRequest(
            patientName: _patientName.text.trim(),
            patientBloodGroup: _patientGroup!,
            bloodGroups: _groups.toList(),
            units: _units,
            urgency: _urgency,
            requestLocationLabel: _location.text.trim(),
            requestLocation: requestPoint,
            bloodType: _bloodType,
            phone: phoneText.isEmpty ? null : phoneText,
            requiredDate: _requiredDate,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            destination: Destination(
              name: _destName.text.trim(),
              address: fullDestAddress,
              wardOrContact: contactText,
              location: destPoint,
            ),
          );
      if (mounted) context.pushReplacement(Routes.requestDetail(req.id));
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t create the request. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: const Text('Request blood'),
      ),
      body: Column(
        children: [
          _StepIndicator(steps: _steps, current: _step),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _buildStep(),
                  ),
                ),
              ),
            ),
          ),
          _Footer(
            canAdvance: _canAdvance,
            isLast: _step == _steps.length - 1,
            submitting: _submitting,
            onNext: _canAdvance ? _next : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _bloodStep();
      case 1:
        return _locationStep();
      case 2:
        return _destinationStep();
      default:
        return _reviewStep();
    }
  }

  // ---- Step 1: blood details ----
  Widget _bloodStep() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          'Who needs blood?',
          'Details of the patient, as the hospital has them.',
        ),
        Text('Patient name', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _patientName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Full name as registered at the hospital',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Phone number', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _patientPhone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '10-digit mobile number for coordination',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Blood Type', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _bloodType,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.water_drop_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'Blood', child: Text('Blood')),
            DropdownMenuItem(value: 'Platelets', child: Text('Platelets')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _bloodType = v);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Required date', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: _pickRequiredDate,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            decoration: const InputDecoration(
              hintText: 'Select required date',
              prefixIcon: Icon(Icons.calendar_today_outlined),
              suffixIcon: Icon(Icons.arrow_drop_down_rounded),
            ),
            child: Text(
              _isToday(_requiredDate)
                  ? 'Today (${Fmt.date(_requiredDate)})'
                  : Fmt.date(_requiredDate),
              style: context.text.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Patient\'s blood group', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        BloodGroupPicker(
          selected: _patientGroup,
          onChanged: (g) => setState(() {
            _patientGroup = g;
            _groups = donorsCompatibleWith(g).toSet();
          }),
        ),
        if (_patientGroup != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('Donors who can give', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          BloodGroupMultiPicker(
            selected: _groups,
            patient: _patientGroup,
            onChanged: (g) => setState(() => _groups = g),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text('Units required', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        _UnitStepper(
          value: _units,
          onChanged: (v) => setState(() => _units = v),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Urgency', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        for (final u in [Urgency.urgent, Urgency.critical]) ...[
          _UrgencyOption(
            urgency: u,
            selected: _urgency == u,
            onTap: () => setState(() => _urgency = u),
          ),
          if (u != Urgency.critical) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  // ---- Step 2: location ----
  Widget _locationStep() {
    final availableCities = _selectedState != null
        ? (indianCitiesByState[_selectedState] ?? const <String>[])
        : const <String>[];
    final usingCurrent = _source == _LocationSource.current;

    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          'Where is the request?',
          'This helps us find donors closest to you.',
        ),
        Consumer(
          builder: (context, ref, _) {
            final deviceLoc = ref.watch(deviceLocationProvider);
            final subtitle = _locating
                ? 'Getting your location…'
                : usingCurrent && _requestPoint != null
                ? '${_location.text} · detected automatically'
                : deviceLoc.status == DeviceLocationStatus.denied ||
                      deviceLoc.status == DeviceLocationStatus.deniedForever
                ? 'Location access denied — tap to allow'
                : deviceLoc.status == DeviceLocationStatus.serviceDisabled
                ? 'Turn on device location, then tap to retry'
                : 'Tap to detect your location';
            return _SelectableTile(
              icon: _locating
                  ? Icons.hourglass_top_rounded
                  : Icons.my_location_rounded,
              title: 'Use current location',
              subtitle: subtitle,
              selected: usingCurrent && _requestPoint != null,
              onTap: _locating
                  ? () {}
                  : () {
                      setState(() {
                        _source = _LocationSource.current;
                        _selectedState = null;
                        _selectedCity = null;
                        _customCityController.clear();
                      });
                      _useDeviceLocation();
                    },
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: Divider(color: context.colors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'OR SELECT LOCATION',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.textSecondary,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Divider(color: context.colors.border)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Select State:', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          key: ValueKey('state-$_selectedState'),
          initialValue: _selectedState,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Choose a state or union territory',
            prefixIcon: Icon(Icons.map_outlined),
          ),
          items: [
            for (final s in indianStates)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (val) {
            setState(() {
              _selectedState = val;
              _selectedCity = null;
              _customCityController.clear();
              _source = _LocationSource.stateCity;
              _requestPoint = null;
              _location.text = val ?? '';
            });
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Select City:', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          key: ValueKey('city-${_selectedState ?? "none"}-$_selectedCity'),
          initialValue: _selectedCity,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: _selectedState == null
                ? 'Select a state first'
                : 'Choose a city',
            prefixIcon: const Icon(Icons.location_city_outlined),
          ),
          items: _selectedState == null
              ? []
              : [
                  for (final c in availableCities)
                    DropdownMenuItem(value: c, child: Text(c)),
                  const DropdownMenuItem(
                    value: 'Other',
                    child: Text('Other (enter manually)'),
                  ),
                ],
          onChanged: _selectedState == null
              ? null
              : (val) {
                  setState(() {
                    _selectedCity = val;
                    _source = _LocationSource.stateCity;
                    _requestPoint = null;
                    if (val == 'Other') {
                      _location.text = _customCityController.text.trim().isEmpty
                          ? _selectedState!
                          : '${_customCityController.text.trim()}, $_selectedState';
                    } else if (val != null) {
                      _location.text = '$val, $_selectedState';
                    }
                  });
                },
        ),
        if (_selectedCity == 'Other') ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _customCityController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Enter city name',
              prefixIcon: Icon(Icons.edit_location_outlined),
            ),
            onChanged: (text) {
              setState(() {
                _location.text = text.trim().isEmpty
                    ? _selectedState!
                    : '${text.trim()}, $_selectedState';
              });
            },
          ),
        ],
      ],
    );
  }

  // ---- Step 3: destination ----
  Widget _destinationStep() {
    final availableCities = _destState != null
        ? (indianCitiesByState[_destState] ?? const <String>[])
        : const <String>[];

    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          'Where should donors go?',
          'The hospital or blood bank where the donation is needed.',
        ),
        Text('Hospital name', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _destName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'e.g. City General Hospital',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Hospital address', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _destAddress,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Street, area, landmark'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Select State:', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          key: ValueKey('dest-state-$_destState'),
          initialValue: _destState,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Choose state or union territory',
            prefixIcon: Icon(Icons.map_outlined),
          ),
          items: [
            for (final s in indianStates)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (val) {
            setState(() {
              _destState = val;
              _destCity = null;
              _destCustomCityController.clear();
            });
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Select City:', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          key: ValueKey('dest-city-${_destState ?? "none"}-$_destCity'),
          initialValue: _destCity,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: _destState == null
                ? 'Select a state first'
                : 'Choose a city',
            prefixIcon: const Icon(Icons.location_city_outlined),
          ),
          items: _destState == null
              ? []
              : [
                  for (final c in availableCities)
                    DropdownMenuItem(value: c, child: Text(c)),
                  const DropdownMenuItem(
                    value: 'Other',
                    child: Text('Other (enter manually)'),
                  ),
                ],
          onChanged: _destState == null
              ? null
              : (val) {
                  setState(() {
                    _destCity = val;
                  });
                },
        ),
        if (_destCity == 'Other') ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _destCustomCityController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Enter city name',
              prefixIcon: Icon(Icons.edit_location_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }

  // ---- Step 4: review ----
  Widget _reviewStep() {
    final c = context.colors;
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          'Check the details',
          'Donors will go to this hospital for this patient, so make sure '
              'everything is right.',
        ),
        if (_urgency == Urgency.critical) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: c.dangerSubtle,
              borderRadius: AppRadius.cardMd,
              border: Border.all(color: c.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 22, color: c.danger),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🚨 EMERGENCY BLOOD REQUEST',
                        style: context.text.titleSmall?.copyWith(
                          color: c.danger,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'This request will immediately alert compatible nearby donors as critical urgency.',
                        style: context.text.bodySmall?.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        AppCard(
          child: Column(
            children: [
              _reviewRow('Patient', _patientName.text.trim()),
              if (_patientPhone.text.trim().isNotEmpty) ...[
                _divider(),
                _reviewRow('Phone', _patientPhone.text.trim(), mono: true),
              ],
              _divider(),
              _reviewRow('Blood type', _bloodType),
              _divider(),
              _reviewRow(
                'Required date',
                _isToday(_requiredDate)
                    ? 'Today (${Fmt.date(_requiredDate)})'
                    : Fmt.date(_requiredDate),
              ),
              _divider(),
              _reviewRowWidget(
                'Patient\'s group',
                Align(
                  alignment: Alignment.centerLeft,
                  child: BloodGroupBadge(_patientGroup!),
                ),
              ),
              _divider(),
              _reviewRowWidget(
                'Donors who can give',
                BloodGroupBadges(_groups.toList(), large: false),
              ),
              _divider(),
              _reviewRow('Units', Fmt.units(_units), mono: true),
              _divider(),
              _reviewRowWidget('Urgency', UrgencyBadge(_urgency, dense: true)),
              _divider(),
              _reviewRow('Your location', _location.text.trim()),
              _divider(),
              _reviewRow('Hospital', _destName.text.trim()),
              _divider(),
              _reviewRow(
                'Hospital address',
                () {
                  final resolved = _destCity == 'Other'
                      ? _destCustomCityController.text.trim()
                      : (_destCity ?? '');
                  final parts = [
                    _destAddress.text.trim(),
                    if (resolved.isNotEmpty) resolved,
                    if (_destState != null && _destState!.isNotEmpty) _destState!,
                  ].where((p) => p.isNotEmpty).join(', ');
                  return parts.isEmpty ? '—' : parts;
                }(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Additional Notes (Optional)', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Any special instructions, room number, or timing for donors…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: c.brand,
          title: Text(
            'These details are correct',
            style: context.text.titleSmall,
          ),
          subtitle: Text(
            'Patient name, blood group and hospital match what the hospital '
            'has on record.',
            style: context.text.bodySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.infoSubtle,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You can cancel this request anytime while it\'s searching.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() =>
      Divider(height: AppSpacing.xl, color: context.colors.border);

  Widget _reviewRow(String label, String value, {bool mono = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: context.text.bodyMedium),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: mono
                ? context.text.titleSmall
                : context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _reviewRowWidget(String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: context.text.bodyMedium),
        ),
        Expanded(child: value),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current ? c.brand : c.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    steps[i],
                    style: context.text.labelSmall?.copyWith(
                      color: i <= current ? c.textPrimary : c.textTertiary,
                      fontWeight: i == current
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (i != steps.length - 1) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.canAdvance,
    required this.isLast,
    required this.submitting,
    required this.onNext,
  });
  final bool canAdvance;
  final bool isLast;
  final bool submitting;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: PrimaryButton(
            label: isLast ? 'Create request' : 'Continue',
            icon: isLast ? Icons.send_rounded : null,
            busy: submitting,
            onPressed: onNext,
          ),
        ),
      ),
    );
  }
}

class _UnitStepper extends StatelessWidget {
  const _UnitStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepBtn(
          icon: Icons.remove_rounded,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Center(
            child: Text(Fmt.units(value), style: context.text.titleMedium),
          ),
        ),
        _StepBtn(
          icon: Icons.add_rounded,
          onTap: value < 10 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Icon(
            icon,
            color: enabled ? c.textPrimary : c.textTertiary,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _UrgencyOption extends StatelessWidget {
  const _UrgencyOption({
    required this.urgency,
    required this.selected,
    required this.onTap,
  });
  final Urgency urgency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = urgencyStyle(context, urgency);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? style.subtle : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? style.color : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(style.icon, color: style.color, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                urgency.label,
                style: context.text.titleSmall?.copyWith(color: c.textPrimary),
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: style.color),
          ],
        ),
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? c.brandSubtle : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? c.brand : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? c.brand : c.textSecondary, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: c.brand, size: 20),
          ],
        ),
      ),
    );
  }
}
