// Smoke tests for the Cabby Lite tablet app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cabby_lite/config/layout.dart';
import 'package:cabby_lite/config/theme.dart';
import 'package:cabby_lite/core/pairing_service.dart';
import 'package:cabby_lite/core/payment_service.dart';
import 'package:cabby_lite/core/ride_service.dart';
import 'package:cabby_lite/core/ride_socket.dart';
import 'package:cabby_lite/models/captain.dart';
import 'package:cabby_lite/models/trip.dart';
import 'package:cabby_lite/screens/captain_home_shell.dart';
import 'package:cabby_lite/screens/device_pairing_screen.dart';
import 'package:cabby_lite/screens/ride_in_progress_screen.dart';
import 'package:cabby_lite/state/location_service.dart';
import 'package:cabby_lite/state/pairing_controller.dart';
import 'package:cabby_lite/state/ride_controller.dart';

/// Stands in for `/captain/active-ride`. These are layout tests — they drive
/// the phase directly and must not reach the network, which under the test
/// binding would fail on the unloaded .env before it ever got to a socket.
class _FakeRideService implements RideService {
  const _FakeRideService([this.active = const ActiveRide()]);

  /// What `/captain/active-ride` answers. Defaults to an idle GPS captain.
  final ActiveRide active;

  @override
  Future<ActiveRide> activeRide() async => active;
}

/// Stands in for the payment endpoints. Layout tests must not reach the
/// network — `ApiClient` reads `.env`, which isn't loaded under the test
/// binding, so a real call throws before it ever gets to a socket.
class _FakePaymentService implements PaymentService {
  _FakePaymentService([this.current = const PaymentStatus(amount: 320)]);

  final PaymentStatus current;
  final List<String> posted = [];

  @override
  Future<PaymentStatus> status(String rideId) async => current;

  @override
  Future<PaymentStatus> confirmCash(String rideId) async {
    posted.add('paid:$rideId');
    return const PaymentStatus(status: 'paid');
  }

  @override
  Future<PaymentStatus> dispute(String rideId, {String? note}) async {
    posted.add('disputed:$rideId');
    return const PaymentStatus(status: 'disputed');
  }
}

/// Stands in for `/device/pair/*`. Hands back a code immediately so a pairing
/// layout test renders a real QR instead of the spinner placeholder, with no
/// network round trip.
///
/// [alreadyExpired] backdates `expiresAt`, which drives the controller's
/// client-side expiry the moment it ticks. That reaches the expired phase — the
/// taller of the two, since it swaps the countdown for a button — without
/// advancing fake time past the 2s poll, which would leave a pending periodic
/// timer and hang the test binding.
class _FakePairingService implements PairingService {
  const _FakePairingService({this.alreadyExpired = false});

  final bool alreadyExpired;

  @override
  Future<PairingCode> start(String deviceId) async => PairingCode(
        code: 'TEST-CODE-1234',
        expiresAt: DateTime.now().add(
          alreadyExpired
              ? const Duration(seconds: -1)
              : const Duration(minutes: 2),
        ),
      );

  @override
  Future<PairingStatus> status(String code, String deviceId) async =>
      const PairingStatus(state: PairingState.pending);
}

/// Counts calls, to pin down when [RideController.startTrip] re-syncs.
class _CountingRideService implements RideService {
  _CountingRideService([this.active = const ActiveRide()]);

  final ActiveRide active;
  int calls = 0;

  @override
  Future<ActiveRide> activeRide() async {
    calls++;
    return active;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The device token lives in the keystore, which has no implementation under
  // the test binding. Stand in for it with an in-memory map so the shell's boot
  // read and signOut()'s clear both resolve instead of hanging.
  final secureStore = <String, String>{};
  setUp(() {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => switch (call.method) {
        'read' => secureStore[call.arguments['key'] as String],
        'write' => secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String,
        'delete' => secureStore.remove(call.arguments['key'] as String),
        'readAll' => secureStore,
        _ => null,
      },
    );
  });

  test('pairing adopts the captain from the linked response', () {
    final ctrl = RideController(rideService: const _FakeRideService(), connectSocket: false);
    expect(ctrl.isPaired, isFalse);

    ctrl.signInFromPairing(Captain.fromPairing(const {
      'fullname': {'firstname': 'Bilal', 'lastname': 'Ahmed'},
      'vehicleNumber': 'ACX-472',
    }));

    expect(ctrl.isPaired, isTrue);
    expect(ctrl.captain?.name, 'Bilal Ahmed');
    expect(ctrl.captain?.vehicleNumber, 'ACX-472');
    expect(ctrl.phase, RidePhase.welcome);
  });

  test('a restored token pairs the tablet without a captain profile', () {
    // What every boot after the first looks like: the token is in the keystore
    // but the profile only arrives with /captain/active-ride.
    final ctrl = RideController(rideService: const _FakeRideService(), connectSocket: false)..restorePairing();
    expect(ctrl.isPaired, isTrue);
    expect(ctrl.captain, isNull);
  });

  test('ride lifecycle moves welcome -> inProgress -> completed -> welcome', () {
    final ctrl = RideController(rideService: const _FakeRideService(), connectSocket: false)..restorePairing();
    expect(ctrl.phase, RidePhase.welcome);

    ctrl.startTrip(Trip.sample());
    expect(ctrl.phase, RidePhase.inProgress);
    expect(ctrl.trip, isNotNull);

    ctrl.completeTrip();
    expect(ctrl.phase, RidePhase.completed);
    expect(ctrl.trip, isNotNull); // summary still needs the trip

    ctrl.clearTrip();
    expect(ctrl.phase, RidePhase.welcome);
    expect(ctrl.trip, isNull);
  });

  test('ride-ended reprices the trip to the final fare', () {
    // Section 6 of the guide: until the payment QR endpoint exists, the fare in
    // the ride-ended payload is what the completion screen must show. A ride
    // can finish at a different price than it was quoted at.
    final ctrl = RideController(
      rideService: const _FakeRideService(),
      connectSocket: false,
    )..restorePairing();
    ctrl.startTrip(Trip.sample());
    expect(ctrl.trip!.fare, 1100); // the sample's local breakdown

    ctrl.completeTrip(finalFare: 1450);

    expect(ctrl.phase, RidePhase.completed);
    expect(ctrl.trip!.fare, 1450);
    // A flat fare has no component split, so the summary hides those rows
    // rather than printing five zeroes.
    expect(ctrl.trip!.hasFareBreakdown, isFalse);
    // Repricing must not disturb anything else on the summary.
    expect(ctrl.trip!.riderName, 'Ayesha Khan');
    expect(ctrl.trip!.destination, isNotEmpty);
  });

  test('completeTrip without a final fare keeps the existing one', () {
    final ctrl = RideController(
      rideService: const _FakeRideService(),
      connectSocket: false,
    )..restorePairing();
    ctrl.startTrip(Trip.sample());

    ctrl.completeTrip();

    expect(ctrl.trip!.fare, 1100);
    expect(ctrl.trip!.hasFareBreakdown, isTrue);
  });

  test('fare breakdown totals and captain payout are consistent', () {
    const b = FareBreakdown(
      base: 120,
      distance: 640,
      time: 190,
      platformFee: 95,
      tax: 55,
    );
    expect(b.total, 1100);
    expect(b.captainPayout, 1005); // total minus platform fee
  });

  test('a captain with no name or plate still yields a usable profile', () {
    // An unprovisioned tablet pairs without a plate — the backend fills it from
    // the scanning captain, so the field can be absent here.
    final captain = Captain.fromPairing(const {});
    expect(captain.name, isNotEmpty);
    expect(captain.vehicleNumber, isEmpty);
  });

  // /captain/active-ride rebuilds the entire screen on every ignition cycle, so
  // a parsing slip here is a tablet that boots into the wrong state.
  group('active-ride parsing', () {
    // A full payload in the exact shape the backend guide documents.
    const payload = {
      'ride': {
        '_id': 'ride-1',
        'status': 'ongoing',
        'pickup': 'Dolmen Mall, Clifton',
        'destination': 'Jinnah International Airport',
        'pickupLocation': {'lat': 24.8138, 'lng': 67.0300},
        'destinationLocation': {'lat': 24.9065, 'lng': 67.1608},
        'routePolyline': '_p~iF~ps|U_ulLnnqC',
        'locationHistory': [
          {'coordinates': [67.0300, 24.8138], 'at': '2026-07-24T10:00:00Z'},
        ],
        'fare': 1450,
        'user': {
          'fullname': {'firstname': 'Ayesha', 'lastname': 'Khan'},
          'phone': '+92 300 1234567',
          'rating': 4.8,
        },
      },
      'captainPosition': {'lat': 24.8200, 'lng': 67.0400},
      'locationSource': 'tracker',
      'device': 'dev-1',
    };

    test('reads the rider, fare and status off a full payload', () {
      final active = ActiveRide.fromJson(payload);
      final trip = active.trip!;

      expect(trip.riderName, 'Ayesha Khan');
      expect(trip.riderPhone, '+92 300 1234567');
      expect(trip.riderRating, closeTo(4.8, 1e-9));
      expect(trip.status, RideStatus.ongoing);
      // The backend's flat number wins over the (empty) local breakdown.
      expect(trip.fare, 1450);
      expect(trip.hasFareBreakdown, isFalse);
      expect(active.locationSource, LocationSource.tracker);
      expect(active.captainPosition?.latitude, closeTo(24.82, 1e-9));
      expect(active.isIdle, isFalse);
    });

    // The guide's explicit warning: locationHistory is GeoJSON [lng, lat] while
    // every other coordinate is {lat, lng}. Reading one as the other puts
    // Karachi in the wrong hemisphere, so pin the orders against each other.
    test('locationHistory is read as [lng, lat], not [lat, lng]', () {
      final trip = ActiveRide.fromJson(payload).trip!;
      final trail = trip.locationHistory.single;

      expect(trail.latitude, closeTo(24.8138, 1e-9));
      expect(trail.longitude, closeTo(67.0300, 1e-9));
      // Same physical point as the {lat, lng} pickup — the two orders agree.
      expect(trail.latitude, closeTo(trip.pickupLocation.latitude, 1e-9));
      expect(trail.longitude, closeTo(trip.pickupLocation.longitude, 1e-9));
    });

    test('ride: null is an idle captain, not an error', () {
      final active = ActiveRide.fromJson(const {
        'ride': null,
        'locationSource': 'gps',
      });
      expect(active.isIdle, isTrue);
      expect(active.trip, isNull);
      expect(active.locationSource, LocationSource.gps);
    });

    test('an unknown location source falls back to this tablet\'s GPS', () {
      // Defaulting to tracker would make the app ignore its own GPS while
      // waiting for my-location events that never arrive.
      expect(
        ActiveRide.fromJson(const {'ride': null}).locationSource,
        LocationSource.gps,
      );
    });

    test('a tracker fix reads {lat, lng}, not GeoJSON order', () {
      // my-location uses the same {lat, lng} shape as captainPosition. Reading
      // it as [lng, lat] would put a Karachi car off the coast of Somalia.
      final fix = TrackerFix.fromJson(const {
        'lat': 24.8138,
        'lng': 67.0300,
        'heading': 47.5,
        'speed': 12.4,
        'source': 'tracker',
        'at': '2026-07-24T10:15:32Z',
      })!;

      expect(fix.point.latitude, closeTo(24.8138, 1e-9));
      expect(fix.point.longitude, closeTo(67.0300, 1e-9));
      expect(fix.heading, closeTo(47.5, 1e-9));
      expect(fix.at, isNotNull);
    });

    // The socket's ride payloads omit `pickupLocation` entirely and put the
    // coordinates in the `pickup` text field instead. Without a fallback both
    // pins land at (0, 0) and the map frames the Gulf of Guinea.
    test('a "lat,lng" pickup string still yields a real point', () {
      final trip = Trip.fromActiveRide(const {
        '_id': '09bec09e',
        'pickup': '24.9337937,67.0289403',
        'destination': 'Aptech Computer Education, Garden Road, Karachi',
      });

      expect(trip.pickupLocation.latitude, closeTo(24.9337937, 1e-9));
      expect(trip.pickupLocation.longitude, closeTo(67.0289403, 1e-9));
      expect(trip.pickupLocation.isUnset, isFalse);
      // A real address is not coordinates — it must not parse into a point.
      expect(trip.destinationLocation.isUnset, isTrue);
    });

    test('structured pickupLocation still wins over the text field', () {
      final trip = Trip.fromActiveRide(const {
        '_id': 'r1',
        'pickup': '1.0,2.0',
        'pickupLocation': {'lat': 24.8138, 'lng': 67.0300},
      });

      expect(trip.pickupLocation.latitude, closeTo(24.8138, 1e-9));
    });

    test('out-of-range numbers are not coordinates', () {
      // "Block 4, 200" splits into two parsable numbers by accident.
      expect(GeoPoint.fromLatLngString('91.0,10.0'), isNull);
      expect(GeoPoint.fromLatLngString('10.0,181.0'), isNull);
      expect(GeoPoint.fromLatLngString('Garden Road, Saddar'), isNull);
      expect(GeoPoint.fromLatLngString(''), isNull);
    });

    test('a fix with no coordinates is not a fix', () {
      // Better no marker movement than a jump to (0, 0) in the Gulf of Guinea.
      expect(TrackerFix.fromJson(const {'heading': 90}), isNull);
      expect(TrackerFix.fromJson(null), isNull);
    });

    test('a multi-point trail keeps its order, oldest first', () {
      // The map draws the trail as a line, so the order of the points is the
      // shape of the road driven — reversing it would still render, wrongly.
      final trip = ActiveRide.fromJson(const {
        'ride': {
          '_id': 'r',
          'locationHistory': [
            {'coordinates': [67.0300, 24.8138]},
            {'coordinates': [67.1000, 24.8500]},
            {'coordinates': [67.1608, 24.9065]},
          ],
        },
      }).trip!;

      expect(trip.locationHistory, hasLength(3));
      expect(trip.locationHistory.first.longitude, closeTo(67.0300, 1e-9));
      expect(trip.locationHistory.last.longitude, closeTo(67.1608, 1e-9));
    });

    test('malformed trail entries are dropped, not defaulted', () {
      // A bad fix must leave a gap in the line rather than a detour through
      // (0, 0) in the Atlantic.
      final trip = ActiveRide.fromJson(const {
        'ride': {
          '_id': 'r',
          'locationHistory': [
            {'coordinates': [67.0300, 24.8138]},
            {'coordinates': [67.1000]},
            {'at': '2026-07-24T10:00:00Z'},
            {'coordinates': [67.1608, 24.9065]},
          ],
        },
      }).trip!;

      expect(trip.locationHistory, hasLength(2));
      for (final p in trip.locationHistory) {
        expect(p.latitude, isNot(closeTo(0, 1e-9)));
      }
    });

    test('a ride missing every optional field still parses', () {
      // Runs on every boot — one absent field must not strand the captain.
      final trip = ActiveRide.fromJson(const {'ride': {}}).trip!;
      expect(trip.riderName, 'Rider');
      expect(trip.status, isNull);
      expect(trip.locationHistory, isEmpty);
      expect(trip.routePolyline, isNull);
    });
  });

  // A tracker vehicle whose map mounted off a `ride-started` socket event used
  // to follow the tablet's own GPS: `locationSource` was still its `gps`
  // default, so every `my-location` was discarded and the car marker showed the
  // tablet rather than the car.
  group('location source', () {
    const fix = TrackerFix(point: GeoPoint(24.86, 67.01));

    test('a tracker fix is kept before the first sync answers', () {
      final ctrl = RideController(
          rideService: const _FakeRideService(), connectSocket: false)
        ..restorePairing();
      // No sync has landed yet — the source is still unknown.
      expect(ctrl.hasLocationSource, isFalse);

      ctrl.receiveTrackerFix(fix);

      // The event only ever arrives in a tracker vehicle, so it is itself the
      // answer: adopt tracker rather than drop the fix.
      expect(ctrl.locationSource, LocationSource.tracker);
      expect(ctrl.usesDeviceGps, isFalse);
      expect(ctrl.captainPosition, isNotNull);
    });

    test('an explicit gps source still ignores tracker fixes', () async {
      final ctrl = RideController(
        rideService: const _FakeRideService(
            ActiveRide(locationSource: LocationSource.gps)),
        connectSocket: false,
      )..restorePairing();
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.hasLocationSource, isTrue);

      ctrl.receiveTrackerFix(fix);

      // Once the backend has spoken, the tablet's own GPS is the authority.
      expect(ctrl.usesDeviceGps, isTrue);
      expect(ctrl.captainPosition, isNull);
    });

    test('startTrip syncs only while the source is unknown', () async {
      final rides = _CountingRideService(
          const ActiveRide(locationSource: LocationSource.tracker));
      final ctrl = RideController(rideService: rides, connectSocket: false)
        ..restorePairing();
      // restorePairing's own sync, which must finish before startTrip runs —
      // syncActiveRide early-returns while one is already in flight.
      await Future<void>.delayed(Duration.zero);
      final afterBoot = rides.calls;

      ctrl.startTrip(Trip.sample());
      await Future<void>.delayed(Duration.zero);

      // The answer was already known, so no extra fetch.
      expect(rides.calls, afterBoot);
      expect(ctrl.usesDeviceGps, isFalse);
    });

    test('a ride starting on an unsynced tablet fetches the source', () async {
      final rides = _CountingRideService(
          const ActiveRide(locationSource: LocationSource.tracker));
      final ctrl = RideController(rideService: rides, connectSocket: false);
      // Paired but never synced — the state a tablet is in when `ride-started`
      // lands before any `/captain/active-ride` has completed.
      ctrl.signInFromPairing(null);
      // Deliberately no await between these two: `ride-started` landing while
      // the pairing sync is still in flight is exactly the race that stranded
      // the source at its `gps` default.
      ctrl.startTrip(Trip.sample());
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(rides.calls, greaterThan(1));
      expect(ctrl.hasLocationSource, isTrue);
      expect(ctrl.usesDeviceGps, isFalse);
    });

    test('a tracker that has never reported reads as stale mid-ride', () {
      final ctrl = RideController(
          rideService: const _FakeRideService(), connectSocket: false)
        ..restorePairing();
      ctrl.receiveTrackerFix(fix);
      expect(ctrl.locationSource, LocationSource.tracker);
      // A fix just landed, so nothing is stale.
      expect(ctrl.isTrackerStale, isFalse);
    });

    test('sign out forgets the vehicle location source', () async {
      secureStore['cabby_device_token'] = 'eyJ-device-token';
      final ctrl = RideController(
          rideService: const _FakeRideService(), connectSocket: false)
        ..restorePairing();
      ctrl.receiveTrackerFix(fix);
      expect(ctrl.usesDeviceGps, isFalse);

      await ctrl.signOut();

      // Otherwise a tablet moved into a GPS car keeps the old car's answer.
      expect(ctrl.hasLocationSource, isFalse);
      expect(ctrl.usesDeviceGps, isTrue);
    });
  });

  group('qr payment', () {
    RideController paired(_FakePaymentService payments) => RideController(
          rideService: const _FakeRideService(),
          paymentService: payments,
          connectSocket: false,
        )..restorePairing();

    test('the QR encodes exactly cabby-pay:v1:<rideId>', () {
      // The rider's scanner posts what it decodes straight through, so any
      // extra field here breaks the parse on their side.
      final trip = Trip.fromActiveRide(const {'_id': '09bec09e', 'fare': 320});
      expect('cabby-pay:v1:${trip.id}', 'cabby-pay:v1:09bec09e');
    });

    test('confirming cash settles the fare as paid', () async {
      final payments = _FakePaymentService();
      final ctrl = paired(payments)..startTrip(Trip.sample());
      expect(ctrl.paymentOutcome, isNull);

      await ctrl.confirmCashPayment();

      expect(payments.posted, ['paid:${Trip.sample().id}']);
      expect(ctrl.paymentOutcome, PaymentOutcome.paid);
    });

    test('a dispute settles as disputed and never blocks', () async {
      final payments = _FakePaymentService();
      final ctrl = paired(payments)..startTrip(Trip.sample());

      await ctrl.disputePayment();

      expect(payments.posted.single, startsWith('disputed:'));
      expect(ctrl.paymentOutcome, PaymentOutcome.disputed);
      // The captain is still free to take the next job.
      expect(ctrl.isPaired, isTrue);
    });

    test('a payment event for another ride is ignored', () {
      final ctrl = paired(_FakePaymentService())..startTrip(Trip.sample());

      ctrl.receivePaymentEvent(PaymentOutcome.paid, 'some-other-ride');

      // Otherwise a late event from the previous trip flashes "Paid" over a
      // fare this rider still owes.
      expect(ctrl.paymentOutcome, isNull);
    });

    test('a payment event for the trip on screen settles it', () {
      final trip = Trip.sample();
      final ctrl = paired(_FakePaymentService())..startTrip(trip);

      ctrl.receivePaymentEvent(PaymentOutcome.paid, trip.id);

      expect(ctrl.paymentOutcome, PaymentOutcome.paid);
    });

    test('the next ride starts with an outstanding fare', () {
      final trip = Trip.sample();
      final ctrl = paired(_FakePaymentService())..startTrip(trip);
      ctrl.receivePaymentEvent(PaymentOutcome.paid, trip.id);
      expect(ctrl.paymentOutcome, PaymentOutcome.paid);

      ctrl.clearTrip();
      ctrl.startTrip(trip);

      // A carried-over outcome would show the new fare as already settled.
      expect(ctrl.paymentOutcome, isNull);
    });

    test('the authoritative amount replaces the fare from ride-ended',
        () async {
      final ctrl = paired(
        _FakePaymentService(const PaymentStatus(amount: 349, status: 'unpaid')),
      )..startTrip(Trip.sample());

      await ctrl.loadPaymentStatus();

      expect(ctrl.paymentStatus?.amount, 349);
      expect(ctrl.paymentOutcome, isNull);
    });
  });

  testWidgets('sign out unpairs and wipes the device token', (tester) async {
    secureStore['cabby_device_token'] = 'eyJ-device-token';
    final ctrl = RideController(rideService: const _FakeRideService(), connectSocket: false)..restorePairing();
    expect(ctrl.isPaired, isTrue);

    await ctrl.signOut();

    expect(ctrl.isPaired, isFalse);
    expect(ctrl.phase, RidePhase.welcome);
    // Without this the app would bounce back to the QR and then let itself
    // straight back in on the next launch.
    expect(secureStore, isEmpty);
  });

  // Driving mode steers the camera off these two, so a silent error here would
  // point the map the wrong way with nothing else to catch it.
  group('driving-mode geo math', () {
    // The sample trip's pickup → drop-off (Clifton → Karachi airport) is a
    // known ~15km north-east hop.
    final trip = Trip.sample();

    test('distance between pickup and drop-off is plausible', () {
      final metres = LocationService.distanceMetres(
        trip.pickupLocation,
        trip.destinationLocation,
      );
      // Straight-line, so shorter than the trip's 18.4km road distance.
      expect(metres, greaterThan(14000));
      expect(metres, lessThan(18400));
    });

    test('distance to self is zero', () {
      expect(
        LocationService.distanceMetres(
            trip.pickupLocation, trip.pickupLocation),
        closeTo(0, 0.001),
      );
    });

    test('bearing points north-east toward the airport', () {
      final deg = LocationService.bearing(
        trip.pickupLocation,
        trip.destinationLocation,
      );
      expect(deg, greaterThan(0));
      expect(deg, lessThan(90));
    });

    test('bearing stays in the 0-360 range going the other way', () {
      final deg = LocationService.bearing(
        trip.destinationLocation,
        trip.pickupLocation,
      );
      expect(deg, inInclusiveRange(0, 360));
      // Reverse of a north-east leg is south-west.
      expect(deg, greaterThan(180));
      expect(deg, lessThan(270));
    });
  });

  // Renders a phase of the app at a given logical screen size and fails if the
  // layout throws (e.g. an unbounded-height Spacer). Covers phones and tablets
  // in both orientations so the responsive layout holds "on all tablets".
  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    void Function(RideController) setup,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = RideController(
      rideService: const _FakeRideService(),
      // The summary screen fetches the authoritative amount on mount; without
      // a fake that reaches the real ApiClient, which reads an unloaded .env.
      paymentService: _FakePaymentService(),
      connectSocket: false,
    );
    setup(ctrl);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ctrl,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CaptainHomeShell(),
        ),
      ),
    );
    // The shell reads the stored token before it renders anything, so pump
    // past the boot spinner and the shell's cross-fade.
    //
    // Deliberately NOT pumpAndSettle: the welcome screen's status dot pulses on
    // an endlessly repeating controller, so there is no quiescent state to
    // settle to and pumpAndSettle would always time out. Fixed pumps are enough
    // — these tests assert on layout, and layout is done by the first frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Logical sizes spanning the phone/tablet breakpoints, each way up.
  const sizes = <String, Size>{
    'phone portrait': Size(390, 844),
    'phone landscape': Size(844, 390),
    'tablet portrait (Tab A7)': Size(800, 1340),
    'tablet landscape (Tab A7)': Size(1340, 800),
    'large tablet landscape': Size(1280, 900),
    // The actual deployment: a windscreen-mounted tablet, landscape-locked.
    'windscreen tablet': Size(1180, 820),
    // A budget 800x480 Android tablet — the shortest viewport that still counts
    // as a real target, and the one where a too-optimistic fits-on-screen
    // estimate showed up as a 1px overflow stripe.
    'budget tablet': Size(800, 480),
  };

  sizes.forEach((label, size) {
    testWidgets('welcome (standby) lays out without overflow — $label',
        (tester) async {
      await pumpAt(tester, size, (c) => c.restorePairing());
      expect(tester.takeException(), isNull);
      // Standby shows the captain, never a rider: a ride only ever starts from
      // a `ride-started` socket event, so there is no demo button to tap and no
      // sample trip's details to leak onto this screen.
      expect(find.text('Start next ride'), findsNothing);
      expect(find.text('Ayesha Khan'), findsNothing);
      expect(find.textContaining('Dolmen Mall'), findsNothing);
    });

    // The trip map itself can't render in tests (Mapbox needs a platform
    // view), so the driving panel is exercised inside the same AnimatedSize +
    // ConstrainedBox wrapper the map screen puts it in. That combination once
    // handed the panel an unbounded width and threw "BoxConstraints forces an
    // infinite width".
    testWidgets('driving panel lays out without overflow — $label',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              final layout = context.layout;
              return Scaffold(
                body: Stack(
                  children: [
                    Align(
                      alignment: layout.isTablet
                          ? Alignment.bottomLeft
                          : Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.all(layout.isTablet ? 16 : 0),
                        child: SizedBox(
                          width: layout.isTablet ? 460.0 : layout.width,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            alignment: Alignment.bottomCenter,
                            child: DrivingPanel(
                              trip: Trip.sample(),
                              floating: layout.isTablet,
                              remainingMetres: 2400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The ride is ended from the captain's phone, never from this tablet.
      expect(find.text('End ride'), findsNothing);
      // 2400m renders through the nav distance formatter.
      expect(find.text('2.4 km'), findsOneWidget);
    });

    // The pre-drive panel is the taller of the two — rider row, fare, and a
    // full RouteCard — so it is the one with something to overflow. Same
    // wrapper as the driving panel above.
    testWidgets('trip panel lays out without overflow — $label',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              final layout = context.layout;
              return Scaffold(
                body: Stack(
                  children: [
                    Align(
                      alignment: layout.isTablet
                          ? Alignment.bottomLeft
                          : Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.all(layout.isTablet ? 16 : 0),
                        child: SizedBox(
                          width: layout.isTablet ? 460.0 : layout.width,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            alignment: Alignment.bottomCenter,
                            child: TripPanel(
                              trip: Trip.sample(),
                              floating: layout.isTablet,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('ride summary lays out without overflow — $label',
        (tester) async {
      await pumpAt(tester, size, (c) {
        c.restorePairing();
        c.startTrip(Trip.sample());
        c.completeTrip();
      });
      expect(tester.takeException(), isNull);
      expect(find.text('Ride completed'), findsOneWidget);
    });

    // Pairing is the one screen with a fixed-size QR and, until recently, no
    // scrollable — a short viewport had nowhere to put the overflow. Both
    // phases are covered: expired swaps the countdown for a taller button, so
    // it is the tighter of the two.
    for (final expired in const [false, true]) {
      final phaseName = expired ? 'expired' : 'live code';
      testWidgets('device pairing ($phaseName) lays out without overflow — '
          '$label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final pairing = PairingController(
          service: _FakePairingService(alreadyExpired: expired),
        );
        addTearDown(pairing.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: pairing,
            child: const MaterialApp(home: DevicePairingScreen()),
          ),
        );
        // Two frames: one for the post-frame start(), one for what it sets to
        // paint. Deliberately short of the 2s poll — advancing past it leaves
        // the periodic timer pending and the binding never settles. The QR card
        // is laid out at its full size from frame one either way (the code
        // arrives later and swaps a spinner for the QR *inside* the card), and
        // layout is all these assert on.
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);

        // The card must sit in the middle of the screen, not just fit on it.
        // A scroll view hands its child a loose width, so without an explicit
        // full-width floor the Column shrank to its widest child and parked the
        // whole thing ~300px left of centre on a wide tablet — no overflow, so
        // the check above sailed straight past it.
        // The QR card is the only large square on the screen. The bound is well
        // under the 200 floor it shrinks to on a short viewport — at 200 exactly
        // a `> 200` test finds nothing and fails on the finder, not the layout.
        Rect? qr;
        for (final e in find.byType(DecoratedBox).evaluate()) {
          final r = tester.getRect(
            find.byElementPredicate((x) => identical(x, e)),
          );
          if (r.width >= 150 && (r.width - r.height).abs() < 1.0) {
            qr = r;
            break;
          }
        }
        expect(qr, isNotNull, reason: 'no square QR card found');
        expect(
          qr!.center.dx,
          closeTo(size.width / 2, 1.0),
          reason: 'QR card not horizontally centred at $label',
        );
      });
    }
  });
}
