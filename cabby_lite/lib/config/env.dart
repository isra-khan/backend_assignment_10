import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the values in `lib/.env`. Loaded once in main() before
/// runApp. Mirrors the Cabby phone app's `Env` so both apps read config the
/// same way and point at the same backend.
class Env {
  /// The Cabby backend. Every pairing call and, later, the socket handshake
  /// hangs off this.
  ///
  /// The fallback is staging rather than localhost: a tablet that shipped
  /// without a `.env` should still reach a real server, and an in-car device
  /// has no localhost worth talking to. Once MDM is in place this comes from
  /// managed configuration per the deployment guide, not from the bundle.
  static String get serverUrl =>
      dotenv.maybeGet('SERVER_URL') ?? 'https://api.staging-cabby.prospertech.io';

  static String get mapboxToken => dotenv.maybeGet('MAPBOX_TOKEN') ?? '';
}
