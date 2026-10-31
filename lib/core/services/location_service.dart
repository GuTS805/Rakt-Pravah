import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/models/models.dart';

/// Outcome of a real location request. Never fabricated — every value here
/// comes from the platform's actual location permission and GPS/network
/// position, not demo data.
sealed class LocationResult {
  const LocationResult();
}

class LocationGranted extends LocationResult {
  const LocationGranted(this.point, this.label);
  final GeoPoint point;

  /// Best-effort human label from reverse geocoding, e.g. "Dubai Marina,
  /// Dubai". Falls back to raw coordinates if geocoding is unavailable.
  final String label;
}

class LocationDenied extends LocationResult {
  const LocationDenied();
}

class LocationDeniedForever extends LocationResult {
  const LocationDeniedForever();
}

class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

/// Thin wrapper around `geolocator` (permission + GPS) and `geocoding`
/// (reverse address lookup). This is the single real seam for device location
/// in the app — every screen that shows "current location" goes through here
/// instead of hardcoding a place name.
class LocationService {
  Geocoding? _geocoding;
  bool _geocodingUnavailable = false;

  /// Lazily constructs the geocoding platform instance, and remembers if it's
  /// unavailable on this platform (e.g. Flutter Web, which the `geocoding`
  /// package doesn't implement) so we stop trying and fall back to
  /// coordinates instead of crashing the whole location flow. Constructing it
  /// eagerly as a field would throw synchronously on unsupported platforms
  /// before permission is ever requested — this is what broke location on web.
  Geocoding? get _geocodingOrNull {
    if (_geocodingUnavailable) return null;
    if (_geocoding != null) return _geocoding;
    try {
      return _geocoding = Geocoding();
    } catch (_) {
      _geocodingUnavailable = true;
      return null;
    }
  }

  /// Current permission status without prompting.
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  /// Requests permission (shows the OS system dialog) and, if granted, fetches
  /// the device's current position and reverse-geocodes it.
  Future<LocationResult> requestAndGetLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return const LocationServiceDisabled();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return const LocationDenied();
    if (permission == LocationPermission.deniedForever) {
      return const LocationDeniedForever();
    }

    return _fetchPosition();
  }

  /// Fetches the current position assuming permission is already granted.
  Future<LocationResult> getLocationIfPermitted() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) return const LocationDenied();
    if (permission == LocationPermission.deniedForever) {
      return const LocationDeniedForever();
    }
    return _fetchPosition();
  }

  /// How long address lookups may take. They go through the phone's Google
  /// geocoder, which can fail to answer at all (no network behind it, or a
  /// device without the service); without a limit the screen waits forever.
  static const _geocodeTimeout = Duration(seconds: 5);

  Future<LocationResult> _fetchPosition() async {
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      // No fresh GPS fix (indoors, cold start): use the last one the phone
      // has rather than waiting indefinitely.
      Position? last;
      try {
        last = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      if (last == null) return const LocationServiceDisabled();
      position = last;
    }
    final point = GeoPoint(position.latitude, position.longitude);
    final label = await _reverseGeocode(point);
    return LocationGranted(point, label);
  }

  Future<String> _reverseGeocode(GeoPoint point) async {
    final geocoding = _geocodingOrNull;
    if (geocoding == null) return _coordsLabel(point);
    try {
      final placemarks = await geocoding
          .placemarkFromCoordinates(point.lat, point.lng)
          .timeout(_geocodeTimeout);
      if (placemarks.isEmpty) return _coordsLabel(point);
      final p = placemarks.first;
      final parts = <String>[
        if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!,
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!,
        if ((p.administrativeArea ?? '').trim().isNotEmpty)
          p.administrativeArea!,
      ];
      return parts.isEmpty ? _coordsLabel(point) : parts.join(', ');
    } catch (_) {
      // Reverse geocoding needs platform services that may be unavailable
      // (e.g. some emulators); fall back to raw coordinates rather than lying
      // with a fake place name.
      return _coordsLabel(point);
    }
  }

  String _coordsLabel(GeoPoint point) =>
      '${point.lat.toStringAsFixed(4)}, ${point.lng.toStringAsFixed(4)}';

  /// Forward-geocodes a typed address into real coordinates, e.g. for the
  /// destination hospital entered during request creation. Returns null if
  /// the address can't be resolved rather than fabricating a position.
  Future<GeoPoint?> forwardGeocode(String address) async {
    final geocoding = _geocodingOrNull;
    if (geocoding == null) return null;
    try {
      final results = await geocoding
          .locationFromAddress(address)
          .timeout(_geocodeTimeout);
      if (results.isEmpty) return null;
      return GeoPoint(results.first.latitude, results.first.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
