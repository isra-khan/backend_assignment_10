import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/env.dart';
import '../models/trip.dart';
import 'device_token_store.dart';

/// A position pushed by the vehicle's tracker over `my-location`.
///
/// Mirrors the shape of [GeoFix] from the local GPS service so both sources
/// feed the map through one path.
class TrackerFix {
  final GeoPoint point;

  /// Degrees clockwise from north, or null when the tracker didn't report one.
  final double? heading;

  /// As reported by the tracker. The guide does not state the unit; nothing
  /// currently displays it, so it is carried through untouched rather than
  /// converted on a guess.
  final double? speed;

  /// When the fix was taken, per the tracker. Used to drop events that arrive
  /// out of order after a reconnect.
  final DateTime? at;

  const TrackerFix({required this.point, this.heading, this.speed, this.at});

  /// Parse `{ lat, lng, heading, speed, source, at }`. Null when there is no
  /// usable position in the payload — a fix without coordinates is not a fix.
  ///
  /// Note `{lat, lng}`, NOT the GeoJSON order used by `locationHistory`.
  static TrackerFix? fromJson(dynamic json) {
    if (json is! Map) return null;
    final point = GeoPoint.fromLatLng(json);
    if (point == null) return null;
    return TrackerFix(
      point: point,
      heading: _toDouble(json['heading']),
      speed: _toDouble(json['speed']),
      at: DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal(),
    );
  }

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
}

/// The ride lifecycle events this tablet reacts to.
///
/// `new-ride` and `ride-taken` are deliberately absent: they belong to the
/// phone's request feed, and a tablet acting on them would leave the welcome
/// screen for a job its captain never took.
enum RideEvent {
  /// `bid-accepted` / `ride-confirmed` — a ride was assigned. Two backend paths
  /// to the same meaning, handled identically per the guide.
  assigned,

  /// `ride-started` — rider is aboard, switch to the navigation map.
  started,

  /// `ride-ended` — trip finished. The payload carries the final fare.
  ended,

  /// `ride-cancelled` — back to standby.
  cancelled,
}

/// One decoded lifecycle event: what happened, and whatever the server sent
/// with it. [data] is passed through unparsed so the controller can decide
/// whether the payload is usable or a re-sync is safer.
class RideEventMessage {
  final RideEvent event;
  final Map<String, dynamic>? data;
  const RideEventMessage(this.event, this.data);
}

/// The tablet's live feed. Listen-only: this class has no emit, by design —
/// "The tablet is a receive-only device. It never emits a socket event and
/// never posts a location."
///
/// Connection lifecycle is socket.io's own (it reconnects with backoff). What
/// this adds is the two things the guide calls out: a reconnect must trigger a
/// fresh `/captain/active-ride` rather than trusting the screen, and a refused
/// connection on a revoked token must drop the app back to the QR.
class RideSocket {
  RideSocket({
    required this.onEvent,
    required this.onLocation,
    required this.onReconnect,
    required this.onRevoked,
  });

  /// A ride lifecycle event arrived.
  final void Function(RideEventMessage) onEvent;

  /// A tracker position arrived. Only meaningful when `locationSource` is
  /// `tracker`; the controller drops it otherwise.
  final void Function(TrackerFix) onLocation;

  /// The socket came back after a drop. Events were missed in the gap, so the
  /// screen has to be rebuilt from the snapshot endpoint.
  final VoidCallback onReconnect;

  /// The server refused this device token — the captain unlinked the tablet.
  final VoidCallback onRevoked;

  io.Socket? _socket;

  /// True once a connection has been established at least once, so the first
  /// `connect` isn't mistaken for a reconnect (boot already syncs on its own).
  bool _hasConnected = false;

  bool get isConnected => _socket?.connected ?? false;

  /// Open the feed. No-op when already connected or when this tablet holds no
  /// device token — an unpaired device has nothing to authenticate with.
  Future<void> connect() async {
    if (_socket != null) return;

    final token = await DeviceTokenStore.token();
    if (token == null || token.isEmpty) return;

    final socket = io.io(
      Env.serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _log(_hasConnected ? 'reconnected' : 'connected', null);
      // The first connect follows a boot sync that has already run; only a
      // genuine reconnect needs to rebuild the screen.
      if (_hasConnected) {
        onReconnect();
      }
      _hasConnected = true;
    });

    socket.onDisconnect((reason) => _log('disconnected', reason));

    // A handshake rejected for auth means the token is dead. socket.io reports
    // this as a connect error rather than a status code, so match on the
    // message — anything else is ordinary network trouble and is left to the
    // built-in reconnection.
    socket.onConnectError((err) {
      _log('connect_error', err);
      if (_looksUnauthorized(err)) onRevoked();
    });
    socket.onError((err) {
      _log('error', err);
      if (_looksUnauthorized(err)) onRevoked();
    });

    // Two paths, one meaning — per the guide, handled identically.
    socket.on('bid-accepted', (d) => _emit('bid-accepted', RideEvent.assigned, d));
    socket.on(
        'ride-confirmed', (d) => _emit('ride-confirmed', RideEvent.assigned, d));
    socket.on('ride-started', (d) => _emit('ride-started', RideEvent.started, d));
    socket.on('ride-ended', (d) => _emit('ride-ended', RideEvent.ended, d));
    socket.on(
        'ride-cancelled', (d) => _emit('ride-cancelled', RideEvent.cancelled, d));

    socket.on('my-location', (d) {
      final fix = TrackerFix.fromJson(d);
      // Logged either way: a payload that fails to parse is invisible
      // otherwise, and "no fix arrived" and "the fix was malformed" are very
      // different faults to chase.
      _log('my-location', d, note: fix == null ? 'DROPPED — unparseable' : null);
      if (fix != null) onLocation(fix);
    });

    // `new-ride` and `ride-taken` belong to the phone's request feed and are
    // deliberately not acted on. Logged only so the feed reads complete while
    // debugging — seeing them proves the socket is live and delivering.
    socket.on('new-ride', (d) => _log('new-ride', d, note: 'ignored'));
    socket.on('ride-taken', (d) => _log('ride-taken', d, note: 'ignored'));

    socket.connect();
  }

  void _emit(String name, RideEvent event, dynamic data) {
    _log(name, data);
    onEvent(RideEventMessage(
      event,
      data is Map ? Map<String, dynamic>.from(data) : null,
    ));
  }

  /// Trace one socket event. Debug builds only — [kDebugMode] compiles this out
  /// of release, so a shipped tablet doesn't log ride payloads to logcat.
  static void _log(String name, dynamic payload, {String? note}) {
    if (!kDebugMode) return;
    final suffix = note == null ? '' : '  ($note)';
    debugPrint('[socket] $name'
        '${payload == null ? '' : '  $payload'}$suffix');
  }

  /// socket.io surfaces auth failures as free-form strings or maps, so this
  /// sniffs rather than matches exactly. False negatives are safe — the app
  /// falls back to the 401 on the next HTTP call, which is authoritative.
  static bool _looksUnauthorized(dynamic err) {
    final text = err is Map
        ? (err['message'] ?? err['msg'] ?? err).toString()
        : err.toString();
    final lower = text.toLowerCase();
    return lower.contains('401') ||
        lower.contains('unauthor') ||
        lower.contains('forbidden') ||
        lower.contains('invalid token');
  }

  /// Close the feed and forget the connection state. Called on unpair and when
  /// the controller is disposed.
  void dispose() {
    final socket = _socket;
    _socket = null;
    _hasConnected = false;
    if (socket == null) return;
    socket.clearListeners();
    socket.dispose();
  }
}
