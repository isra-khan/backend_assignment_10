import 'package:flutter/foundation.dart';

import '../core/device_token_store.dart';
import '../core/ride_service.dart';
import '../core/ride_socket.dart';
import '../models/captain.dart';
import '../models/trip.dart';

/// The captain's high-level flow phase.
///
/// The home surface renders one of three faces off this: the welcome/standby
/// screen (no active ride), the live navigation map (ride running), and the
/// ride summary with the payment QR (ride just ended).
enum RidePhase { welcome, inProgress, completed }

/// Drives the whole session: who's signed in and where the current trip is in
/// its lifecycle. A single [ChangeNotifier] keeps the transitions
/// Welcome → In Progress → Completed in one place so the screens stay dumb.
class RideController extends ChangeNotifier {
  /// [connectSocket] is false in tests, which drive the phase directly and must
  /// not open a real connection.
  RideController({RideService? rideService, this.connectSocket = true})
      : _rides = rideService ?? const RideService();

  final RideService _rides;

  /// Whether this controller opens the live ride feed.
  final bool connectSocket;

  RideSocket? _socket;

  Captain? _captain;
  RidePhase _phase = RidePhase.welcome;
  Trip? _trip;
  bool _paired = false;
  GeoPoint? _captainPosition;
  /// Null until the first `/captain/active-ride` answers. Deliberately NOT
  /// defaulted to `gps`: that made "we haven't asked yet" indistinguishable
  /// from "this vehicle has no tracker", so a tracker tablet whose map mounted
  /// off a `ride-started` socket event followed its own GPS and discarded every
  /// `my-location`.
  LocationSource? _locationSource;
  bool _syncing = false;
  bool _disposed = false;

  /// When the tracker last reported a position. Null in a GPS vehicle, or
  /// before the first `my-location` arrives.
  DateTime? _lastTrackerFixAt;

  /// Bumped by every local phase change. An in-flight [syncActiveRide] captures
  /// this before awaiting and discards its result if the value moved — the
  /// snapshot it is holding is older than what the app already knows.
  int _generation = 0;

  Captain? get captain => _captain;
  RidePhase get phase => _phase;
  Trip? get trip => _trip;

  /// Where to draw the car before any live fix arrives, from the last
  /// `/captain/active-ride`. Null when the backend didn't report one.
  GeoPoint? get captainPosition => _captainPosition;

  /// Whether the car's position comes from a vehicle tracker or this tablet's
  /// own GPS. The map uses this to decide which source to trust.
  ///
  /// Falls back to `gps` before the backend has answered — the same fail-safe
  /// [ActiveRide.fromJson] applies to an unrecognised value, and the guide's
  /// stated default.
  LocationSource get locationSource => _locationSource ?? LocationSource.gps;

  /// True once `/captain/active-ride` has told us which source this vehicle
  /// uses. Until then [locationSource] is a fail-safe guess, not an answer.
  bool get hasLocationSource => _locationSource != null;

  /// True when the tablet uses its own GPS for the car marker — i.e. there is
  /// no tracker in this vehicle and no `my-location` events will arrive.
  bool get usesDeviceGps => locationSource == LocationSource.gps;

  /// True while an active-ride sync is in flight.
  bool get isSyncing => _syncing;

  /// Whether the live feed is currently up.
  bool get isSocketConnected => _socket?.isConnected ?? false;

  /// When the tracker last reported. Null in a GPS vehicle.
  DateTime? get lastTrackerFixAt => _lastTrackerFixAt;

  /// A tracker vehicle whose box has gone quiet for well over the ~10s the
  /// guide describes. The car marker is showing a position that is no longer
  /// current, and the map says so rather than implying a parked car.
  ///
  /// Only ever true in a tracker vehicle: with `locationSource: gps` the
  /// tablet's own GPS is the source and there is nothing to go stale.
  bool get isTrackerStale {
    if (usesDeviceGps) return false;
    final at = _lastTrackerFixAt;
    // No fix has EVER arrived in a vehicle the backend says has a tracker.
    // That is the failure that used to be silent — a car frozen at its last
    // known `captainPosition` read as a healthily parked one. Only during a
    // live ride, where the ~10s cadence is expected; an idle tablet on the
    // welcome screen isn't waiting on anything.
    if (at == null) return _phase == RidePhase.inProgress;
    return DateTime.now().difference(at) > _trackerStaleAfter;
  }

  // Six missed reports. Long enough that ordinary jitter or one dropped packet
  // doesn't flash a warning at the captain.
  static const _trackerStaleAfter = Duration(seconds: 60);

  /// Whether this tablet holds a device token. The single gate between the
  /// pairing screen and the ride faces.
  ///
  /// Note this is not the same as "we know who the captain is": a tablet
  /// restored from a stored token is paired but has no profile until the first
  /// /captain/active-ride lands, so [captain] can be null here.
  bool get isPaired => _paired;

  /// Restore a previous pairing on boot, from the token in the keystore.
  ///
  /// Marks the tablet paired immediately so the QR screen never flashes at an
  /// already-linked device, then rebuilds the real screen from the backend and
  /// opens the live feed.
  void restorePairing() {
    _paired = true;
    _phase = RidePhase.welcome;
    notifyListeners();
    syncActiveRide();
    _openSocket();
  }

  /// Adopt the captain this tablet just paired to. [captain] comes from the
  /// `linked` pairing response, so it is the real account, not a local guess.
  void signInFromPairing(Captain? captain) {
    _captain = captain ?? const Captain(name: 'Captain');
    _paired = true;
    _phase = RidePhase.welcome;
    _trip = null;
    notifyListeners();
    // A captain can pair mid-ride — a tablet swapped into a moving car, or one
    // that was unlinked and re-linked. Don't assume the fresh pairing means an
    // idle vehicle.
    syncActiveRide();
    _openSocket();
  }

  /// Open the live ride feed, if this controller runs one and isn't already
  /// connected. Safe to call repeatedly.
  void _openSocket() {
    if (!connectSocket || _socket != null || _disposed) return;

    _socket = RideSocket(
      onEvent: _onRideEvent,
      onLocation: _onTrackerFix,
      // The guide is explicit: after a reconnect, re-fetch rather than assume
      // the screen is still right. Everything that happened while the socket
      // was down was missed outright.
      onReconnect: syncActiveRide,
      onRevoked: _onRevoked,
    );
    _socket!.connect();
  }

  /// A ride lifecycle event.
  ///
  /// Payload shapes are documented only for `ride-ended` ("payload has the
  /// final fare"), so each handler uses what it is given when it is usable and
  /// falls back to the snapshot endpoint when it isn't. That keeps the tablet
  /// correct against event bodies this app has not seen yet.
  void _onRideEvent(RideEventMessage message) {
    if (_disposed || !_paired) {
      _log('${message.event.name} ignored — '
          '${_disposed ? 'controller disposed' : 'tablet not paired'}');
      return;
    }

    switch (message.event) {
      case RideEvent.assigned:
      case RideEvent.started:
        final trip = _tripFrom(message.data);
        if (trip != null) {
          // Both states put the captain on the map — the tablet has no separate
          // "heading to pickup" face — so this is one path, matching how
          // syncActiveRide treats `accepted` and `ongoing`.
          _log('${message.event.name} → startTrip(${trip.id}) '
              'phase=$_phase→inProgress');
          startTrip(trip);
        } else {
          _log('${message.event.name} → no usable ride in payload, re-syncing');
          syncActiveRide();
        }

      case RideEvent.ended:
        final fare = _fareFrom(message.data);
        // Section 6: the payment QR endpoint doesn't exist yet, so the final
        // fare in this payload is the only source for the completion screen.
        _log('ended → completeTrip(finalFare: $fare) phase=$_phase→completed');
        completeTrip(finalFare: fare);

      case RideEvent.cancelled:
        _log('cancelled → clearTrip() phase=$_phase→welcome');
        clearTrip();
    }
  }

  /// Trace a state transition driven by the live feed. Debug builds only — see
  /// the note on [RideSocket]'s logger.
  static void _log(String message) {
    if (kDebugMode) debugPrint('[ride] $message');
  }

  /// Pull a ride out of an event payload, tolerating both a bare ride object
  /// and one nested under `ride`. Null when there is nothing usable, which
  /// tells the caller to re-sync instead.
  Trip? _tripFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final ride = data['ride'] ?? data;
    if (ride is! Map) return null;
    final map = Map<String, dynamic>.from(ride);
    // A payload with no id is a notification, not a ride — re-sync rather than
    // render an empty trip.
    if (map['_id'] == null && map['pickup'] == null) return null;
    return Trip.fromActiveRide(map);
  }

  /// The final fare from a `ride-ended` payload, looked for both at the top
  /// level and under `ride`.
  int? _fareFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final direct = data['fare'];
    if (direct != null) return _asInt(direct);
    final ride = data['ride'];
    return ride is Map ? _asInt(ride['fare']) : null;
  }

  static int? _asInt(dynamic v) => v is num
      ? v.round()
      : double.tryParse(v?.toString() ?? '')?.round();

  /// Feed a tracker fix as if it arrived over the socket. Tests run with
  /// `connectSocket: false`, so there is no other way to reach [_onTrackerFix].
  @visibleForTesting
  void receiveTrackerFix(TrackerFix fix) => _onTrackerFix(fix);

  /// A tracker position. Ignored in a vehicle the backend has told us runs on
  /// device GPS, per the guide — there the tablet's own GPS is the authority
  /// and these would fight it.
  void _onTrackerFix(TrackerFix fix) {
    if (_disposed) return;

    // A `my-location` only ever arrives in a tracker vehicle — the backend
    // does not emit it otherwise. So the event is itself the answer to a
    // question we may not have asked yet: adopt tracker before the first sync
    // lands, rather than dropping the fix against a default that was only ever
    // a guess. Once sync has spoken, an explicit `gps` still wins.
    if (_locationSource == null) {
      _locationSource = LocationSource.tracker;
    } else if (usesDeviceGps) {
      return;
    }

    // Drop a fix older than the one already shown. Reconnects can replay
    // events out of order, and a stale position would drag the car backwards.
    final at = fix.at;
    final last = _lastTrackerFixAt;
    if (at != null && last != null && at.isBefore(last)) return;

    _captainPosition = fix.point;
    _lastTrackerFixAt = at ?? DateTime.now();
    notifyListeners();
  }

  /// The socket was refused for auth — the captain unlinked this tablet.
  Future<void> _onRevoked() async {
    if (_disposed || !_paired) return;
    await signOut();
  }

  /// Rebuild the whole screen from `/captain/active-ride`.
  ///
  /// Called on boot, right after pairing, and after any socket reconnect. This
  /// is the authority: whatever it returns wins over the current screen, since
  /// a tablet that was off or offline has missed every event in the gap.
  ///
  /// Failures are deliberately quiet. A tablet with no signal keeps showing the
  /// last known screen rather than blanking to an error — except on a 401,
  /// which means the captain revoked this device and the only correct screen is
  /// the QR.
  Future<void> syncActiveRide() async {
    if (_syncing || !_paired) return;
    _syncing = true;
    notifyListeners();

    final generation = _generation;
    try {
      final active = await _rides.activeRide();

      // A socket event (or an unpair) can land while this request is in
      // flight, and it is strictly newer than the snapshot now arriving. Drop
      // the stale answer rather than overwriting live state with it —
      // otherwise a sync started before `ride-ended` would drag the captain
      // off the fare screen and back onto the map.
      if (generation != _generation || !_paired) return;

      _captainPosition = active.captainPosition;
      _locationSource = active.locationSource;
      _trip = active.trip;
      // `ride: null` is an idle captain, not a fault. An `accepted` ride is
      // already assigned, so it belongs on the trip surface alongside
      // `ongoing` — the tablet has no separate "heading to pickup" face.
      _phase = active.isIdle ? RidePhase.welcome : RidePhase.inProgress;
    } on DeviceRevokedException {
      // ApiClient already wiped the token; drop the session so the shell falls
      // back to pairing, and close the feed — a revoked token can't hold one.
      _closeSocket();
      _captain = null;
      _paired = false;
      _trip = null;
      _phase = RidePhase.welcome;
    } on RideException {
      // Network or server trouble — keep the current screen. A reconnect or the
      // next ignition cycle retries.
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Unpair this tablet. Wipes the device token as well as the local session —
  /// without that the app would return to the QR screen and then immediately
  /// let itself back in on the next launch.
  Future<void> signOut() async {
    await DeviceTokenStore.clear();
    _closeSocket();
    _generation++;
    _captain = null;
    _paired = false;
    _phase = RidePhase.welcome;
    _trip = null;
    _captainPosition = null;
    _lastTrackerFixAt = null;
    // Otherwise the only ride state to survive an unpair: a tablet moved from
    // a tracker car into a GPS one would start with the old car's answer.
    _locationSource = null;
    notifyListeners();
  }

  /// Tear the feed down. Separate from [dispose] because an unpaired tablet
  /// keeps this controller alive while showing the QR screen.
  void _closeSocket() {
    _socket?.dispose();
    _socket = null;
  }

  /// Begin driving a trip — moves the home surface to the live map.
  void startTrip(Trip trip) {
    _generation++;
    _trip = trip;
    _phase = RidePhase.inProgress;
    notifyListeners();

    // A ride can start from a socket event on a tablet that has never synced,
    // and `ride-started` carries no `locationSource`. The map is mounting right
    // now and needs to know which source to follow, so ask. Skipped once the
    // answer is known: a needless snapshot could return a backend view that
    // hasn't committed this ride yet and bounce the captain back to welcome.
    if (!hasLocationSource) _syncLocationSource();
  }

  /// Learn `locationSource` for a ride that started before any sync landed.
  ///
  /// Can't just call [syncActiveRide]: a sync begun by [restorePairing] or
  /// [signInFromPairing] is usually still in flight here, which both blocks
  /// this call on `_syncing` AND has its own result thrown away, because
  /// [startTrip] bumped `_generation` while it was awaiting. So wait that one
  /// out, then ask again — otherwise the answer never arrives and a tracker
  /// vehicle spends the whole ride following the tablet's GPS.
  Future<void> _syncLocationSource() async {
    // Captured before waiting. The retry below starts a NEW sync, whose own
    // guard captures a fresh generation and so cannot recognise a snapshot as
    // stale. Without this check a ride that ended while we waited would be
    // rebuilt from an `/active-ride` that no longer knows about it, dropping
    // the captain off the fare screen.
    final generation = _generation;

    if (_syncing) {
      // One microtask-drain at a time, so a slow request doesn't spin here.
      while (_syncing && !_disposed) {
        await Future<void>.delayed(Duration.zero);
      }
      // The sync we waited for may have answered this already.
      if (_disposed || hasLocationSource) return;
    }
    if (generation != _generation || !_paired) return;
    await syncActiveRide();
  }

  /// End the running trip — surfaces the summary + payment QR.
  ///
  /// [finalFare] comes from the `ride-ended` payload, which the guide names as
  /// the source for the completion screen until the payment QR endpoint lands.
  /// It overrides whatever fare the trip was carrying — a ride can end at a
  /// different price than it started (waiting time, a changed drop-off).
  void completeTrip({int? finalFare}) {
    final trip = _trip;
    if (trip == null) return;
    _generation++;
    if (finalFare != null) _trip = trip.withFare(finalFare);
    _phase = RidePhase.completed;
    notifyListeners();
  }

  /// Rider has paid (or the captain dismissed the summary) — back to standby.
  void clearTrip() {
    _generation++;
    _trip = null;
    _phase = RidePhase.welcome;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _closeSocket();
    super.dispose();
  }
}
