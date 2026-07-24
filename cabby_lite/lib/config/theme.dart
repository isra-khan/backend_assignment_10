import 'package:flutter/material.dart';
import 'palette.dart';

/// Light + dark themes, ported from the main Cabby app so the captain companion
/// stays in visual step with the rider/captain app.
///
/// Type is Inter: it holds up at the small sizes this app leans on (fares, ETA
/// chips) and ships tabular figures. Bundled in pubspec, not fetched at runtime.
class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.brand,
      primary: Palette.brand,
      brightness: Brightness.light,
    );
    return _base(scheme, Palette.surface, Palette.surfaceMuted, Palette.brandInk);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.brand,
      primary: Palette.brandAccent,
      brightness: Brightness.dark,
    );
    return _base(scheme, Palette.zinc950, Palette.zinc900, Palette.zinc100);
  }

  static ThemeData _base(
    ColorScheme scheme,
    Color scaffold,
    Color card,
    Color onSurface,
  ) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      cardColor: card,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(letterSpacing: -0.5),
        headlineMedium: TextStyle(letterSpacing: -0.4),
        headlineSmall: TextStyle(letterSpacing: -0.3),
        titleLarge: TextStyle(letterSpacing: -0.2),
      ).apply(bodyColor: onSurface, displayColor: onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
