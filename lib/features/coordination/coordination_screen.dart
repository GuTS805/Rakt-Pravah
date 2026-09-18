import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'map_panel.dart';

/// The private coordination space between requester and donor. Contextual —
/// reached only after a donor accepts (spec §17). Chat and Live Location live
/// here, not in the bottom navigation.
class CoordinationScreen extends ConsumerWidget {
  const CoordinationScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestProvider(requestId));
    final me = ref.watch(currentUserProvider);
    final myLocation = ref.watch(deviceLocationProvider).point;

    return Scaffold(
      appBar: AppBar(title: const Text('Coordination')),
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CardSkeleton(),
        ),
        error: (e, _) => ErrorStateView(
          message: 'We couldn\'t open coordination.',
          onRetry: () => ref.invalidate(requestProvider(requestId)),
        ),
        data: (req) {
          final iAmDonor = req.acceptedDonorIds.contains(me?.id);
          // A donor coordinates with the requester; the requester coordinates
          // with every donor who has committed a unit.
          final partners = iAmDonor
              ? [(req.requesterName, 'Requester')]
              : [for (final d in req.acceptedDonors) (d.name, 'Donor')];

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _PartnerCard(
                partners: partners,
                request: req,
                showProgress: !iAmDonor,
              ),
              const SizedBox(height: AppSpacing.lg),
              MapPanel(
                destination: req.destination,
                myLocation: myLocation,
                onLocateMe: () async =>
                    (await ref.read(deviceLocationProvider.notifier).request())
                        .point,
                // Once a donor is sharing their live position, that's what
                // this map follows — seeing them get closer matters more
                // than the static destination pin at this point. A donor
                // watches nobody; they're the one being watched.
                trackedLocations: iAmDonor
                    ? const []
                    : [for (final p in req.donorLiveLocations.values) p.point],
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Coordinate'),
              _ActionTile(
                icon: Icons.forum_rounded,
                title: 'Open chat',
                subtitle: partners.length == 1
                    ? 'Message ${partners.first.$1.split(' ').first} privately'
                    : 'Message everyone helping with this request',
                onTap: () => context.push(Routes.chat(requestId)),
              ),
              const SizedBox(height: AppSpacing.md),
              _ActionTile(
                icon: Icons.my_location_rounded,
                title: 'Share live location',
                subtitle: 'Temporary — you choose when to start and stop',
                onTap: () => context.push(Routes.liveLocation(requestId)),
              ),
              const SizedBox(height: AppSpacing.md),
              _ActionTile(
                icon: Icons.directions_rounded,
                title: 'Get directions',
                subtitle: 'Fastest route to ${req.destination.name}',
                onTap: () => _openDirections(context, req.destination),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (req.status.isTerminal)
                Text(
                  req.status == RequestStatus.fulfilled
                      ? 'This request is fulfilled. Thank you.'
                      : 'This request was ${req.status.label.toLowerCase()}. '
                            'No need to go to the hospital.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium,
                )
              else if (iAmDonor)
                SecondaryButton(
                  label: 'I can\'t make it',
                  icon: Icons.close_rounded,
                  destructive: true,
                  onPressed: () => _withdraw(context, ref),
                )
              else ...[
                PrimaryButton(
                  label: 'Mark request fulfilled',
                  icon: Icons.check_rounded,
                  onPressed: () => _fulfill(context, ref),
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Cancel request',
                  icon: Icons.close_rounded,
                  destructive: true,
                  onPressed: () => _cancel(context, ref, req),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _fulfill(BuildContext context, WidgetRef ref) async {
    await ref.read(backendProvider).markFulfilled(requestId);
    if (context.mounted) context.pop();
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    BloodRequest req,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Cancel this request?',
      body:
          '${req.acceptedDonorName ?? 'Your donor'} will be told not to come.',
      confirmLabel: 'Cancel request',
    );
    if (ok != true) return;
    await ref.read(backendProvider).cancelRequest(requestId);
    if (context.mounted) context.pop();
  }

  /// The donor backs out. The request isn't cancelled: it goes back to
  /// searching so the patient can still get another donor.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Can\'t make it?',
      body:
          'The requester will be told, and we\'ll look for another donor '
          'straight away.',
      confirmLabel: 'I can\'t make it',
    );
    if (ok != true) return;
    try {
      await ref.read(backendProvider).withdrawFromRequest(requestId);
      if (context.mounted) context.go(Routes.donate);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t update. Try again.')),
        );
      }
    }
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
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
              style: context.text.labelLarge?.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens turn-by-turn navigation in the device's maps app — real
  /// coordinates when the address geocoded successfully, otherwise a text
  /// search so it still works rather than silently doing nothing.
  Future<void> _openDirections(BuildContext context, Destination dest) async {
    final loc = dest.location;
    final query = loc != null
        ? '${loc.lat},${loc.lng}'
        : Uri.encodeComponent('${dest.name}, ${dest.address}');
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$query&travelmode=driving',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open maps for directions.')),
      );
    }
  }
}

class _PartnerCard extends ConsumerWidget {
  const _PartnerCard({
    required this.partners,
    required this.request,
    required this.showProgress,
  });

  /// Name and role of everyone on the other side of this coordination.
  final List<(String, String)> partners;
  final BloodRequest request;
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Read from the request's private subcollection, which only the
    // requester and the donors who accepted are allowed to open.
    final patientName =
        ref.watch(patientNameProvider(request.id)).valueOrNull ??
        request.patientName;
    return AppCard(
      accent: c.success,
      child: Column(
        children: [
          for (final (index, partner) in partners.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Avatar(initials: _initials(partner.$1), size: 46),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(partner.$1, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(partner.$2, style: context.text.bodySmall),
                    ],
                  ),
                ),
                if (index == 0) StatusBadge(request.status, dense: true),
              ],
            ),
          ],
          if (showProgress && request.units > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              request.isFullyMatched
                  ? 'All ${Fmt.units(request.units)} covered.'
                  : '${request.unitsPledged} of ${request.units} units '
                        'covered. Still searching for the rest.',
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              BloodGroupBadges(request.bloodGroups, maxVisible: 2),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(request.units), style: context.text.titleSmall),
              const Spacer(),
              UrgencyBadge(request.urgency, dense: true),
            ],
          ),
          // The donor needs this at the blood bank to donate against the
          // right patient.
          if (patientName != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: c.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Patient: $patientName'
                    '${request.patientBloodGroup == null ? '' : ' · ${request.patientBloodGroup!.label}'}',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: c.brandSubtle,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: c.brand, size: 22),
          ),
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
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ],
      ),
    );
  }
}
