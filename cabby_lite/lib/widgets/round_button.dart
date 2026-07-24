import 'package:flutter/material.dart';

import '../config/layout.dart';
import '../config/tone.dart';

/// Circular icon button that floats over the map (menu, close, recenter),
/// ported from the main Cabby captain home.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    return Material(
      color: tone.card,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(layout.scale(10)),
          child: Icon(icon, size: layout.scale(20), color: tone.ink),
        ),
      ),
    );
  }
}

/// White-on-brand button spinner used inside filled buttons while busy.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}
