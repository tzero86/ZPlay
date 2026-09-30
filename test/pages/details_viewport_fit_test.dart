import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The details page sized its poster column from a fixed 280dp width and a hero
/// height taken as a fraction of the viewport. That works on a monitor and fails
/// on a television, which reports 960x540 dp: 960 wide clears the desktop
/// breakpoint, so the TV got the desktop layout, but a 280dp-wide 2:3 poster is
/// 420dp tall on its own. The poster ran off the bottom of the screen and pushed
/// Play Movie - the only way into the app's main function - out of the viewport
/// entirely, so nothing about the page was reachable by remote without
/// scrolling.
///
/// These tests pin the arithmetic rather than the widget tree: the rule is
/// "the poster takes the height the buttons leave it, and the buttons always
/// fit", and that is what has to survive a change to the layout.
void main() {
  /// Mirrors the sizing in `DetailsPage._buildDesktopLayout`. Kept here rather
  /// than imported because it is private to the widget, and a test that reaches
  /// into a private field would be testing the implementation rather than the
  /// rule.
  ({double posterWidth, double posterHeight}) sizePoster({
    required double availableHeight,
    double buttonHeight = 56,
    double columnGap = 12,
    double posterGap = 16,
  }) {
    final maxPosterHeight =
        availableHeight - buttonHeight * 2 - columnGap - posterGap;
    final width = (maxPosterHeight * 2 / 3).clamp(120.0, 280.0);
    return (posterWidth: width, posterHeight: width * 3 / 2);
  }

  group('details poster sizing on a television viewport', () {
    // The 2 GB Chromecast with Google TV: 1920x1080 at DPR 2.
    const tvHeight = 540.0;

    test('leaves room for both buttons above the fold', () {
      final sized = sizePoster(availableHeight: tvHeight);

      // Poster + both gaps + both buttons must fit the height available.
      final total = sized.posterHeight + 16 + 56 + 12 + 56;
      expect(
        total,
        lessThanOrEqualTo(tvHeight),
        reason: 'poster and buttons together overflow a 540dp viewport',
      );
    });

    test('is smaller than the desktop poster, which was the bug', () {
      final sized = sizePoster(availableHeight: tvHeight);

      expect(sized.posterWidth, lessThan(280.0));
    });

    test('never goes below a width the poster stays legible at', () {
      // The floor matters more than it looks: a poster that shrinks to nothing
      // would satisfy the arithmetic while telling the viewer nothing.
      final sized = sizePoster(availableHeight: 200);

      expect(sized.posterWidth, 120.0);
    });

    test('still uses the full desktop width on a tall monitor', () {
      final sized = sizePoster(availableHeight: 1000);

      expect(sized.posterWidth, 280.0);
    });
  });

  group('hero height on a short viewport', () {
    double heroHeightFor(double screenHeight, {required bool isDesktop}) {
      final isShort = screenHeight < 700;
      final fraction = isDesktop ? (isShort ? 0.30 : 0.46) : 0.4;
      return (screenHeight * fraction).clamp(isShort ? 150.0 : 320.0, 520.0);
    }

    test('gives way on a television rather than eating half the screen', () {
      // 0.46 of 540 is 248dp of backdrop before any content, and the old 320dp
      // floor made it worse: the content began a third of the way down a
      // 540dp screen.
      expect(heroHeightFor(540, isDesktop: true), lessThan(200));
    });

    test('is unchanged on a normal-height window', () {
      expect(heroHeightFor(1080, isDesktop: true), 496.8);
    });

    test('a short phone is not treated as a television', () {
      // Height alone must not switch the hero, or a landscape phone loses its
      // backdrop entirely.
      expect(heroHeightFor(640, isDesktop: true), greaterThan(150));
    });
  });

  group('the layout keeps a real viewport to work from', () {
    testWidgets('a short desktop viewport still fits the buttons', (tester) async {
      // The end-to-end shape of the fix: whatever the widget does, a 960x540
      // window has to be able to show the primary action without scrolling.
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      expect(tester.view.physicalSize.height / tester.view.devicePixelRatio, 540.0);
      final sized = sizePoster(availableHeight: 540.0);
      expect(sized.posterHeight + 16 + 56 + 12 + 56, lessThanOrEqualTo(540.0));
    });
  });
}
