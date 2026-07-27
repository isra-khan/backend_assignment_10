import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/device_id.dart';
import '../core/device_token_store.dart';
import '../core/pairing_service.dart';
import '../models/captain.dart';

/// What the pairing screen is showing right now.
enum PairingPhase {
  /// Asking the backend for a code.
  requesting,

  /// A code is on screen, waiting for a captain to scan it.
  showingCode,

  /// The code timed out unclaimed. A fresh one is one tap (or one tick) away.
  expired,

  /// Couldn't reach the server. The poll keeps trying underneath.
  error,

  /// A captain claimed it. The token is stored; the shell moves on.
  linked,
}

/// Owns the whole pairing loop so the screen stays a pure render of this state.
///
///   requesting → showingCode ⇄ error
///                     ↓  ↑
///                  expired ┘        (a new code restarts at requesting)
///                     ↓
///                  linked
class PairingController extends ChangeNotifier {
  PairingController({PairingService? service})
      : _service = service ?? const PairingService();

  final PairingService _service;

  // Polled every 2s, per the backend guide.
  static const _pollInterval = Duration(seconds: 2);

  PairingPhase _phase = PairingPhase.requesting;
  String? _code;
  DateTime? _expiresAt;
  String? _errorMessage;
  Captain? _captain;

  Timer? _poll;
  bool _disposed = false;
  // Guards against two overlapping start() calls (e.g. an expiry tick landing
  // at the same moment the captain taps "New code") racing to set _code.
  bool _starting = false;

  PairingPhase get phase => _phase;
  String? get code => _code;
  DateTime? get expiresAt => _expiresAt;
  String? get errorMessage => _errorMessage;

  /// The captain who claimed this tablet. Null until [PairingPhase.linked].
  Captain? get captain => _captain;

  /// Open a pairing: fetch a code, render it, and start polling.
  ///
  /// Safe to call again at any point — it tears down the previous poll first,
  /// so the "New code" button and the expiry path share one path.
  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    _poll?.cancel();
    _poll = null;

    _phase = PairingPhase.requesting;
    _errorMessage = null;
    _code = null;
    _expiresAt = null;
    _notify();

    try {
      final deviceId = await DeviceId.getOrCreate();
      AppLog.info('pair', 'opening a pairing for deviceId=$deviceId');
      final pairing = await _service.start(deviceId);
      if (_disposed) return;

      _code = pairing.code;
      _expiresAt = pairing.expiresAt;
      _phase = PairingPhase.showingCode;
      _notify();

      AppLog.info('pair', 'showing QR — polling status every 2s');
      _poll = Timer.periodic(_pollInterval, (_) => _tick(deviceId));
    } on PairingException catch (e) {
      if (_disposed) return;
      // No code to show and no poll to lean on, so this one is terminal until
      // the captain retries.
      AppLog.error('pair', 'could not open a pairing', e.message);
      _phase = PairingPhase.error;
      _errorMessage = e.message;
      _notify();
    } finally {
      _starting = false;
    }
  }

  Future<void> _tick(String deviceId) async {
    final code = _code;
    if (code == null || _disposed) return;

    // Client-side expiry. The server is the authority, but acting on
    // `expiresAt` means a dead QR stops inviting scans even if the poll is
    // struggling to get a response through.
    final expiresAt = _expiresAt;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _markExpired();
      return;
    }

    try {
      final status = await _service.status(code, deviceId);
      if (_disposed) return;

      switch (status.state) {
        case PairingState.pending:
          // A recovered connection clears a previously shown error.
          if (_phase == PairingPhase.error) {
            _phase = PairingPhase.showingCode;
            _errorMessage = null;
            _notify();
          }

        case PairingState.expired:
          _markExpired();

        case PairingState.linked:
          await _onLinked(status);
      }
    } on PairingException catch (e) {
      if (_disposed) return;
      // Non-fatal: the poll is still running, so surface it as a banner and let
      // the next tick recover rather than dropping out of the flow.
      _phase = PairingPhase.error;
      _errorMessage = e.message;
      _notify();
    }
  }

  Future<void> _onLinked(PairingStatus status) async {
    final token = status.token;
    if (token == null || token.isEmpty) {
      // Linked, but the token has already been handed out — this poll lost the
      // race to an earlier one, or the pairing belongs to a previous install.
      // There is no way to recover the token, so start over with a fresh code.
      AppLog.warn(
        'pair',
        'linked but token already consumed — restarting with a fresh code',
      );
      _markExpired();
      return;
    }

    // Stop the timer BEFORE the await. The token is returned exactly once; if
    // another tick fires while this write is in flight it will see
    // `token: null` and wrongly reset the screen.
    _poll?.cancel();
    _poll = null;

    await DeviceTokenStore.save(token);
    if (_disposed) return;

    AppLog.info(
      'pair',
      'device token stored — tablet paired to ${status.captain?.name ?? 'captain'}',
    );
    _captain = status.captain;
    _phase = PairingPhase.linked;
    _errorMessage = null;
    _notify();
  }

  void _markExpired() {
    _poll?.cancel();
    _poll = null;
    _phase = PairingPhase.expired;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    super.dispose();
  }
}
