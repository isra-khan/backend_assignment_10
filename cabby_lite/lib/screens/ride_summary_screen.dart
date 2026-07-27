import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/layout.dart';
import '../config/palette.dart';
import '../config/tone.dart';
import '../models/trip.dart';
import '../state/ride_controller.dart';
import '../widgets/route_card.dart';

/// Shown after a trip ends. Presents the fare, the trip details, and a QR the
/// rider scans to pay — then returns the captain to standby.
class RideSummaryScreen extends StatelessWidget {
  const RideSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final ctrl = context.watch<RideController>();
    final trip = ctrl.trip;
    if (trip == null) return const SizedBox.shrink();

    // On a wide tablet the payment QR sits beside the fare + route rather than
    // scrolling below them, so it's visible without scrolling for the rider.
    final twoColumn = layout.isWide;

    final header = Column(
      children: [
        Container(
          width: layout.scale(56),
          height: layout.scale(56),
          decoration: BoxDecoration(
            color: tone.brandWash,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded,
              color: tone.brand, size: layout.scale(30)),
        ),
        SizedBox(height: layout.scale(12)),
        Text(
          'Ride completed',
          style: TextStyle(
            fontSize: layout.scale(22),
            fontWeight: FontWeight.w800,
            color: tone.ink,
          ),
        ),
        SizedBox(height: layout.scale(4)),
        Text(
          'Trip ${trip.id} · ${trip.km.toStringAsFixed(1)} km · '
          '${trip.minutes} min',
          style: TextStyle(fontSize: layout.scale(13), color: tone.muted),
        ),
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: () => ctrl.clearTrip(),
          child: const Text('Payment received · Back to standby'),
        ),
        SizedBox(height: layout.scale(8)),
        TextButton(
          onPressed: () => ctrl.clearTrip(),
          child: Text('Skip', style: TextStyle(color: tone.muted)),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: layout.pagePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: twoColumn ? 900 : layout.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  SizedBox(height: layout.scale(20)),
                  if (twoColumn)
                    // No IntrinsicHeight here: the QR card contains a
                    // LayoutBuilder (QrImageView) which can't be intrinsically
                    // measured. Top-aligned columns don't need equal heights.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _FareCard(trip: trip),
                              SizedBox(height: layout.gap),
                              RouteCard(
                                  pickup: trip.pickup,
                                  destination: trip.destination),
                            ],
                          ),
                        ),
                        SizedBox(width: layout.gap),
                        Expanded(child: _PaymentQrCard(trip: trip)),
                      ],
                    )
                  else ...[
                    _FareCard(trip: trip),
                    SizedBox(height: layout.gap),
                    _PaymentQrCard(trip: trip),
                    SizedBox(height: layout.gap),
                    RouteCard(
                        pickup: trip.pickup, destination: trip.destination),
                  ],
                  SizedBox(height: layout.scale(24)),
                  actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand-green earnings header with the fare breakdown beneath it — mirrors
/// the receipt overlay in the main Cabby captain app.
class _FareCard extends StatelessWidget {
  const _FareCard({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    final b = trip.fareBreakdown;

    Widget line(String label, int amount, {bool strong = false}) => Padding(
          padding: EdgeInsets.symmetric(vertical: layout.scale(4)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: layout.scale(strong ? 14 : 13),
                    color: strong ? tone.ink : tone.muted,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'PKR $amount',
                style: TextStyle(
                  fontSize: layout.scale(strong ? 14 : 13),
                  color: strong ? tone.ink : tone.muted,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.ring),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(layout.scale(20)),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Palette.brand, Palette.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL FARE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: layout.scale(11),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'PKR ${trip.fare}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: layout.scale(36),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // The payout is only knowable when we have the component split
                // — it is the total minus the platform's cut. A backend fare
                // arrives as one number, so there is nothing to subtract and
                // the line is omitted rather than guessed at.
                if (trip.hasFareBreakdown)
                  Text(
                    'Your earning · PKR ${b.captainPayout}',
                    style: TextStyle(
                        color: Colors.white70, fontSize: layout.scale(13)),
                  ),
              ],
            ),
          ),
          // Likewise the line items. `/captain/active-ride` and the
          // `ride-ended` payload both send a flat `fare`, so rendering the
          // breakdown there would print five confident zeroes.
          if (trip.hasFareBreakdown)
            Padding(
              padding: EdgeInsets.fromLTRB(layout.scale(16), layout.scale(12),
                  layout.scale(16), layout.scale(14)),
              child: Column(
                children: [
                  line('Base fare', b.base),
                  line('Distance (${trip.km.toStringAsFixed(1)} km)',
                      b.distance),
                  line('Time (${trip.minutes} min)', b.time),
                  line('Platform fee', b.platformFee),
                  line('Tax', b.tax),
                  Divider(color: tone.ring, height: layout.scale(20)),
                  line('Total', b.total, strong: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The scannable payment QR the rider uses to settle the fare.
class _PaymentQrCard extends StatelessWidget {
  const _PaymentQrCard({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final layout = context.layout;
    // Payment intent the rider's app resolves. Kept simple and self-describing.
    final payload =
        'cabby-pay:trip=${trip.id};amount=${trip.fare};currency=PKR';
    // Larger, easier-to-scan QR on tablets. LayoutBuilder below clamps it to
    // the card's width so it never overflows a narrow two-column layout.
    final preferredQr = layout.isTablet ? 260.0 : 200.0;

    return Container(
      padding: EdgeInsets.all(layout.scale(20)),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'SCAN TO PAY',
            style: TextStyle(
              fontSize: layout.scale(11),
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: tone.muted,
            ),
          ),
          SizedBox(height: layout.scale(4)),
          Text(
            'Ask the rider to scan with their Cabby app',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: layout.scale(13), color: tone.muted),
          ),
          SizedBox(height: layout.scale(16)),
          // QR always on white so scanners read it in either theme.
          Container(
            padding: EdgeInsets.all(layout.scale(16)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: tone.shadow(blur: 16),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                // Never exceed the card's inner width (two-column tablet).
                final side = c.maxWidth.isFinite
                    ? (preferredQr < c.maxWidth ? preferredQr : c.maxWidth)
                    : preferredQr;
                return QrImageView(
                  data: payload,
                  size: side,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Palette.brand,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Palette.brandInk,
                  ),
                );
              },
            ),
          ),
          SizedBox(height: layout.scale(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: layout.scale(13), color: tone.muted),
              SizedBox(width: layout.scale(6)),
              Flexible(
                child: Text(
                  'PKR ${trip.fare} · secured by Cabby',
                  style:
                      TextStyle(fontSize: layout.scale(12), color: tone.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
