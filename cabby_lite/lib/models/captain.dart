/// The signed-in captain. In this companion app the profile is decoded from the
/// login QR payload (or a demo default), not fetched from a backend.
class Captain {
  final String name;
  final String phone;
  final String vehicleType; // car | bike | auto
  final String vehicleNumber;
  final String vehicleColor;
  final int seats;

  const Captain({
    required this.name,
    this.phone = '',
    this.vehicleType = 'car',
    this.vehicleNumber = '',
    this.vehicleColor = '',
    this.seats = 4,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Build a captain from a scanned QR payload. Accepts a few shapes so a demo
  /// QR encoding just a name still logs in; unknown/blank scans fall back to a
  /// sensible default rather than failing the login.
  factory Captain.fromScan(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return Captain.demo();

    // Supported demo format: `cabby-captain:Name|Phone|type|NUMBER|color|seats`
    if (value.startsWith('cabby-captain:')) {
      final parts = value.substring('cabby-captain:'.length).split('|');
      String at(int i) => i < parts.length ? parts[i].trim() : '';
      return Captain(
        name: at(0).isEmpty ? 'Captain' : at(0),
        phone: at(1),
        vehicleType: at(2).isEmpty ? 'car' : at(2),
        vehicleNumber: at(3),
        vehicleColor: at(4),
        seats: int.tryParse(at(5)) ?? 4,
      );
    }

    // Any other payload — treat the whole thing as an ID and sign in as a
    // generic verified captain so the demo flow proceeds.
    return Captain.demo();
  }

  factory Captain.demo() => const Captain(
        name: 'Bilal Ahmed',
        phone: '+92 321 9876543',
        vehicleType: 'car',
        vehicleNumber: 'ACX-472',
        vehicleColor: 'White',
        seats: 4,
      );
}
