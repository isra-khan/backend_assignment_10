import 'package:flutter/material.dart';
import '../config/palette.dart';
import '../config/tone.dart';

/// The Cabby wordmark — the route mark + "Cabby", with the C in brand green and
/// the rest in the current text colour. Rebuilt natively from logo-cabby.svg
/// (flutter_svg can't render the SVG text node).
///
/// The compact lockup stops at "Cabby": this sits inside tight rows (the drawer
/// header, the live-trip pill) beside other content, and the full "Cabby Ride"
/// name would crowd them. The complete lockup lives on the splash and in
/// logo-cabby.svg.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 30, this.color});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final ink = color ?? DefaultTextStyle.of(context).style.color ?? tone.ink;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            // The arc is near-square: 2r + stroke tall, and a little narrower
            // across because the aperture cuts the right-hand side.
            width: height * 0.84,
            height: height,
            child: CustomPaint(
              painter: _RouteMarkPainter(dark: context.tone.isDark),
            ),
          ),
          SizedBox(width: height * 0.18),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: height * 0.78,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1,
              ),
              children: [
                TextSpan(text: 'C', style: TextStyle(color: tone.brand)),
                TextSpan(text: 'abby', style: TextStyle(color: ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The route mark: a 250° arc opening right, matching icon-cabby.svg and the
/// launcher icon. Terminals sit at 55° and 305°; the last 30° carries the
/// accent as the leading tip.
class _RouteMarkPainter extends CustomPainter {
  const _RouteMarkPainter({required this.dark});

  /// The deep green all but disappears on the dark scaffold, so the arc lifts a
  /// step while staying darker than the accent tip in front of it.
  final bool dark;

  static const _startDeg = 55.0;
  static const _sweepDeg = 250.0;
  static const _tipDeg = 30.0;

  static double _rad(double deg) => deg * 3.1415926535897932 / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Proportions taken straight from the SVG: r 18, stroke 8, over 44 tall.
    final strokeWidth = size.height * 8 / 44;
    final radius = size.height * 18 / 44;
    final center = Offset(radius + strokeWidth / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      _rad(_startDeg),
      _rad(_sweepDeg - _tipDeg),
      false,
      stroke(dark ? Palette.brand : Palette.brandDark),
    );
    canvas.drawArc(
      rect,
      _rad(_startDeg + _sweepDeg - _tipDeg),
      _rad(_tipDeg),
      false,
      stroke(Palette.brandAccent),
    );
  }

  @override
  bool shouldRepaint(covariant _RouteMarkPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
