import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/models.dart';
import '../router/routes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'avatar.dart';
import 'badges.dart';

/// Comprehensive profile card for an accepted donor shown to the requester.
/// Strictly enforces privacy: only donation-essential information, verification
/// status, and transit journey are visible. Permanent home addresses and ID
/// documents are never exposed.
class AcceptedDonorProfileCard extends StatelessWidget {
  const AcceptedDonorProfileCard({
    super.key,
    required this.donor,
    required this.request,
    this.isSelected = true,
    this.onSelect,
    this.showActions = true,
    this.onTrackLive,
  });

  final AcceptedDonor donor;
  final BloodRequest request;
  final bool isSelected;
  final VoidCallback? onSelect;
  final bool showActions;
  final VoidCallback? onTrackLive;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'D';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _makePhoneCall(BuildContext context, String rawPhone) async {
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final livePing = request.donorLiveLocations[donor.id];
    final effectiveTransitStatus =
        livePing?.transitStatus ?? donor.transitStatus;

    final double effectiveDistance;
    if (livePing != null && request.destination.location != null) {
      // Calculate real-time distance from live ping to destination
      final p1 = livePing.point;
      final p2 = request.destination.location!;
      effectiveDistance = _haversineKm(p1, p2);
    } else {
      effectiveDistance = donor.distanceKm ?? 2.4;
    }
    final travelMins = (effectiveDistance / 0.5).round().clamp(2, 180);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isSelected ? c.success.withValues(alpha: 0.6) : c.border,
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top selection / status header
          if (isSelected)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: c.successSubtle,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.card - 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.stars_rounded, size: 16, color: c.success),
                  const SizedBox(width: 6),
                  Text(
                    'Selected Donor · Primary Contact',
                    style: AppTypography.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: c.success,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: c.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: c.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Active',
                          style: AppTypography.mono(
                            size: 10,
                            weight: FontWeight.w700,
                            color: c.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Donor identity row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Avatar(
                      initials: _initials(donor.name),
                      photoUrl: donor.photoUrl,
                      size: 52,
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
                                  style: context.text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (donor.isVerified)
                                Tooltip(
                                  message: 'Verified Donor Profile',
                                  child: Icon(
                                    Icons.verified_rounded,
                                    size: 18,
                                    color: c.brand,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Badges row: Blood Group, Blood Type, Verification
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (donor.bloodGroup != null)
                                BloodGroupBadge(donor.bloodGroup!),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surfaceMuted,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.pill,
                                  ),
                                  border: Border.all(color: c.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.water_drop_rounded,
                                      size: 11,
                                      color: c.brand,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      donor.bloodType,
                                      style: context.text.bodySmall?.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (donor.isVerified)
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield_rounded,
                                        size: 10,
                                        color: c.brand,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Verified',
                                        style: AppTypography.mono(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.brand,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Donor availability / status indicator
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: donor.isDonorModeOn
                                      ? c.success
                                      : c.textTertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                donor.isDonorModeOn
                                    ? 'Available · Donor Mode ON'
                                    : 'Donor Mode OFF',
                                style: context.text.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: donor.isDonorModeOn
                                      ? c.success
                                      : c.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Phone number display (revealed after acceptance)
                if (donor.phone != null && donor.phone!.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: c.border.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 16, color: c.success),
                        const SizedBox(width: 8),
                        Text(
                          'Phone: ',
                          style: context.text.bodySmall?.copyWith(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                        Text(
                          donor.phone!,
                          style: AppTypography.mono(
                            size: 13,
                            weight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        const Spacer(),
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
                ],

                // Distance & ETA metrics
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: c.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.near_me_rounded,
                              size: 16,
                              color: c.brand,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Distance',
                                    style: context.text.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: c.textTertiary,
                                    ),
                                  ),
                                  Text(
                                    '${effectiveDistance.toStringAsFixed(1)} km away',
                                    style: AppTypography.mono(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: c.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.directions_car_rounded,
                              size: 16,
                              color: c.brand,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Travel ETA',
                                    style: context.text.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: c.textTertiary,
                                    ),
                                  ),
                                  Text(
                                    '~$travelMins min travel',
                                    style: AppTypography.mono(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // Journey status stepper
                Text(
                  'Donor Journey Status',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _JourneyStepper(currentStatus: effectiveTransitStatus),

                if (showActions) ...[
                  const SizedBox(height: AppSpacing.lg),
                  // Primary action buttons: Track Donor, Call, Chat
                  Row(
                    children: [
                      // Track Donor button
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed:
                              onTrackLive ??
                              () =>
                                  context.push(Routes.liveLocation(request.id)),
                          icon: const Icon(Icons.navigation_rounded, size: 16),
                          label: const Text('Track Donor (Live)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Call button
                      if (donor.phone != null && donor.phone!.isNotEmpty) ...[
                        OutlinedButton(
                          onPressed: () =>
                              _makePhoneCall(context, donor.phone!),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.success,
                            side: BorderSide(
                              color: c.success.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_rounded, size: 16),
                              SizedBox(width: 4),
                              Text('Call'),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      // Chat button
                      OutlinedButton(
                        onPressed: () => context.push(Routes.chat(request.id)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.brand,
                          side: BorderSide(
                            color: c.brand.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_rounded, size: 16),
                            SizedBox(width: 4),
                            Text('Chat'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: AppSpacing.md),
                // Privacy note
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: c.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Privacy rule: Only active coordination details and live transit are shared. Personal address & ID are never disclosed.',
                          style: context.text.bodySmall?.copyWith(
                            fontSize: 10,
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _haversineKm(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLng = _deg2rad(b.lng - a.lng);
    final lat1 = _deg2rad(a.lat);
    final lat2 = _deg2rad(b.lat);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2 * math.asin(math.sqrt(h));
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);
}

/// Journey step bar for:
/// Accepted → On the Way → Near Hospital → Reached → Donation Completed
class _JourneyStepper extends StatelessWidget {
  const _JourneyStepper({required this.currentStatus});
  final DonorTransitStatus currentStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currentIdx = currentStatus.stepIndex;
    final steps = DonorTransitStatus.values;

    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 3,
                    color: i <= currentIdx ? c.success : c.surfaceMuted,
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < currentIdx
                      ? c.success
                      : i == currentIdx
                      ? c.brand
                      : c.surfaceMuted,
                  border: Border.all(
                    color: i <= currentIdx ? Colors.white : c.border,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: i < currentIdx
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : Text(
                          '${i + 1}',
                          style: AppTypography.mono(
                            size: 10,
                            weight: FontWeight.w700,
                            color: i == currentIdx
                                ? Colors.white
                                : c.textTertiary,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Step labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final status in steps)
              SizedBox(
                width: 58,
                child: Text(
                  status.label,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    fontSize: 9,
                    fontWeight: status == currentStatus
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: status == currentStatus
                        ? c.brand
                        : status.stepIndex < currentIdx
                        ? c.success
                        : c.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
