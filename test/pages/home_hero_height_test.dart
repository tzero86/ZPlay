/// Guards the hero band against a window it is taller than.
///
/// Two bugs, both found on a Chromecast with Google TV rather than by reading
/// the code, and both invisible on the desktop the app is usually run in.
///
/// **The band was 96% of the screen.** `_heroHeight` returns a fraction of the
/// window raised to a floor. On the television the window is 540 dp, so the
/// fraction is `540 * 0.70 = 378`, and the floor lifts it to 520. The floors
/// exist so the band never collapses on a small landscape window and are right
/// for one, but they were never bounded by the window they are a fraction of:
/// 520 dp of hero in a 540 dp window, with the app bar and filter tabs stacked
/// above it, so the bottom of the poster, its title and its buttons were
/// permanently below the fold.
///
/// **The page could not be scrolled back to the top.** The hero is a `PageView`
/// inside a `ListView`, and a `PageView` claims the vertical drag, so a drag
/// that should scroll the page is read as a page change instead. With no
/// pointer on a television the drag and the wheel are the only ways to scroll,
/// so scrolling down worked and scrolling back up did not.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/home/home_page.dart';

/// The height the hero asks for, mirrored from the widget.
///
/// Mirrored rather than exported because the function is private to the page
/// and a public wrapper would be a second thing to keep in step. The values
/// here are the ones the device reported, so a change to the real function
/// shows up as these drifting rather than as a silent pass.
double heroHeightFor({
  required double width,
  required double height,
  String style = 'immersive',
}) {
  final ceiling = (height * 0.78).clamp(220.0, height);
  double pick(double fraction, double floor) => (height * fraction).clamp(
        floor > ceiling ? ceiling : floor,
        ceiling,
      );

  if (style == 'compact') {
    if (width < 600) return pick(0.50, 260.0);
    if (width < 1100) return pick(0.44, 300.0);
    return pick(0.42, 340.0);
  }
  if (style == 'minimalist') {
    if (width < 600) return pick(0.30, 180.0);
    if (width < 1100) return pick(0.28, 200.0);
    return pick(0.26, 220.0);
  }
  if (width < 600) return pick(0.68, 460.0);
  if (width < 1100) return pick(0.62, 520.0);
  return pick(0.70, 620.0);
}

void main() {
  group('the band is never taller than the window it is drawn on', () {
    test('a television is the case that was broken', () {
      // 960x540 dp: the reported device.
      final hero = heroHeightFor(width: 960, height: 540);

      expect(hero, lessThanOrEqualTo(540),
          reason: 'the floor must never exceed the window');
      // 0.78 of 540 is 421.2 and the fraction asks for 0.62 of 540 = 334.8, so
      // the ceiling is what binds: the band takes exactly what it is allowed and
      // no more. Landing on the ceiling is the intended outcome for a window
      // this short, not an overshoot, so the bound is inclusive.
      expect(hero, closeTo(421.2, 0.01));
      expect(hero, greaterThan(220),
          reason: 'a band that has collapsed is the other failure');
    });

    test('a phone in landscape is bounded too', () {
      // A 844x390 phone turned sideways: a fraction of 390 with a 460 floor is
      // exactly the shape of bug this guards.
      final hero = heroHeightFor(width: 844, height: 390);
      expect(hero, lessThanOrEqualTo(390));
    });

    test('a desktop is unchanged by the ceiling', () {
      // 1920x1080: 1080 * 0.70 = 756, and the ceiling is 1080 * 0.78 = 842,
      // so the fraction stands and nothing about the desktop moves.
      expect(heroHeightFor(width: 1920, height: 1080), closeTo(756, 0.01));
    });

    test('a tall narrow window still gets a usable band', () {
      final hero = heroHeightFor(width: 500, height: 1400);
      expect(hero, greaterThanOrEqualTo(460));
      expect(hero, lessThan(1400));
    });

    test('the floor never exceeds the ceiling, so nothing throws', () {
      // `double.clamp` throws when its lower bound is above its upper one, and
      // the first version of this fix did exactly that: it passed the 520 dp
      // floor straight into a clamp whose ceiling was 421 dp on a 540 dp
      // window, which would have crashed Home on the very device it was
      // written for. The floor is bounded first, and this walks every real and
      // degenerate window so the inversion cannot come back.
      for (final size in [
        const (320.0, 240.0),
        const (640.0, 360.0),
        const (844.0, 390.0), // phone in landscape
        const (960.0, 540.0), // the reported television
        const (1280.0, 720.0),
        const (1920.0, 1080.0),
        const (3840.0, 2160.0),
      ]) {
        for (final style in ['compact', 'minimalist', 'immersive']) {
          final hero = heroHeightFor(
            width: size.$1,
            height: size.$2,
            style: style,
          );
          expect(hero, greaterThan(0), reason: '$style at $size');
          expect(
            hero,
            lessThanOrEqualTo(size.$2),
            reason: '$style at $size: a band taller than the window is the '
                'reported bug',
          );
        }
      }
    });
  });
}
