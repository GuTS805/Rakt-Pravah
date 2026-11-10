import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/services/donor_gate.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../data/backend_error.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Donor Mode status with an inline toggle. The backend is the source of truth:
/// the switch shows a busy state while the change is in flight and reverts with
/// a message if it fails (spec §15) — a local toggle never lies about server
/// state.
///
/// While a donor is within the 3-month (90-day) cooldown after their last donation,
/// Donor Mode is automatically turned OFF and the switch is frozen. The next
/// eligible donation date is displayed with a live countdown. When the waiting
/// period ends, Donor Mode automatically turns back ON.
class DonorStatusCard extends ConsumerStatefulWidget {
  const DonorStatusCard({super.key});

  @override
  ConsumerState<DonorStatusCard> createState() => _DonorStatusCardState();
}

class _DonorStatusCardState extends ConsumerState<DonorStatusCard> {
  bool _busy = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The notification setting can change in the system settings while the
    // app is in the background; look again on coming back.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(notificationsAllowedProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Asks again where the system still allows it, otherwise opens this app's
  /// system settings, where notifications can be switched back on.
  Future<void> _enableNotifications() async {
    await NotificationService.instance.requestPermission();
    final allowed = await NotificationService.instance.notificationsAllowed();
    if (allowed != true) await Geolocator.openAppSettings();
    ref.invalidate(notificationsAllowedProvider);
  }

  void _checkAutoReenable(DonorProfile donor) {
    if (donor.lastDonation != null &&
        !donor.isInCooldown &&
        donor.availability == DonorAvailability.off &&
        !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(backendProvider)
            .setDonorProfile(
              donor.copyWith(availability: DonorAvailability.available),
            );
      });
    }
  }

  /// Says why a change didn't go through: the backend's own explanation when
  /// it has one (no connection, no database), otherwise [fallback].
  void _fail(Object error, String fallback) {
    if (!mounted) return;
    final message = error is BackendUnavailable ? error.message : fallback;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
  }

  Future<void> _toggle(bool on) async {
    if (on && !requireDonorProfile(context, ref)) return;
    final backend = ref.read(backendProvider);
    final current = ref.read(donorProfileValueProvider);
    setState(() => _busy = true);
    try {
      await backend.setDonorProfile(
        current.copyWith(
          availability: on
              ? DonorAvailability.available
              : DonorAvailability.off,
        ),
      );
    } catch (e) {
      _fail(e, 'Couldn\'t update Donor Mode. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordDonationToday() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Donated Blood Today?'),
        content: const Text(
          'Marking that you donated blood today will start your mandatory 3-month '
          'recovery period. Donor Mode will automatically turn OFF for safety, '
          'and will automatically reactivate ON when the 3 months end.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Donation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).recordDonation(DateTime.now());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Thank you for donating blood! Donor Mode is now OFF for 3 months recovery.',
            ),
          ),
        );
      }
    } catch (e) {
      _fail(e, 'Couldn\'t record donation. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetCooldown() async {
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).resetDonationCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donation removed. Donor Mode is ON.')),
        );
      }
    } catch (e) {
      _fail(e, 'Couldn\'t undo that. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final donor = ref.watch(donorProfileValueProvider);
    final now = ref.watch(currentTimeProvider).valueOrNull ?? DateTime.now();
    final canAct = ref.watch(canActValueProvider);
    final notificationsOff =
        ref.watch(notificationsAllowedProvider).valueOrNull == false;
    _checkAutoReenable(donor);

    final cooldown = donor.isInCooldown;
    // The heart stays warm whether or not Donor Mode is on — it's an
    // invitation, and the switch beside it already says what the state is.
    // Greying it out only when the cooldown locks the control keeps "off"
    // looking switchable instead of looking broken.
    final (tint, tintSubtle) = cooldown
        ? (c.textTertiary, c.surfaceMuted)
        : donor.availability == DonorAvailability.paused
        ? (c.warning, c.warningSubtle)
        : (c.brand, c.brandSubtle);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: tintSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  cooldown ? Icons.bedtime_rounded : Icons.favorite_rounded,
                  color: tint,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A Wrap, so on a narrow card the badge drops under the
                    // title instead of squeezing it to one letter per line.
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Donor Mode', style: context.text.titleMedium),
                        // Only the cooldown badge survives: it carries a number
                        // the subtitle doesn't. An availability chip would just
                        // repeat the line underneath it.
                        if (cooldown)
                          _CooldownBadge(remaining: donor.cooldownRemaining),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cooldown
                          ? 'Resting after your last donation — thank you.'
                          : _subtitle(donor.availability, canAct: canAct),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_busy)
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(c.brand),
                  ),
                )
              else
                Switch(
                  value: donor.isOn && !cooldown,
                  activeThumbColor: c.brand,
                  onChanged: cooldown ? null : (v) => _toggle(v),
                ),
            ],
          ),

          // A donor who has said no to notifications is still matched, but
          // the alert never shows. Say so, with the way to fix it.
          if (donor.isOn && !cooldown && notificationsOff) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.warningSubtle,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 18,
                    color: c.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      "Notifications are off, so requests can't reach you.",
                      style: context.text.bodySmall?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _enableNotifications,
                    child: const Text('Turn on'),
                  ),
                ],
              ),
            ),
          ],

          // Cooldown details with Next Eligible Date and live countdown
          if (cooldown && donor.nextEligibleDonationDate != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.warningSubtle,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: c.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        size: 16,
                        color: c.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Next eligible donation date (3 months later):',
                          style: context.text.labelSmall?.copyWith(
                            color: c.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Fmt.fullDate(donor.nextEligibleDonationDate!),
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 15, color: c.warning),
                      const SizedBox(width: AppSpacing.xs),
                      // Wraps the countdown under the label on narrow
                      // screens and with large system text.
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Time remaining: ',
                              style: context.text.bodySmall?.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                            Text(
                              Fmt.countdown(donor.cooldownRemaining),
                              style: AppTypography.mono(
                                size: 13,
                                weight: FontWeight.w700,
                                color: c.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Donor Mode is automatically OFF and will automatically become ON again when the 3-month waiting period ends.',
                    style: context.text.bodySmall?.copyWith(
                      fontSize: 11,
                      color: c.textTertiary,
                    ),
                  ),
                  // Only to fix a mistaken tap. Waiting 90 days between
                  // donations protects the donor, so it can't be skipped
                  // later on.
                  if (donor.lastDonation != null &&
                      now.difference(donor.lastDonation!) <
                          const Duration(hours: 24)) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _resetCooldown,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.undo_rounded, size: 14),
                        label: const Text(
                          "Undo: I didn't donate",
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _recordDonationToday,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: Icon(
                    Icons.water_drop_outlined,
                    size: 14,
                    color: c.brand,
                  ),
                  label: Text(
                    'I donated blood today',
                    style: context.text.labelSmall?.copyWith(
                      color: c.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(DonorAvailability a, {required bool canAct}) {
    switch (a) {
      case DonorAvailability.available:
        return canAct
            ? 'You can receive matching requests nearby.'
            : 'Verify your phone number to start receiving requests.';
      case DonorAvailability.paused:
        return 'Paused — you won\'t be notified for now.';
      case DonorAvailability.off:
        return 'You\'re not participating as a donor.';
    }
  }
}

class _CooldownBadge extends StatelessWidget {
  const _CooldownBadge({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = remaining.inHours < 24 ? 1 : (remaining.inHours / 24).ceil();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: c.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime_rounded, size: 12, color: c.warning),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              days == 1 ? 'Eligible tomorrow' : 'Eligible in $days days',
              style: context.text.labelSmall?.copyWith(
                color: c.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
