import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatar.dart';
import '../../data/models/models.dart';

const _defaultTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const _fallbackCenter = ll.LatLng(28.6139, 77.2090); // Delhi default

/// Full-featured, real-time live tracking map (Zepto/Blinkit style).
/// Displays the destination hospital, live donor position with smooth
/// movement interpolation, and a curved route polyline connecting them.
class LiveTrackingMap extends StatefulWidget {
  const LiveTrackingMap({
    super.key,
    required this.destination,
    this.donorLocation,
    this.requesterLocation,
    this.donorName,
    this.donorBloodGroup,
    this.transitStatus = DonorTransitStatus.onTheWay,
    this.height,
    this.onLocateMe,
  });

  final Destination destination;
  final GeoPoint? donorLocation;
  final GeoPoint? requesterLocation;
  final String? donorName;
  final BloodGroup? donorBloodGroup;
  final DonorTransitStatus transitStatus;
  final double? height;
  final Future<void> Function()? onLocateMe;

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap>
    with TickerProviderStateMixin {
  final _mapController = MapController();

  // Animation controller for smooth marker lerping
  late AnimationController _markerAnimController;
  ll.LatLng? _previousDonorLatLng;
  ll.LatLng? _targetDonorLatLng;
  ll.LatLng? _currentAnimatedDonorLatLng;

  // Pulse animation controller for marker halos
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    if (widget.donorLocation != null) {
      final initial = ll.LatLng(
        widget.donorLocation!.lat,
        widget.donorLocation!.lng,
      );
      _previousDonorLatLng = initial;
      _targetDonorLatLng = initial;
      _currentAnimatedDonorLatLng = initial;
    }

    _markerAnimController.addListener(() {
      if (_previousDonorLatLng != null && _targetDonorLatLng != null) {
        final t = _markerAnimController.value;
        final lat = _previousDonorLatLng!.latitude +
            (_targetDonorLatLng!.latitude - _previousDonorLatLng!.latitude) * t;
        final lng = _previousDonorLatLng!.longitude +
            (_targetDonorLatLng!.longitude - _previousDonorLatLng!.longitude) *
                t;
        setState(() {
          _currentAnimatedDonorLatLng = ll.LatLng(lat, lng);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant LiveTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.donorLocation != null) {
      final next = ll.LatLng(
        widget.donorLocation!.lat,
        widget.donorLocation!.lng,
      );
      if (_targetDonorLatLng == null) {
        _previousDonorLatLng = next;
        _targetDonorLatLng = next;
        _currentAnimatedDonorLatLng = next;
      } else if (next.latitude != _targetDonorLatLng!.latitude ||
          next.longitude != _targetDonorLatLng!.longitude) {
        _previousDonorLatLng = _currentAnimatedDonorLatLng ?? _targetDonorLatLng;
        _targetDonorLatLng = next;
        _markerAnimController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _markerAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Creates a realistic route curve connecting the donor and destination
  List<ll.LatLng> _generateRouteWaypoints(ll.LatLng start, ll.LatLng end) {
    final points = <ll.LatLng>[start];
    const steps = 12;

    // Slight lateral bow to simulate road turns
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;
    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;

    // Perpendicular offset vector
    final perpLat = -dLng * 0.15;
    final perpLng = dLat * 0.15;
    final controlPoint = ll.LatLng(midLat + perpLat, midLng + perpLng);

    for (int i = 1; i < steps; i++) {
      final t = i / steps;
      // Quadratic Bezier curve
      final lat = (1 - t) * (1 - t) * start.latitude +
          2 * (1 - t) * t * controlPoint.latitude +
          t * t * end.latitude;
      final lng = (1 - t) * (1 - t) * start.longitude +
          2 * (1 - t) * t * controlPoint.longitude +
          t * t * end.longitude;
      points.add(ll.LatLng(lat, lng));
    }

    points.add(end);
    return points;
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'D';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final destGeo = widget.destination.location;
    final destLatLng = destGeo != null
        ? ll.LatLng(destGeo.lat, destGeo.lng)
        : null;
    final donorLatLng = _currentAnimatedDonorLatLng;
    final reqGeo = widget.requesterLocation;
    final reqLatLng = reqGeo != null ? ll.LatLng(reqGeo.lat, reqGeo.lng) : null;

    final allPoints = <ll.LatLng>[
      ?destLatLng,
      ?donorLatLng,
      ?reqLatLng,
    ];

    final LatLngBounds? bounds = allPoints.length >= 2
        ? LatLngBounds.fromPoints(allPoints)
        : null;

    final initialCenter = donorLatLng ?? destLatLng ?? reqLatLng ?? _fallbackCenter;

    final routePoints = (donorLatLng != null && destLatLng != null)
        ? _generateRouteWaypoints(donorLatLng, destLatLng)
        : const <ll.LatLng>[];

    final content = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: donorLatLng != null && destLatLng != null ? 14 : 15,
        initialCameraFit: bounds == null
            ? null
            : CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.fromLTRB(48, 80, 48, 260),
              ),
      ),
      children: [
        TileLayer(
          urlTemplate: _defaultTileUrl,
          userAgentPackageName: 'com.raktpravah.app',
        ),

        // Route Polyline (Delivery-style glowing route)
        if (routePoints.isNotEmpty) ...[
          // Outer shadow polyline
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 7.0,
                color: Colors.black.withValues(alpha: 0.18),
              ),
              Polyline(
                points: routePoints,
                strokeWidth: 4.5,
                color: c.brand,
              ),
            ],
          ),
        ],

        // Markers Layer
        MarkerLayer(
          markers: [
            // 🩸 Hospital / Destination Marker
            if (destLatLng != null)
              Marker(
                point: destLatLng,
                width: 140,
                height: 90,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: c.danger, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🩸 ', style: TextStyle(fontSize: 10)),
                          Flexible(
                            child: Text(
                              widget.destination.name.isNotEmpty
                                  ? widget.destination.name
                                  : 'Hospital',
                              style: context.text.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 36 + (_pulseController.value * 6),
                          height: 36 + (_pulseController.value * 6),
                          decoration: BoxDecoration(
                            color: c.danger.withValues(
                              alpha: 0.22 - (_pulseController.value * 0.1),
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c.danger,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: c.danger.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_hospital_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

            // 🧑🦱 Live Donor Marker (Zepto/Blinkit Rider-style)
            if (donorLatLng != null)
              Marker(
                point: donorLatLng,
                width: 140,
                height: 94,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.brand,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.transitStatus == DonorTransitStatus.reached ||
                                    widget.transitStatus == DonorTransitStatus.donationCompleted
                                ? Icons.check_circle_rounded
                                : Icons.directions_bike_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.donorName != null
                                ? '${widget.donorName!.split(' ').first} (${widget.transitStatus.label})'
                                : widget.transitStatus.label,
                            style: AppTypography.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 42 + (_pulseController.value * 8),
                          height: 42 + (_pulseController.value * 8),
                          decoration: BoxDecoration(
                            color: c.success.withValues(
                              alpha: 0.28 - (_pulseController.value * 0.12),
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: c.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.success, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Avatar(
                                  initials: _initials(widget.donorName),
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

            // 📍 Requester Marker (when different from hospital destination)
            if (reqLatLng != null &&
                (destLatLng == null ||
                    (reqLatLng.latitude - destLatLng.latitude).abs() > 0.005 ||
                    (reqLatLng.longitude - destLatLng.longitude).abs() >
                        0.005))
              Marker(
                point: reqLatLng,
                width: 90,
                height: 60,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.info,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'Requester',
                        style: AppTypography.mono(
                          size: 9,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.person_pin_circle_rounded,
                        color: c.info, size: 28),
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    return ClipRRect(
      borderRadius: widget.height != null
          ? AppRadius.cardLg
          : BorderRadius.zero,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            content,
            // Recenter/Fit Camera button
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'fitCameraTag',
                    backgroundColor: c.surface,
                    foregroundColor: c.textPrimary,
                    tooltip: 'Fit Route',
                    onPressed: () {
                      if (bounds != null) {
                        _mapController.fitCamera(
                          CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.fromLTRB(48, 80, 48, 260),
                          ),
                        );
                      } else {
                        _mapController.move(initialCenter, 15);
                      }
                    },
                    child: const Icon(Icons.center_focus_strong_rounded),
                  ),
                  if (widget.onLocateMe != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FloatingActionButton.small(
                      heroTag: 'locateMeTag',
                      backgroundColor: c.surface,
                      foregroundColor: c.brand,
                      tooltip: 'My Location',
                      onPressed: () => widget.onLocateMe!(),
                      child: const Icon(Icons.my_location_rounded),
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
