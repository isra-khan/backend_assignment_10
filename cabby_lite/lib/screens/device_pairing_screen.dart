import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../state/pairing_controller.dart';
import '../widgets/brand_logo.dart';

/// Pairs this tablet to a captain.
///
/// The tablet *displays* the QR; the captain scans it with the Cabby phone app
/// — the WhatsApp Web model. This device has no camera role in the flow and
/// never asks the driver to type anything.
///
/// The QR encodes the pairing code and nothing else: no JSON, no URL, no
/// prefix. The phone's scanner posts whatever it decodes straight to the
/// backend, so any wrapper here breaks the link.
class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  // Drives the "expires in 4:32" countdown. Independent of the 2s poll so the
  // clock ticks smoothly regardless of network timing.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // The controller is created by the provider above us; kick the first
    // pairing off once this frame is done so notifyListeners() lands safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PairingController>().start();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final ctrl = context.watch<PairingController>();

    return Scaffold(
      backgroundColor: Palette.zinc950,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Everything on the card except the QR itself: the logo, the pill,
            // both blocks of copy, the footer, and the gaps between them.
            //
            // These are estimates — the copy wraps and the footer swaps a
            // countdown for a button — so a slack allowance covers the error.
            // Without it the estimate lands a hair under the truth, `fits` says
            // yes, and IntrinsicHeight then forces a height the viewport can't
            // take: a 1px overflow on an 800x480 tablet, which is a stripe
            // across the screen rather than a rounding detail.
            const slack = 24.0;
            final chrome =
                layout.scale(34 + 29 + 75 + 17 + 14 + 14 + 10) + slack;
            final qrSide = _qrSide(
              layout,
              room: (constraints.maxHeight - layout.scale(24) * 2 - chrome)
                  .clamp(0.0, double.infinity),
            );

            final card = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _accessPill(context),
                  SizedBox(height: layout.scale(14)),
                  _QrCard(controller: ctrl, side: qrSide),
                  SizedBox(height: layout.scale(14)),
                  _copy(context, ctrl),
                  SizedBox(height: layout.scale(10)),
                  _footer(context, ctrl),
                ],
              ),
            );
            final logo = BrandLogo(
              height: layout.scale(34),
              color: Colors.white,
            );
            final pad = layout.scale(24) * 2;
            final available =
                (constraints.maxHeight - pad).clamp(0.0, double.infinity);
            final fullWidth =
                (constraints.maxWidth - pad).clamp(0.0, double.infinity);

            // The QR has already been shrunk to whatever height was going, so
            // if the total still doesn't fit, nothing further will make it —
            // the screen scrolls rather than shrink the code past scanning.
            final fits = chrome + qrSide <= available;

            // Two modes, and the difference matters. When there is room, the
            // Spacers centre the card — but a Spacer needs a bounded height,
            // which a scroll view won't give, hence IntrinsicHeight. When there
            // isn't room, that same forced height is what overflows: the scroll
            // view is willing to scroll and IntrinsicHeight won't let it. So a
            // short screen drops both and just scrolls.
            final body = fits
                ? IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        logo,
                        const Spacer(),
                        card,
                        const Spacer(),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      logo,
                      SizedBox(height: layout.scale(24)),
                      card,
                    ],
                  );

            return SingleChildScrollView(
              padding: EdgeInsets.all(layout.scale(24)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: fits ? available : 0.0,
                  // Full viewport width, so the Column has something to centre
                  // within. A scroll view hands its child a LOOSE width, and a
                  // Column under a loose constraint shrinks to its widest child
                  // — which left the whole card sitting off-centre on a wide
                  // tablet no matter what crossAxisAlignment said.
                  minWidth: fullWidth,
                ),
                child: body,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _accessPill(BuildContext context) {
    final layout = context.layout;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.scale(12),
        vertical: layout.scale(6),
      ),
      decoration: BoxDecoration(
        color: Palette.brandAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user,
            size: layout.scale(13),
            color: Palette.brandAccent,
          ),
          SizedBox(width: layout.scale(6)),
          // Flexible so the label can give: the Row is mainAxisSize.min inside
          // a 520-wide cap, and at tablet scale this string plus the icon and
          // padding runs past it. Unwrapped it had no way to shrink and simply
          // overflowed to the right.
          Flexible(
            child: Text(
              'Government of Sindh · Captain access',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Palette.brandAccent,
                fontSize: layout.scale(12),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Heading + instructions. The wording names the exact path on the phone so a
  /// captain doing this for the first time doesn't have to hunt for it.
  Widget _copy(BuildContext context, PairingController ctrl) {
    final layout = context.layout;
    final (title, body) = switch (ctrl.phase) {
      PairingPhase.expired => (
          'Code expired',
          'Nobody scanned this code in time. Tap below for a new one.',
        ),
      PairingPhase.error => (
          'Can’t reach Cabby',
          ctrl.errorMessage ?? 'Check the connection and try again.',
        ),
      _ => (
          'Link this tablet',
          'On your phone, open Cabby → Linked Devices → Scan, '
              'then point it at this screen.',
        ),
    };

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: layout.scale(22),
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: layout.scale(8)),
        Text(
          body,
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

  /// Countdown while a code is live, a refresh button once it isn't.
  Widget _footer(BuildContext context, PairingController ctrl) {
    final layout = context.layout;

    if (ctrl.phase == PairingPhase.expired ||
        ctrl.phase == PairingPhase.error) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: ctrl.start,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            minimumSize: Size.fromHeight(layout.scale(50)),
            textStyle: TextStyle(
              fontSize: layout.scale(14),
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Icon(Icons.refresh, size: layout.scale(18)),
          label: const Text('Show a new code'),
        ),
      );
    }

    final remaining = _remaining(ctrl.expiresAt);
    return Column(
      children: [
        if (remaining != null)
          Text(
            'Code expires in $remaining',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: layout.scale(12),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        // The captain never needs the raw code, but testing does: until the
        // phone's Linked Devices screen exists it gets claimed by hand over
        // curl. Debug-only so it can't reach a production tablet.
        if (kDebugMode && ctrl.code != null) ...[
          SizedBox(height: layout.scale(8)),
          SelectableText(
            ctrl.code!,
            style: TextStyle(
              color: Palette.brandAccent.withValues(alpha: 0.8),
              fontSize: layout.scale(12),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }

  /// `m:ss` left on the code, or null when there's nothing to count down.
  String? _remaining(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final left = expiresAt.difference(DateTime.now());
    if (left.isNegative) return null;
    final m = left.inMinutes;
    final s = left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Side length of the square QR card.
///
/// Big enough to scan from the driver's seat, capped so it doesn't dominate a
/// large landscape panel, and — when [room] says the screen is short on height
/// — allowed to give some of that back so the card fits without scrolling.
///
/// The 200 floor is where it stops giving: below roughly that a QR can't be
/// read from the driver's seat, which is the screen's whole job, so a very
/// short viewport scrolls rather than rendering something unscannable. On a
/// tablet there is always room to spare and [room] never binds.
double _qrSide(AppLayout layout, {double room = double.infinity}) {
  final preferred = (layout.shortestSide * 0.42).clamp(280.0, 460.0);
  if (room >= preferred) return preferred;
  return room.clamp(200.0, preferred);
}

/// The QR itself, on a white card.
///
/// The white ground is functional, not decorative: a QR drawn on the app's dark
/// background is a contrast inversion that many scanners refuse, and the quiet
/// zone around it is part of the spec.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.controller, required this.side});

  final PairingController controller;

  /// Measured by the screen, which knows how much height is left over.
  final double side;

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final code = controller.code;
    final expired = controller.phase == PairingPhase.expired;

    return SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(layout.scale(20)),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.scale(20)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (code != null)
                // The raw code, verbatim — see the note on this class's screen.
                QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Palette.zinc950,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Palette.zinc950,
                  ),
                )
              else
                const Center(child: CircularProgressIndicator()),

              // An expired code stays visible but is clearly dead, so nobody
              // wastes a scan on it.
              if (expired)
                ClipRRect(
                  borderRadius: BorderRadius.circular(layout.scale(8)),
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.88),
                    child: Center(
                      child: Icon(
                        Icons.refresh,
                        size: layout.scale(56),
                        color: Palette.zinc950.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
