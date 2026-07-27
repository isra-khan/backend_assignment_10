import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/palette.dart';
import '../core/device_token_store.dart';
import '../state/pairing_controller.dart';
import '../state/ride_controller.dart';
import 'device_pairing_screen.dart';
import 'ride_in_progress_screen.dart';
import 'ride_summary_screen.dart';
import 'welcome_screen.dart';

/// Top-level surface. Decides between pairing and the ride faces, and swaps
/// between the three ride faces with a cross-fade so the transitions
/// Welcome → Ride in Progress → Ride Completed feel smooth.
///
/// A paired tablet skips the QR entirely: the device token lasts a year, so
/// pairing is a one-time event per vehicle, not a per-shift or per-ride step.
class CaptainHomeShell extends StatefulWidget {
  const CaptainHomeShell({super.key});

  @override
  State<CaptainHomeShell> createState() => _CaptainHomeShellState();
}

class _CaptainHomeShellState extends State<CaptainHomeShell> {
  // False while the keystore read is in flight — the app must not flash the QR
  // at an already-paired tablet on every ignition cycle.
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final token = await DeviceTokenStore.token();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      context.read<RideController>().restorePairing();
    }
    setState(() => _restored = true);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RideController>();

    if (!_restored) {
      return const Scaffold(
        backgroundColor: Palette.zinc950,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!ctrl.isPaired) {
      // Scope the controller to this screen so a re-pair after revocation
      // starts from a clean loop rather than a disposed one.
      return ChangeNotifierProvider(
        create: (_) => PairingController(),
        child: Consumer<PairingController>(
          builder: (context, pairing, child) {
            if (pairing.phase == PairingPhase.linked) {
              // Defer: we're inside build, and this notifies RideController.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                context.read<RideController>().signInFromPairing(
                      pairing.captain,
                    );
              });
            }
            return child!;
          },
          child: const DevicePairingScreen(),
        ),
      );
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
