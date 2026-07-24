// Smoke tests for the Cabby Captain app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cabby_lite/config/theme.dart';
import 'package:cabby_lite/models/captain.dart';
import 'package:cabby_lite/models/trip.dart';
import 'package:cabby_lite/screens/captain_home_shell.dart';
import 'package:cabby_lite/state/location_service.dart';
import 'package:cabby_lite/state/ride_controller.dart';

void main() {
  test('QR scan payload signs a captain in and starts at the welcome phase', () {
    final ctrl = RideController();
    expect(ctrl.isLoggedIn, isFalse);

    ctrl.signInFromScan('cabby-captain:Bilal Ahmed|+92 321|car|ACX-472|White|4');

    expect(ctrl.isLoggedIn, isTrue);
    expect(ctrl.captain?.name, 'Bilal Ahmed');
    expect(ctrl.captain?.vehicleNumber, 'ACX-472');
    expect(ctrl.phase, RidePhase.welcome);
  });

  test('ride lifecycle moves welcome -> inProgress -> completed -> welcome', () {
    final ctrl = RideController()..signInFromScan('demo');
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

  test('a blank scan falls back to the demo captain rather than failing', () {
    final captain = Captain.fromScan('   ');
    expect(captain.name, isNotEmpty);
  });

  testWidgets('sign out returns to a logged-out controller', (tester) async {
    final ctrl = RideController()..signInFromScan('demo');
    expect(ctrl.isLoggedIn, isTrue);
    ctrl.signOut();
    expect(ctrl.isLoggedIn, isFalse);
    expect(ctrl.phase, RidePhase.welcome);
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

    final ctrl = RideController();
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
    await tester.pump();
  }

  // Logical sizes spanning the phone/tablet breakpoints, each way up.
  const sizes = <String, Size>{
    'phone portrait': Size(390, 844),
    'phone landscape': Size(844, 390),
    'tablet portrait (Tab A7)': Size(800, 1340),
    'tablet landscape (Tab A7)': Size(1340, 800),
    'large tablet landscape': Size(1280, 900),
  };

  sizes.forEach((label, size) {
    testWidgets('welcome (standby) lays out without overflow — $label',
        (tester) async {
      await pumpAt(tester, size, (c) => c.signInFromScan('demo'));
      expect(tester.takeException(), isNull);
      expect(find.text('Start next ride'), findsOneWidget);
    });

    testWidgets('ride summary lays out without overflow — $label',
        (tester) async {
      await pumpAt(tester, size, (c) {
        c.signInFromScan('demo');
        c.startTrip(Trip.sample());
        c.completeTrip();
      });
      expect(tester.takeException(), isNull);
      expect(find.text('Ride completed'), findsOneWidget);
    });
  });
}
