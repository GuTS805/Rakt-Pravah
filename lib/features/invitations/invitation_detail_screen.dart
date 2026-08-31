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
import '../../core/widgets/buttons.dart';
import '../../core/widgets/states.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Donor opportunity detail. Before acceptance it exposes only what's needed to
/// decide — no private requester data (spec §16, §26). Accepting opens the
/// coordination context.
class InvitationDetailScreen extends ConsumerStatefulWidget {
  const InvitationDetailScreen({super.key, required this.invitationId});
  final String invitationId;

  @override
  ConsumerState<InvitationDetailScreen> createState() =>
      _InvitationDetailScreenState();
}

class _InvitationDetailScreenState
    extends ConsumerState<InvitationDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(invitationsProvider).valueOrNull ?? const [];
    final matches = invites.where((i) => i.id == widget.invitationId);
    final inv = matches.isEmpty ? null : matches.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Donor opportunity')),
      body: inv == null
          ? const EmptyState(
              icon: Icons.link_off_rounded,
              title: 'Opportunity unavailable',
              message: 'This request is no longer available.',
            )
          : _content(context, inv),
    );
  }

  Widget _content(BuildContext context, inv) {
    final c = context.colors;
    final expired = inv.status == InvitationStatus.expired ||
        (inv.expiresAt != null && inv.expiresAt!.isBefore(DateTime.now()));
    final acted = inv.status != InvitationStatus.pending;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              AppCard(
                accent: urgencyStyle(context, inv.urgency).color,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        BloodGroupBadge(inv.bloodGroup, large: true),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(Fmt.units(inv.units),
                              style: context.text.headlineSmall),
                        ),
                        UrgencyBadge(inv.urgency),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                            child: DataField(
                                label: 'Distance',
                                value:
                                    '${inv.distanceKm.toStringAsFixed(1)} km')),
                        Expanded(
                            child: DataField(
                                label: 'Expires in',
                                value: Fmt.remaining(inv.expiresAt))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Destination'),
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.local_hospital_rounded,
                        color: c.textSecondary, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inv.destinationName,
                              style: context.text.titleSmall),
                          const SizedBox(height: 2),
                          Text(inv.destinationArea,
                              style: context.text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PrivacyNote(),
            ],
          ),
        ),
        if (!acted && !expired)
          _actions(context, inv)
        else
          _statusBar(context, inv, expired),
      ],
    );
  }

  Widget _actions(BuildContext context, inv) {
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
          child: Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Decline',
                  onPressed: _busy ? null : () => _decline(inv),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: 'Accept & help',
                  icon: Icons.favorite_rounded,
                  busy: _busy,
                  onPressed: () => _accept(inv),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar(BuildContext context, inv, bool expired) {
    final c = context.colors;
    final label = expired
        ? 'This opportunity is no longer available.'
        : inv.status == InvitationStatus.accepted
            ? 'You accepted this request.'
            : 'You declined this request.';
    return Container(
      width: double.infinity,
      color: c.surfaceMuted,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(label,
              textAlign: TextAlign.center, style: context.text.bodyMedium),
        ),
      ),
    );
  }

  Future<void> _decline(inv) async {
    setState(() => _busy = true);
    await ref
        .read(backendProvider)
        .respondToInvitation(inv.id, InvitationStatus.declined);
    if (mounted) context.pop();
  }

  Future<void> _accept(inv) async {
    setState(() => _busy = true);
    await ref
        .read(backendProvider)
        .respondToInvitation(inv.id, InvitationStatus.accepted);
    if (mounted) {
      context.pushReplacement(Routes.coordination(inv.requestId));
    }
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.infoSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: c.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'The requester\'s contact details stay private until you accept. '
              'After that, a private chat opens to coordinate.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
