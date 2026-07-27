import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The device token handed over when a captain claims this tablet's pairing
/// code. It authenticates every subsequent call as *this vehicle*.
///
/// Two properties drive the design. It is long-lived — a year, no re-scan per
/// day and none per ride — so it goes in the keystore rather than plain prefs.
/// And `/device/pair/status` returns it exactly once: a second poll returns
/// `token: null`, so a failed write is unrecoverable without re-pairing.
class DeviceTokenStore {
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'cabby_device_token';

  static Future<void> save(String token) =>
      _storage.write(key: _kToken, value: token);

  static Future<String?> token() => _storage.read(key: _kToken);

  /// Wipe the pairing. Called on sign-out and whenever the API returns 401 —
  /// a 401 means the captain revoked this tablet from their phone.
  static Future<void> clear() => _storage.delete(key: _kToken);
}
