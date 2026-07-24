import 'package:flutter/material.dart';

/// Brand palette, ported verbatim from the main Cabby Mobile app (which in turn
/// mirrors the web app's tailwind.config.js) so all three surfaces look
/// identical.
class Palette {
  static const brand = Color(0xFF0A7C42);
  static const brandDark = Color(0xFF065C30);
  static const brandAccent = Color(0xFF27C281);
  static const brandInk = Color(0xFF16241F);
  static const brandMuted = Color(0xFF5E6E68);

  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF3F6F4);
  static const surfaceRing = Color(0xFFE3EBE5);

  // Dark-mode surfaces (tailwind zinc scale the web app uses).
  static const zinc950 = Color(0xFF09090B);
  static const zinc900 = Color(0xFF18181B);
  static const zinc800 = Color(0xFF27272A);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc100 = Color(0xFFF4F4F5);

  static const danger = Color(0xFFDC2626);
}
