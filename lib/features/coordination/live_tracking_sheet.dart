import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../data/models/models.dart';

class LiveTrackingSheet extends StatelessWidget {
  const LiveTrackingSheet({
    super.key,
    required this.request,
    required this.partnerName,
    this.partnerPhone,
    this.partnerPhoneCountryCode,
    this.partnerBloodGroup,
    this.partnerPhoto,
    required this.isDonor,
    required this.transitStatus,
    required this.distanceKm,
    required this.isSharingLocation,
    required this.onToggleSharing,
    required this.onUpdateTransitStatus,
  });

  final BloodRequest request;
  final String partnerName;
  final String? partnerPhone;
  final String? partnerPhoneCountryCode;
  final BloodGroup? partnerBloodGroup;
  final String? partnerPhoto;
  final bool isDonor;
  final DonorTransitStatus transitStatus;
  /// How far the donor is from the hospital. Null until the donor's
  /// position is known, so no distance or arrival time is made up.
  final double? distanceKm;
  final bool isSharingLocation;
  final VoidCallback onToggleSharing;
  final ValueChanged<DonorTransitStatus> onUpdateTransitStatus;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'D';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _callPartner(BuildContext context, String rawPhone) =>
      PhoneUtils.makePhoneCall(
        context,
        rawPhone,
        countryCode: partnerPhoneCountryCode,
      );

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
        const SnackBar(content: Text('Could not open maps for directions.')),
      );
    }
  }

  Widget _buildStepIndicator(BuildContext context) {
    final c = context.colors;
    final currentStep = transitStatus.stepIndex;
    final steps = DonorTransitStatus.values;

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                color: i <= currentStep ? c.brand : c.surfaceMuted,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < currentStep
                      ? c.success
                      : i == currentStep
                      ? c.brand
                      : c.surfaceMuted,
                  border: Border.all(
                    color: i <= currentStep ? Colors.white : c.border,
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (i == currentStep)
                      BoxShadow(
                        color: c.brand.withValues(alpha: 0.35),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Center(
                  child: i < currentStep
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : i == currentStep
                      ? const Icon(
                          Icons.directions_bike_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: c.textTertiary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[i].label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: i == currentStep
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: i == currentStep
                      ? c.brand
                      : i < currentStep
                      ? c.textPrimary
                      : c.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final km = distanceKm;
    final etaMinutes = km == null ? null : (km / 0.5).round().clamp(2, 180);
    final etaTime = etaMinutes == null
        ? null
        : DateFormat.jm().format(
            DateTime.now().add(Duration(minutes: etaMinutes)),
          );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.35 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.borderStrong.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Zepto/Blinkit Style ETA & Live Indicator Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              transitStatus ==
                                      DonorTransitStatus.donationCompleted
                                  ? 'Donation Completed'
                                  : transitStatus == DonorTransitStatus.reached
                                  ? 'Arrived at destination'
                                  : etaMinutes == null
                                  ? transitStatus.label
                                  : '$etaMinutes mins',
                              style: context.text.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          transitStatus == DonorTransitStatus.donationCompleted
                              ? 'Blood donation has been completed successfully'
                              : transitStatus == DonorTransitStatus.reached
                              ? 'Donor has reached the hospital location'
                              : km == null
                              ? "Waiting for the donor's location"
                              : '${km.toStringAsFixed(1)} km away • Arriving by $etaTime',
                          style: context.text.bodyMedium?.copyWith(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSharingLocation
                          ? c.successSubtle
                          : c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isSharingLocation
                            ? c.success.withValues(alpha: 0.35)
                            : c.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSharingLocation
                                ? c.success
                                : c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isSharingLocation ? 'LIVE TRACKING' : 'OFFLINE',
                          style: AppTypography.mono(
                            size: 10,
                            weight: FontWeight.w800,
                            color: isSharingLocation
                                ? c.success
                                : c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // 4-Step Status Progress Bar
              _buildStepIndicator(context),

              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // Partner Strip (Donor or Requester card)
              Row(
                children: [
                  Avatar(
                    initials: _initials(partnerName),
                    photo: partnerPhoto,
                    photoUrl: partnerPhoto,
                    size: 46,
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
                                partnerName,
                                style: context.text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (partnerBloodGroup != null) ...[
                              const SizedBox(width: 6),
                              BloodGroupBadge(partnerBloodGroup!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isDonor
                              ? 'Requester • Patient: ${request.patientName ?? "Needed"} (${request.bloodType})'
                              : 'Confirmed Donor • Donor Mode ON (${request.bloodType})',
                          style: context.text.bodySmall?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        if (partnerPhone != null &&
                            partnerPhone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                size: 12,
                                color: c.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                partnerPhone!,
                                style: AppTypography.mono(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Action Buttons Row: Call, Chat, Directions
              Row(
                children: [
                  if (partnerPhone != null && partnerPhone!.isNotEmpty) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.phone_rounded,
                          size: 18,
                          color: c.success,
                        ),
                        label: Text(
                          'Call',
                          style: TextStyle(
                            color: c.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: c.success.withValues(alpha: 0.35),
                          ),
                          backgroundColor: c.successSubtle,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        onPressed: () => _callPartner(context, partnerPhone!),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: c.brand,
                      ),
                      label: Text(
                        'Chat',
                        style: TextStyle(
                          color: c.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: c.brand.withValues(alpha: 0.35),
                        ),
                        backgroundColor: c.brandSubtle,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      onPressed: () => context.push(Routes.chat(request.id)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text(
                        'Directions',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      onPressed: () =>
                          _openDirections(context, request.destination),
                    ),
                  ),
                ],
              ),

              // Donor transit controls: location sharing and status
              if (isDonor) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.share_location_rounded,
                            size: 18,
                            color: c.brand,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Donor Transit & Location Controls',
                            style: context.text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isSharingLocation
                                  ? 'Sharing live location with requester'
                                  : 'Location sharing is paused',
                              style: context.text.bodySmall,
                            ),
                          ),
                          Switch(
                            value: isSharingLocation,
                            onChanged: (_) => onToggleSharing(),
                            activeThumbColor: c.brand,
                            activeTrackColor: c.brandSubtle,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Advance transit status buttons
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final status in DonorTransitStatus.values)
                            ChoiceChip(
                              label: Text(status.label),
                              selected: transitStatus == status,
                              onSelected: (_) => onUpdateTransitStatus(status),
                              selectedColor: c.brandSubtle,
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: transitStatus == status
                                    ? c.brand
                                    : c.textSecondary,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // Privacy Notice
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: c.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Live GPS sharing automatically ends when donation is completed or cancelled.',
                      style: context.text.bodySmall?.copyWith(
                        fontSize: 11,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
