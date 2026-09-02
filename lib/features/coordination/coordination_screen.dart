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
          final iAmDonor = req.acceptedDonorId == me?.id;
          final counterpartName =
              iAmDonor ? req.requesterName : (req.acceptedDonorName ?? 'Donor');
          final counterpartRole = iAmDonor ? 'Requester' : 'Donor';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _PartnerCard(
                name: counterpartName,
                role: counterpartRole,
                request: req,
              ),
              const SizedBox(height: AppSpacing.lg),
              MapPanel(
                destination: req.destination,
                myLocation: myLocation,
                // Once the donor is sharing their live position, that's what
                // this map follows — seeing them get closer matters more
                // than the static destination pin at this point.
                trackedLocation: req.donorLiveLocation,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Coordinate'),
              _ActionTile(
                icon: Icons.forum_rounded,
                title: 'Open chat',
                subtitle: 'Message ${counterpartName.split(' ').first} privately',
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
              if (!iAmDonor && req.status == RequestStatus.coordinating)
                PrimaryButton(
                  label: 'Mark request fulfilled',
                  icon: Icons.check_rounded,
                  onPressed: () => _fulfill(context, ref),
                ),
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

  /// Opens turn-by-turn navigation in the device's maps app — real
  /// coordinates when the address geocoded successfully, otherwise a text
  /// search so it still works rather than silently doing nothing.
  Future<void> _openDirections(BuildContext context, Destination dest) async {
    final loc = dest.location;
    final query = loc != null
        ? '${loc.lat},${loc.lng}'
        : Uri.encodeComponent('${dest.name}, ${dest.address}');
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$query&travelmode=driving');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open maps for directions.')),
      );
    }
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard(
      {required this.name, required this.role, required this.request});
  final String name;
  final String role;
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      accent: c.success,
      child: Column(
        children: [
          Row(
            children: [
              Avatar(initials: _initials(name), size: 46),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(role, style: context.text.bodySmall),
                  ],
                ),
              ),
              StatusBadge(request.status, dense: true),
            ],
          ),
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
