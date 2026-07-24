import 'package:flutter/material.dart';

/// Responsive layout tokens so the captain app reads well on both phones and
/// tablets. Phones keep the original phone-first design untouched (scale 1.0,
/// no width cap); tablets get larger type, roomier spacing, and content held to
/// a comfortable measure instead of stretched edge-to-edge across a wide panel.
///
/// Usage: `final layout = context.layout;` then `layout.scale(16)`,
/// `layout.gap`, `layout.contentMaxWidth`, `layout.isTablet`, `layout.isWide`.
class AppLayout {
  const AppLayout._(this.width, this.height);

  /// Below this the device is treated as a phone. 600dp is the conventional
  /// Material breakpoint between a phone and a small tablet's shortest side.
  static const double _tabletBreakpoint = 600;

  /// Above this a tablet is roomy enough to place two columns side by side.
  static const double _wideBreakpoint = 900;

  factory AppLayout.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppLayout._(size.width, size.height);
  }

  final double width;
  final double height;

  double get shortestSide => width < height ? width : height;

  /// A tablet-class device (by shortest side, so it holds in both rotations).
  bool get isTablet => shortestSide >= _tabletBreakpoint;

  /// Wide enough (in the current orientation) to lay out two columns.
  bool get isWide => width >= _wideBreakpoint;

  /// Multiplier applied to type and spacing. Phones stay at 1.0 so their layout
  /// is pixel-identical to before; tablets lift ~25% for arm's-length reading.
  double get factor => isTablet ? 1.25 : 1.0;

  /// Scale a phone-tuned dimension (font size, icon, spacing) for the device.
  double scale(double value) => value * factor;

  /// Standard vertical rhythm gap, scaled.
  double get gap => scale(16);

  /// Max width a single content column is held to. Unbounded on phones; on
  /// tablets a readable measure so cards and text don't sprawl.
  double get contentMaxWidth => isTablet ? 560 : double.infinity;

  /// Page padding, scaled and a touch roomier on tablets.
  EdgeInsets get pagePadding => EdgeInsets.all(isTablet ? 32 : 20);
}

extension AppLayoutContext on BuildContext {
  /// Responsive layout tokens for the current context.
  AppLayout get layout => AppLayout.of(this);
}
