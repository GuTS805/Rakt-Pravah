import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

/// A real interactive map (OpenStreetMap tiles via flutter_map — no API key
/// required, unlike Google Maps). Shows the destination pin and, when the
/// device's real location is known, the user's own position too.
///
/// This is genuine map data: panning/zooming loads real street tiles for the
/// actual coordinates, not a decorative placeholder.
class MapPanel extends StatelessWidget {
  const MapPanel({
    super.key,
    required this.destination,
    this.myLocation,
    this.height = 200,
    this.interactive = true,
  });

  final Destination destination;
  final GeoPoint? myLocation;
  final double height;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Fall back to a reasonable default center (Bengaluru) only when the
    // destination itself has no coordinates — the pin label still shows the
    // real destination name/address regardless.
    final destPoint = destination.location ??
        const GeoPoint(12.9716, 77.5946);
    final destLatLng = ll.LatLng(destPoint.lat, destPoint.lng);
    final myLatLng =
        myLocation == null ? null : ll.LatLng(myLocation!.lat, myLocation!.lng);

    final bounds = myLatLng == null
        ? null
        : LatLngBounds.fromPoints([destLatLng, myLatLng]);

    return ClipRRect(
      borderRadius: AppRadius.cardLg,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: AppRadius.cardLg,
        ),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: destLatLng,
                initialZoom: 14,
                initialCameraFit: bounds == null
                    ? null
                    : CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(48),
                      ),
                interactionOptions: InteractionOptions(
                  flags: interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bloodlink.bloodlink',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: destLatLng,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on_rounded,
                          color: c.brand, size: 36),
                    ),
                    if (myLatLng != null)
                      Marker(
                        point: myLatLng,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.info,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              right: AppSpacing.md,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_hospital_rounded,
                          size: 15, color: c.brand),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(destination.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleSmall),
                            Text(destination.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
