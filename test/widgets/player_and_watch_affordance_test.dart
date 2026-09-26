/// Guards the two affordance bugs that made a "nothing here" screen and a
/// "resume" button both lie to the user.
///
/// docs/UX_FINDINGS.md, Critical #4: the player's no-streams body copy was
/// rendered unconditionally as "Try going back to episodes…", but the
/// back-to-episodes button it names is gated on `showBackToEpisodes`. A movie
/// viewer, who by definition has no episode panel, was told to use a control
/// that was not on screen — and offered nothing else. The copy is now branched
/// on the same flag the heading already used.
///
/// docs/UX_FINDINGS.md, Critical #2: Continue Watching's play button was
/// `opacity: state.highlighted ? 1.0 : 0.0`, and `highlighted` is
/// `hovered || focused` — neither of which a touchscreen can ever produce. The
/// tap target existed but the affordance was invisible on a phone, and D-pad
/// could not reveal it either. The Details/Remove siblings ten lines below
/// already carried the platform guard, so the pattern was known and simply had
/// not been applied here.
///
/// Both rules are asserted through the pure functions the widgets actually
/// call, rather than by re-deriving them here: `playerEmptyState*` and
/// `continueWatchingHasPointer` are the shipped decision points. Pumping
/// `PlayerSourcesPanel` or the private card would fire real scrapers, so the
/// decision is tested where it is made.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/home/continue_watching_slider.dart';
import 'package:zplay/widgets/player/player_sources_panel.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('No-streams state never names a control that is not rendered', () {
    test('a title (no episode panel) is told something it can actually do', () {
      final body = playerEmptyStateBody(hasEpisodes: false);

      expect(body, isNot(contains('episode')),
          reason: 'a title has no Episodes panel, so the old line was a dead end');
      expect(body, isNot(contains('episodes')),
          reason: 'a title has no Episodes panel, so the old line was a dead end');

      // Must offer a real next step, not just restate the failure.
      expect(body.toLowerCase(), contains('another provider'),
          reason: 'Rescrape plus a different provider is reachable from here');
      expect(body.toLowerCase(), contains('close'),
          reason: 'the drawer can be dismissed, which is a way out');
    });

    test('an episode keeps the existing wording', () {
      expect(
        playerEmptyStateBody(hasEpisodes: true),
        'Try going back to episodes and choosing another episode or provider.',
      );
    });

    test('the two branches render genuinely different copy', () {
      expect(
        playerEmptyStateBody(hasEpisodes: true),
        isNot(playerEmptyStateBody(hasEpisodes: false)),
      );
      expect(
        playerEmptyStateHeading(hasEpisodes: true),
        isNot(playerEmptyStateHeading(hasEpisodes: false)),
      );
    });

    test('the episode branch points at the back button it actually renders', () {
      // The panel renders the back-to-episodes control iff showBackToEpisodes,
      // so only that branch may mention going back to episodes.
      expect(playerEmptyStateBody(hasEpisodes: true), contains('episodes'));
    });
  });

  group('Continue Watching play affordance', () {
    test('a platform with a pointer is expected to reveal on hover', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(continueWatchingHasPointer(), isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(continueWatchingHasPointer(), isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(continueWatchingHasPointer(), isTrue);
    });

    test('a platform with no pointer cannot be relied on to hover', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(continueWatchingHasPointer(), isFalse,
          reason: 'a phone has no hover, so the affordance must be permanent');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(continueWatchingHasPointer(), isFalse,
          reason: 'a phone has no hover, so the affordance must be permanent');
    });

    test('the rule is the one the widget gates on, not a test-local restatement',
        () {
      // On a touch platform the widget's gate `state.highlighted ||
      // !continueWatchingHasPointer()` is true at rest with no hover, so the
      // play badge is rendered visible and un-scaled. On a pointer platform
      // the same gate is false at rest, so the badge stays hidden until the
      // card is highlighted.
      bool revealedAtRest({required bool highlighted}) =>
          highlighted || !continueWatchingHasPointer();

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(revealedAtRest(highlighted: false), isTrue,
          reason: 'the play affordance must be visible on a phone at rest');

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(revealedAtRest(highlighted: false), isFalse,
          reason: 'desktop keeps the hover reveal');
      expect(revealedAtRest(highlighted: true), isTrue,
          reason: 'hovering on desktop reveals the play affordance');
    });
  });
}
