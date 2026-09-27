/// Guards the ten-foot rail against a canvas it was not measured on.
///
/// 236 dp was a desktop number and stayed correct there: 236 of 1920 dp is 12%,
/// a comfortable rail. A television does not present that canvas. A Chromecast
/// with Google TV reports 1920x1080 at density 320, so Flutter divides by 2.0
/// and gets 960 by 540 dp - the same 236 px is then 24.5% of the width, a
/// quarter of the screen.
///
/// Confirmed on the device rather than inferred: `dumpsys window displays`
/// reports `w960dp h540dp 320dpi television -touch dpad/v`, and `wm size`
/// shows the 1920x1080 as the device's own `base` display rather than an
/// override this app asked for. 1080p at 320dpi is a common Google TV
/// configuration, so this is living-room hardware, not an edge case.
///
/// These pin the clamp at both ends. The pure functions mean neither assertion
/// depends on the density of the machine running the suite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/shell/shell_rail.dart';

void main() {
  group('the rail takes a share of the canvas, not a fixed width', () {
    test('a 960 dp television does not get the desktop rail', () {
      // The reported failure: 236 of 960 is a quarter of the screen.
      expect(ShellRail.televisionRailWidth(960), lessThan(236));
    });

    test('a 1920 dp desktop keeps the measured value', () {
      // 1920 * 0.13 is 249, above the ceiling, so this is the cap doing the
      // work: nothing measured against a desktop canvas changes.
      expect(ShellRail.televisionRailWidth(1920), 236);
    });

    test('a very wide canvas is still capped', () {
      expect(ShellRail.televisionRailWidth(3840), 236);
    });

    test('a narrow television keeps the label-fit floor', () {
      // 172 is derived, not chosen: it is the rail whose label space still fits
      // "Fullscreen" at the smallest type step, with 8+8 padding, a 32 icon, an
      // 8 gap and a 4 selection border. Below that the type has to shrink, and a
      // 12 px name at ten feet is worse than a slightly wide rail.
      expect(ShellRail.televisionRailWidth(600), 172);
    });

    test('and the floor is never crossed', () {
      for (final width in [320.0, 480.0, 600.0, 800.0, 960.0, 1280.0]) {
        expect(ShellRail.televisionRailWidth(width), greaterThanOrEqualTo(172));
      }
    });

    test('between the bounds it is a bounded share of the canvas', () {
      // The ratio only holds while neither bound is pinned. A 960 dp canvas
      // cannot both keep the 172 dp label-fit floor and stay under a seventh of
      // itself, and the label is the one that should win on a television.
      for (final width in [1440.0, 1600.0, 1920.0, 2560.0]) {
        expect(
          ShellRail.televisionRailWidth(width),
          lessThanOrEqualTo(width / 7 + 0.001),
        );
      }
    });
  });

  group('row targets scale the same way', () {
    test('a 540 dp television does not get the 64 dp target', () {
      // 540 * 0.0625 is 33.75, below the floor, so this is the floor holding:
      // 56 dp is the accessibility minimum for a remote target and is never
      // crossed in either direction.
      expect(ShellRail.televisionRowHeight(540), 56);
    });

    test('a tall television keeps the 64 dp ceiling', () {
      expect(ShellRail.televisionRowHeight(2160), 64);
    });

    test('and the floor holds at every canvas', () {
      for (final height in [400.0, 540.0, 720.0, 1080.0, 2160.0]) {
        expect(ShellRail.televisionRowHeight(height), greaterThanOrEqualTo(56));
        expect(ShellRail.televisionRowHeight(height), lessThanOrEqualTo(64));
      }
    });
  });

  test('a 960 by 540 television is the case that was broken', () {
    // Both numbers together, as the device reported them. Before this was a
    // fixed 236 by 64 - a quarter of the width and an eighth of the height.
    expect(ShellRail.televisionRailWidth(960), 172);
    expect(ShellRail.televisionRowHeight(540), 56);
  });
}
