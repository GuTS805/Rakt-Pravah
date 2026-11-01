import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/maps_links.dart';
import '../../data/models/models.dart';

/// Where the donation happens, with buttons that open Google Maps: driving
/// directions to the hospital and, while a donor shares it, the donor's live
/// position. See [MapsLinks] for why the app has no map of its own.
class MapPanel extends StatelessWidget {
  const MapPanel({
    super.key,
    required this.destination,
    this.trackedLocations = const [],
  });

  final Destination destination;

  /// Live positions of donors heading to the destination. The first one is
  /// shown.
  final List<GeoPoint> trackedLocations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final donor = trackedLocations.firstOrNull;
    final dest = destination.location;
    final km = donor != null && dest != null ? distanceKm(donor, dest) : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_hospital_rounded, color: c.brand, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.name, style: context.text.titleSmall),
                    if (destination.address.isNotEmpty)
                      Text(destination.address, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (donor != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.navigation_rounded, color: c.success, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    km == null
                        ? 'The donor is sharing their live location'
                        : 'The donor is ${km.toStringAsFixed(1)} km away',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    openInMaps(context, MapsLinks.directions(destination)),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Directions'),
              ),
              if (donor != null)
                OutlinedButton.icon(
                  onPressed: () => openInMaps(context, MapsLinks.place(donor)),
                  icon: const Icon(Icons.person_pin_circle_rounded, size: 18),
                  label: const Text('Donor on map'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
