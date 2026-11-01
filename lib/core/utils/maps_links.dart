import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/models.dart';

/// Links that open Google Maps (the app if installed, otherwise the
/// website). The app shows no map of its own: the free OpenStreetMap tile
/// server doesn't allow use by published apps, and Google Maps gives
/// directions and traffic besides.
abstract final class MapsLinks {
  /// Driving directions to [dest], by its coordinates when known.
  static Uri directions(Destination dest) {
    final loc = dest.location;
    final to = loc != null
        ? '${loc.lat},${loc.lng}'
        : Uri.encodeComponent('${dest.name}, ${dest.address}');
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$to&travelmode=driving',
    );
  }

  /// A pin at [point].
  static Uri place(GeoPoint point) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${point.lat},${point.lng}',
  );
}

/// Opens [uri] in Google Maps, or says it couldn't.
Future<void> openInMaps(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await openMapsLink(uri);
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open Google Maps.")),
    );
  }
}

/// Replaceable in tests, which have no Maps app.
@visibleForTesting
Future<bool> Function(Uri uri) openMapsLink = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Straight-line distance between two points, in km.
double distanceKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}
