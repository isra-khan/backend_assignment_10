import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/captain.dart';

/// The profile of the captain this tablet is paired to, held across restarts.
///
/// The backend hands the captain over exactly once, in the `linked` pairing
/// response — `/captain/active-ride` returns no captain object — so without
/// this the name and vehicle are lost the moment the app is killed, and the
/// welcome screen falls back to greeting a generic "Captain".
///
/// Plain prefs rather than the keystore: [DeviceTokenStore] guards a year-long
/// credential and belongs there, but a name and a number plate are not secrets,
/// and the keystore's algorithm migrations are a cost with no benefit here.
class CaptainStore {
  static const _key = 'cabby_captain';

  // Cached so the welcome screen doesn't hit disk on every rebuild.
  static Captain? _cached;

  static Future<void> save(Captain captain) async {
    _cached = captain;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(captain.toJson()));
  }

  /// The stored profile, or null when this tablet has never paired — or when
  /// what was stored no longer parses, which is not worth failing a launch
  /// over. The captain re-appears on the next `/device/pair/status`.
  static Future<Captain?> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _cached = Captain.fromStored(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  /// Wipe the profile. Called on unpair, so a tablet moved to another vehicle
  /// never greets the previous captain.
  static Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
