import '../models/trip.dart';

/// Decoder for Google's encoded polyline format, which is what the backend
/// sends as `routePolyline` at precision 5.
///
/// Hand-rolled rather than pulled in as a package: it is one well-specified
/// loop, and the map is the only caller. The algorithm reads groups of 5 bits
/// per character, little-endian, where each value is a *delta* from the
/// previous point in units of 1e-5 degrees, zig-zag encoded so negatives pack
/// into unsigned values.
class Polyline {
  const Polyline._();

  /// Decode [encoded] into points, oldest first. Returns an empty list for a
  /// null, empty, or malformed string — a broken route line should cost the
  /// captain the overlay, not the whole navigation screen.
  static List<GeoPoint> decode(String? encoded, {int precision = 5}) {
    if (encoded == null || encoded.isEmpty) return const [];

    final factor = _pow10(precision);
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      final dLat = _nextDelta(encoded, index);
      if (dLat == null) return points;
      index = dLat.nextIndex;
      lat += dLat.value;

      final dLng = _nextDelta(encoded, index);
      if (dLng == null) return points;
      index = dLng.nextIndex;
      lng += dLng.value;

      points.add(GeoPoint(lat / factor, lng / factor));
    }

    return points;
  }

  /// Read one zig-zag-encoded varint starting at [start]. Null when the string
  /// ends mid-value, which means the payload is truncated.
  static _Delta? _nextDelta(String encoded, int start) {
    var index = start;
    var shift = 0;
    var result = 0;
    int chunk;

    do {
      if (index >= encoded.length) return null;
      chunk = encoded.codeUnitAt(index++) - 63;
      result |= (chunk & 0x1f) << shift;
      shift += 5;
    } while (chunk >= 0x20);

    // Low bit is the sign flag: odd values are negative.
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return _Delta(value, index);
  }

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}

class _Delta {
  final int value;
  final int nextIndex;
  const _Delta(this.value, this.nextIndex);
}
