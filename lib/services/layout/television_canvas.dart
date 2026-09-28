/// Wraps the app so a television draws against a canvas the app was designed for.
///
/// **The problem.** A 55" 4K Google TV reports 3840x2160 but runs apps at
/// 1920x1080 with density 320. Flutter divides by the 2.0 device pixel ratio and
/// hands the app a **960 x 540 dp** canvas. Every dp also paints as two physical
/// pixels, so type and controls render at twice their intended size inside a
/// canvas half the width a desktop window gets. The result is the whole app
/// looking oversized, with content clipped because the page cannot fit.
///
/// Confirmed on the device: `dumpsys window` reports
/// `w960dp h540dp 320dpi television -touch dpad/v`. Forcing the density to 160
/// with `wm density` produced a 1920x1080 dp canvas and an immediately correct
/// layout - the one the app is actually designed against, and the one desktop
/// and phone already give it.
///
/// **Why the manifest cannot fix it.** `android:supports-screens` looks like the
/// answer and is not: it is a Play Store *filter*, declaring which devices the
/// app may install on. It has no effect on the density Android hands a running
/// process. Tested - a build declaring `largeScreens`, `xlargeScreens` and
/// `anyDensity` still came up `w960dp h540dp 320dpi`.
///
/// **What this does instead.** The app can only change the density it is *given*
/// by treating the canvas as a window of the size the design assumed. Dividing
/// the reported size by [DeviceProfile.televisionCanvasScale] gives a 1920x1080
/// canvas, and the physical pixels are unchanged, so what the user sees is the
/// same pixels at half the reported size - the layout the design was measured
/// against rather than one that has to be re-measured per television.
///
/// Deliberately a scale of the *reported* size rather than a hardcoded
/// resolution: a 720p set reports 1280x720 and gets a 1280x720 canvas, which is
/// correct for it, and an unknown television is not assumed to be 1080p.
///
/// **The cost, stated plainly.** `MediaQuery` is overridden, so anything that
/// reads it - `MediaQuery.of(context).size`, the window manager, the keyboard's
/// own insets - sees the scaled canvas rather than the real one. That is the
/// trade this makes, and it is the same trade every TV app makes: the design
/// target wins over raw device pixels. Pointer devices are untouched, because
/// this only installs where [DeviceProfile.isTelevision] is true, and the
/// density override is exactly the problem the two do not share - a phone at
/// density 320 has a genuinely small canvas and a large one is correct.
library;

import 'package:flutter/widgets.dart';

import 'device_profile.dart';

class TelevisionCanvas extends StatelessWidget {
  const TelevisionCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!DeviceProfile.isTelevision) return child;

    // **Multiply, not divide.** The framework has already divided: a 1920x1080
    // panel at device pixel ratio 2 arrives here as 960x540 dp. Dividing that
    // again gives 480x270, which is a smaller canvas than before and the
    // opposite of the fix. Setting `wm density 160` on the device produced
    // 1920x1080 dp because the ratio became 1.0, so the multiplication here
    // restores the same canvas: the panel size at a ratio of one.
    //
    // In physical pixels nothing changes - 1920x1080 either way - so what
    // differs is how much design space the layout is told it has, and it is
    // now told the truth.
    return MediaQuery(
      data: media.copyWith(
        size: media.size * DeviceProfile.televisionCanvasScale,
        // Ratio of one, so a logical pixel is a physical pixel and the canvas
        // is the panel's own resolution. This is exactly the state `wm density
        // 160` produced on the device, which is what confirmed the fix.
        devicePixelRatio: 1.0,
        // The keyboard is sized in physical pixels by the platform; scaling its
        // insets would detach the field from the keys on screen, which is a
        // worse bug than the one being fixed.
        viewInsets: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        systemGestureInsets: EdgeInsets.zero,
      ),
      child: child,
    );
  }
}
