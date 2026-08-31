import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'donor_status_card.dart';

/// The Home dashboard prioritizes what the user needs to do now: request blood,
/// see an active request or donation, and manage Donor Mode (spec §9).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final activeRequest = ref.watch(activeRequestProvider);
    final acceptedInvite = ref.watch(acceptedInvitationProvider);
    final pending = ref.watch(pendingInvitationsProvider).length;
    final donorOn = ref.watch(donorProfileValueProvider).isOn;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(myRequestsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
            children: [
              _Header(name: user?.name ?? 'there', hasUnread: pending > 0),
              const SizedBox(height: AppSpacing.xl),

              // Primary action.
              _RequestBloodCard(
                onTap: () => context.push(Routes.createRequest),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Active request (if any).
              if (activeRequest != null) ...[
                const SectionHeader('Your active request'),
                _ActiveRequestCard(request: activeRequest),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Active donation (if the user accepted an invitation).
              if (acceptedInvite != null) ...[
                const SectionHeader('You\'re donating'),
                _ActiveDonationCard(invitation: acceptedInvite),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Donor status.
              const SectionHeader('Donor Mode'),
              const DonorStatusCard(),

              // Helpful context when nothing is active.
              if (activeRequest == null && acceptedInvite == null) ...[
                const SizedBox(height: AppSpacing.lg),
                _HelpCard(donorOn: donorOn),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.hasUnread});
  final String name;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final first = name.split(' ').first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: context.text.bodyMedium),
              const SizedBox(height: 2),
              Text(first, style: context.text.headlineMedium),
            ],
          ),
        ),
        _IconButton(
          icon: Icons.notifications_none_rounded,
          badge: hasUnread,
          onTap: () => context.push(Routes.notifications),
        ),
        const SizedBox(width: AppSpacing.sm),
        Consumer(builder: (context, ref, _) {
          final user = ref.watch(currentUserProvider);
          return Avatar(
            initials: user?.initials ?? '?',
            onTap: () => context.go(Routes.you),
          );
        }),
      ],
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap, this.badge = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: c.textPrimary),
            if (badge)
              Positioned(
                right: 11,
                top: 11,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestBloodCard extends StatelessWidget {
  const _RequestBloodCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.brand,
      borderRadius: AppRadius.cardLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardLg,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.add_rounded, color: c.onBrand, size: 28),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Request blood',
                        style: context.text.titleLarge
                            ?.copyWith(color: c.onBrand)),
                    const SizedBox(height: 2),
                    Text(
                      'Find nearby donors in minutes',
                      style: context.text.bodyMedium?.copyWith(
                          color: c.onBrand.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: c.onBrand),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = statusStyle(context, request.status);
    return AppCard(
      onTap: () => context.push(Routes.requestDetail(request.id)),
      emphasize: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BloodGroupBadge(request.bloodGroup),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(request.units), style: context.text.titleSmall),
              const Spacer(),
              StatusBadge(request.status, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (request.status == RequestStatus.searching)
            _SearchingRow(request: request)
          else
            Row(
              children: [
                Icon(style.icon, size: 16, color: style.color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _statusLine(request),
                    style: context.text.bodyMedium
                        ?.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Track request',
                  style: context.text.labelLarge?.copyWith(color: c.brand)),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(BloodRequest r) {
    switch (r.status) {
      case RequestStatus.donorAccepted:
        return '${r.acceptedDonorName} accepted — coordination starting';
      case RequestStatus.coordinating:
        return 'Coordinating with ${r.acceptedDonorName}';
      case RequestStatus.created:
        return 'Request created — preparing search';
      default:
        return r.status.label;
    }
  }
}

class _SearchingRow extends StatelessWidget {
  const _SearchingRow({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.info)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            request.donorsContacted == 0
                ? 'Searching for nearby donors…'
                : '${request.donorsContacted} donors contacted · '
                    'within ${request.searchRadiusKm.toStringAsFixed(0)} km',
            style: AppTypography.mono(size: 12.5, color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ActiveDonationCard extends StatelessWidget {
  const _ActiveDonationCard({required this.invitation});
  final Invitation invitation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: () => context.push(Routes.coordination(invitation.requestId)),
      accent: c.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BloodGroupBadge(invitation.bloodGroup),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(invitation.units),
                  style: context.text.titleSmall),
              const Spacer(),
              Icon(Icons.how_to_reg_rounded, size: 18, color: c.success),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('${invitation.destinationName} · ${invitation.destinationArea}',
              style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Open coordination',
                  style: context.text.labelLarge?.copyWith(color: c.brand)),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.donorOn});
  final bool donorOn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 20, color: c.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  donorOn ? 'You\'re ready to help' : 'Become a lifesaver',
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  donorOn
                      ? 'Donor Mode is on. We\'ll notify you when someone nearby needs your blood type.'
                      : 'Turn on Donor Mode to receive requests from people near you who share your blood type.',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
