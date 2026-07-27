/// The captain this tablet is paired to. The profile arrives from the backend
/// in the `linked` pairing response — it is not decoded from the QR, which
/// carries nothing but the pairing code.
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

  /// Build a captain from the `captain` object in a `linked` pairing response:
  /// `{ "fullname": { "firstname", "lastname" }, "vehicleNumber": "AQC-858" }`.
  ///
  /// Fields are read defensively — the plate in particular can be absent when
  /// an unprovisioned tablet pairs, and a missing name must not cost the
  /// captain their session, so it degrades to "Captain" rather than throwing.
  factory Captain.fromPairing(Map<String, dynamic> json) {
    final fullname = json['fullname'];
    final name = fullname is Map
        ? [fullname['firstname'], fullname['lastname']]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' ')
        : fullname?.toString().trim() ?? '';

    return Captain(
      name: name.isEmpty ? 'Captain' : name,
      phone: json['phone']?.toString() ?? '',
      vehicleType: json['vehicleType']?.toString() ?? 'car',
      vehicleNumber: json['vehicleNumber']?.toString() ?? '',
      vehicleColor: json['vehicleColor']?.toString() ?? '',
      seats: int.tryParse(json['seats']?.toString() ?? '') ?? 4,
    );
  }
}
