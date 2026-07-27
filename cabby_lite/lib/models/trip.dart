/// A plain latitude/longitude pair. Kept map-SDK-agnostic so the trip model
/// doesn't depend on Mapbox (or any) map package — the map screen adapts this
/// to whatever the renderer needs.
class GeoPoint {
  final double latitude;
  final double longitude;
  const GeoPoint(this.latitude, this.longitude);

  /// Parse `{ "lat": .., "lng": .. }` — the shape used by `pickupLocation`,
  /// `destinationLocation` and `captainPosition`.
  ///
  /// Note this is NOT the shape of `locationHistory`, which is GeoJSON
  /// `[lng, lat]` — see [GeoPoint.fromGeoJson]. Reading one with the other puts
  /// the point in the wrong hemisphere, which is why they are separate
  /// constructors rather than one lenient parser.
  static GeoPoint? fromLatLng(dynamic json) {
    if (json is! Map) return null;
    final lat = _toDouble(json['lat']);
    final lng = _toDouble(json['lng']);
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  /// Parse a GeoJSON `[lng, lat]` pair — longitude FIRST. Used only by
  /// `locationHistory.coordinates`.
  static GeoPoint? fromGeoJson(dynamic json) {
    if (json is! List || json.length < 2) return null;
    final lng = _toDouble(json[0]);
    final lat = _toDouble(json[1]);
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
}

/// Where the car's position comes from for this ride.
///
/// [tracker] means a hardware GPS unit in the vehicle reports it, and the
/// backend pushes `my-location` roughly every 10s. [gps] means there is no
/// tracker, no `my-location` will ever arrive, and the tablet must use its own
/// GPS for the car marker.
enum LocationSource { tracker, gps }

/// Where a ride is in its lifecycle, as the backend reports it on
/// `/captain/active-ride`. Both values mean a ride is live; they differ in
/// whether the captain has set off yet.
enum RideStatus {
  /// Assigned but not started — heading to the pickup.
  accepted,

  /// Under way, rider on board.
  ongoing,
}

/// The fare split shown on the ride summary, mirroring the main Cabby app's
/// `FareBreakdown` fields so the numbers read the same way to a captain.
class FareBreakdown {
  final int base;
  final int distance;
  final int time;
  final int platformFee;
  final int tax;

  const FareBreakdown({
    this.base = 0,
    this.distance = 0,
    this.time = 0,
    this.platformFee = 0,
    this.tax = 0,
  });

  int get total => base + distance + time + platformFee + tax;

  /// What lands in the captain's pocket — everything but the platform's cut.
  int get captainPayout => total - platformFee;
}

/// A single trip the captain is driving, as returned by `/captain/active-ride`
/// and updated by the ride socket events.
class Trip {
  final String id;
  final String riderName;
  final String riderPhone;

  /// The rider's rating, when the backend sends one. Null on a trip built
  /// locally or when the account has no ratings yet.
  final double? riderRating;
  final String pickup;
  final String destination;
  final GeoPoint pickupLocation;
  final GeoPoint destinationLocation;
  final String vehicle; // car | bike | auto
  final int distanceMetres;
  final int durationSeconds;
  final FareBreakdown fareBreakdown;

  /// Where this ride is in its lifecycle. Null on a locally built trip that
  /// never came from the backend.
  final RideStatus? status;

  /// The route line, encoded polyline at precision 5. Null when the backend has
  /// no route for this ride; the map then falls back to a direct line.
  final String? routePolyline;

  /// The breadcrumb trail already driven, oldest first. Decoded from GeoJSON
  /// `[lng, lat]` — see [GeoPoint.fromGeoJson].
  final List<GeoPoint> locationHistory;

  /// The backend's single `fare` number. The tablet shows this verbatim when
  /// present rather than deriving it, because the backend does not send the
  /// component split that [fareBreakdown] models.
  final int? serverFare;

  const Trip({
    required this.id,
    required this.riderName,
    required this.riderPhone,
    required this.pickup,
    required this.destination,
    required this.pickupLocation,
    required this.destinationLocation,
    this.riderRating,
    this.vehicle = 'car',
    this.distanceMetres = 0,
    this.durationSeconds = 0,
    this.fareBreakdown = const FareBreakdown(),
    this.status,
    this.routePolyline,
    this.locationHistory = const [],
    this.serverFare,
  });

  /// Build a trip from the `ride` object of `/captain/active-ride`.
  ///
  /// Everything is read defensively: this runs on every ignition cycle, and a
  /// single missing field must not leave a captain staring at a crashed tablet.
  /// Absent coordinates fall back to (0, 0) — the caller has already checked
  /// `ride != null`, so a ride with no geometry is a backend fault, not an
  /// idle tablet.
  factory Trip.fromActiveRide(Map<String, dynamic> json) {
    final user = json['user'];
    final history = json['locationHistory'];

    return Trip(
      id: json['_id']?.toString() ?? '',
      riderName: _fullName(user is Map ? user['fullname'] : null),
      riderPhone: (user is Map ? user['phone']?.toString() : null) ?? '',
      riderRating:
          user is Map ? GeoPoint._toDouble(user['rating']) : null,
      pickup: json['pickup']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      pickupLocation:
          GeoPoint.fromLatLng(json['pickupLocation']) ?? const GeoPoint(0, 0),
      destinationLocation: GeoPoint.fromLatLng(json['destinationLocation']) ??
          const GeoPoint(0, 0),
      status: switch (json['status']?.toString()) {
        'ongoing' => RideStatus.ongoing,
        'accepted' => RideStatus.accepted,
        _ => null,
      },
      routePolyline: json['routePolyline']?.toString(),
      // GeoJSON order — longitude first. Malformed entries are dropped rather
      // than defaulted, so a bad fix leaves a gap instead of a line to (0, 0).
      locationHistory: history is List
          ? history
              .map((e) => e is Map ? GeoPoint.fromGeoJson(e['coordinates']) : null)
              .whereType<GeoPoint>()
              .toList(growable: false)
          : const [],
      serverFare: GeoPoint._toDouble(json['fare'])?.round(),
    );
  }

  /// `{ "firstname": .., "lastname": .. }` → "First Last", degrading to
  /// "Rider" so an unnamed account still renders.
  static String _fullName(dynamic fullname) {
    final name = fullname is Map
        ? [fullname['firstname'], fullname['lastname']]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' ')
        : fullname?.toString().trim() ?? '';
    return name.isEmpty ? 'Rider' : name;
  }

  /// What the captain is owed. Prefers the backend's number; falls back to the
  /// local breakdown when there isn't one.
  int get fare => serverFare ?? fareBreakdown.total;

  /// Whether the fare came from the backend as a flat number, meaning there is
  /// no component split to show on the summary screen.
  bool get hasFareBreakdown => serverFare == null;

  /// This trip repriced to [fare] — used when `ride-ended` reports a final
  /// amount that differs from the one the ride was quoted at.
  Trip withFare(int fare) => Trip(
        id: id,
        riderName: riderName,
        riderPhone: riderPhone,
        riderRating: riderRating,
        pickup: pickup,
        destination: destination,
        pickupLocation: pickupLocation,
        destinationLocation: destinationLocation,
        vehicle: vehicle,
        distanceMetres: distanceMetres,
        durationSeconds: durationSeconds,
        fareBreakdown: fareBreakdown,
        status: status,
        routePolyline: routePolyline,
        locationHistory: locationHistory,
        serverFare: fare,
      );
  String get riderInitials {
    final parts = riderName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  double get km => distanceMetres / 1000;
  int get minutes => (durationSeconds / 60).round();

  /// A deterministic demo trip so a fresh scan always produces a real-looking
  /// job to drive. In the production app this arrives from the dispatch socket.
  static Trip sample() {
    return const Trip(
      id: 'CBY-4821',
      riderName: 'Ayesha Khan',
      riderPhone: '+92 300 1234567',
      pickup: 'Dolmen Mall, Clifton Block 4',
      destination: 'Jinnah International Airport, T1',
      pickupLocation: GeoPoint(24.8138, 67.0300),
      destinationLocation: GeoPoint(24.9065, 67.1608),
      vehicle: 'car',
      distanceMetres: 18400,
      durationSeconds: 2280,
      fareBreakdown: FareBreakdown(
        base: 120,
        distance: 640,
        time: 190,
        platformFee: 95,
        tax: 55,
      ),
    );
  }
}
