import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/ride_controller.dart';
import 'qr_login_screen.dart';
import 'ride_in_progress_screen.dart';
import 'ride_summary_screen.dart';
import 'welcome_screen.dart';

/// Top-level surface for a signed-in captain. Swaps between the three ride
/// faces with a cross-fade so the transitions
/// Welcome → Ride in Progress → Ride Completed feel smooth. Before sign-in it
/// shows the QR login (the only entry point).
class CaptainHomeShell extends StatelessWidget {
  const CaptainHomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RideController>();

    if (!ctrl.isLoggedIn) {
      return const QrLoginScreen();
    }

    final Widget face = switch (ctrl.phase) {
      RidePhase.welcome => const WelcomeScreen(key: ValueKey('welcome')),
      RidePhase.inProgress =>
        const RideInProgressScreen(key: ValueKey('in_progress')),
      RidePhase.completed =>
        const RideSummaryScreen(key: ValueKey('completed')),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: face,
    );
  }
}
