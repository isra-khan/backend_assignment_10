import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../config/tone.dart';
import '../models/captain.dart';
import '../state/ride_controller.dart';
import '../widgets/brand_logo.dart';
import '../widgets/status_pill.dart';

/// The default home surface when there is no active ride. Greets the captain,
/// shows their standby status and vehicle, and waits for a trip to start.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final ctrl = context.watch<RideController>();
    final captain = ctrl.captain;
    final name = captain?.name ?? 'Captain';

    // On a wide tablet the standby hero sits alongside the vehicle +
    // instructions rather than stacking, so the extra width is used.
    final twoColumn = layout.isWide;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: layout.pagePadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: twoColumn ? 920 : layout.contentMaxWidth,
                    minHeight:
                        constraints.maxHeight - layout.pagePadding.vertical,
                  ),
                  // IntrinsicHeight gives the Column a bounded height even
                  // inside the (vertically unbounded) scroll view, so the
                  // Spacer below can resolve and pin the button to the bottom
                  // when the content is shorter than the viewport.
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar: logo + sign out.
                        Row(
                          children: [
                            BrandLogo(height: layout.scale(28)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Sign out',
                              onPressed: () => ctrl.signOut(),
                              icon: Icon(Icons.logout, color: tone.muted),
                            ),
                          ],
                        ),
                        SizedBox(height: layout.scale(8)),
                        const StatusPill(online: true),
                        SizedBox(height: layout.scale(28)),

                        // Greeting.
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                              fontSize: layout.scale(16), color: tone.muted),
                        ),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: layout.scale(30),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: layout.scale(20)),

                        if (twoColumn)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _StandbyCard()),
                                SizedBox(width: layout.gap),
                                Expanded(
                                  child: Column(
                                    children: [
                                      if (captain != null)
                                        _VehicleCard(captain: captain),
                                      if (captain != null)
                                        SizedBox(height: layout.gap),
                                      _InstructionsCard(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          _StandbyCard(),
                          SizedBox(height: layout.gap),
                          if (captain != null) _VehicleCard(captain: captain),
                          if (captain != null) SizedBox(height: layout.gap),
                          _InstructionsCard(),
                        ],

                        // Nothing follows the cards: a ride starts from a
                        // `ride-started` socket event, never from a tap here.
                        // The Spacer keeps the content top-aligned in a tall
                        // viewport rather than stretching to fill it.
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StandbyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(layout.scale(20)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Palette.brand, Palette.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Palette.brand.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _PulseDot(),
              SizedBox(width: layout.scale(8)),
              Text(
                'READY FOR RIDES',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: layout.scale(11),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: layout.scale(14)),
          Text(
            "You're online and waiting for your next trip.",
            style: TextStyle(
              color: Colors.white,
              fontSize: layout.scale(18),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: layout.scale(6)),
          Text(
            'Keep the app open — the map opens automatically when a ride begins.',
            style: TextStyle(
                color: Colors.white70, fontSize: layout.scale(13), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6 * (1 - _anim.value)),
                blurRadius: 4 + _anim.value * 8,
                spreadRadius: _anim.value * 4,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.captain});
  final Captain captain;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    return Container(
      padding: EdgeInsets.all(layout.scale(14)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.ring),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/marker-${captain.vehicleType}.png',
            height: layout.scale(40),
            errorBuilder: (_, _, _) =>
                Icon(Icons.directions_car, color: tone.brand),
          ),
          SizedBox(width: layout.scale(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  captain.vehicleNumber.isNotEmpty
                      ? captain.vehicleNumber
                      : '—',
                  style: TextStyle(
                      fontSize: layout.scale(14),
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  '${captain.vehicleColor} ${captain.vehicleType} · ${captain.seats} seats'
                      .trim(),
                  style: TextStyle(
                      fontSize: layout.scale(12), color: tone.muted),
                ),
              ],
            ),
          ),
          Text(
            'VERIFIED',
            style: TextStyle(
              fontSize: layout.scale(10),
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: tone.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    Widget step(IconData icon, String text) => Padding(
          padding: EdgeInsets.symmetric(vertical: layout.scale(6)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: layout.scale(14),
                backgroundColor: tone.brandWash,
                child: Icon(icon, size: layout.scale(14), color: tone.brand),
              ),
              SizedBox(width: layout.scale(12)),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                      fontSize: layout.scale(13),
                      color: tone.ink,
                      height: 1.35),
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(layout.scale(16)),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHILE YOU WAIT',
            style: TextStyle(
              fontSize: layout.scale(10),
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: tone.muted,
            ),
          ),
          SizedBox(height: layout.scale(6)),
          step(Icons.location_on, 'Your location is shared with the Cabby '
              'centre while you are online.'),
          step(Icons.navigation, 'When a ride starts, turn-by-turn navigation '
              'opens on the map.'),
          step(Icons.qr_code_2, 'At drop-off, show the rider your payment QR to '
              'settle the fare.'),
        ],
      ),
    );
  }
}
