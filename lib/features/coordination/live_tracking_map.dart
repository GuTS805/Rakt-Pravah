import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/maps_links.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../data/models/models.dart';

/// The top of the live tracking screen: who is coming, how far they are from
/// the hospital, and buttons that open their live position and the route in
/// Google Maps. See [MapsLinks] for why the app has no map of its own.
class LiveTrackingMap extends StatelessWidget {
  const LiveTrackingMap({
    super.key,
    required this.destination,
    this.donorLocation,
    this.donorName,
    this.donorBloodGroup,
    this.transitStatus = DonorTransitStatus.onTheWay,
  });

  final Destination destination;
  final GeoPoint? donorLocation;
  final String? donorName;
  final BloodGroup? donorBloodGroup;
  final DonorTransitStatus transitStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final donor = donorLocation;
    final dest = destination.location;
    final km = donor != null && dest != null ? distanceKm(donor, dest) : null;
    final name = donorName ?? 'Donor';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.brandSubtle, c.background],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.cardLg,
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(initials: _initials(name), size: 44),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: context.text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              transitStatus.label,
                              style: context.text.bodySmall?.copyWith(
                                color: c.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (donorBloodGroup != null)
                        BloodGroupBadge(donorBloodGroup!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Icon(
                        Icons.local_hospital_rounded,
                        size: 18,
                        color: c.brand,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          destination.name,
                          style: context.text.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    km != null
                        ? '${km.toStringAsFixed(1)} km from the hospital'
                        : donor == null
                        ? 'Waiting for the donor’s location'
                        : 'On the way to the hospital',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (donor != null)
                        FilledButton.icon(
                          onPressed: () =>
                              openInMaps(context, MapsLinks.place(donor)),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.brand,
                          ),
                          icon: const Icon(
                            Icons.person_pin_circle_rounded,
                            size: 18,
                          ),
                          label: const Text('Donor on map'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => openInMaps(
                          context,
                          MapsLinks.directions(destination),
                        ),
                        icon: const Icon(
                          Icons.local_hospital_rounded,
                          size: 18,
                        ),
                        label: const Text('Hospital route'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'D';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
