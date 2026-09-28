/// Guards the television canvas against the device's density.
///
/// A 55" 4K Google TV reports 3840x2160 but runs apps at 1920x1080 with
/// density 320. Flutter divides by the 2.0 device pixel ratio and hands the app
/// a 960x540 dp canvas, while every dp paints as two physical pixels - so type
/// and controls render at twice their intended size inside a canvas half the
/// width a desktop window gets. The app looked oversized everywhere and clipped
/// its own content, which is what a user reports as "the whole UI renders huge"
/// and which was invisible on desktop and phone, because those genuinely give
/// it the canvas the design was measured against.
///
/// The manifest cannot fix this. `android:supports-screens` is a Play Store
/// filter, not a density override: a build declaring `largeScreens`,
/// `xlargeScreens` and `anyDensity` still came up `w960dp h540dp 320dpi` on the
/// device. So the app changes the canvas it is given instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/layout/television_canvas.dart';
/// Pumps [TelevisionCanvas] over a child that reports the `MediaQuery` it sees.
///
/// [physicalSize] is what the device reports, and the `MediaQuery` is built
/// the way the framework builds it: logical size is the physical size divided
/// by the device pixel ratio, so a 1920x1080 screen at DPR 2 arrives as
/// 960x540 - the value that is the whole point of this test.
Future<Size> _canvasSeenBy(
  WidgetTester tester, {
  required Size reported,
  double dpr = 2.0,
}) async {
  Size? seen;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: reported,
        devicePixelRatio: dpr,
      ),
      child: TelevisionCanvas(
        child: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return seen!;
}

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('a pointer device is left exactly as the platform reports it',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: false);
    final seen = await _canvasSeenBy(
      tester,
      reported: const Size(1920, 1080),
    );
    // Untouched: a desktop window is already the design canvas, and changing
    // it would break the one platform that works.
    expect(seen, const Size(1920, 1080));
  });

  testWidgets('a television gets the canvas the app was designed against',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    // The reported device: 1920x1080 at density 320.
    final seen = await _canvasSeenBy(
      tester,
      reported: const Size(960, 540),
    );
    expect(seen, const Size(1920, 1080),
        reason: '960x540 is half the width a desktop window gets, and every dp '
            'paints at two physical pixels - the double whammy that made the '
            'whole app look oversized and clipped its own content');
  });

  testWidgets('a 720p set gets a 720p canvas, not a hardcoded 1080p',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    // 1280x720 at density 320 reports 640x360; dividing by the same factor
    // gives 1280x720, which is right for that set. What is normalised is the
    // density of the design space, not the resolution.
    final seen = await _canvasSeenBy(
      tester,
      reported: const Size(640, 360),
    );
    expect(seen, const Size(1280, 720));
  });

  test('the scale matches the density the device reports', () {
    // Density 320 against the 160 baseline gives 2.0. If this drifts, the
    // canvas is wrong on every television at once.
    expect(320 / 160, DeviceProfile.televisionCanvasScale);
  });
}
