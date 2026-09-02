import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
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

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  static const _steps = ['Blood', 'Location', 'Destination', 'Review'];
  int _step = 0;
  bool _submitting = false;

  // Step 1 — open to any of these groups, not just one exact match.
  Set<BloodGroup> _groups = {};
  int _units = 1;
  Urgency _urgency = Urgency.urgent;

  // Step 2 — backed by real device location, not a hardcoded place name.
  final _location = TextEditingController();
  bool _useCurrent = true;
  bool _locating = false;
  GeoPoint? _requestPoint;

  // Step 3
  final _destName = TextEditingController();
  final _destAddress = TextEditingController();
  final _destWard = TextEditingController();

  @override
  void initState() {
    super.initState();
    final myGroup = ref.read(currentUserProvider)?.bloodGroup;
    if (myGroup != null) _groups = {myGroup};
    // If location was already granted (e.g. prompted on Home), use it
    // immediately without asking again; otherwise prompt now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _useDeviceLocation());
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
        _requestPoint = state.point;
        _location.text = state.label ?? 'Current location';
      } else {
        // Be honest when we don't have a real fix — never fall back to a
        // fabricated place name.
        _location.text = '';
        _useCurrent = false;
      }
    });
  }

  @override
  void dispose() {
    _location.dispose();
    _destName.dispose();
    _destAddress.dispose();
    _destWard.dispose();
    super.dispose();
  }

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _groups.isNotEmpty && _units >= 1;
      case 1:
        return _location.text.trim().isNotEmpty;
      case 2:
        return _destName.text.trim().isNotEmpty &&
            _destAddress.text.trim().isNotEmpty;
      default:
        return true;
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
      final destPoint = await ref
          .read(locationServiceProvider)
          .forwardGeocode(_destAddress.text.trim());

      final req = await ref.read(backendProvider).createRequest(
            bloodGroups: _groups.toList(),
            units: _units,
            urgency: _urgency,
            requestLocationLabel: _location.text.trim(),
            requestLocation: _requestPoint,
            destination: Destination(
              name: _destName.text.trim(),
              address: _destAddress.text.trim(),
              wardOrContact:
                  _destWard.text.trim().isEmpty ? null : _destWard.text.trim(),
              location: destPoint,
            ),
          );
      if (mounted) context.pushReplacement(Routes.requestDetail(req.id));
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Couldn\'t create the request. Try again.')),
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
        _StepTitle('What blood is needed?',
            'Choose the groups that can help, how many units, and how urgent it is.'),
        Text('Blood group', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        BloodGroupMultiPicker(
            selected: _groups, onChanged: (g) => setState(() => _groups = g)),
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
        for (final u in Urgency.values) ...[
          _UrgencyOption(
            urgency: u,
            selected: _urgency == u,
            onTap: () => setState(() => _urgency = u),
          ),
          if (u != Urgency.values.last) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  // ---- Step 2: location ----
  Widget _locationStep() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle('Where is the request?',
            'This helps us find donors closest to you.'),
        Consumer(builder: (context, ref, _) {
          final deviceLoc = ref.watch(deviceLocationProvider);
          final subtitle = _locating
              ? 'Getting your location…'
              : _useCurrent && _requestPoint != null
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
            selected: _useCurrent && _requestPoint != null,
            onTap: _locating
                ? () {}
                : () {
                    setState(() => _useCurrent = true);
                    _useDeviceLocation();
                  },
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        _SelectableTile(
          icon: Icons.edit_location_alt_rounded,
          title: 'Enter a different location',
          subtitle: 'Search an address or area',
          selected: !_useCurrent,
          onTap: () => setState(() {
            _useCurrent = false;
            _requestPoint = null;
            _location.clear();
          }),
        ),
        if (!_useCurrent) ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _location,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'e.g. Indiranagar, Bengaluru',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ],
      ],
    );
  }

  // ---- Step 3: destination ----
  Widget _destinationStep() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle('Where should donors go?',
            'The hospital or blood bank where the donation is needed.'),
        Text('Hospital / destination', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _destName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration:
              const InputDecoration(hintText: 'e.g. City General Hospital'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Address', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _destAddress,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Street, area, city'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Ward / contact (optional)', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _destWard,
          decoration:
              const InputDecoration(hintText: 'e.g. Ward 3B, Dr. Rao'),
        ),
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
        _StepTitle('Review your request',
            'Check the details. Donors nearby will be notified right away.'),
        AppCard(
          child: Column(
            children: [
              _reviewRowWidget('Blood group',
                  BloodGroupBadges(_groups.toList(), large: false)),
              _divider(),
              _reviewRow('Units', Fmt.units(_units), mono: true),
              _divider(),
              _reviewRowWidget('Urgency', UrgencyBadge(_urgency, dense: true)),
              _divider(),
              _reviewRow('Request location', _location.text.trim()),
              _divider(),
              _reviewRow('Destination', _destName.text.trim()),
              _divider(),
              _reviewRow('Address', _destAddress.text.trim()),
              if (_destWard.text.trim().isNotEmpty) ...[
                _divider(),
                _reviewRow('Ward / contact', _destWard.text.trim()),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
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

  Widget _divider() => Divider(height: AppSpacing.xl, color: context.colors.border);

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
                : context.text.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
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
            width: 120, child: Text(label, style: context.text.bodyMedium)),
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
          AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.lg),
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
                      fontWeight:
                          i == current ? FontWeight.w600 : FontWeight.w500,
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
            onTap: value > 1 ? () => onChanged(value - 1) : null),
        Expanded(
          child: Center(
            child: Text(Fmt.units(value), style: context.text.titleMedium),
          ),
        ),
        _StepBtn(
            icon: Icons.add_rounded,
            onTap: value < 10 ? () => onChanged(value + 1) : null),
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
          child: Icon(icon,
              color: enabled ? c.textPrimary : c.textTertiary, size: 20),
        ),
      ),
    );
  }
}

class _UrgencyOption extends StatelessWidget {
  const _UrgencyOption(
      {required this.urgency, required this.selected, required this.onTap});
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
              child: Text(urgency.label,
                  style: context.text.titleSmall
                      ?.copyWith(color: c.textPrimary)),
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
