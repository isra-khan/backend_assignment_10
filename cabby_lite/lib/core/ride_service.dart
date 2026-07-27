import 'package:dio/dio.dart';

import '../models/trip.dart';
import 'api_client.dart';

/// One reading of `/captain/active-ride` — the whole screen in a single object.
///
/// The tablet calls this on every boot and after every socket reconnect, and
/// rebuilds from it rather than trusting whatever the screen was showing. An
/// ignition cycle mid-ride, or two minutes without signal, both mean events
/// were missed; this is the recovery.
class ActiveRide {
  /// The live ride, or null when the captain is idle. `ride: null` with a 200
  /// is a normal answer, not an error — it means show the welcome screen.
  final Trip? trip;

  /// Where to draw the car on frame 1, before any socket event arrives.
  final GeoPoint? captainPosition;

  /// Whether the car's position comes from a hardware tracker or this tablet's
  /// own GPS. Decides whether `my-location` events are meaningful.
  final LocationSource locationSource;

  const ActiveRide({
    this.trip,
    this.captainPosition,
    this.locationSource = LocationSource.gps,
  });

  /// True when the captain has no live ride.
  bool get isIdle => trip == null;

  factory ActiveRide.fromJson(Map<String, dynamic> json) {
    final ride = json['ride'];
    return ActiveRide(
      // Matched as a bare Map, then copied: a decoded body gives
      // Map<String, dynamic>, but a literal (or a re-encoded fixture) can
      // arrive as Map<String, Object>, and the tighter check silently drops a
      // live ride on the floor.
      trip: ride is Map
          ? Trip.fromActiveRide(Map<String, dynamic>.from(ride))
          : null,
      captainPosition: GeoPoint.fromLatLng(json['captainPosition']),
      // Anything other than an explicit "tracker" means this tablet is the
      // location source. Defaulting the other way would make the app ignore
      // its own GPS while waiting for events that never come.
      locationSource: json['locationSource']?.toString() == 'tracker'
          ? LocationSource.tracker
          : LocationSource.gps,
    );
  }
}

/// Raised when the active-ride call fails in a way the caller can't act on.
/// A 401 is deliberately NOT one of these — see [RideService.activeRide].
class RideException implements Exception {
  final String message;
  const RideException(this.message);
  @override
  String toString() => message;
}

/// Raised when the device token has been revoked. The captain unlinked this
/// tablet from their phone, so the only correct response is to fall back to the
/// pairing screen. [ApiClient] has already wiped the stored token by the time
/// this is thrown.
class DeviceRevokedException implements Exception {
  const DeviceRevokedException();
  @override
  String toString() => 'This tablet was unlinked';
}

/// The tablet's one authenticated read. Everything else it learns arrives over
/// the socket.
class RideService {
  const RideService();

  /// `GET /captain/active-ride`, authenticated by the device token header that
  /// [ApiClient] attaches.
  ///
  /// Throws [DeviceRevokedException] on a 401 so the caller can unpair, and
  /// [RideException] on anything else it can't interpret.
  Future<ActiveRide> activeRide() async {
    try {
      final res = await ApiClient.instance.dio.get<dynamic>(
        '/captain/active-ride',
      );
      if (res.statusCode == 401) throw const DeviceRevokedException();

      final data = res.data;
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return ActiveRide.fromJson(data);
      }
      throw RideException(
        ApiClient.messageFrom(res, 'Could not load the current ride'),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const DeviceRevokedException();
      throw RideException(
        ApiClient.messageFrom(e.response, 'No connection to the server'),
      );
    }
  }
}
