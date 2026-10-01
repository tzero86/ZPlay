/// Cards did not fit on a television.
///
/// Two independent defects produced the same visible result - a movie title cut
/// in half at the bottom of the screen, and a Browse grid whose posters were so
/// tall that not even one row fitted.
///
/// **The card had no shape.** `MovieCard` wrapped its poster in a bare
/// `Expanded`, so whatever height a parent offered became the poster. That made
/// `MovieCardSizing.posterHeight` decorative: nothing checked it against what the
/// card actually rendered.
///
/// **The grid derived a proportion from the wrong width.** `discover_page.dart`
/// computed `childAspectRatio = sizing.cardWidth / sizing.totalHeight`, which
/// describes the card correctly only at exactly `cardWidth`. Its cells are
/// `columns`-driven and came out *wider* - 220 dp against a nominal 176 - so
/// every card rendered 25% too tall: 408 dp instead of 326.5, in a viewport with
/// about 200 dp to spend. One row did not fit.
///
/// `manga_page.dart` already had this right, with `mainAxisExtent` instead of a
/// ratio. These tests pin the numbers the fix is made of, so the inflation
/// cannot come back through a well-meaning "just make it proportional" edit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

void main() {
  // The reported device: 1920x1080 at DPR 2, so a 960x540 dp canvas.
  const tvWidth = 960.0;
  const tvHeight = 540.0;

  group('a card sized only from width overflows the canvas', () {
    test('the width-only sizing is what overflowed', () {
      // Before the fix, height was not an input, so the card was always
      // 176 * 1.48 + 66 = 326.5 dp however short the window was.
      final sizing = MovieCardSizing.fromWidth(tvWidth);
      expect(sizing.totalHeight, greaterThan(300.0));
    });

    test('and it cannot fit below Home hero', () {
      // App bar + filter row, hero, section header, gap - all measured on the
      // device.
      const chrome = 44.0 + 234.0 + 38.0 + 12.0;
      const available = tvHeight - chrome;
      final sizing = MovieCardSizing.fromWidth(tvWidth);
      expect(
        sizing.totalHeight,
        greaterThan(available),
        reason: 'precondition: the card is taller than the space, which is '
            'why the title was cut off',
      );
    });
  });

  group('a card respects the height it is given', () {
    test('a short budget produces a shorter card', () {
      final tight = MovieCardSizing.fromWidth(tvWidth, availableHeight: 200);
      final loose = MovieCardSizing.fromWidth(tvWidth, availableHeight: 300);

      expect(
        tight.totalHeight,
        lessThan(loose.totalHeight),
        reason: 'the budget has to actually change the answer',
      );
    });

    test('a card never exceeds the height it was offered', () {
      for (final budget in [140.0, 180.0, 200.0, 240.0, 320.0, 420.0]) {
        final sizing = MovieCardSizing.fromWidth(tvWidth, availableHeight: budget);
        expect(
          sizing.totalHeight,
          lessThanOrEqualTo(budget + 0.01),
          reason: 'a budget of $budget dp must not produce a card taller than '
              'that - that is the chop',
        );
      }
    });

    test('the title is never what gets cut', () {
      // The text block is fixed and always present; only the poster may shrink.
      final tiny = MovieCardSizing.fromWidth(tvWidth, availableHeight: 120);
      expect(
        tiny.totalHeight,
        greaterThanOrEqualTo(MovieCardSizing.textBlockHeight),
        reason: 'below a certain height the card gives up width, not its title',
      );
    });

    test('a generous budget leaves the card at its natural shape', () {
      // This is the pointer-device case and it must be unchanged by the fix.
      final natural = MovieCardSizing.fromWidth(1920);
      final generous = MovieCardSizing.fromWidth(1920, availableHeight: 900);
      expect(generous.totalHeight, closeTo(natural.totalHeight, 0.01));
    });

    test('an absent budget is the same as a generous one', () {
      final absent = MovieCardSizing.fromWidth(1920);
      final generous = MovieCardSizing.fromWidth(1920, availableHeight: 900);
      expect(absent.totalHeight, closeTo(generous.totalHeight, 0.01));
    });
  });

  group('the text block is what it costs', () {
    test('totalHeight is poster plus the measured text block', () {
      final sizing = MovieCardSizing.fromWidth(1920);
      expect(
        sizing.totalHeight,
        closeTo(sizing.posterHeight + MovieCardSizing.textBlockHeight, 0.01),
        reason: 'the two have to be derived from each other or they drift',
      );
    });

    test('the text block is not a rounded-up guess', () {
      // 8 gap + subtitle 15 x 1.30 + 4 gap + label 13 x 1.20 = 47.1.
      expect(MovieCardSizing.textBlockHeight, 47.1);
      expect(
        MovieCardSizing.textBlockHeight,
        lessThan(66),
        reason: 'the old constant over-charged every card on every screen by '
            'nearly 19 dp',
      );
    });
  });

  group('the poster keeps its shape', () {
    testWidgets('the card honours a poster aspect ratio', (tester) async {
      // The defect itself: a bare `Expanded` let any parent stretch the poster,
      // so the aspect ratio was not something the card could honour.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                // Deliberately a shape the poster ratio does not want.
                width: 220,
                height: 408,
                child: MovieCard(
                  movie: Movie(
                    id: 'test-1',
                    name: 'A Title Long Enough To Ellipsise',
                    addonBaseUrl: 'test',
                    type: 'movie',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final poster = tester.getSize(
        find.descendant(
          of: find.byType(MovieCard),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(
        poster.width / poster.height,
        closeTo(1 / MovieCardSizing.posterRatio, 0.05),
        reason: 'the poster keeps its drawn shape instead of absorbing the '
            'height it was handed',
      );
    });
  });

  group('a card never overflows the box it is given', () {
    // The first attempt at this fix put a bare `AspectRatio` where the
    // `Expanded` had been, which overflowed by 109 px wherever the parent gave
    // the card less than poster + text. `Flexible` makes the ratio a preference
    // rather than a demand, and this is the test that says so.
    testWidgets('a short box does not overflow', (tester) async {
      for (final height in [200.0, 260.0, 326.5, 400.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 176,
                  height: height,
                  child: MovieCard(
                    movie: Movie(
                      id: 'test-$height',
                      name: 'A Title Long Enough To Ellipsise',
                      addonBaseUrl: 'test',
                      type: 'movie',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'a $height dp box must fit the card rather than overflow it',
        );
      }
    });

    testWidgets('the poster is capped by the box, not only by the ratio', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                // Deliberately far shorter than width x 1.48.
                width: 176,
                height: 200,
                child: MovieCard(
                  movie: Movie(
                    id: 'test-short',
                    name: 'Short Box',
                    addonBaseUrl: 'test',
                    type: 'movie',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final poster = tester.getSize(
        find.descendant(
          of: find.byType(MovieCard),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(
        poster.height,
        lessThanOrEqualTo(200 - MovieCardSizing.textBlockHeight + 0.01),
        reason: 'the poster yields to the box; the title does not',
      );
    });
  });
}
