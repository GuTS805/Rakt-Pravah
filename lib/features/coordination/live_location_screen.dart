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

/// Live tracking for a donation in progress.
/// Displays live donor transit, hospital destination, ETA, interactive
/// 4-step progress, call/chat actions, and two-way location sharing.
class LiveLocationScreen extends ConsumerStatefulWidget {
  const LiveLocationScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends ConsumerState<LiveLocationScreen> {
  // Often enough to follow someone driving across a city, and a third of
  // the database writes that every five seconds cost.
  static const _updateInterval = Duration(seconds: 15);

  bool _sharing = false;
  Timer? _locationTimer;

  /// The status this donor just tapped, shown until the request reflects it.
  /// Opening this screen does not by itself mean they have set off.
  DonorTransitStatus? _chosenStatus;

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
    if (_sharing) {
      ref.read(backendProvider).stopLiveLocation(widget.requestId);
    }
    super.dispose();
  }

  Future<void> _startSharing() async {
    // Shown as on straight away: a GPS fix can take ten seconds or more, and
    // "paused" meanwhile would say the opposite of what is happening.
    setState(() => _sharing = true);
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!mounted || !_sharing) return;

    if (!result.isGranted) {
      // In dev/web environments without hardware GPS permission, proceed with cached location
      debugPrint(
        'Device location permission not granted, proceeding with fallback.',
      );
    }

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
            isRequester: isRequester,
          );
    }
  }

  void _stopSharing() {
    _locationTimer?.cancel();
    ref.read(backendProvider).stopLiveLocation(widget.requestId);
    setState(() => _sharing = false);
  }

  void _toggleSharing() {
    if (_sharing) {
      _stopSharing();
    } else {
      _startSharing();
    }
  }

  void _updateTransitStatus(DonorTransitStatus next) {
    setState(() => _chosenStatus = next);
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
      // The page scrolls, so the bar is solid: content must not slide under
      // the status bar and the back button.
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
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

          final donorEntry = req.acceptedDonors
              .where((d) => d.id == donorId)
              .firstOrNull;
          final effectiveTransitStatus =
              (isDonor ? _chosenStatus : null) ??
              donorPing?.transitStatus ??
              donorEntry?.transitStatus ??
              DonorTransitStatus.accepted;

          // Only a real position: the last one shared, the one given when
          // accepting, or this phone's own. Never a made-up point.
          final effectiveDonorPoint =
              donorPing?.point ??
              firstDonor?.location ??
              (isDonor
                  ? (ref.watch(deviceLocationProvider).point ??
                        ref.watch(backendProvider).myLocation)
                  : null);

          final double? currentDistance =
              effectiveDonorPoint != null && req.destination.location != null
              ? _haversineKm(effectiveDonorPoint, req.destination.location!)
              : firstDonor?.distanceKm;

          final partnerName = isDonor
              ? req.requesterName
              : (firstDonor?.name ?? 'Assigned Donor');
          final partnerPhone = isDonor ? req.phone : firstDonor?.phone;
          final partnerPhoneCountryCode = isDonor
              ? req.phoneCountryCode
              : firstDonor?.phoneCountryCode;
          // Beside the partner's name: a donor's own group, never the
          // patient's next to the requester's name.
          final partnerBloodGroup = isDonor ? null : firstDonor?.bloodGroup;

          // The card on top and the sheet under it scroll as one page: laid
          // over each other, the sheet hid the card and its Maps buttons.
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Who is coming, and links to Google Maps
                LiveTrackingMap(
                  destination: req.destination,
                  donorLocation: effectiveDonorPoint,
                  donorName: isDonor ? me?.name : firstDonor?.name,
                  donorBloodGroup: isDonor
                      ? me?.bloodGroup
                      : firstDonor?.bloodGroup,
                  transitStatus: effectiveTransitStatus,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Status, the other person, and the donor's controls
                LiveTrackingSheet(
                  request: req,
                  patientName:
                      ref.watch(patientNameProvider(req.id)).valueOrNull ??
                      req.patientName,
                  partnerName: partnerName,
                  partnerPhone: partnerPhone,
                  partnerPhoneCountryCode: partnerPhoneCountryCode,
                  partnerBloodGroup: partnerBloodGroup,
                  partnerPhoto: isDonor
                      ? req.requesterPhoto
                      : firstDonor?.photoUrl,
                  isDonor: isDonor,
                  transitStatus: effectiveTransitStatus,
                  distanceKm: currentDistance,
                  isSharingLocation: _sharing,
                  onToggleSharing: _toggleSharing,
                  onUpdateTransitStatus: _updateTransitStatus,
                ),
              ],
            ),
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
