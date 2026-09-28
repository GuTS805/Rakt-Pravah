import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/models.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'avatar.dart';
import 'badges.dart';

class DonorRankingCard extends StatelessWidget {
  const DonorRankingCard({
    super.key,
    required this.donor,
    this.destination,
    this.isAccepted = false,
    this.onTrackLive,
  });

  final MatchedDonor donor;
  final Destination? destination;
  final bool isAccepted;
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

  Future<void> _openDirections(BuildContext context) async {
    final loc = donor.location ?? destination?.location;
    final Uri uri;
    if (loc != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${loc.lat},${loc.lng}&travelmode=driving',
      );
    } else if (destination != null) {
      final query = Uri.encodeComponent(
        '${destination!.name}, ${destination!.address}',
      );
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$query&travelmode=driving',
      );
    } else {
      uri = Uri.parse('https://www.google.com/maps');
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open map directions.')),
      );
    }
  }

  Widget _buildStatusBadge(BuildContext context) {
    final c = context.colors;
    final (label, Color bg, Color fg, IconData icon) = switch (donor.status) {
      DonorRequestInteractionStatus.accepted => (
        'Accepted',
        c.successSubtle,
        c.success,
        Icons.check_circle_rounded,
      ),
      DonorRequestInteractionStatus.viewed => (
        'Viewed',
        c.brandSubtle,
        c.brand,
        Icons.visibility_rounded,
      ),
      DonorRequestInteractionStatus.notified => (
        'Notified',
        context.isDark
            ? const Color(0xFF3E2723)
            : const Color(0xFFFFF3E0),
        const Color(0xFFE65100),
        Icons.notifications_active_rounded,
      ),
      DonorRequestInteractionStatus.declined => (
        'Declined',
        c.surfaceMuted,
        c.textTertiary,
        Icons.cancel_outlined,
      ),
      DonorRequestInteractionStatus.expired => (
        'Expired',
        c.surfaceMuted,
        c.textTertiary,
        Icons.timer_off_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.mono(
              size: 11,
              weight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final travelMins = donor.estimatedTravelMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(
          color: isAccepted
              ? c.success.withValues(alpha: 0.45)
              : c.border,
          width: isAccepted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.22 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(initials: _initials(donor.name), size: 42),
              const SizedBox(width: AppSpacing.sm),
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
                        BloodGroupBadge(donor.bloodGroup),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
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
                              ? 'Donor Mode ON'
                              : 'Donor Mode OFF',
                          style: context.text.bodySmall?.copyWith(
                            fontSize: 11,
                            color: donor.isDonorModeOn
                                ? c.success
                                : c.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(context),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              // Distance indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.near_me_rounded,
                      size: 14,
                      color: c.brand,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${donor.distanceKm.toStringAsFixed(1)} km away',
                      style: AppTypography.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Travel time indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_car_outlined,
                      size: 14,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '~$travelMins min travel',
                      style: context.text.bodySmall?.copyWith(
                        fontSize: 11,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Privacy / Action controls
              if (onTrackLive != null) ...[
                IconButton(
                  tooltip: 'Live Track Donor',
                  icon: Icon(Icons.delivery_dining_rounded,
                      size: 20, color: c.brand),
                  style: IconButton.styleFrom(
                    backgroundColor: c.brandSubtle,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(34, 34),
                  ),
                  onPressed: onTrackLive,
                ),
                const SizedBox(width: 6),
              ],
              if (donor.phone != null && donor.phone!.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Call Donor',
                  icon: Icon(Icons.phone_rounded, size: 20, color: c.success),
                  style: IconButton.styleFrom(
                    backgroundColor: c.successSubtle,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(34, 34),
                  ),
                  onPressed: () => _makePhoneCall(context, donor.phone!),
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                tooltip: 'View Directions',
                icon: Icon(Icons.directions_rounded, size: 20, color: c.brand),
                style: IconButton.styleFrom(
                  backgroundColor: c.brandSubtle,
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(34, 34),
                ),
                onPressed: () => _openDirections(context),
              ),
            ],
          ),
          if (!isAccepted) ...[
            const SizedBox(height: 6),
            Text(
              'Approx. neighborhood distance • Exact location shared on acceptance',
              style: context.text.bodySmall?.copyWith(
                fontSize: 10,
                color: c.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
