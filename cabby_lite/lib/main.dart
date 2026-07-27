import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show MapboxOptions;
import 'package:provider/provider.dart';

import 'config/env.dart';
import 'config/layout.dart';
import 'config/palette.dart';
import 'config/theme.dart';
import 'screens/captain_home_shell.dart';
import 'state/ride_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // lib/.env carries the Mapbox token and the backend URL. Load it before
  // runApp: the map renders blank without the token, and pairing can't start
  // without the server URL.
  await dotenv.load(fileName: 'lib/.env');
  if (Env.mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(Env.mapboxToken);
  }
  runApp(const CabbyCaptainApp());
}

/// Cabby Lite — the in-car tablet companion. Pairs to a captain by displaying a
/// QR their phone scans, then runs receive-only for the rest of its life.
/// Shares the Cabby Mobile design system (Palette, AppTone, AppTheme, Inter) so
/// it reads as part of the same product family.
class CabbyCaptainApp extends StatelessWidget {
  const CabbyCaptainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RideController(),
      child: MaterialApp(
        title: 'Cabby Captain',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        // Lift primary-button height and label size on tablets. The base theme
        // is phone-tuned (52dp / 16sp); on a tablet those read small, so the
        // filled-button style is re-scaled per-device here where a MediaQuery
        // is available (the static AppTheme getters have no BuildContext).
        builder: (context, child) {
          final layout = context.layout;
          if (!layout.isTablet || child == null) return child ?? const SizedBox();
          final base = Theme.of(context);
          return Theme(
            data: base.copyWith(
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.brand,
                  foregroundColor: Colors.white,
                  minimumSize: Size.fromHeight(layout.scale(52)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: layout.scale(16),
                  ),
                ),
              ),
            ),
            child: child,
          );
        },
        home: const CaptainHomeShell(),
      ),
    );
  }
}
