import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/action_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/accepted_donor_profile_card.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/donor_ranking_card.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/status_timeline.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Live request tracking. Auto-updates as the backend advances the state
/// machine: created -> searching -> donor accepted -> coordinating -> fulfilled
/// (spec §12). Terminal states show the appropriate final UI.
class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestProvider(requestId));

    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: async.when(
        loading: () => const _LoadingBody(),
        error: (e, _) => ErrorStateView(
          message: 'We couldn\'t load this request.',
          onRetry: () => ref.invalidate(requestProvider(requestId)),
        ),
        data: (req) => _Body(request: req),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.lg),
    child: Column(
      children: [
        CardSkeleton(),
        SizedBox(height: AppSpacing.lg),
        CardSkeleton(),
      ],
    ),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _SummaryCard(request: request),
              const SizedBox(height: AppSpacing.lg),
              if (request.acceptedDonors.isNotEmpty) ...[
                _AcceptedDonorsSection(request: request),
              ],
              if (request.status.isActive) ...[
                _NearbyDonorsSection(request: request),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (request.status == RequestStatus.searching) ...[
                _SearchingCard(request: request),
                const SizedBox(height: AppSpacing.lg),
              ],
              const SectionHeader('Progress'),
              AppCard(child: StatusTimeline(request: request)),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Destination'),
              _DestinationCard(request: request),
              if (request.status.isTerminal) ...[
                const SizedBox(height: AppSpacing.lg),
                _TerminalNote(status: request.status),
              ],
            ],
          ),
        ),
        _ActionBar(request: request),
      ],
    );
  }
}

class _AcceptedDonorsSection extends StatefulWidget {
  const _AcceptedDonorsSection({required this.request});
  final BloodRequest request;

  @override
  State<_AcceptedDonorsSection> createState() => _AcceptedDonorsSectionState();
}

class _AcceptedDonorsSectionState extends State<_AcceptedDonorsSection> {
  String? _selectedDonorId;

  Future<void> _makePhoneCall(
    BuildContext context,
    String rawPhone,
    String? countryCode,
  ) async {
    await PhoneUtils.makePhoneCall(context, rawPhone, countryCode: countryCode);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = [...widget.request.acceptedDonors]
      ..sort((a, b) {
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        return da.compareTo(db);
      });

    if (sorted.isEmpty) return const SizedBox.shrink();

    final selectedId =
        _selectedDonorId != null && sorted.any((d) => d.id == _selectedDonorId)
        ? _selectedDonorId!
        : sorted.first.id;

    final primaryDonor = sorted.firstWhere(
      (d) => d.id == selectedId,
      orElse: () => sorted.first,
    );
    final alternativeDonors = sorted
        .where((d) => d.id != primaryDonor.id)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader('Accepted Donors')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.successSubtle,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.success.withValues(alpha: 0.25)),
              ),
              child: Text(
                '${sorted.length} accepted · nearest first',
                style: AppTypography.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: c.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Primary selected accepted donor profile card
        AcceptedDonorProfileCard(
          donor: primaryDonor,
          request: widget.request,
          isSelected: true,
          onTrackLive: () =>
              context.push(Routes.liveLocation(widget.request.id)),
        ),

        // Alternative donors if multiple donors accepted
        if (alternativeDonors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                'Alternative Donors (${alternativeDonors.length} available)',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Tap any donor to select and coordinate with them',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final alt in alternativeDonors) ...[
            _AlternativeDonorCard(
              donor: alt,
              request: widget.request,
              onSelect: () => setState(() => _selectedDonorId = alt.id),
              onCall: alt.phone != null && alt.phone!.isNotEmpty
                  ? () => _makePhoneCall(
                      context,
                      alt.phone!,
                      alt.phoneCountryCode,
                    )
                  : null,
              onChat: () => context.push(Routes.chat(widget.request.id)),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _AlternativeDonorCard extends StatelessWidget {
  const _AlternativeDonorCard({
    required this.donor,
    required this.request,
    required this.onSelect,
    this.onCall,
    required this.onChat,
  });

  final AcceptedDonor donor;
  final BloodRequest request;
  final VoidCallback onSelect;
  final VoidCallback? onCall;
  final VoidCallback onChat;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'D';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dist = donor.distanceKm != null
        ? '${donor.distanceKm!.toStringAsFixed(1)} km away'
        : 'Nearby';
    final eta = donor.estimatedTravelMinutes != null
        ? '~${donor.estimatedTravelMinutes} min'
        : '';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Avatar(
            initials: _initials(donor.name),
            photoUrl: donor.photoUrl,
            size: 42,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        donor.name,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (donor.bloodGroup != null)
                      BloodGroupBadge(donor.bloodGroup!),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$dist ${eta.isNotEmpty ? "• $eta travel" : ""}',
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Actions
          if (onCall != null)
            IconButton(
              tooltip: 'Call donor',
              icon: Icon(Icons.phone_rounded, size: 18, color: c.success),
              style: IconButton.styleFrom(
                backgroundColor: c.successSubtle,
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
              onPressed: onCall,
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Chat with donor',
            icon: Icon(Icons.forum_rounded, size: 18, color: c.brand),
            style: IconButton.styleFrom(
              backgroundColor: c.brandSubtle,
              minimumSize: const Size(32, 32),
              padding: EdgeInsets.zero,
            ),
            onPressed: onChat,
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: onSelect,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surfaceMuted,
              foregroundColor: c.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(60, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                side: BorderSide(color: c.border),
              ),
            ),
            child: const Text(
              'Select',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyDonorsSection extends ConsumerWidget {
  const _NearbyDonorsSection({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nearbyAsync = ref.watch(nearbyDonorsProvider(request.id));
    final currentRadius = request.searchRadiusKm > 0
        ? request.searchRadiusKm
        : 25.0;

    Widget searching() => AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 36,
                color: c.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Alerting donors within ${currentRadius.round()} km',
                style: context.text.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Donors nearby with a matching blood group can see '
                "this request. You'll see a donor here as soon as "
                'one accepts. Widen the search to reach more people.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Expand to ${(currentRadius + 25).round()} km',
                icon: Icons.zoom_out_map_rounded,
                onPressed: () {
                  ref
                      .read(backendProvider)
                      .expandSearchRadius(request.id, currentRadius + 25);
                },
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader('Nearby & Matched Donors')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.brandSubtle,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.brand.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radar_rounded, size: 12, color: c.brand),
                  const SizedBox(width: 4),
                  Text(
                    '${currentRadius.round()} km radius',
                    style: AppTypography.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: c.brand,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Ranked by real distance from hospital • Nearest first',
          style: context.text.bodySmall?.copyWith(
            color: c.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in [15.0, 25.0, 50.0, 100.0])
              ChoiceChip(
                label: Text('${r.round()} km'),
                selected: (currentRadius - r).abs() < 1.0,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(backendProvider).expandSearchRadius(request.id, r);
                  }
                },
                selectedColor: c.brandSubtle,
                labelStyle: AppTypography.mono(
                  size: 11,
                  weight: FontWeight.w600,
                  color: (currentRadius - r).abs() < 1.0
                      ? c.brand
                      : c.textSecondary,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        nearbyAsync.when(
          loading: () => const CardSkeleton(),
          // Donor profiles are private, so the list can come back refused;
          // the search is still running either way.
          error: (_, _) => searching(),
          data: (donors) {
            final acceptedIds = request.acceptedDonorIds.toSet();
            final unaccepted = donors
                .where((d) => !acceptedIds.contains(d.id))
                .toList();

            if (unaccepted.isEmpty) return searching();

            return Column(
              children: [
                for (final donor in unaccepted)
                  DonorRankingCard(
                    donor: donor,
                    destination: request.destination,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The name lives in the request's private subcollection now, readable
    // only by this requester and the donors who accepted.
    final patientName =
        ref.watch(patientNameProvider(request.id)).valueOrNull ??
        request.patientName;
    return AppCard(
      accent: request.status.isActive
          ? urgencyStyle(context, request.urgency).color
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The badges and the status pill share a line and the text sits
          // under them. All on one row, a request open to eight groups left
          // the text no width at all and it stacked one letter per line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BloodGroupBadges(
                  request.bloodGroups,
                  large: true,
                  maxVisible: 3,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusBadge(request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(Fmt.units(request.units), style: context.text.titleLarge),
          const SizedBox(height: 2),
          Text(
            patientName == null
                ? 'Created ${Fmt.relative(request.createdAt)}'
                : 'For $patientName'
                      '${request.patientBloodGroup == null ? '' : ' (${request.patientBloodGroup!.label})'}'
                      ' · ${Fmt.relative(request.createdAt)}',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: DataField(
                  label: 'Urgency',
                  value: request.urgency.label,
                ),
              ),
              if (request.requiredDate != null)
                Expanded(
                  child: DataField(
                    label: 'Date needed',
                    value: Fmt.date(request.requiredDate!),
                  ),
                ),
              Expanded(
                child: DataField(
                  label: 'Location',
                  value: request.requestLocationLabel.split('·').first.trim(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(c.info),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  request.hasAcceptedDonor
                      ? 'Searching for the remaining donors…'
                      : 'Searching for nearby donors…',
                  style: context.text.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: DataField(
                  label: 'Units covered',
                  value: '${request.unitsPledged} of ${request.units}',
                ),
              ),
              Expanded(
                child: DataField(
                  label: 'Time left',
                  value: Fmt.remaining(request.expiresAt),
                ),
              ),
            ],
          ),
          if (request.hasAcceptedDonor) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              '${request.acceptedDonors.map((d) => d.name).join(', ')} '
              'already said yes. Still looking for '
              '${Fmt.units(request.unitsRemaining)}.',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = request.destination;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.local_hospital_rounded,
              color: c.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(d.address, style: context.text.bodyMedium),
                if (d.wardOrContact != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    d.wardOrContact!,
                    style: context.text.bodySmall?.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalNote extends StatelessWidget {
  const _TerminalNote({required this.status});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(context, status);
    final (title, body) = switch (status) {
      RequestStatus.fulfilled => (
        'Request fulfilled',
        'Thank you. This request is complete — no further donors will be contacted.',
      ),
      RequestStatus.cancelled => (
        'Request cancelled',
        'This request was cancelled. Donors are no longer being contacted.',
      ),
      RequestStatus.expired => (
        'Request expired',
        'This request is no longer active. Create a new one if you still need help.',
      ),
      RequestStatus.removedByAdmin => (
        'Removed by an administrator',
        'This request was removed. Contact support if you believe this is a mistake.',
      ),
      _ => ('', ''),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: style.subtle,
        borderRadius: AppRadius.cardLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.color, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = request.status;

    Widget? primary;
    Widget? secondary;

    if (status == RequestStatus.expired) {
      // Expired requests aren't a dead end: the patient usually still needs
      // the blood, so the requester can put it back in front of donors.
      primary = PrimaryButton(
        label: 'Search again for 6 more hours',
        icon: Icons.refresh_rounded,
        onPressed: () => ref.read(backendProvider).extendRequest(request.id),
      );
    } else if (request.hasAcceptedDonor && status.isActive) {
      primary = PrimaryButton(
        label: 'Open coordination',
        icon: Icons.forum_rounded,
        onPressed: () => context.push(Routes.coordination(request.id)),
      );
      secondary = Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Cancel',
              icon: Icons.close_rounded,
              destructive: true,
              onPressed: () => _confirmCancel(context, ref),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SecondaryButton(
              label: 'Mark fulfilled',
              icon: Icons.check_rounded,
              onPressed: () => _confirmFulfill(context, ref),
            ),
          ),
        ],
      );
    } else if (status == RequestStatus.searching ||
        status == RequestStatus.created) {
      primary = SecondaryButton(
        label: 'Cancel request',
        icon: Icons.close_rounded,
        destructive: true,
        onPressed: () => _confirmCancel(context, ref),
      );
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              primary,
              if (secondary != null) ...[
                const SizedBox(height: AppSpacing.sm),
                secondary,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Cancel this request?',
      body: request.hasAcceptedDonor
          ? '${request.acceptedDonorName ?? 'Your donor'} will be told not '
                'to come. You can create a new request anytime.'
          : 'Donors will stop being contacted. You can create a new request '
                'anytime.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(backendProvider).cancelRequest(request.id);
    } catch (e) {
      if (context.mounted) {
        showActionError(context, e, 'Couldn\'t cancel the request. Try again.');
      }
    }
  }

  Future<void> _confirmFulfill(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Mark as fulfilled?',
      body: 'This closes the request and thanks your donor.',
      confirmLabel: 'Mark fulfilled',
      destructive: false,
    );
    if (ok != true) return;
    try {
      await ref.read(backendProvider).markFulfilled(request.id);
    } catch (e) {
      if (context.mounted) {
        showActionError(context, e, 'Couldn\'t close the request. Try again.');
      }
    }
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required bool destructive,
}) {
  final c = context.colors;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: context.text.titleLarge),
      content: Text(body, style: context.text.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Keep',
            style: context.text.labelLarge?.copyWith(color: c.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: context.text.labelLarge?.copyWith(
              color: destructive ? c.danger : c.brand,
            ),
          ),
        ),
      ],
    ),
  );
}
