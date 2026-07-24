import 'package:flutter/foundation.dart';

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
  Captain? _captain;
  RidePhase _phase = RidePhase.welcome;
  Trip? _trip;

  Captain? get captain => _captain;
  RidePhase get phase => _phase;
  Trip? get trip => _trip;
  bool get isLoggedIn => _captain != null;

  /// Complete the QR login. [raw] is the decoded QR string.
  void signInFromScan(String raw) {
    _captain = Captain.fromScan(raw);
    _phase = RidePhase.welcome;
    _trip = null;
    notifyListeners();
  }

  void signOut() {
    _captain = null;
    _phase = RidePhase.welcome;
    _trip = null;
    notifyListeners();
  }

  /// Begin driving a trip — moves the home surface to the live map.
  void startTrip(Trip trip) {
    _trip = trip;
    _phase = RidePhase.inProgress;
    notifyListeners();
  }

  /// End the running trip — surfaces the summary + payment QR.
  void completeTrip() {
    if (_trip == null) return;
    _phase = RidePhase.completed;
    notifyListeners();
  }

  /// Rider has paid (or the captain dismissed the summary) — back to standby.
  void clearTrip() {
    _trip = null;
    _phase = RidePhase.welcome;
    notifyListeners();
  }
}
