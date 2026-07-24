import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../models/trip.dart';

/// A location fix plus the direction of travel. Driving mode needs the heading
/// to turn the map so the road ahead is always up; the plain [GeoPoint] the
/// overview map uses carries position only.
class GeoFix {
  final GeoPoint point;

  /// Degrees clockwise from true north, or null when the device is stationary
  /// (geolocator reports a meaningless heading below its speed threshold).
  final double? heading;

  /// Metres per second, as reported by the device.
  final double speed;

  const GeoFix(this.point, {this.heading, this.speed = 0});
}

/// Thin wrapper over `geolocator` that yields the captain's live location as a
/// stream of [GeoPoint]s. The map screen listens to this to move the car puck.
///
/// Permission and service-enabled checks are handled here so the UI just gets
/// positions (or nothing, if the captain declines). Everything is best-effort:
/// on a device with no GPS fix the stream simply stays quiet and the map falls
/// back to the trip's pickup point.
class LocationService {
  /// Ensures location permission is granted, requesting it if needed.
  /// Returns true when the app may read the device location.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// A one-shot best-effort current fix, or null if unavailable.
  static Future<GeoPoint?> current() async {
    if (!await ensurePermission()) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// A live stream of the captain's location. Emits a new point whenever the
  /// device moves ~5m. Completes silently if permission is refused.
  static Stream<GeoPoint> stream() async* {
    yield* fixStream().map((f) => f.point);
  }

  /// A live stream of position *and* heading. Driving mode listens to this so
  /// it can rotate the camera to the direction of travel; the overview map only
  /// needs [stream]. Emits every ~5m of movement.
  ///
  /// A stationary device reports a garbage heading, so below [_headingMinSpeed]
  /// the heading comes through as null and callers keep the last good bearing
  /// rather than spinning the map on GPS jitter at a red light.
  static Stream<GeoFix> fixStream() async* {
    if (!await ensurePermission()) return;
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map((p) => GeoFix(
          GeoPoint(p.latitude, p.longitude),
          heading: p.speed >= _headingMinSpeed ? p.heading : null,
          speed: p.speed,
        ));
  }

  /// Below ~1 m/s (a slow walk) the device heading is noise, not direction.
  static const double _headingMinSpeed = 1.0;

  static const double _earthRadiusMetres = 6371000;

  static double _rad(double deg) => deg * math.pi / 180;

  /// Great-circle distance between two points, in metres (haversine).
  static double distanceMetres(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * _earthRadiusMetres * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Initial bearing from [a] to [b], in degrees clockwise from north. Used to
  /// aim the camera down the route before the first moving GPS fix arrives.
  static double bearing(GeoPoint a, GeoPoint b) {
    final dLon = _rad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(_rad(b.latitude));
    final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
        math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
