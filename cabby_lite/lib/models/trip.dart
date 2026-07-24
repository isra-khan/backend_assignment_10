/// A plain latitude/longitude pair. Kept map-SDK-agnostic so the trip model
/// doesn't depend on Mapbox (or any) map package — the map screen adapts this
/// to whatever the renderer needs.
class GeoPoint {
  final double latitude;
  final double longitude;
  const GeoPoint(this.latitude, this.longitude);
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

/// A single trip the captain is driving. Self-contained (no backend) — this
/// companion app is QR-driven and simulates the trip lifecycle locally.
class Trip {
  final String id;
  final String riderName;
  final String riderPhone;
  final String pickup;
  final String destination;
  final GeoPoint pickupLocation;
  final GeoPoint destinationLocation;
  final String vehicle; // car | bike | auto
  final int distanceMetres;
  final int durationSeconds;
  final FareBreakdown fareBreakdown;

  const Trip({
    required this.id,
    required this.riderName,
    required this.riderPhone,
    required this.pickup,
    required this.destination,
    required this.pickupLocation,
    required this.destinationLocation,
    this.vehicle = 'car',
    this.distanceMetres = 0,
    this.durationSeconds = 0,
    this.fareBreakdown = const FareBreakdown(),
  });

  int get fare => fareBreakdown.total;
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
