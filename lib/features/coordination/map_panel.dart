import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

const _defaultTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

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
    this.trackedLocations = const [],
    this.height = 260,
    this.interactive = true,
    this.enlargeable = true,
    this.onLocateMe,
  });

  final Destination destination;

  /// The viewer's own position, shown as a plain marker (e.g. confirming
  /// what you're about to share).
  final GeoPoint? myLocation;

  /// Positions to actively follow as they update — the live locations of
  /// donors heading to the destination (spec: "zoom into the donor location
  /// who is heading to the requester location"). Rendered as pulsing markers
  /// to read as "in motion"; the camera follows the first.
  final List<GeoPoint> trackedLocations;

  final double height;
  final bool interactive;

  /// Shows a corner button that opens the same map full-screen.
  final bool enlargeable;

  /// Fetches a fresh device position (asking for permission if needed) for
  /// the "my location" button. Without it the button isn't shown.
  final Future<GeoPoint?> Function()? onLocateMe;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

/// Centre of India, used only when there's no point at all to show.
const _fallbackCenter = ll.LatLng(22.9734, 78.6569);

ll.LatLng? _toLatLng(GeoPoint? p) => p == null ? null : ll.LatLng(p.lat, p.lng);

/// Moves [controller] to the device position from [onLocateMe], or explains
/// why it can't.
Future<GeoPoint?> _locate(
  BuildContext context,
  MapController controller,
  Future<GeoPoint?> Function() onLocateMe,
) async {
  final point = await onLocateMe();
  if (!context.mounted) return point;
  if (point == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Turn on location access to see where you are.'),
      ),
    );
    return null;
  }
  try {
    controller.move(ll.LatLng(point.lat, point.lng), 16);
  } catch (_) {
    // Map not laid out yet; the marker still appears on the next build.
  }
  return point;
}

class _MapPanelState extends State<MapPanel> {
  final _controller = MapController();
  GeoPoint? _lastTracked;
  GeoPoint? _located;
  bool _locating = false;

  Future<void> _locateMe() async {
    setState(() => _locating = true);
    final point = await _locate(context, _controller, widget.onLocateMe!);
    if (mounted) {
      setState(() {
        _locating = false;
        _located = point ?? _located;
      });
    }
  }

  @override
  void didUpdateWidget(covariant MapPanel old) {
    super.didUpdateWidget(old);
    final tracked = widget.trackedLocations.firstOrNull;
    if (tracked != null &&
        (tracked.lat != _lastTracked?.lat ||
            tracked.lng != _lastTracked?.lng)) {
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
    final destLatLng = _toLatLng(widget.destination.location);
    final myLatLng = _toLatLng(_located ?? widget.myLocation);
    final trackedLatLngs = [
      for (final p in widget.trackedLocations) ll.LatLng(p.lat, p.lng),
    ];

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
              trackedLatLngs: trackedLatLngs,
              interactive: widget.interactive,
              destination: widget.destination,
              tileUrl: _defaultTileUrl,
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              right: widget.enlargeable ? 56 : AppSpacing.md,
              child: IgnorePointer(
                child: _DestinationChip(destination: widget.destination),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Column(
                children: [
                  if (widget.enlargeable)
                    _RoundIconButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Enlarge map',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => _FullscreenMap(
                            destination: widget.destination,
                            myLocation: _located ?? widget.myLocation,
                            trackedLocations: widget.trackedLocations,
                            onLocateMe: widget.onLocateMe,
                          ),
                        ),
                      ),
                    ),
                  if (widget.onLocateMe != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _RoundIconButton(
                      icon: _locating
                          ? Icons.hourglass_top_rounded
                          : Icons.my_location_rounded,
                      tooltip: 'My location',
                      onTap: _locating ? () {} : _locateMe,
                    ),
                  ],
                ],
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
    required this.trackedLatLngs,
    required this.interactive,
    required this.destination,
    required this.tileUrl,
  }) : initialZoom = 14;

  final MapController controller;

  /// Null when the hospital address couldn't be placed on the map. No pin is
  /// drawn then, rather than one in a made-up spot.
  final ll.LatLng? destLatLng;
  final ll.LatLng? myLatLng;
  final List<ll.LatLng> trackedLatLngs;
  final bool interactive;
  final Destination destination;
  final String tileUrl;
  final double initialZoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Prefer centering on whoever is actively heading over; otherwise fit
    // the destination and the viewer's own point if they're actually close
    // together (a bad geocode landing far away shouldn't zoom the map out to
    // a whole-region view — better to just show the destination clearly).
    final dest = destLatLng;
    final tracked = trackedLatLngs.firstOrNull;
    final anchor = tracked ?? dest ?? myLatLng ?? _fallbackCenter;
    final hasAnyPoint = tracked != null || dest != null || myLatLng != null;
    final farApart =
        dest != null &&
        myLatLng != null &&
        tracked == null &&
        ((dest.latitude - myLatLng!.latitude).abs() > 1.5 ||
            (dest.longitude - myLatLng!.longitude).abs() > 1.5);
    final bounds =
        (dest == null || myLatLng == null || farApart || tracked != null)
        ? null
        : LatLngBounds.fromPoints([dest, myLatLng!]);

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: anchor,
        initialZoom: !hasAnyPoint
            ? 4
            : tracked != null
            ? 16
            : initialZoom,
        initialCameraFit: bounds == null
            ? null
            : CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(48),
              ),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.bloodlink.bloodlink',
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: [
            if (dest != null)
              Marker(
                point: dest,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on_rounded,
                  color: c.brand,
                  size: 36,
                ),
              ),
            if (myLatLng != null)
              Marker(
                point: myLatLng!,
                width: 22,
                height: 22,
                child: _Dot(color: c.info),
              ),
            for (final point in trackedLatLngs)
              Marker(
                point: point,
                width: 26,
                height: 26,
                child: _PulsingDot(color: c.success),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
          alignment: Alignment.topLeft,
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
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

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
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                  ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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
                Text(
                  destination.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                Text(
                  destination.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
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
    this.trackedLocations = const [],
    this.onLocateMe,
  });

  final Destination destination;
  final GeoPoint? myLocation;
  final List<GeoPoint> trackedLocations;
  final Future<GeoPoint?> Function()? onLocateMe;

  @override
  State<_FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<_FullscreenMap> {
  final _controller = MapController();
  GeoPoint? _located;

  @override
  Widget build(BuildContext context) {
    final myLatLng = _toLatLng(_located ?? widget.myLocation);
    final trackedLatLngs = [
      for (final p in widget.trackedLocations) ll.LatLng(p.lat, p.lng),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(widget.destination.name)),
      floatingActionButton: widget.onLocateMe == null
          ? null
          : FloatingActionButton.small(
              tooltip: 'My location',
              onPressed: () async {
                final point = await _locate(
                  context,
                  _controller,
                  widget.onLocateMe!,
                );
                if (point != null && mounted) {
                  setState(() => _located = point);
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
      body: _MapView(
        controller: _controller,
        destLatLng: _toLatLng(widget.destination.location),
        myLatLng: myLatLng,
        trackedLatLngs: trackedLatLngs,
        interactive: true,
        destination: widget.destination,
        tileUrl: _defaultTileUrl,
      ),
    );
  }
}
