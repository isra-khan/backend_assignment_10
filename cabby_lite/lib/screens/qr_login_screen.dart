import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../models/captain.dart';
import '../state/ride_controller.dart';
import '../widgets/brand_logo.dart';

/// Captain login — QR only. There is no email/phone/password path anywhere in
/// this app; a captain is issued a QR by the Cabby centre and scans it to sign
/// in. A "simulate" affordance is provided for demoing on devices without a
/// physical captain QR to hand.
class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({super.key});

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // Guards against the camera firing onDetect repeatedly for the same code
  // while the sign-in transition is still animating out.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;
    _signIn(raw);
  }

  void _signIn(String raw) {
    if (_handled) return;
    setState(() => _handled = true);
    context.read<RideController>().signInFromScan(raw);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    return Scaffold(
      backgroundColor: Palette.zinc950,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Dim the camera feed so the brand chrome stays legible.
          Container(color: Colors.black.withValues(alpha: 0.35)),
          const _ScannerReticle(),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(layout.scale(24)),
              child: Column(
                children: [
                  SizedBox(height: layout.scale(8)),
                  BrandLogo(height: layout.scale(34), color: Colors.white),
                  const Spacer(),
                  // Hold the copy + button to a readable measure so they don't
                  // stretch across the full width of a tablet.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      children: [
                        _instructions(context),
                        SizedBox(height: layout.scale(20)),
                        _demoButton(context),
                        SizedBox(height: layout.scale(12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _instructions(BuildContext context) {
    final layout = context.layout;
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: layout.scale(12), vertical: layout.scale(6)),
          decoration: BoxDecoration(
            color: Palette.brandAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_user,
                  size: layout.scale(13), color: Palette.brandAccent),
              SizedBox(width: layout.scale(6)),
              Text(
                'Government of Sindh · Captain access',
                style: TextStyle(
                  color: Palette.brandAccent,
                  fontSize: layout.scale(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: layout.scale(16)),
        Text(
          'Scan your captain QR',
          style: TextStyle(
            color: Colors.white,
            fontSize: layout.scale(22),
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: layout.scale(8)),
        Text(
          'Point the camera at the QR code issued to you by the Cabby centre. '
          'This is the only way to sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: layout.scale(13),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _demoButton(BuildContext context) {
    final layout = context.layout;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _signIn('cabby-captain:${Captain.demo().name}'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          minimumSize: Size.fromHeight(layout.scale(50)),
          textStyle: TextStyle(
              fontSize: layout.scale(14), fontWeight: FontWeight.w600),
        ),
        icon: Icon(Icons.qr_code_2, size: layout.scale(18)),
        label: const Text('Simulate scan (demo)'),
      ),
    );
  }
}

/// The bracketed viewfinder square with a sweeping scan line.
class _ScannerReticle extends StatefulWidget {
  const _ScannerReticle();

  @override
  State<_ScannerReticle> createState() => _ScannerReticleState();
}

class _ScannerReticleState extends State<_ScannerReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Grow the viewfinder on tablets so it's a comfortable target, but cap it
    // so it never dominates a large landscape screen.
    final side = MediaQuery.sizeOf(context).shortestSide;
    final box = (side * 0.5).clamp(240.0, 420.0);
    return Center(
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _BracketPainter()),
            ),
            AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                return Positioned(
                  left: 12,
                  right: 12,
                  top: 12 + _anim.value * (box - 24),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        Colors.transparent,
                        Palette.brandAccent,
                        Colors.transparent,
                      ]),
                      boxShadow: [
                        BoxShadow(
                          color: Palette.brandAccent.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Palette.brandAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 34.0;
    final w = size.width, h = size.height;
    // Four corner brackets.
    void corner(Offset o, Offset a, Offset b) {
      canvas.drawLine(o, o + a, paint);
      canvas.drawLine(o, o + b, paint);
    }

    corner(const Offset(0, 0), const Offset(len, 0), const Offset(0, len));
    corner(Offset(w, 0), const Offset(-len, 0), const Offset(0, len));
    corner(Offset(0, h), const Offset(len, 0), const Offset(0, -len));
    corner(Offset(w, h), const Offset(-len, 0), const Offset(0, -len));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
