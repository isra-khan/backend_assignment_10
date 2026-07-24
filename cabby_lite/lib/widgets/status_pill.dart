import 'package:flutter/material.dart';

import '../config/layout.dart';
import '../config/palette.dart';

/// The online/offline status pill from the main Cabby captain home. A green
/// dot-and-label chip that floats over the map.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.online, this.label});

  final bool online;

  /// Overrides the default "Online · accepting rides" / "Offline" copy.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: layout.scale(12), vertical: layout.scale(7)),
      decoration: BoxDecoration(
        color: online ? Palette.brand : const Color(0xE6111111),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: layout.scale(6),
            height: layout.scale(6),
            decoration: BoxDecoration(
              color: online ? Colors.white : Colors.white54,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: layout.scale(6)),
          Text(
            label ?? (online ? 'Online · accepting rides' : 'Offline'),
            style: TextStyle(
              color: Colors.white,
              fontSize: layout.scale(11),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
