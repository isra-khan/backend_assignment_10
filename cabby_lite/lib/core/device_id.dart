import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The stable identity of this physical tablet.
///
/// `deviceId` is the one field `/device/pair/start` actually requires, and the
/// backend keys the pairing on it — so the same tablet must present the same id
/// every time it re-pairs, or it looks like a brand new device.
///
/// Resolution order, per the backend guide:
///   1. Android Enterprise managed configuration, injected by MDM per device.
///   2. A value this app generated earlier and persisted.
///   3. A freshly generated one, persisted for next time.
class DeviceId {
  static const _key = 'cabby_device_id';

  // Cached so the pairing loop doesn't hit disk on every retry.
  static String? _cached;

  static Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    final fromMdm = await _fromManagedConfig();
    if (fromMdm != null && fromMdm.isNotEmpty) {
      return _cached = fromMdm;
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      return _cached = saved;
    }

    final generated = _uuidV4();
    await prefs.setString(_key, generated);
    return _cached = generated;
  }

  /// Managed-configuration lookup. Not wired yet — there is no MDM console, so
  /// there is nothing to read from. Kept as an explicit seam so switching it on
  /// later is a change to this one method and no call site moves.
  ///
  /// TODO(mdm): read `deviceId` (and `vehicleRegNo` / `fleetId` / `serverUrl`)
  /// from RestrictionsManager over a platform channel once the MDM console
  /// exists. See deployment guide section 2.2.
  static Future<String?> _fromManagedConfig() async => null;

  /// A v4 UUID from a cryptographic source. Hand-rolled to avoid pulling in a
  /// package for a single call made once in the lifetime of the device.
  static String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
