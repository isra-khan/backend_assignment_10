import 'package:flutter/material.dart';

import 'palette.dart';

/// Theme-aware surface tokens, ported from the main Cabby app.
///
/// [Palette] holds raw brand values, several of which only work on a light
/// background — `surfaceMuted` fills and `surfaceRing` borders vanish in dark
/// mode, and `brandInk` text goes invisible on it. Widgets should reach for
/// these tokens instead of the raw palette so both themes stay correct.
///
/// Usage: `final tone = context.tone;` then `tone.muted`, `tone.ring`, etc.
class AppTone {
  const AppTone._(this.isDark, this.card, this.ink);

  factory AppTone.of(BuildContext context) {
    final theme = Theme.of(context);
    return AppTone._(
      theme.brightness == Brightness.dark,
      theme.cardColor,
      theme.textTheme.bodyLarge?.color ?? Palette.brandInk,
    );
  }

  final bool isDark;

  /// Card / sheet background.
  final Color card;

  /// Primary body text.
  final Color ink;

  /// Secondary text and inactive icons.
  Color get muted => isDark ? Palette.zinc400 : Palette.brandMuted;

  /// Hairline borders and dividers.
  Color get ring => isDark ? Palette.zinc700 : Palette.surfaceRing;

  /// Subtle filled backgrounds (chips, inset rows, search bars).
  Color get fill => isDark ? Palette.zinc800 : Palette.surfaceMuted;

  /// The page behind the cards.
  Color get scaffold => isDark ? Palette.zinc950 : Palette.surface;

  /// Brand-tinted selection background.
  Color get activeFill =>
      isDark ? Palette.brand.withValues(alpha: 0.16) : const Color(0xFFF2F8F4);

  /// Brand colour that stays legible on the current background — the deep
  /// green disappears against dark surfaces, so lift to the accent there.
  Color get brand => isDark ? Palette.brandAccent : Palette.brand;

  /// A brand wash for icon tiles and badges.
  Color get brandWash => brand.withValues(alpha: isDark ? 0.18 : 0.12);

  /// Elevation shadow — heavier on light, near-invisible on dark surfaces.
  List<BoxShadow> shadow({double blur = 20, Offset offset = const Offset(0, 6)}) =>
      [
        BoxShadow(
          color: Color(isDark ? 0x66000000 : 0x1A000000),
          blurRadius: blur,
          offset: offset,
        ),
      ];
}

extension AppToneContext on BuildContext {
  /// Theme-aware surface tokens for the current context.
  AppTone get tone => AppTone.of(this);
}
