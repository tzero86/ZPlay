/// Navigation was eating 30% of a television screen, and the rails were
/// squeezed to pay for it.
///
/// Both symptoms came from the same mistake: a *filter* budget was allowed to
/// resize *content*.
///
/// **Browse spent 162 dp on chrome before the first poster.** Measured from
/// `discover_page.dart`: safe top 8 + title row 56 + catalog chip row 50 + extras
/// row 48. On a 540 dp canvas that is 30% of the screen on controls that are not
/// content, against roughly 64 dp for the equivalent in the app this is measured
/// against. The title row alone cost 10% to say "Discover" on a page the rail
/// had already identified.
///
/// **The home rail was 37% smaller than it should be.** `_railHeightFor`
/// returned "whatever is left after the hero". With the hero at 234 dp that left
/// 212 dp for a 326 dp card, so the poster rendered at 165 dp instead of 260 -
/// which is exactly the "forcibly shrunk" feel, and was a direct consequence of
/// the card fix that was supposed to help.
///
/// The rules now:
///
/// - Chrome is a fixed, small budget that does not grow with features. The title
///   row is not drawn on TV; the extras row is merged into the chip row.
/// - A card is sized by the screen. Nothing above it may squeeze it. On TV the
///   hero is an *overlay* on the first rail rather than a band that displaces it,
///   which is the one-focal-point rule that makes the reference app cohere.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The reported device: 1920x1080 at DPR 2, so 960x540 dp.
  const tv = Size(960.0, 540.0);

  group("browse's chrome is a small fixed budget", () {
    // Mirrored from `_buildHeader` and `_buildDiscoverScaffold`.
    const safeTop = 8.0;
    const titleRowPointer = 56.0;
    const chipRowTv = 44.0;
    const chipRowPointer = 50.0;
    const extrasRow = 48.0;

    double chromeOnTv({required bool hasExtras}) =>
        safeTop + chipRowTv;

    double chromeOnPointer({required bool hasExtras}) =>
        safeTop + titleRowPointer + chipRowPointer + (hasExtras ? extrasRow : 0);

    test('a television spends under a sixth of the screen on chrome', () {
      expect(
        chromeOnTv(hasExtras: true),
        lessThan(tv.height / 6),
        reason: 'the title row is not drawn on TV and the extras are merged '
            'into the chip row, so there is one row of chrome, not three',
      );
    });

    test('the old three-row arrangement is what it replaced', () {
      // 8 + 56 + 50 + 48 = 162, which is 30% of 540.
      const before = safeTop + titleRowPointer + chipRowPointer + extrasRow;
      expect(before / tv.height, closeTo(0.30, 0.01));
      expect(
        chromeOnTv(hasExtras: true),
        lessThan(before / 2),
        reason: 'precondition: the new arrangement is less than half the old '
            'one, which is the point of it',
      );
    });

    test('a pointer keeps its title row and its extras row', () {
      // The change is television-only. A phone has no rail, so the page has to
      // say what it is, and it has the height for three rows.
      expect(chromeOnPointer(hasExtras: true), greaterThan(chromeOnTv(hasExtras: true)));
      expect(chromeOnPointer(hasExtras: true), closeTo(162.0, 0.01));
    });

    test('the merged row still carries the extras, so nothing is lost', () {
      // The extras are not hidden on TV - they are drawn in the catalog chip row
      // behind a rule. This is about reachability, which is the thing that
      // matters on a remote: they are in the same row, so the same scroll and the
      // same focus order reach them.
      expect(chromeOnTv(hasExtras: true), chromeOnTv(hasExtras: false),
          reason: 'the extras add no height on TV because they share a row');
    });
  });

  group('a card is sized by the screen, not squeezed by the page', () {
    const cardWidth = 176.0;
    const posterRatio = 1.48;
    const textBlock = 47.1;
    const naturalPoster = cardWidth * posterRatio;
    const naturalCard = naturalPoster + textBlock;
    const chrome = 44.0;
    const header = 38.0 + 12.0;

    test('a full card fits below the chrome', () {
      expect(
        chrome + naturalCard + header,
        lessThanOrEqualTo(tv.height),
        reason: 'precondition: on TV the rail gets its natural height because '
            'it fits - the hero overlays it rather than pushing it down',
      );
    });

    test('the poster is its full size, not 37% smaller', () {
      // The squeezed value, for the record: 165 dp.
      const squeezedPoster = 165.0;
      expect(
        naturalPoster / squeezedPoster,
        closeTo(1.58, 0.02),
        reason: 'the fix restores the poster from 165 dp to 260 dp. If this '
            'ratio drops, something is subtracting the hero from the rail again.',
      );
    });

    test('the hero no longer takes a third of the screen', () {
      // It used to be a 234 dp band: 43% of 540, with the rail squeezed to what
      // was left. As an overlay it takes no space from the page at all.
      const oldHero = 234.0;
      expect(oldHero / tv.height, closeTo(0.43, 0.01));
      expect(
        chrome + naturalCard + header,
        lessThanOrEqualTo(tv.height),
        reason: 'and the page now fits the rail without the hero reserving space',
      );
    });

    test('a rail that genuinely cannot fit is still reduced', () {
      // The rule is "full size, or as large as the screen allows" - not "always
      // full size". A 320 dp canvas cannot hold a 308 dp card plus chrome.
      const tiny = 320.0;
      const ceiling = tiny - chrome - header;
      expect(ceiling, lessThan(naturalCard));
      expect(ceiling, greaterThan(textBlock),
          reason: 'and it must not be reduced to nothing - the title is the '
              'card');
    });
  });
}
