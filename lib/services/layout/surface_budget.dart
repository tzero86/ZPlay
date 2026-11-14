import 'package:flutter/widgets.dart';

/// What the window's size lets the app spend on motion nobody asked for.
///
/// Measured on Linux with a maximized window on a 4K monitor at 150%: GTK3
/// cannot render a fractional scale, so it draws the window at 2x - a ~14
/// megapixel surface - and the compositor scales it down. Presenting a
/// surface that size caps delivery at roughly 20-25 frames a second however
/// little the app draws, and every frame an idle animation asks for comes out
/// of that budget: the page felt laggy while doing nothing. On a 1080p-class
/// surface the same page scrolls at a steady 60, and ambient motion is free.
///
/// So the always-on decoration - the ambient glow's drift, the hero's slow
/// zoom - runs only on surfaces up to [ambientMotionMaxPixels], and holds a
/// still frame above it. Interactive motion (focus, transitions, scrolling)
/// is never gated: that is motion the user asked for.
abstract final class SurfaceBudget {
  /// 2.5 MP keeps ambient motion on 1080p and 1920x1200 surfaces - every
  /// television this app targets included - and holds it still from 1440p up.
  static const double ambientMotionMaxPixels = 2.5e6;

  /// Whether ambient decoration may animate on the surface [context] is
  /// drawn into. Reads MediaQuery, so a resize re-runs the caller's
  /// `didChangeDependencies`.
  static bool allowsAmbientMotion(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return size.width * size.height * dpr * dpr <= ambientMotionMaxPixels;
  }
}
