import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

/// A real interactive map (OpenStreetMap tiles via flutter_map — no API key
/// required, unlike Google Maps). Shows the destination pin and, when known,
/// the user's own position and/or the donor's live position.
///
/// This is genuine map data: panning/zooming loads real street tiles for the
/// actual coordinates, not a decorative placeholder.
class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    required this.destination,
    this.myLocation,
    this.trackedLocation,
    this.height = 260,
    this.interactive = true,
    this.enlargeable = true,
  });

  final Destination destination;

  /// The viewer's own position, shown as a plain marker (e.g. confirming
  /// what you're about to share).
  final GeoPoint? myLocation;

  /// A position to actively follow with the camera as it updates — the
  /// donor's live location while they're heading to the destination (spec:
  /// "zoom into the donor location who is heading to the requester
  /// location"). Rendered as a pulsing marker to read as "in motion."
  final GeoPoint? trackedLocation;

  final double height;
  final bool interactive;

  /// Shows a corner button that opens the same map full-screen.
  final bool enlargeable;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  final _controller = MapController();
  GeoPoint? _lastTracked;

  @override
  void didUpdateWidget(covariant MapPanel old) {
    super.didUpdateWidget(old);
    final tracked = widget.trackedLocation;
    if (tracked != null &&
        (tracked.lat != _lastTracked?.lat || tracked.lng != _lastTracked?.lng)) {
      _lastTracked = tracked;
      // A live position update takes priority over whatever the viewer was
      // looking at — that's the point of tracking someone heading your way.
      try {
        _controller.move(ll.LatLng(tracked.lat, tracked.lng), 16);
      } catch (_) {
        // Controller not attached yet (e.g. first frame); the initial
        // camera already accounts for trackedLocation, so this is safe to
        // ignore.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final destPoint = widget.destination.location ?? const GeoPoint(12.9716, 77.5946);
    final destLatLng = ll.LatLng(destPoint.lat, destPoint.lng);
    final myLatLng = widget.myLocation == null
        ? null
        : ll.LatLng(widget.myLocation!.lat, widget.myLocation!.lng);
    final trackedLatLng = widget.trackedLocation == null
        ? null
        : ll.LatLng(widget.trackedLocation!.lat, widget.trackedLocation!.lng);

    return ClipRRect(
      borderRadius: AppRadius.cardLg,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: AppRadius.cardLg,
        ),
        child: Stack(
          children: [
            _MapView(
              controller: _controller,
              destLatLng: destLatLng,
              myLatLng: myLatLng,
              trackedLatLng: trackedLatLng,
              interactive: widget.interactive,
              destination: widget.destination,
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              right: widget.enlargeable ? 56 : AppSpacing.md,
              child: IgnorePointer(
                child: _DestinationChip(destination: widget.destination),
              ),
            ),
            if (widget.enlargeable)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: _RoundIconButton(
                  icon: Icons.open_in_full_rounded,
                  tooltip: 'Enlarge map',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => _FullscreenMap(
                        destination: widget.destination,
                        myLocation: widget.myLocation,
                        trackedLocation: widget.trackedLocation,
                      ),
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

class _MapView extends StatelessWidget {
  const _MapView({
    required this.controller,
    required this.destLatLng,
    required this.myLatLng,
    required this.trackedLatLng,
    required this.interactive,
    required this.destination,
    this.initialZoom = 14,
  });

  final MapController controller;
  final ll.LatLng destLatLng;
  final ll.LatLng? myLatLng;
  final ll.LatLng? trackedLatLng;
  final bool interactive;
  final Destination destination;
  final double initialZoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Prefer centering on whoever is actively heading over; otherwise fit
    // the destination and the viewer's own point if they're actually close
    // together (a bad geocode landing far away shouldn't zoom the map out to
    // a whole-region view — better to just show the destination clearly).
    final anchor = trackedLatLng ?? destLatLng;
    final farApart = myLatLng != null &&
        trackedLatLng == null &&
        ((destLatLng.latitude - myLatLng!.latitude).abs() > 1.5 ||
            (destLatLng.longitude - myLatLng!.longitude).abs() > 1.5);
    final bounds = (myLatLng == null || farApart || trackedLatLng != null)
        ? null
        : LatLngBounds.fromPoints([destLatLng, myLatLng!]);

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: anchor,
        initialZoom: trackedLatLng != null ? 16 : initialZoom,
        initialCameraFit: bounds == null
            ? null
            : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
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
              child: Icon(Icons.location_on_rounded, color: c.brand, size: 36),
            ),
            if (myLatLng != null)
              Marker(
                point: myLatLng!,
                width: 22,
                height: 22,
                child: _Dot(color: c.info),
              ),
            if (trackedLatLng != null)
              Marker(
                point: trackedLatLng!,
                width: 26,
                height: 26,
                child: _PulsingDot(color: c.success),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
          ],
        ),
      );
}

/// A gently pulsing marker — the visual cue that this point is live and
/// moving, distinct from a fixed pin or a static "my location" dot.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 12 + t * 16,
              width: 12 + t * 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: (1 - t) * 0.4),
              ),
            ),
            Container(
              height: 14,
              width: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({required this.destination});
  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_hospital_rounded, size: 15, color: c.brand),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(destination.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                Text(destination.address,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Material(
      color: c.surface.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, size: 18, color: c.textPrimary),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Full-screen version of the same map, reached via the enlarge button —
/// same live tracking behavior, just with room to actually read it.
class _FullscreenMap extends StatefulWidget {
  const _FullscreenMap({
    required this.destination,
    this.myLocation,
    this.trackedLocation,
  });

  final Destination destination;
  final GeoPoint? myLocation;
  final GeoPoint? trackedLocation;

  @override
  State<_FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<_FullscreenMap> {
  final _controller = MapController();

  @override
  Widget build(BuildContext context) {
    final destPoint = widget.destination.location ?? const GeoPoint(12.9716, 77.5946);
    final myLatLng =
        widget.myLocation == null ? null : ll.LatLng(widget.myLocation!.lat, widget.myLocation!.lng);
    final trackedLatLng = widget.trackedLocation == null
        ? null
        : ll.LatLng(widget.trackedLocation!.lat, widget.trackedLocation!.lng);

    return Scaffold(
      appBar: AppBar(title: Text(widget.destination.name)),
      body: _MapView(
        controller: _controller,
        destLatLng: ll.LatLng(destPoint.lat, destPoint.lng),
        myLatLng: myLatLng,
        trackedLatLng: trackedLatLng,
        interactive: true,
        destination: widget.destination,
      ),
    );
  }
}
