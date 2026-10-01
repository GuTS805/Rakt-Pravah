import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'live_tracking_map.dart';
import 'live_tracking_sheet.dart';

/// Full-screen real-time delivery-style tracking screen (Zepto/Blinkit style).
/// Displays live donor transit, hospital destination, ETA, interactive
/// 4-step progress, call/chat actions, and two-way location sharing.
class LiveLocationScreen extends ConsumerStatefulWidget {
  const LiveLocationScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends ConsumerState<LiveLocationScreen> {
  static const _updateInterval = Duration(seconds: 5);

  bool _sharing = false;
  bool _simulating = false;
  Timer? _locationTimer;
  Timer? _simulationTimer;

  DonorTransitStatus _transitStatus = DonorTransitStatus.onTheWay;
  GeoPoint? _simulatedDonorPoint;
  double _simProgress = 0.0;

  @override
  void initState() {
    super.initState();
    // Start the Donor <-> Requester live-location session after acceptance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final req = ref.read(requestProvider(widget.requestId)).valueOrNull;
      final me = ref.read(currentUserProvider);
      final isDonor = req?.acceptedDonorIds.contains(me?.id) ?? false;
      final isRequester = req?.requesterId == me?.id;
      if (req != null && req.status.isActive && (isDonor || isRequester)) {
        _startSharing();
      }
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _simulationTimer?.cancel();
    if (_sharing) {
      ref.read(backendProvider).stopLiveLocation(widget.requestId);
    }
    super.dispose();
  }

  Future<void> _startSharing() async {
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!mounted) return;

    if (!result.isGranted) {
      // In dev/web environments without hardware GPS permission, proceed with cached location
      debugPrint(
        'Device location permission not granted, proceeding with fallback.',
      );
    }

    setState(() => _sharing = true);

    // Initial push
    await _pushCurrentLocation();

    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      _updateInterval,
      (_) => _pushCurrentLocation(),
    );
  }

  Future<void> _pushCurrentLocation() async {
    if (!_sharing || !mounted) return;

    final req = ref.read(requestProvider(widget.requestId)).valueOrNull;
    final me = ref.read(currentUserProvider);
    final isRequester = req?.requesterId == me?.id;

    final locResult = await ref
        .read(locationServiceProvider)
        .getLocationIfPermitted();
    GeoPoint? point;

    if (locResult is LocationGranted) {
      point = locResult.point;
    } else {
      point =
          ref.read(deviceLocationProvider).point ??
          ref.read(backendProvider).myLocation;
    }

    if (point != null && mounted) {
      await ref
          .read(backendProvider)
          .updateLiveLocation(
            widget.requestId,
            point,
            transitStatus: _transitStatus,
            isRequester: isRequester,
          );
    }
  }

  void _stopSharing() {
    _locationTimer?.cancel();
    _simulationTimer?.cancel();
    ref.read(backendProvider).stopLiveLocation(widget.requestId);
    setState(() {
      _sharing = false;
      _simulating = false;
    });
  }

  void _toggleSharing() {
    if (_sharing) {
      _stopSharing();
    } else {
      _startSharing();
    }
  }

  void _toggleSimulation() {
    if (_simulating) {
      _simulationTimer?.cancel();
      setState(() => _simulating = false);
      return;
    }

    setState(() {
      _simulating = true;
      _sharing = true;
      _simProgress = 0.0;
    });

    final req = ref.read(requestProvider(widget.requestId)).valueOrNull;
    final dest = req?.destination.location ?? const GeoPoint(28.6139, 77.2090);

    // Start simulated point ~4 km away from hospital
    const startOffsetLat = 0.028;
    const startOffsetLng = -0.025;
    final startLat = dest.lat + startOffsetLat;
    final startLng = dest.lng + startOffsetLng;

    _simulatedDonorPoint = GeoPoint(startLat, startLng);

    // Push initial simulated point
    ref
        .read(backendProvider)
        .updateLiveLocation(
          widget.requestId,
          _simulatedDonorPoint!,
          transitStatus: DonorTransitStatus.onTheWay,
        );

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _simProgress += 0.12;
        if (_simProgress >= 1.0) {
          _simProgress = 1.0;
          _transitStatus = DonorTransitStatus.reached;
          _simulatedDonorPoint = dest;
          timer.cancel();
          _simulating = false;
        } else {
          final curLat = startLat + (dest.lat - startLat) * _simProgress;
          final curLng = startLng + (dest.lng - startLng) * _simProgress;
          _simulatedDonorPoint = GeoPoint(curLat, curLng);

          if (_simProgress > 0.75) {
            _transitStatus = DonorTransitStatus.nearHospital;
          } else if (_simProgress > 0.1) {
            _transitStatus = DonorTransitStatus.onTheWay;
          }
        }
      });

      ref
          .read(backendProvider)
          .updateLiveLocation(
            widget.requestId,
            _simulatedDonorPoint!,
            transitStatus: _transitStatus,
          );
    });
  }

  void _updateTransitStatus(DonorTransitStatus next) {
    setState(() => _transitStatus = next);
    ref.read(backendProvider).updateDonorTransitStatus(widget.requestId, next);
  }

  double _haversineKm(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * (math.pi / 180.0);
    final dLng = (b.lng - a.lng) * (math.pi / 180.0);
    final lat1 = a.lat * (math.pi / 180.0);
    final lat2 = b.lat * (math.pi / 180.0);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2 * math.asin(math.sqrt(h));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final asyncReq = ref.watch(requestProvider(widget.requestId));
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: c.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Live Donation Tracking',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: asyncReq.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorStateView(
          message: 'Unable to load live location session.',
          onRetry: () => ref.invalidate(requestProvider(widget.requestId)),
        ),
        data: (req) {
          if (req.status.isTerminal) {
            if (_sharing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _stopSharing();
              });
            }
            return _buildClosedSessionView(context, req);
          }
          final isDonor = req.acceptedDonorIds.contains(me?.id);
          final firstDonor = req.acceptedDonors.firstOrNull;
          final donorId = isDonor ? me?.id : firstDonor?.id;
          final donorPing = donorId != null
              ? req.donorLiveLocations[donorId]
              : null;

          final effectiveTransitStatus =
              donorPing?.transitStatus ?? _transitStatus;

          final effectiveDonorPoint =
              _simulatedDonorPoint ??
              donorPing?.point ??
              firstDonor?.location ??
              (isDonor
                  ? (ref.watch(deviceLocationProvider).point ??
                        ref.watch(backendProvider).myLocation)
                  : null) ??
              (req.destination.location != null
                  ? GeoPoint(
                      req.destination.location!.lat + 0.02,
                      req.destination.location!.lng - 0.02,
                    )
                  : null);

          final effectiveRequesterPoint =
              req.requesterLiveLocation?.point ??
              (isDonor ? null : ref.watch(deviceLocationProvider).point);

          final double currentDistance;
          if (effectiveDonorPoint != null && req.destination.location != null) {
            currentDistance = _haversineKm(
              effectiveDonorPoint,
              req.destination.location!,
            );
          } else {
            currentDistance = firstDonor?.distanceKm ?? 2.4;
          }

          final partnerName = isDonor
              ? req.requesterName
              : (firstDonor?.name ?? 'Assigned Donor');
          final partnerPhone = isDonor ? req.phone : firstDonor?.phone;
          final partnerBloodGroup = isDonor
              ? req.patientBloodGroup
              : firstDonor?.bloodGroup;

          return Stack(
            children: [
              // Full-screen Map
              Positioned.fill(
                child: LiveTrackingMap(
                  destination: req.destination,
                  donorLocation: effectiveDonorPoint,
                  requesterLocation: effectiveRequesterPoint,
                  donorName: isDonor ? me?.name : firstDonor?.name,
                  donorBloodGroup: isDonor
                      ? me?.bloodGroup
                      : firstDonor?.bloodGroup,
                  transitStatus: effectiveTransitStatus,
                  onLocateMe: () async {
                    await ref.read(deviceLocationProvider.notifier).request();
                  },
                ),
              ),

              // Bottom Tracking Card (Zepto/Blinkit style)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LiveTrackingSheet(
                  request: req,
                  partnerName: partnerName,
                  partnerPhone: partnerPhone,
                  partnerBloodGroup: partnerBloodGroup,
                  partnerPhoto: isDonor ? req.requesterPhoto : firstDonor?.photoUrl,
                  isDonor: isDonor,
                  transitStatus: effectiveTransitStatus,
                  distanceKm: currentDistance,
                  isSharingLocation: _sharing,
                  isSimulating: _simulating,
                  onToggleSharing: _toggleSharing,
                  onToggleSimulation: _toggleSimulation,
                  onUpdateTransitStatus: _updateTransitStatus,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClosedSessionView(BuildContext context, BloodRequest req) {
    final c = context.colors;
    final isFulfilled = req.status == RequestStatus.fulfilled;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isFulfilled ? c.successSubtle : c.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFulfilled
                    ? Icons.volunteer_activism_rounded
                    : Icons.lock_outline_rounded,
                size: 48,
                color: isFulfilled ? c.success : c.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isFulfilled ? 'Donation Completed' : 'Session Closed',
              style: context.text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isFulfilled
                  ? 'The blood donation was completed successfully. Live-location sharing has stopped to protect donor and requester privacy.'
                  : 'This request was ${req.status.label.toLowerCase()}. Active tracking and live-location sharing have been terminated.',
              style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
