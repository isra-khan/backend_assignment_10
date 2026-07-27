import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight, dependency-free logging for the tablet's networked flows —
/// pairing, active-ride, and the socket. Wraps `dart:developer.log`, so entries
/// carry a name and level and show up cleanly in the IDE console and DevTools
/// rather than as bare `print` lines.
///
/// Debug/profile only: in a release build every call is a no-op, so a shipped
/// tablet doesn't spend cycles formatting logs or leak a device token into a
/// system log. Nothing here should ever be relied on for user-facing behaviour.
class AppLog {
  const AppLog._();

  /// A step happened as expected. Use for the normal path — a request fired, a
  /// response came back, the device linked.
  static void info(String area, String message) => _emit(area, message);

  /// Something went wrong but the flow can carry on — a poll failed and will
  /// retry, a payload was unusable and triggered a re-sync.
  static void warn(String area, String message) =>
      _emit(area, 'WARN $message');

  /// A failure the flow can't recover from on its own — a malformed response, a
  /// revoked token.
  static void error(String area, String message, [Object? err]) => _emit(
        area,
        err == null ? 'ERROR $message' : 'ERROR $message — $err',
      );

  static void _emit(String area, String message) {
    // Stripped entirely from release builds.
    if (kReleaseMode) return;
    final line = 'cabby.$area: $message';
    // Two sinks on purpose. developer.log feeds DevTools → Logging (named,
    // filterable). debugPrint feeds the `flutter run` console and adb logcat,
    // where developer.log does NOT reliably surface on Android — so a device
    // being watched over logcat would otherwise show nothing.
    developer.log(message, name: 'cabby.$area');
    debugPrint(line);
  }
}
