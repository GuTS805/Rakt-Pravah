import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/accepted_donor_profile_card.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'map_panel.dart';

/// The private mutual coordination space between requester and donor.
/// Created after acceptance to share relevant profile and request details.
/// Call, Chat, and Live Location are enabled here.
class CoordinationScreen extends ConsumerWidget {
  const CoordinationScreen({super.key, required this.requestId});
  final String requestId;

  Future<void> _makePhoneCall(BuildContext context, String? rawPhone) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number is not available.')),
      );
      return;
    }
    final clean = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place call to $rawPhone')),
      );
    }
  }

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
          final partners = iAmDonor
              ? [(req.requesterName, 'Requester')]
              : [for (final d in req.acceptedDonors) (d.name, 'Donor')];

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Connection status header
              _ConnectionHeader(request: req),
              const SizedBox(height: AppSpacing.md),

              if (iAmDonor) ...[
                // Donor view: Requester and Patient details
                _DonorViewOfRequester(
                  request: req,
                  onCall: () => _makePhoneCall(context, req.phone),
                  onChat: () => context.push(Routes.chat(requestId)),
                  onNavigate: () => _openDirections(context, req.destination),
                ),
              ] else ...[
                // Requester view: Accepted Donor profile(s)
                _RequesterViewOfDonor(
                  request: req,
                  onTrackLive: () =>
                      context.push(Routes.liveLocation(requestId)),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              MapPanel(
                destination: req.destination,
                myLocation: myLocation,
                onLocateMe: () async =>
                    (await ref.read(deviceLocationProvider.notifier).request())
                        .point,
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
                icon: Icons.delivery_dining_rounded,
                title: 'Live Tracking & Route',
                subtitle: 'Real-time Zepto-style map, donor transit & ETA',
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

/// Mutual connection header indicating connection status
class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFulfilled = request.status == RequestStatus.fulfilled;
    final isTerminal = request.status.isTerminal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFulfilled
            ? c.successSubtle
            : isTerminal
            ? c.surfaceMuted
            : c.successSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isFulfilled
              ? c.success.withValues(alpha: 0.4)
              : isTerminal
              ? c.border
              : c.success.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFulfilled
                ? Icons.check_circle_rounded
                : isTerminal
                ? Icons.lock_outline_rounded
                : Icons.handshake_rounded,
            size: 20,
            color: isFulfilled
                ? c.success
                : isTerminal
                ? c.textTertiary
                : c.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFulfilled
                      ? 'Donation Completed · Connection Closed'
                      : isTerminal
                      ? '${request.status.label} · Connection Closed'
                      : 'Mutual Connection Active',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isFulfilled
                        ? c.success
                        : isTerminal
                        ? c.textSecondary
                        : c.success,
                  ),
                ),
                Text(
                  isFulfilled
                      ? 'Blood donation was completed. Tracking & coordination closed.'
                      : isTerminal
                      ? 'This request is closed.'
                      : 'Requester & Donor connected. Contact details & tracking shared.',
                  style: context.text.bodySmall?.copyWith(
                    fontSize: 11,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Donor's view: Requester & Patient profiles, hospital destination, notes, call & navigate
class _DonorViewOfRequester extends ConsumerWidget {
  const _DonorViewOfRequester({
    required this.request,
    required this.onCall,
    required this.onChat,
    required this.onNavigate,
  });

  final BloodRequest request;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onNavigate;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'R';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final patientName =
        ref.watch(patientNameProvider(request.id)).valueOrNull ??
        request.patientName;
    final patientBloodGroup =
        request.patientBloodGroup ?? request.bloodGroups.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Requester details card
        AppCard(
          accent: c.brand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Requester identity row
              Row(
                children: [
                  Avatar(initials: _initials(request.requesterName), size: 50),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.requesterName,
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.brandSubtle,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                'Requester',
                                style: AppTypography.mono(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: c.brand,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.successSubtle,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                'Verified Requester',
                                style: AppTypography.mono(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: c.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Requester's Phone Number (Revealed after acceptance)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 16, color: c.success),
                    const SizedBox(width: 8),
                    Text(
                      'Requester Phone: ',
                      style: context.text.bodySmall?.copyWith(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        request.phone ?? 'Not provided',
                        style: AppTypography.mono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.successSubtle,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'Shared on Accept',
                        style: AppTypography.mono(
                          size: 9,
                          weight: FontWeight.w700,
                          color: c.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Prominent Action Buttons: 📞 Call, 💬 Chat, 🧭 Navigate
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: ElevatedButton.icon(
                      onPressed:
                          (request.phone != null && request.phone!.isNotEmpty)
                          ? onCall
                          : null,
                      icon: const Icon(Icons.phone_rounded, size: 16),
                      label: const Text('Call'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: onChat,
                      icon: Icon(Icons.forum_rounded, size: 16, color: c.brand),
                      label: Text(
                        'Chat',
                        style: TextStyle(
                          color: c.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.brand.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      onPressed: onNavigate,
                      icon: const Icon(Icons.directions_rounded, size: 16),
                      label: const Text('Navigate'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Patient & Requirement Details Card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient & Medical Details',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.person_rounded, size: 18, color: c.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'Patient Name: ',
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  Text(
                    patientName ?? 'Needed',
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (patientBloodGroup != null)
                    BloodGroupBadge(patientBloodGroup),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop_rounded,
                          size: 12,
                          color: c.brand,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          request.bloodType,
                          style: context.text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      '${request.units} ${request.units == 1 ? "unit" : "units"} required',
                      style: context.text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  UrgencyBadge(request.urgency, dense: true),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Hospital & Request Location Card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_hospital_rounded, size: 20, color: c.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hospital / Destination',
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                request.destination.name,
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                request.destination.address,
                style: context.text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.requestLocationLabel,
                      style: context.text.bodySmall?.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              if (request.destination.wardOrContact != null &&
                  request.destination.wardOrContact!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    request.destination.wardOrContact!,
                    style: context.text.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Additional Notes Card (if present)
        if (request.notes != null && request.notes!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 18, color: c.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Additional Notes',
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(request.notes!, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Requester's view: Accepted Donor profile card(s)
class _RequesterViewOfDonor extends StatelessWidget {
  const _RequesterViewOfDonor({
    required this.request,
    required this.onTrackLive,
  });

  final BloodRequest request;
  final VoidCallback onTrackLive;

  @override
  Widget build(BuildContext context) {
    if (request.acceptedDonors.isEmpty) {
      return const AppCard(
        child: Text('Searching for nearby donors to accept...'),
      );
    }

    final sorted = [...request.acceptedDonors]
      ..sort((a, b) {
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        return da.compareTo(db);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final donor in sorted) ...[
          AcceptedDonorProfileCard(
            donor: donor,
            request: request,
            isSelected: true,
            onTrackLive: onTrackLive,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
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
