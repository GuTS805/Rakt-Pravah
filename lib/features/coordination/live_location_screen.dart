import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/buttons.dart';
import '../../data/providers.dart';
import 'map_panel.dart';

/// Live location sharing (spec §19). Never on by default: the user explicitly
/// starts a temporary, time-boxed session and can stop it anytime. The backend
/// must enforce authorization for real sessions — hiding the button is never
/// the security boundary.
class LiveLocationScreen extends ConsumerStatefulWidget {
  const LiveLocationScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends ConsumerState<LiveLocationScreen> {
  static const _sessionMinutes = 30;
  static const _updateInterval = Duration(seconds: 15);

  bool _sharing = false;
  bool _starting = false;
  Duration _remaining = const Duration(minutes: _sessionMinutes);
  Timer? _countdownTimer;
  Timer? _locationTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    // Leaving this screen ends sharing rather than leaving a stale position
    // visible on the other side indefinitely — "Stop sharing" is explicit,
    // but so is walking away from the temporary session that created it.
    if (_sharing) {
      ref.read(backendProvider).stopLiveLocation(widget.requestId);
    }
    super.dispose();
  }

  Future<void> _start() async {
    // Sharing is explicit and opt-in: fetching the real position only happens
    // here, the moment the user taps to start — never before, never silently.
    setState(() => _starting = true);
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!mounted) return;
    setState(() => _starting = false);

    if (!result.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location access is needed to share your live location.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _sharing = true;
      _remaining = const Duration(minutes: _sessionMinutes);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final next = _remaining - const Duration(seconds: 1);
      if (next.isNegative) {
        _stop();
      } else {
        setState(() => _remaining = next);
      }
    });
    // Push a real position update immediately, then keep refreshing it —
    // this is what the other party's coordination map actually tracks.
    unawaited(_pushLocation());
    _locationTimer = Timer.periodic(_updateInterval, (_) => _pushLocation());
  }

  Future<void> _pushLocation() async {
    final result = await ref
        .read(locationServiceProvider)
        .getLocationIfPermitted();
    if (result is LocationGranted && mounted) {
      await ref
          .read(backendProvider)
          .updateLiveLocation(widget.requestId, result.point);
    }
  }

  void _stop() {
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    ref.read(backendProvider).stopLiveLocation(widget.requestId);
    setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final req = ref.watch(requestProvider(widget.requestId)).valueOrNull;
    final myLocation = ref.watch(deviceLocationProvider).point;
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Live location')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_sharing) _ActiveBanner(remaining: _remaining),
          if (_sharing) const SizedBox(height: AppSpacing.lg),
          if (req != null)
            MapPanel(
              destination: req.destination,
              // Only reveal the position dot while actually sharing — this
              // mirrors what the other party would see: nothing until you
              // explicitly opt in.
              myLocation: _sharing ? myLocation : null,
            ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: c.info),
                    const SizedBox(width: AppSpacing.sm),
                    Text('How sharing works', style: context.text.titleSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _bullet(
                  context,
                  'Only the person you\'re coordinating with can see it.',
                ),
                _bullet(
                  context,
                  'It\'s temporary — sharing ends automatically after $_sessionMinutes minutes.',
                ),
                _bullet(context, 'You can stop sharing at any time.'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_sharing)
            PrimaryButton(
              label: 'Stop sharing',
              icon: Icons.stop_circle_outlined,
              danger: true,
              onPressed: _stop,
            )
          else
            PrimaryButton(
              label: 'Share live location',
              icon: Icons.my_location_rounded,
              busy: _starting,
              onPressed: _start,
            ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              height: 5,
              width: 5,
              decoration: BoxDecoration(
                color: c.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mm = remaining.inMinutes.toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.successSubtle,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          _PulsingDot(color: c.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Your live location is being shared temporarily.',
              style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
            ),
          ),
          Text(
            '$mm:$ss',
            style: AppTypography.mono(
              size: 14,
              weight: FontWeight.w600,
              color: c.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      width: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 8 + _ctrl.value * 8,
                width: 8 + _ctrl.value * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(
                    alpha: (1 - _ctrl.value) * 0.4,
                  ),
                ),
              ),
              Container(
                height: 8,
                width: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
