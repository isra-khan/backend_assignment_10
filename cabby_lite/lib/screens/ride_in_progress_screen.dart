import 'dart:async';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui
    show
        PictureRecorder,
        ImageByteFormat,
        ParagraphBuilder,
        ParagraphStyle,
        ParagraphConstraints;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:provider/provider.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../config/tone.dart';
import '../core/polyline.dart';
import '../models/trip.dart';
import '../state/location_service.dart';
import '../state/ride_controller.dart';
import '../widgets/round_button.dart';
import '../widgets/route_card.dart';
import '../widgets/status_pill.dart';

/// How the trip map frames the drive.
///
/// [overview] is the planning view — north-up, flat, with the whole route in
/// frame. [driving] is the heads-down navigation view — camera locked to the
/// car, rotated so the direction of travel is up, tilted into a 3D perspective
/// and zoomed to street level, with the chrome pared back to what a captain can
/// read at a glance while moving.
enum MapMode { overview, driving }

/// Live trip surface. Replaces the welcome screen the moment a ride starts: a
/// full-bleed Mapbox navigation map with the trip's route drawn on it, a live
/// car puck at the captain's position, and a bottom panel carrying rider
/// details.
///
/// The trip is ended from the captain's phone. This tablet is receive-only and
/// moves to the summary when `ride-ended` arrives, never from a tap here.
class RideInProgressScreen extends StatefulWidget {
  const RideInProgressScreen({super.key});

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  /// Width of the floating trip/nav card on a tablet.
  ///
  /// Shared by the panel itself and by the camera padding that has to steer the
  /// route clear of it — as two separate literals they drifted apart silently,
  /// and the map has no way to tell you the route is hidden behind a card.
  static const double _panelWidth = 460;

  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _points;
  mb.PolylineAnnotationManager? _lines;
  mb.PointAnnotation? _carAnnotation;
  StreamSubscription<GeoFix>? _locSub;

  /// Where the CAR starts — the backend's `captainPosition`, falling back to a
  /// device fix, and only to the trip's pickup when neither exists.
  ///
  /// Not the rider's pickup point: in a tracker vehicle the two can be
  /// kilometres apart. Anything drawn as "the pickup" must read
  /// `trip.pickupLocation` instead.
  GeoPoint? _carStart;

  // The car's current position — starts at [_carStart] and moves to the live
  // fix as soon as one arrives.
  GeoPoint? _carAt;

  /// The road already driven. Seeded from the ride's `locationHistory` and
  /// extended by every position the car reaches while this screen is up, so the
  /// trail keeps growing rather than freezing at whatever the backend last knew.
  List<GeoPoint> _trail = const [];

  /// The drawn trail, held so it can be updated in place. Null until there are
  /// enough points to make a line.
  mb.PolylineAnnotation? _trailLine;

  /// Watches the controller for tracker positions. Attached for the whole ride
  /// alongside [_locSub] — each no-ops while the other's source is the live
  /// one, so a `locationSource` arriving mid-ride switches the map over.
  VoidCallback? _trackerListener;

  /// Which way the map frames the drive. Starts in overview so the captain sees
  /// the whole job before setting off.
  MapMode _mode = MapMode.overview;

  /// Last known direction of travel, held across stationary fixes so the map
  /// doesn't snap back to north every time the car stops.
  double _bearing = 0;

  /// Straight-line metres left to the drop-off, refreshed on every GPS fix.
  /// Null until the first fix lands.
  double? _remainingMetres;

  /// Layout tokens captured from the last build.
  ///
  /// The camera helpers are async and run well after their frame, so an
  /// ancestor lookup there can hit a defunct element. Reading the tokens during
  /// build and holding them is the same trick [_controller] uses.
  AppLayout? _layout;

  bool get _driving => _mode == MapMode.driving;

  /// Camera zoom/pitch for the current mode. Driving pulls in close and tilts
  /// into perspective; overview stays flat and wide.
  double get _modeZoom => _driving ? 17 : 15;
  double get _modePitch => _driving ? 55 : 0;

  /// The controller, captured while the element tree is still stable.
  ///
  /// [dispose] must detach [_trackerListener], but an ancestor lookup there is
  /// illegal — the element is already deactivated and Flutter throws "Looking
  /// up a deactivated widget's ancestor is unsafe". Holding the reference from
  /// [didChangeDependencies] is the documented way round it.
  RideController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = context.read<RideController>();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    // The controller outlives this screen, so a listener left attached would
    // keep firing into a disposed State.
    final listener = _trackerListener;
    if (listener != null) {
      _controller?.removeListener(listener);
      _trackerListener = null;
    }
    super.dispose();
  }

  mb.Point _pt(GeoPoint g) =>
      mb.Point(coordinates: mb.Position(g.longitude, g.latitude));

  /// Camera padding that matches where the chrome actually sits.
  ///
  /// The previous constants (top 120, bottom 320) were tuned for a portrait
  /// phone, where the trip panel was a full-bleed sheet across the bottom of a
  /// tall screen. Landscape changed the geometry underneath them: on a tablet
  /// the panel is a floating [_panelWidth]-wide card at bottomLeft, so it
  /// covers the LEFT of the map for its own height, not a band across the whole
  /// bottom. Reserving 320px down there pushed the route up into the top third
  /// of a screen whose bottom two-thirds were clear map.
  ///
  /// Every inset is capped so the box Mapbox fits into stays comfortably
  /// positive — it frames the route inside `viewport - padding`, and an inset
  /// that swallows its axis leaves nothing to fit and yields a useless camera.
  /// Height is the scarce axis in landscape, so it gets the tighter third;
  /// width can afford the panel's full column and caps at half.
  mb.MbxEdgeInsets _mapPadding() {
    final layout = _layout;
    if (layout == null) {
      return mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);
    }

    double capV(double v) => v.clamp(0.0, layout.height / 3);
    double capH(double v) => v.clamp(0.0, layout.width / 2);

    return mb.MbxEdgeInsets(
      // Clears the chrome row and the nav banner sitting under it.
      top: capV(layout.scale(112)),
      // On a tablet the panel is beside the map rather than under it, so the
      // route has to clear its column instead of its height.
      left: capH(layout.isTablet ? _panelWidth + 32 : layout.scale(24)),
      bottom: capV(layout.scale(96)),
      right: capH(layout.scale(24)),
    );
  }

  /// Frame both the pickup and drop-off (plus the car if we have it) in view.
  /// In driving mode "recenter" means something different — snap back to the
  /// car rather than zooming out to the whole route — so this defers to
  /// [_cameraToCar] there.
  Future<void> _fitRoute(Trip trip) async {
    final map = _map;
    if (map == null) return;
    if (_driving) return _cameraToCar(animate: true);

    // Unset points are excluded: framing a (0, 0) placeholder alongside a real
    // one zooms out to span half the planet and the trip becomes a dot.
    //
    // The car is framed separately from the pickup — in a tracker vehicle they
    // can be kilometres apart, and the captain needs both in view to see how
    // far they are from the rider.
    final pts = [
      if (!trip.pickupLocation.isUnset) _pt(trip.pickupLocation),
      if (!trip.destinationLocation.isUnset) _pt(trip.destinationLocation),
      if (_carAt != null && !_carAt!.isUnset) _pt(_carAt!),
    ];
    // Nothing real to frame — leave the camera where it is rather than flying
    // it to null island.
    if (pts.isEmpty) return;
    final camera = await map.cameraForCoordinatesPadding(
      pts,
      mb.CameraOptions(bearing: 0, pitch: 0),
      _mapPadding(),
      null,
      null,
    );
    await map.flyTo(camera, mb.MapAnimationOptions(duration: 700));
  }

  /// Lock the camera onto the car at the current mode's zoom/pitch/bearing.
  ///
  /// The car is parked low in the frame in driving mode (via bottom padding) so
  /// most of the screen shows the road *ahead* rather than the road already
  /// driven — the standard turn-by-turn framing.
  Future<void> _cameraToCar({bool animate = true}) async {
    final map = _map;
    final at = _carAt;
    if (map == null || at == null) return;

    final camera = mb.CameraOptions(
      center: _pt(at),
      zoom: _modeZoom,
      pitch: _modePitch,
      bearing: _driving ? _bearing : 0,
      // Park the car low in frame so the screen shows the road ahead. A
      // fraction rather than a constant: the old 260 was about a third of a
      // portrait phone's height but two thirds of a landscape one, which drove
      // the car off the bottom edge instead of just lowering it.
      padding: _driving
          ? mb.MbxEdgeInsets(
              top: (_layout?.height ?? 0) * 0.35,
              left: 0,
              bottom: 0,
              right: 0,
            )
          : mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
    );

    if (animate) {
      await map.easeTo(camera, mb.MapAnimationOptions(duration: 600));
    } else {
      await map.setCamera(camera);
    }
  }

  /// Flip between overview and driving framing.
  Future<void> _toggleMode(Trip trip) async {
    setState(() {
      _mode = _driving ? MapMode.overview : MapMode.driving;
    });

    if (_driving) {
      // Entering driving mode before the car has ever moved leaves no heading
      // to steer by — aim down the route so the first frame still faces the
      // right way.
      if (_bearing == 0 && _carAt != null) {
        _bearing = LocationService.bearing(_carAt!, trip.destinationLocation);
      }
      await _cameraToCar(animate: true);
    } else {
      await _fitRoute(trip);
    }
  }

  /// Once the style is loaded, resolve the pickup to the captain's current GPS
  /// location, draw the route line + pickup/drop-off markers, place the car,
  /// then follow the live location.
  Future<void> _onMapReady(Trip trip, mb.MapboxMap map) async {
    _map = map;
    // Hide Mapbox's default scale/logo clutter from the driving surface.
    await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(mb.CompassSettings(enabled: false));

    _lines = await map.annotations.createPolylineAnnotationManager();
    _points = await map.annotations.createPointAnnotationManager();

    // Where the CAR starts. The backend's `captainPosition` is authoritative
    // and already loaded, so it draws the car correctly on frame 1 — including
    // in a tracker vehicle, where this tablet's own GPS is the wrong source
    // entirely. Only fall back to a local fix when the backend sent none, and
    // to the trip's pickup when there is no fix at all.
    // Captured reference, not `context.read`: this runs after the map style
    // has loaded, several awaits from where the widget was built.
    final ctrl = _controller;
    if (!mounted || ctrl == null) return;
    _carStart = ctrl.captainPosition ??
        (ctrl.usesDeviceGps ? await LocationService.current() : null) ??
        trip.pickupLocation;

    // The road already driven, drawn first so the route line above reads as
    // "still to go". Matters most after an ignition cycle mid-ride: without it
    // a trip twenty minutes in looks identical to one that just started.
    //
    // Two points minimum — a single fix is a dot, not a trail.
    _trail = List<GeoPoint>.of(trip.locationHistory);
    if (_trail.length >= 2) {
      _trailLine = await _lines!.create(mb.PolylineAnnotationOptions(
        geometry: mb.LineString(
          coordinates: _trail.map((p) => _pt(p).coordinates).toList(),
        ),
        lineColor: Palette.zinc950.toARGB32(),
        lineOpacity: 0.35,
        lineWidth: 4,
        lineJoin: mb.LineJoin.ROUND,
      ));
    }

    // Route line. The backend's encoded polyline follows the actual roads;
    // without one, fall back to a straight pickup → drop-off line so the
    // captain still sees the direction of travel.
    final route = Polyline.decode(trip.routePolyline);
    final hasRoad = route.length >= 2;
    if (kDebugMode) {
      final raw = trip.routePolyline;
      debugPrint(hasRoad
          ? '[map] route: ${route.length} points from routePolyline'
          : '[map] route: STRAIGHT LINE fallback — routePolyline '
              '${raw == null ? 'absent' : raw.isEmpty ? 'empty' : 'decoded to '
                  '${route.length} pt(s) from ${raw.length} chars'}');
    }
    // The straight-line fallback runs pickup → drop-off, the trip the rider
    // booked. Starting it at the car would draw a line the vehicle isn't going
    // to take, and in a tracker vehicle parked kilometres away it would point
    // in the wrong direction entirely.
    final straightLine = !trip.pickupLocation.isUnset &&
        !trip.destinationLocation.isUnset;
    if (hasRoad || straightLine) {
      await _lines!.create(mb.PolylineAnnotationOptions(
        geometry: mb.LineString(
          coordinates: hasRoad
              ? route.map((p) => _pt(p).coordinates).toList()
              : [
                  _pt(trip.pickupLocation).coordinates,
                  _pt(trip.destinationLocation).coordinates,
                ],
        ),
        lineColor: Palette.brand.toARGB32(),
        // Matches the phone app: 4px, rounded caps so the road geometry reads
        // as a drawn route rather than a hard-edged bar.
        lineWidth: 4,
        lineJoin: mb.LineJoin.ROUND,
      ));
    }

    // Pickup + drop-off pin markers. Skipped when the backend gave no usable
    // coordinate: a pin at (0, 0) is the Gulf of Guinea, which drags the camera
    // off the actual trip. The phone app does the same — no point, no pin.
    // Same glyphs the phone app uses: a brand-green origin ring for the pickup
    // and a red place pin for the drop-off, rather than text labels.
    //
    // Deliberately `trip.pickupLocation`, NOT `_pickup`: the latter is where
    // the CAR starts (captainPosition, falling back to a device fix), which is
    // only the pickup point by coincidence. Pinning it there put the "pickup"
    // marker on the car and left the rider's actual pickup unmarked.
    if (!trip.pickupLocation.isUnset) {
      await _points!.create(mb.PointAnnotationOptions(
        geometry: _pt(trip.pickupLocation),
        image: await _iconImage(Icons.trip_origin, color: Palette.brand),
        iconSize: 0.5,
      ));
    }
    if (!trip.destinationLocation.isUnset) {
      await _points!.create(mb.PointAnnotationOptions(
        geometry: _pt(trip.destinationLocation),
        image: await _iconImage(Icons.place, color: Palette.danger),
        iconSize: 0.6,
        // Anchor the pin's tip at the coordinate, not its centre — a place pin
        // points at the spot below it.
        iconAnchor: mb.IconAnchor.BOTTOM,
      ));
    }

    // Car puck — starts at the vehicle's last known position, then follows the
    // live feed (tracker fixes or this tablet's GPS).
    _carAt = _carStart;
    // Seed the banner's distance from the starting point so it reads sensibly
    // before the first live fix arrives. Meaningless without a real drop-off,
    // so it stays null there rather than reporting the distance to (0, 0).
    if (mounted && !trip.destinationLocation.isUnset) {
      setState(() {
        _remainingMetres = LocationService.distanceMetres(
          _carStart!,
          trip.destinationLocation,
        );
      });
    }
    await _placeCar();
    await _fitRoute(trip);
    // Both attach; each filters per fix on the live `locationSource`, so the
    // map follows the right source even when the answer arrives after this ran.
    // Only one ever acts at a time — the two guards are exact opposites.
    _followLocation(trip);
    _followTracker();
  }

  /// Extend the driven trail to [point] and redraw it.
  ///
  /// Ignores movement under [_trailMinMetres] so a car idling at a light doesn't
  /// accumulate hundreds of near-identical points from GPS jitter.
  Future<void> _extendTrail(GeoPoint point) async {
    final mgr = _lines;
    if (mgr == null) return;

    if (_trail.isNotEmpty &&
        LocationService.distanceMetres(_trail.last, point) < _trailMinMetres) {
      return;
    }

    _trail = [..._trail, point];
    if (_trail.length < 2) return;

    final coordinates = _trail.map((p) => _pt(p).coordinates).toList();
    final line = _trailLine;
    if (line == null) {
      // First time there are two points to join — the ride began with an empty
      // or single-entry history.
      _trailLine = await mgr.create(mb.PolylineAnnotationOptions(
        geometry: mb.LineString(coordinates: coordinates),
        lineColor: Palette.zinc950.toARGB32(),
        lineOpacity: 0.35,
        lineWidth: 4,
        lineJoin: mb.LineJoin.ROUND,
      ));
    } else {
      line.geometry = mb.LineString(coordinates: coordinates);
      await mgr.update(line);
    }
  }

  /// Below this, a new fix is GPS noise rather than travel. Matches the 5m
  /// distance filter the location stream itself uses.
  static const double _trailMinMetres = 5;

  /// Rasterise a Material icon into PNG bytes for use as a Mapbox marker.
  ///
  /// The phone app draws its pins as Flutter `Icon` widgets, but Mapbox's
  /// annotation API takes image bytes, so the same glyph is painted to a canvas
  /// here. Keeps the two apps visually identical without shipping a PNG per
  /// icon per density.
  Future<Uint8List> _iconImage(
    IconData icon, {
    required Color color,
    double size = 96,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: icon.fontFamily,
      fontSize: size,
    ))
      ..pushStyle(TextStyle(
        color: color,
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        // A white halo so a dark pin stays legible on a dark map tile.
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 3),
          Shadow(color: Colors.white, blurRadius: 6),
        ],
      ).getTextStyle())
      ..addText(String.fromCharCode(icon.codePoint));

    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size * 1.4));
    canvas.drawParagraph(paragraph, Offset.zero);

    final image = await recorder
        .endRecording()
        .toImage((size * 1.4).ceil(), (size * 1.3).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// Draw (or move) the car marker at [_carAt] using the bundled car image.
  Future<void> _placeCar() async {
    final mgr = _points;
    final at = _carAt;
    if (mgr == null || at == null) return;

    if (_carAnnotation == null) {
      final bytes = await rootBundle.load('assets/images/marker-car.png');
      _carAnnotation = await mgr.create(mb.PointAnnotationOptions(
        geometry: _pt(at),
        image: bytes.buffer.asUint8List(),
        // The source PNG is 256×118, so this renders ~102×47 logical px.
        iconSize: 0.4,
      ));
    } else {
      _carAnnotation!.geometry = _pt(at);
      await mgr.update(_carAnnotation!);
    }
  }

  /// Subscribe to live GPS and slide the car puck as the captain moves.
  ///
  /// Each fix also refreshes the distance-to-drop-off the nav banner reads
  /// from, and — in driving mode — steers the camera to the new heading so the
  /// map turns with the car.
  ///
  /// Only runs when this tablet IS the location source. In a tracker vehicle
  /// the car's position arrives over the socket as `my-location`, and the
  /// tablet's own GPS is a second, disagreeing opinion — following it would
  /// fight the authoritative one.
  void _followLocation(Trip trip) {
    _locSub?.cancel();
    _locSub = LocationService.fixStream().listen((fix) async {
      // Checked per fix, not once at subscribe time. `locationSource` is only
      // known after `/captain/active-ride` answers, which can land well after
      // this screen mounted off a `ride-started` socket event — so the choice
      // of source has to be re-made on every fix rather than frozen on the
      // first. Read through the captured controller rather than the context:
      // this fires from a stream that outlives the widget, and an ancestor
      // lookup on a defunct element throws.
      final ctrl = _controller;
      if (!mounted || ctrl == null || !ctrl.usesDeviceGps) return;

      _carAt = fix.point;
      // Hold the last good bearing when stationary; a parked car reports noise.
      if (fix.heading != null) _bearing = fix.heading!;

      final remaining = LocationService.distanceMetres(
        fix.point,
        trip.destinationLocation,
      );
      if (mounted) setState(() => _remainingMetres = remaining);

      await _placeCar();
      await _extendTrail(fix.point);
      await _cameraToCar(animate: true);
    });
  }

  /// Follow tracker positions pushed over the socket.
  ///
  /// The mirror of [_followLocation] for a tracker vehicle, where this tablet's
  /// GPS is not the source: `my-location` lands on the controller as
  /// `captainPosition`, and this moves the car and grows the trail off it so
  /// both sources drive the map through the same code.
  void _followTracker() {
    _trackerListener = () async {
      final ctrl = _controller;
      if (!mounted || ctrl == null) return;
      // The mirror of the guard in [_followLocation]: re-decided per
      // notification, so a `locationSource` that arrives after this screen
      // mounted switches the map over without needing a remount.
      if (ctrl.usesDeviceGps) return;

      final at = ctrl.captainPosition;
      // `identical` rather than ==: GeoPoint has no value equality, so this
      // only skips a repeat notification carrying the very same object. Real
      // de-duplication is the distance guard in _extendTrail.
      if (at == null || identical(at, _carAt)) return;

      // Aim the camera along the direction of travel; a tracker fix carries no
      // heading by the time it reaches the controller.
      final from = _carAt;
      if (from != null &&
          LocationService.distanceMetres(from, at) >= _trailMinMetres) {
        _bearing = LocationService.bearing(from, at);
      }
      _carAt = at;

      final trip = ctrl.trip;
      if (trip != null) {
        final remaining =
            LocationService.distanceMetres(at, trip.destinationLocation);
        if (mounted) setState(() => _remainingMetres = remaining);
      }

      await _placeCar();
      await _extendTrail(at);
      await _cameraToCar(animate: true);
    };
    // Attach through the same reference [dispose] will detach from, so the two
    // can never end up on different controller instances.
    _controller?.addListener(_trackerListener!);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RideController>();
    final trip = ctrl.trip;
    if (trip == null) return const SizedBox.shrink();
    final tone = context.tone;
    final layout = context.layout;
    // Held for the async camera helpers, which run after this frame and can't
    // safely look the tokens up themselves.
    _layout = layout;
    // On a tablet the trip panel and nav banner float as cards with a capped
    // width instead of spanning the whole screen; on a phone they stay full-
    // bleed as before. Phones resolve to the real screen width rather than
    // double.infinity — the panels sit inside an AnimatedSize, which sizes to
    // its child and would otherwise hand a `width: double.infinity` panel an
    // unbounded constraint.
    final panelMaxWidth = layout.isTablet ? _panelWidth : layout.width;

    return Scaffold(
      body: Stack(
        children: [
          mb.MapWidget(
            key: const ValueKey('trip-map'),
            cameraOptions: mb.CameraOptions(
              center: _pt(trip.pickupLocation),
              zoom: 12,
            ),
            styleUri: tone.isDark
                ? mb.MapboxStyles.DARK
                : mb.MapboxStyles.MAPBOX_STREETS,
            onMapCreated: (map) => _onMapReady(trip, map),
          ),

          // Top chrome: recenter + live status + drive-mode toggle. The status
          // pill is noise while driving, so it drops out of the row there.
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(layout.scale(12)),
              child: Row(
                children: [
                  RoundButton(
                    icon: _driving
                        ? Icons.my_location
                        : Icons.center_focus_strong,
                    onTap: () => _fitRoute(trip),
                  ),
                  const Spacer(),
                  if (!_driving)
                    const StatusPill(online: true, label: 'On trip · en route'),
                  const Spacer(),
                  _ModeButton(
                    driving: _driving,
                    onTap: () => _toggleMode(trip),
                  ),
                ],
              ),
            ),
          ),

          // Turn banner near the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                // Clears the chrome row above: a RoundButton (scale(10) padding
                // either side of a scale(20) icon) inside scale(12) padding.
                // Derived rather than a flat 60 — that was the height of
                // portrait phone chrome and left a gap once type scaled up.
                padding: EdgeInsets.fromLTRB(
                  layout.scale(12),
                  layout.scale(12) * 2 + layout.scale(40),
                  layout.scale(12),
                  0,
                ),
                child: Align(
                  alignment: layout.isTablet
                      ? Alignment.topLeft
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: panelMaxWidth),
                    child: _NavBanner(
                      trip: trip,
                      driving: _driving,
                      remainingMetres: _remainingMetres,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Align(
            // Anchor the panel bottom-left on tablets so it reads as a floating
            // control card beside the map, not a full-width sheet.
            alignment:
                layout.isTablet ? Alignment.bottomLeft : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(layout.isTablet ? 16 : 0),
              // A hard width, not just a max: AnimatedSize measures its child
              // against unbounded width, which an interior Row with a flexible
              // child (or a Spacer) cannot resolve. Pinning the width here
              // keeps the cross-fade between the two panels animating the
              // height only, which is all that should change anyway.
              child: SizedBox(
                // Tablets: the capped floating-card width. Phones: full-bleed
                // (the surrounding padding is zero there).
                width: layout.isTablet ? panelMaxWidth : layout.width,
                // Driving mode swaps the full rider/route panel for a compact
                // strip — the captain's eyes belong on the road, and the map
                // gets the space back.
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: _driving
                      ? DrivingPanel(
                          trip: trip,
                          floating: layout.isTablet,
                          remainingMetres: _remainingMetres,
                        )
                      : TripPanel(
                          trip: trip,
                          floating: layout.isTablet,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Format a metre distance the way a nav banner should read: coarse in
/// kilometres far out, sharpening to rounded metres on approach.
String _formatDistance(double metres) {
  if (metres >= 10000) return '${(metres / 1000).round()} km';
  if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(1)} km';
  if (metres >= 100) return '${(metres / 100).round() * 100} m';
  return '${(metres / 10).round() * 10} m';
}

/// The turn instruction across the top of the map. In driving mode it grows
/// into the primary heads-up element — bigger type, a live distance readout —
/// since it's the one thing a moving captain should be able to read at a
/// glance.
class _NavBanner extends StatelessWidget {
  const _NavBanner({
    required this.trip,
    this.driving = false,
    this.remainingMetres,
  });

  final Trip trip;
  final bool driving;
  final double? remainingMetres;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final distance = remainingMetres;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: layout.scale(14),
        vertical: layout.scale(driving ? 16 : 12),
      ),
      decoration: BoxDecoration(
        color: Palette.brand,
        borderRadius: BorderRadius.circular(16),
        boxShadow: tone.shadow(blur: driving ? 24 : 16),
      ),
      child: Row(
        children: [
          Icon(Icons.turn_slight_right,
              color: Colors.white, size: layout.scale(driving ? 38 : 30)),
          SizedBox(width: layout.scale(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Driving leads with the distance-to-go; overview leads with
                // the plain instruction.
                Text(
                  driving && distance != null
                      ? _formatDistance(distance)
                      : 'Head toward the drop-off',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: layout.scale(driving ? 24 : 15),
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: layout.scale(driving ? 3 : 0)),
                Text(
                  trip.destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: layout.scale(driving ? 13 : 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The overview ⇄ driving toggle that floats top-right over the map.
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.driving, required this.onTap});

  final bool driving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    // Active driving mode reads as a filled brand chip so the captain can tell
    // at a glance which framing they're in.
    final background = driving ? Palette.brand : tone.card;
    final foreground = driving ? Colors.white : tone.ink;

    return Material(
      color: background,
      shape: const StadiumBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.scale(12),
            vertical: layout.scale(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(driving ? Icons.navigation : Icons.navigation_outlined,
                  size: layout.scale(16), color: foreground),
              SizedBox(width: layout.scale(6)),
              Text(
                driving ? 'Driving' : 'Drive',
                style: TextStyle(
                  color: foreground,
                  fontSize: layout.scale(12),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pared-back bottom strip shown while driving: distance/ETA, the rider's
/// name and a call button. Everything else (fare breakdown, full route card,
/// chat) waits for overview mode.
///
/// The ride is ended by the captain's phone, not here — this tablet is a
/// receive-only device and learns the trip is over from `ride-ended`.
///
/// Public only so the layout tests can render it without a Mapbox platform
/// view; nothing outside this file should build it directly.
@visibleForTesting
class DrivingPanel extends StatelessWidget {
  const DrivingPanel({
    super.key,
    required this.trip,
    this.remainingMetres,
    this.floating = false,
  });

  final Trip trip;
  final double? remainingMetres;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final distance = remainingMetres;

    return Container(
      // Fills the width its parent allots. Without this the Container sizes to
      // its child, handing the Row below an unbounded width that its flexible
      // child can't resolve.
      width: double.infinity,
      decoration: BoxDecoration(
        color: tone.card,
        borderRadius: floating
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: !floating,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.scale(16),
            vertical: layout.scale(12),
          ),
          child: Row(
            children: [
              // Expanded rather than a trailing Spacer: this row is measured at
              // unbounded width by the AnimatedSize that wraps the panel, and a
              // Spacer contributes no intrinsic width — the button after it
              // would be handed an infinite constraint. Flexing the text block
              // also lets the rider name ellipsize instead of overflowing.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distance != null
                          ? _formatDistance(distance)
                          : '${trip.km.toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontSize: layout.scale(20),
                        fontWeight: FontWeight.w800,
                        color: tone.brand,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '${trip.minutes} min · ${trip.riderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: layout.scale(12), color: tone.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: layout.scale(12)),
              _CircleAction(icon: Icons.call, onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pre-drive panel: rider, fare, and the route's two ends.
///
/// Public only so the layout tests can render it without a Mapbox platform
/// view; nothing outside this file should build it directly.
@visibleForTesting
class TripPanel extends StatelessWidget {
  const TripPanel({
    super.key,
    required this.trip,
    this.floating = false,
  });
  final Trip trip;

  /// When true the panel is a fully-rounded floating card (tablet); otherwise a
  /// full-width bottom sheet rounded only at the top (phone).
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tone.card,
        borderRadius: floating
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: !floating,
        child: Padding(
          padding: EdgeInsets.all(layout.scale(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trip meta chips, then the fare hard right.
              //
              // The fare is Flexible, not the chips: at tablet scale a
              // four-figure "PKR 1100" at scale(20)/w800 is the widest thing in
              // the row by some margin, and it was pushing the chips off the
              // 460 card. It ellipsizes rather than overflow, while the chips
              // keep their (short, fixed) labels intact.
              Row(
                children: [
                  _chip(tone, layout, Icons.route,
                      '${trip.km.toStringAsFixed(1)} km'),
                  SizedBox(width: layout.scale(8)),
                  _chip(tone, layout, Icons.schedule, '${trip.minutes} min'),
                  SizedBox(width: layout.scale(8)),
                  Expanded(
                    child: Text(
                      'PKR ${trip.fare}',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: layout.scale(20),
                        fontWeight: FontWeight.w800,
                        color: tone.brand,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.scale(14)),

              // Rider row.
              Row(
                children: [
                  CircleAvatar(
                    radius: layout.scale(20),
                    backgroundColor: Palette.brand,
                    child: Text(
                      trip.riderInitials,
                      style: TextStyle(
                          color: Colors.white, fontSize: layout.scale(14)),
                    ),
                  ),
                  SizedBox(width: layout.scale(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.riderName,
                          style: TextStyle(
                              fontSize: layout.scale(16),
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          trip.riderPhone,
                          style: TextStyle(
                              fontSize: layout.scale(12), color: tone.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.scale(14)),

              RouteCard(pickup: trip.pickup, destination: trip.destination),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(AppTone tone, AppLayout layout, IconData icon, String text) =>
      Container(
        padding: EdgeInsets.symmetric(
            horizontal: layout.scale(10), vertical: layout.scale(6)),
        decoration: BoxDecoration(
          color: tone.fill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: layout.scale(13), color: tone.muted),
            SizedBox(width: layout.scale(5)),
            Text(text,
                style: TextStyle(
                    fontSize: layout.scale(12),
                    fontWeight: FontWeight.w600,
                    color: tone.ink)),
          ],
        ),
      );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    return Material(
      color: tone.brandWash,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(layout.scale(10)),
          child: Icon(icon, size: layout.scale(18), color: tone.brand),
        ),
      ),
    );
  }
}
