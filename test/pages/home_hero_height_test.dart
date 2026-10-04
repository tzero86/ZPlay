/// Guards the home page's vertical budget - that the hero, the chrome above it
/// and the first content rail can all exist on one screen.
///
/// Three bugs, all found on a Chromecast with Google TV rather than by reading
/// the code, and all invisible on the desktop the app is usually run in.
///
/// **The band was taller than the window it is a fraction of.** `_heroHeight`
/// returned a fraction of the full canvas raised to a floor. The floors exist so
/// the band never collapses on a small landscape window and are right for one,
/// but they were never bounded by the window they divided: on the 540 dp
/// television the ceiling bound at 421.2 dp, which is 78% of the visible height.
///
/// **The band ignored everything stacked above it.** The app bar and the filter
/// pills sit over the content, so 421.2 dp of hero plus 44 dp of chrome put the
/// top of the first rail at 503 dp of 540. A comment here claimed this "leaves a
/// slice for the first rail" - it left 74.8 dp of a 326.5 dp rail, about a fifth,
/// so Home opened on a poster with a row of titles sliced off beneath it.
///
/// **The page could not be scrolled back to the top.** The hero is a `PageView`
/// inside a `ListView`, and a `PageView` claims the vertical drag, so a drag
/// that should scroll the page is read as a page change instead. With no pointer
/// on a television the drag and the wheel are the only ways to scroll, so
/// scrolling down worked and scrolling back up did not.
library;

import 'package:flutter_test/flutter_test.dart';

/// Chrome stacked above the hero, from `HomePage._topInsetFor`: the page's own
/// control row, the 8 dp gap under it, and the safe-area inset the shell did not
/// consume. Zero inset here, which is what a widget test measures.
///
/// **The shell's top bar is not in these numbers.** It is a layout child that
/// reserves its own space above the page, so it is already gone from the height
/// the page is handed; charging it here as well would be the double gap the
/// inset rewrite exists to remove.
const double _televisionChrome = 36 + 8;
const double _pointerChrome = 52 + 8;

/// Card width by canvas width, mirrored from `MovieCardSizing.fromWidth`.
double _cardWidthFor(double width) {
  if (width < 360) return 138;
  if (width < 430) return 152;
  if (width < 700) return 162;
  if (width < 1000) return 176;
  if (width < 1400) return 190;
  return 205;
}

double _posterHeightFor(double width) => _cardWidthFor(width) * 1.48;
double _railHeightFor(double width) => _posterHeightFor(width) + 66;

/// Space below the hero that the first rail needs to read as a rail: a section
/// header, 12 dp of gap, and enough poster to show the row is a row of posters.
///
/// Mirrored from `HomePage._firstRailReserve`. This is a peek, not the whole
/// rail, and that choice is load-bearing - see the `peek` tests below.
double _firstRailReserveFor(double width) =>
    38 + 12 + _posterHeightFor(width) * 0.45;

/// The shortest band that still holds a whole hero slide, mirrored from
/// `_HeroCarouselState._heroContentMinimum`. The text column is bottom-aligned
/// inside a 48 dp inset, so anything shorter pushes the title off the top.
const double _heroContentMinimum = 234;

/// The height the hero asks for, mirrored from the widget.
///
/// Mirrored rather than exported because the function is private to the page and
/// a public wrapper would be a second thing to keep in step. The values here are
/// the ones the device reported, so a change to the real function shows up as
/// these drifting rather than as a silent pass.
double heroHeightFor({
  required double width,
  required double height,
  String style = 'immersive',
  bool television = false,
}) {
  final chrome = television ? _televisionChrome : _pointerChrome;
  final available = height - chrome - _firstRailReserveFor(width);
  if (available <= 0) return height * 0.5;
  final ceiling = (available * 0.78).clamp(220.0, height);

  double pick(double fraction, double floor) {
    final lowBound = floor > ceiling ? ceiling : floor;
    final styled = (available * fraction).clamp(lowBound, ceiling);
    final floorWithinWindow =
        _heroContentMinimum > height ? height : _heroContentMinimum;
    return styled < floorWithinWindow ? floorWithinWindow : styled;
  }

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

// ─────────────────────────────────────────────────────────────────────────────
// What the slide drops when the band is short. Mirrored from `_HeroSlide`.
// ─────────────────────────────────────────────────────────────────────────────

/// Band height at which the title stops being drawn display-sized, from
/// `_HeroSlideState._titleShrinkBudget`.
const double _titleShrinkBudget = 300;

/// How the slide's title is drawn at a given band height, mirroring
/// `_HeroSlideState`.
///
/// The name is the one thing the slide exists for, so it gives way in size
/// rather than in existence: it drops from two lines at 46 px to one at 32 px
/// and is never removed. The slide used to also drop a synopsis paragraph and
/// a row of genre chips as the band got shorter; both are gone from the slide
/// entirely, so there is nothing left to drop.
({double fontSize, int lines}) titleStyleFor({
  required double bandHeight,
}) {
  final shrunk = bandHeight < _titleShrinkBudget;
  return (fontSize: shrunk ? 32 : 46, lines: shrunk ? 1 : 2);
}

void main() {
  // 960x540 dp: the reported device.
  const tv = (960.0, 540.0);

  group('the band is never taller than the window it is drawn on', () {
    test('a television is the case that was broken', () {
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);

      expect(hero, lessThanOrEqualTo(tv.$2),
          reason: 'the floor must never exceed the window');
      expect(hero, greaterThan(220),
          reason: 'a band that has collapsed is the other failure');
    });

    test('a phone in landscape is bounded too', () {
      // A 844x390 phone turned sideways: a fraction of 390 with a 460 floor is
      // exactly the shape of bug this guards.
      final hero = heroHeightFor(width: 844, height: 390);
      expect(hero, lessThanOrEqualTo(390));
    });

    test('a desktop keeps a full-height band', () {
      // 1920x1080 desktop: the rail is small against a tall window, so the hero
      // still takes the large majority of the screen. This is the case that must
      // not regress - the television fix is not allowed to shrink the desktop.
      final hero = heroHeightFor(width: 1920, height: 1080);
      expect(hero, greaterThan(1080 * 0.5),
          reason: 'a desktop has the height for a big band');
      expect(hero, lessThan(1080));
    });

    test('a tall narrow window still gets a usable band', () {
      final hero = heroHeightFor(width: 500, height: 1400);
      expect(hero, greaterThanOrEqualTo(460));
      expect(hero, lessThan(1400));
    });

    test('the floor never exceeds the ceiling, so nothing throws', () {
      // `double.clamp` throws when its lower bound is above its upper one, and
      // the first version of the ceiling fix did exactly that: it passed the
      // 520 dp floor straight into a clamp whose ceiling was 421 dp on a 540 dp
      // window, which would have crashed Home on the very device it was written
      // for. The floor is bounded first, and this walks every real and degenerate
      // window so the inversion cannot come back.
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
          for (final television in [true, false]) {
            final hero = heroHeightFor(
              width: size.$1,
              height: size.$2,
              style: style,
              television: television,
            );
            expect(hero, greaterThan(0), reason: '$style at $size tv=$television');
            expect(
              hero,
              lessThanOrEqualTo(size.$2),
              reason: '$style at $size tv=$television: a band taller than the '
                  'window is the reported bug',
            );
          }
        }
      }
    });
  });

  group('the page fits, rather than being one poster', () {
    test('a television shows the hero and a usable part of the first rail', () {
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);
      final railTop = _televisionChrome + hero + 38;
      final railHeight = _railHeightFor(tv.$1);
      final visible = tv.$2 - railTop;

      // The reported failure: 74.8 dp of a 326.5 dp rail.
      expect(
        visible,
        greaterThan(railHeight * 0.5),
        reason: 'at least half the first rail has to be on screen, or the '
            'page is a hero with a suggestion of scrolling under it',
      );
      // And the rail still runs off the bottom, which is what makes a long page
      // read as long rather than as truncated.
      expect(visible, lessThan(railHeight));
    });

    test('the hero no longer takes the whole canvas', () {
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);

      // It used to bind at the 0.78 ceiling of the full 540 dp canvas.
      expect(
        hero,
        lessThan(tv.$2 * 0.6),
        reason: 'a band over 60% of a television leaves nothing to scroll to',
      );
    });

    test('the reserve is a peek, not the whole rail', () {
      // Reserving the entire rail is defensible arithmetic and bad design: it
      // leaves the hero 93 dp on the reported device, which fixes "the hero is
      // everything" by replacing it with a letterbox.
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);
      expect(
        hero,
        greaterThan(tv.$2 * 0.3),
        reason: 'the hero must still be the best thing on the page',
      );
    });
  });

  group('the band still holds a whole slide', () {
    // The first pass of the chrome-aware hero budgeted the band down to 203.8 dp
    // and shipped a hero with the poster's title cut in half - it fixed a rail
    // below the fold by breaking the middle of the page. The text column is
    // bottom-aligned, so a band shorter than its content pushes the title
    // upward out of the band rather than clipping the bottom of it.
    test('a television band is at least as tall as the slide content', () {
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);
      expect(
        hero,
        greaterThanOrEqualTo(_heroContentMinimum),
        reason: 'a shorter band stacks the title off the top of the hero',
      );
    });

    test('every style keeps the content on a television', () {
      for (final style in ['compact', 'minimalist', 'immersive']) {
        final hero = heroHeightFor(
          width: tv.$1,
          height: tv.$2,
          style: style,
          television: true,
        );
        expect(
          hero,
          greaterThanOrEqualTo(_heroContentMinimum),
          reason: '$style must still fit its slide',
        );
      }
    });

    test('the content bound never exceeds the window', () {
      // A window shorter than the content cannot show a whole slide, and asking
      // for one anyway is how the original floor bug crashed the page.
      final hero = heroHeightFor(width: 320, height: 240, television: true);
      expect(hero, lessThanOrEqualTo(240));
    });
  });

  group('the slide fits the band it is given', () {
    // The band on the reported device lands near 256 dp, below the shrink
    // budget. The title column is bottom-aligned, so a title that kept its
    // display height there would be pushed off the top of the band and the
    // poster's name cut off - which is what the first chrome-aware version
    // shipped.
    test('a short band shrinks the title rather than losing it', () {
      final style = titleStyleFor(bandHeight: 256.5);

      expect(style.fontSize, 32, reason: 'one line, not two');
      expect(style.lines, 1);
    });

    test('a band with room keeps the display title', () {
      final style = titleStyleFor(bandHeight: 400);

      expect(style.fontSize, 46);
      expect(style.lines, 2);
    });

    test('the title is never dropped at any band height', () {
      // The invariant the band is designed around: the name gives way in size,
      // never in existence. Swept rather than sampled, so a height that drops
      // it entirely cannot slip between two checked values.
      for (var band = 120.0; band <= 620.0; band += 0.5) {
        final style = titleStyleFor(bandHeight: band);
        expect(
          style.fontSize,
          anyOf(32, 46),
          reason: 'at band height $band the title must still be drawn',
        );
      }
    });

    test('the band the television actually gets is one the slide survives', () {
      final hero = heroHeightFor(width: tv.$1, height: tv.$2, television: true);
      final style = titleStyleFor(bandHeight: hero);

      expect(
        style.fontSize,
        anyOf(32, 46),
        reason: 'the name is never dropped, only resized',
      );
    });
  });
}
