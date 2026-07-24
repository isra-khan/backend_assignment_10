import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:provider/provider.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../config/tone.dart';
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
/// car puck at the captain's GPS location, and a bottom panel carrying rider
/// details and the "End ride" action.
class RideInProgressScreen extends StatefulWidget {
  const RideInProgressScreen({super.key});

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _points;
  mb.PolylineAnnotationManager? _lines;
  mb.PointAnnotation? _carAnnotation;
  StreamSubscription<GeoFix>? _locSub;

  // The pickup point — resolved to the captain's current GPS location when the
  // trip starts (falls back to the trip's stored pickup with no fix).
  GeoPoint? _pickup;

  // The car's current position — starts at the pickup and moves to the live
  // GPS fix as soon as one arrives.
  GeoPoint? _carAt;
  bool _ending = false;

  /// Which way the map frames the drive. Starts in overview so the captain sees
  /// the whole job before setting off.
  MapMode _mode = MapMode.overview;

  /// Last known direction of travel, held across stationary fixes so the map
  /// doesn't snap back to north every time the car stops.
  double _bearing = 0;

  /// Straight-line metres left to the drop-off, refreshed on every GPS fix.
  /// Null until the first fix lands.
  double? _remainingMetres;

  bool get _driving => _mode == MapMode.driving;

  /// Camera zoom/pitch for the current mode. Driving pulls in close and tilts
  /// into perspective; overview stays flat and wide.
  double get _modeZoom => _driving ? 17 : 15;
  double get _modePitch => _driving ? 55 : 0;

  @override
  void dispose() {
    _locSub?.cancel();
    super.dispose();
  }

  mb.Point _pt(GeoPoint g) =>
      mb.Point(coordinates: mb.Position(g.longitude, g.latitude));

  /// Frame both the pickup and drop-off (plus the car if we have it) in view.
  /// In driving mode "recenter" means something different — snap back to the
  /// car rather than zooming out to the whole route — so this defers to
  /// [_cameraToCar] there.
  Future<void> _fitRoute(Trip trip) async {
    final map = _map;
    if (map == null) return;
    if (_driving) return _cameraToCar(animate: true);

    final pts = [
      _pt(_pickup ?? trip.pickupLocation),
      _pt(trip.destinationLocation),
      if (_carAt != null) _pt(_carAt!),
    ];
    final camera = await map.cameraForCoordinatesPadding(
      pts,
      mb.CameraOptions(bearing: 0, pitch: 0),
      mb.MbxEdgeInsets(top: 120, left: 48, bottom: 320, right: 48),
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
      padding: _driving
          ? mb.MbxEdgeInsets(top: 260, left: 0, bottom: 0, right: 0)
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

    // Pickup is the captain's current location (fall back to the trip's stored
    // pickup only when there's no GPS fix), so the route starts from where the
    // captain actually is.
    _pickup = await LocationService.current() ?? trip.pickupLocation;

    // Route line pickup → drop-off.
    await _lines!.create(mb.PolylineAnnotationOptions(
      geometry: mb.LineString(coordinates: [
        _pt(_pickup!).coordinates,
        _pt(trip.destinationLocation).coordinates,
      ]),
      lineColor: Palette.brand.toARGB32(),
      lineWidth: 5,
      lineJoin: mb.LineJoin.ROUND,
    ));

    // Pickup + drop-off pin markers.
    await _points!.create(mb.PointAnnotationOptions(
      geometry: _pt(_pickup!),
      textField: 'Pickup',
      textOffset: [0, -2],
      textColor: Palette.brandAccent.toARGB32(),
      iconColor: Palette.brandAccent.toARGB32(),
      iconSize: 1.4,
    ));
    await _points!.create(mb.PointAnnotationOptions(
      geometry: _pt(trip.destinationLocation),
      textField: 'Drop off',
      textOffset: [0, -2],
      textColor: Palette.danger.toARGB32(),
      iconColor: Palette.danger.toARGB32(),
      iconSize: 1.4,
    ));

    // Car puck — starts at the pickup (the current location), then follows GPS.
    _carAt = _pickup;
    // Seed the banner's distance from the starting point so it reads sensibly
    // before the first live fix arrives.
    if (mounted) {
      setState(() {
        _remainingMetres = LocationService.distanceMetres(
          _pickup!,
          trip.destinationLocation,
        );
      });
    }
    await _placeCar();
    await _fitRoute(trip);
    _followLocation(trip);
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
        iconSize: 0.7,
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
  void _followLocation(Trip trip) {
    _locSub?.cancel();
    _locSub = LocationService.fixStream().listen((fix) async {
      _carAt = fix.point;
      // Hold the last good bearing when stationary; a parked car reports noise.
      if (fix.heading != null) _bearing = fix.heading!;

      final remaining = LocationService.distanceMetres(
        fix.point,
        trip.destinationLocation,
      );
      if (mounted) setState(() => _remainingMetres = remaining);

      await _placeCar();
      await _cameraToCar(animate: true);
    });
  }

  Future<void> _end(RideController ctrl) async {
    setState(() => _ending = true);
    // Small pause so the button reads as doing work, then hand off to summary.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    ctrl.completeTrip();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RideController>();
    final trip = ctrl.trip;
    if (trip == null) return const SizedBox.shrink();
    final tone = context.tone;
    final layout = context.layout;
    // On a tablet the trip panel and nav banner float as cards with a capped
    // width instead of spanning the whole screen; on a phone they stay full-
    // bleed as before.
    final panelMaxWidth = layout.isTablet ? 460.0 : double.infinity;

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
              padding: const EdgeInsets.all(12),
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
                padding: const EdgeInsets.fromLTRB(12, 60, 12, 0),
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
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: panelMaxWidth),
                // Driving mode swaps the full rider/route panel for a compact
                // strip — the captain's eyes belong on the road, and the map
                // gets the space back.
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: _driving
                      ? _DrivingPanel(
                          trip: trip,
                          busy: _ending,
                          floating: layout.isTablet,
                          remainingMetres: _remainingMetres,
                          onEnd: () => _end(ctrl),
                        )
                      : _TripPanel(
                          trip: trip,
                          busy: _ending,
                          floating: layout.isTablet,
                          onEnd: () => _end(ctrl),
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
/// name, a call button and "End ride". Everything else (fare breakdown, full
/// route card, chat) waits for overview mode.
class _DrivingPanel extends StatelessWidget {
  const _DrivingPanel({
    required this.trip,
    required this.busy,
    required this.onEnd,
    this.remainingMetres,
    this.floating = false,
  });

  final Trip trip;
  final bool busy;
  final VoidCallback onEnd;
  final double? remainingMetres;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final distance = remainingMetres;

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
          padding: EdgeInsets.symmetric(
            horizontal: layout.scale(16),
            vertical: layout.scale(12),
          ),
          child: Row(
            children: [
              Column(
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
              SizedBox(width: layout.scale(12)),
              _CircleAction(icon: Icons.call, onTap: () {}),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.danger,
                  padding:
                      EdgeInsets.symmetric(horizontal: layout.scale(20)),
                ),
                onPressed: busy ? null : onEnd,
                child: busy ? const ButtonSpinner() : const Text('End ride'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripPanel extends StatelessWidget {
  const _TripPanel({
    required this.trip,
    required this.busy,
    required this.onEnd,
    this.floating = false,
  });
  final Trip trip;
  final bool busy;
  final VoidCallback onEnd;

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
              // Trip meta chips.
              Row(
                children: [
                  _chip(tone, layout, Icons.route,
                      '${trip.km.toStringAsFixed(1)} km'),
                  SizedBox(width: layout.scale(8)),
                  _chip(tone, layout, Icons.schedule, '${trip.minutes} min'),
                  const Spacer(),
                  Text(
                    'PKR ${trip.fare}',
                    style: TextStyle(
                      fontSize: layout.scale(20),
                      fontWeight: FontWeight.w800,
                      color: tone.brand,
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
                  _CircleAction(
                    icon: Icons.call,
                    onTap: () {},
                  ),
                  SizedBox(width: layout.scale(8)),
                  _CircleAction(
                    icon: Icons.chat_bubble_outline,
                    onTap: () {},
                  ),
                ],
              ),
              SizedBox(height: layout.scale(14)),

              RouteCard(pickup: trip.pickup, destination: trip.destination),
              SizedBox(height: layout.scale(14)),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: Palette.danger),
                  onPressed: busy ? null : onEnd,
                  child: busy ? const ButtonSpinner() : const Text('End ride'),
                ),
              ),
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
