import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/invitation_card.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../home/donor_status_card.dart';

/// The donor dashboard. Donor Mode is a capability, not a separate app — this
/// tab is where the user turns it on, tunes it, and acts on opportunities.
class DonateScreen extends ConsumerWidget {
  const DonateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donor = ref.watch(donorProfileValueProvider);
    final invitesAsync = ref.watch(invitationsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            Text('Donate', style: context.text.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            const DonorStatusCard(),
            const SizedBox(height: AppSpacing.md),
            _DonorSummary(donor: donor),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader('Incoming requests'),
            if (!donor.isOn)
              const _DonorOffNote()
            else
              invitesAsync.when(
                loading: () => const CardSkeleton(),
                error: (e, _) => ErrorStateView(
                  message: 'We couldn\'t load requests near you.',
                  onRetry: () => ref.invalidate(invitationsProvider),
                ),
                data: (invites) {
                  final pending = invites
                      .where((i) => i.status == InvitationStatus.pending)
                      .toList();
                  if (pending.isEmpty) {
                    return const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No matching requests right now',
                      message:
                          'You\'re available. We\'ll notify you the moment '
                          'someone nearby needs your blood type.',
                    );
                  }
                  return Column(
                    children: [
                      for (final inv in pending) ...[
                        InvitationCard(
                          invitation: inv,
                          onTap: () =>
                              context.push(Routes.invitationDetail(inv.id)),
                          onAccept: () =>
                              context.push(Routes.invitationDetail(inv.id)),
                          onDecline: () => ref
                              .read(backendProvider)
                              .respondToInvitation(
                                inv.id,
                                InvitationStatus.declined,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DonorSummary extends StatelessWidget {
  const _DonorSummary({required this.donor});
  final DonorProfile donor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: null,
      child: Column(
        children: [
          _row(
            context,
            icon: Icons.bloodtype_rounded,
            label: 'Your blood group',
            trailing: BloodGroupBadge(donor.bloodGroup),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.social_distance_rounded,
            label: 'Match radius',
            trailing: Text(
              '${donor.maxDistanceKm.toStringAsFixed(0)} km',
              style: AppTypography.mono(size: 14, color: c.textPrimary),
            ),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.location_on_outlined,
            label: 'Location access',
            trailing: Text(
              donor.locationGranted ? 'Granted' : 'Not granted',
              style: context.text.bodyMedium?.copyWith(
                color: donor.locationGranted ? c.success : c.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => context.push(Routes.donorSettings),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: c.brand),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Donor settings',
                    style: context.text.labelLarge?.copyWith(color: c.brand),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget trailing,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 18, color: c.textTertiary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: context.text.bodyLarge)),
        trailing,
      ],
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: AppSpacing.xl, color: context.colors.border);
}

class _DonorOffNote extends StatelessWidget {
  const _DonorOffNote();
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.do_not_disturb_on_outlined,
            size: 20,
            color: c.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Turn on Donor Mode above to start receiving requests near you.',
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
