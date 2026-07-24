import 'package:flutter/material.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../config/tone.dart';

/// Pickup → drop-off summary card, ported from the main Cabby app's captain
/// panel so the trip route reads identically here.
class RouteCard extends StatelessWidget {
  const RouteCard({super.key, required this.pickup, required this.destination});

  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    return Container(
      padding: EdgeInsets.all(layout.scale(12)),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _row(tone, layout, Palette.brandAccent, 'Pickup', pickup),
          Divider(height: layout.scale(12)),
          _row(tone, layout, Palette.danger, 'Drop off', destination),
        ],
      ),
    );
  }

  Widget _row(AppTone tone, AppLayout layout, Color dot, String label,
          String value) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: layout.scale(4)),
            child: Container(
              width: layout.scale(10),
              height: layout.scale(10),
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          SizedBox(width: layout.scale(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: tone.muted, fontSize: layout.scale(11))),
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: layout.scale(14))),
              ],
            ),
          ),
        ],
      );
}
