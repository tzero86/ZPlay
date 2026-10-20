/// Semantics for the app's primary content and player controls.
///
/// The rules asserted here are the ones a screen reader depends on:
///
/// * A poster card is *one* button named `title, year` with the hint "Open
///   details" - not a stack of text nodes that reads the caption twice.
/// * A Continue Watching card says what it resumes and how far in.
/// * Player controls keep their name (tooltip first, icon second), report
///   whether they are enabled, and say so when they are toggles.
/// * The timeline and volume tracks are sliders whose value is readable and
///   whose increase/decrease actions move by the same step the arrow keys use.
///
/// Plus one 200% text-scale smoke test for a card and the transport, because a
/// screen reader and a large font are the same user.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/anime/anime_media.dart';
import 'package:zplay/models/continue_watching/continue_watching_item.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/continue_watching/continue_watching_service.dart';
import 'package:zplay/utils/a11y.dart';
import 'package:zplay/widgets/anime/anime_card.dart';
import 'package:zplay/widgets/home/continue_watching_slider.dart';
import 'package:zplay/widgets/movie/movie_card.dart';
import 'package:zplay/widgets/player/player_glass.dart';
import 'package:zplay/widgets/player/player_seek_bar.dart';
import 'package:zplay/widgets/player/player_transport.dart';
import 'package:zplay/widgets/player/player_volume_control.dart';

/// The app's standard host: the tokens resolve from the ambient theme, so a
/// plain [MaterialApp] is enough.
Widget _host(Widget child, {double width = 400, double height = 600}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

/// The same host with a 200% text scale, applied through the app's builder so
/// `MediaQuery.sizeOf` keeps the real canvas.
Widget _hostAt200PercentText(Widget child) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2.0)),
    child: app!,
  ),
  home: Scaffold(
    body: Center(child: SizedBox(width: 220, height: 700, child: child)),
  ),
);

Movie _movie({String name = 'Probe Title', String? year = '2024'}) => Movie(
  id: 'probe',
  name: name,
  year: year,
  type: 'movie',
  addonBaseUrl: 'test',
);

void main() {
  group('the A11y helper', () {
    test('a card label joins title and year, and skips an empty year', () {
      expect(A11y.cardLabel('Dune'), 'Dune');
      expect(A11y.cardLabel('Dune', year: '  '), 'Dune');
      expect(A11y.cardLabel('Dune', year: '2021'), 'Dune, 2021');
    });

    test('a resume label states how far in the user is', () {
      expect(A11y.resumeLabel('Dune', 0.4235), 'Resume Dune, 42% watched');
      expect(
        A11y.resumeLabel('Dune', 2.0),
        'Resume Dune, 100% watched',
        reason: 'a stored progress beyond 100% is clamped, not printed',
      );
    });

    testWidgets('announcing is safe with an initialized binding', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      // Both routes into the announcement: the binding's implicit view and an
      // explicit context. Neither may assert on a headless host.
      A11y.announce('Now playing');
      A11y.announce(
        'Now playing',
        context: tester.element(find.byType(Scaffold)),
      );
      await tester.pump();
    });
  });

  group('poster cards', () {
    testWidgets('a movie card is one button named title and year', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_host(MovieCard(movie: _movie(), onTap: () {})));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Probe Title, 2024')),
        matchesSemantics(
          label: 'Probe Title, 2024',
          hint: 'Open details',
          isButton: true,
          hasTapAction: true,
        ),
        reason: 'the card announces once, as a destination, not as a caption',
      );

      // Disposed before the test body returns: the framework checks handles
      // before tearDown callbacks run.
      handle.dispose();
    });

    testWidgets('the year is dropped when the catalog does not know it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(MovieCard(movie: _movie(year: null), onTap: () {})),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Probe Title')),
        matchesSemantics(
          label: 'Probe Title',
          hint: 'Open details',
          isButton: true,
          hasTapAction: true,
        ),
        reason: 'no dangling comma for an unknown year',
      );

      handle.dispose();
    });

    testWidgets('an anime card carries its own title and year', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          AnimeCard(
            anime: const AnimeMedia(
              id: 1,
              titleEnglish: 'Probe Anime',
              seasonYear: 2021,
              format: 'TV',
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(AnimeCard)),
        matchesSemantics(
          label: 'Probe Anime, 2021',
          hint: 'Open details',
          isButton: true,
          hasTapAction: true,
        ),
      );

      handle.dispose();
    });
  });

  group('continue watching', () {
    testWidgets('the card says what resumes and how far in', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(() => ContinueWatchingService.activeItems.value = const []);

      ContinueWatchingService.activeItems.value = [
        ContinueWatchingItem(
          id: 'probe',
          title: 'Probe Show',
          type: 'movie',
          positionSeconds: 2520,
          totalDurationSeconds: 6000,
          lastWatchedAt: DateTime(2024),
          isTorrent: false,
        ),
      ];

      await tester.pumpWidget(
        _host(const ContinueWatchingSlider(), width: 800, height: 400),
      );
      await tester.pump();

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Resume Probe Show, 42% watched'),
        ),
        matchesSemantics(
          label: 'Resume Probe Show, 42% watched',
          hint: 'Resume playback',
          isButton: true,
          hasTapAction: true,
        ),
        reason: 'the percentage is the state the user resumes from',
      );

      handle.dispose();
    });
  });

  group('player icon buttons', () {
    testWidgets('a button is named by its tooltip and reports enabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      var pressed = 0;
      await tester.pumpWidget(
        _host(
          PlayerIconButton(
            icon: const Icon(Icons.subtitles_rounded),
            tooltip: 'Subtitles',
            onPressed: () => pressed++,
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Subtitles')),
        matchesSemantics(
          label: 'Subtitles',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      tester.semantics.tap(find.semantics.byLabel('Subtitles'));
      expect(pressed, 1, reason: 'the semantics tap reaches the button action');

      handle.dispose();
    });

    testWidgets('a disabled button says it is disabled', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const PlayerIconButton(
            icon: Icon(Icons.cast_rounded),
            tooltip: 'Cast',
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Cast')),
        matchesSemantics(
          label: 'Cast',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      handle.dispose();
    });

    testWidgets('a toggle reports its state', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          PlayerIconButton(
            icon: const Icon(Icons.video_library_rounded),
            tooltip: 'Episodes',
            active: true,
            activeColor: Colors.orange,
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Episodes')),
        matchesSemantics(
          label: 'Episodes',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('an icon without a tooltip still gets a name', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          PlayerIconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Close')),
        matchesSemantics(
          label: 'Close',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
        reason: 'an unnamed button is announced as "button" and is useless',
      );

      handle.dispose();
    });
  });

  group('the timeline', () {
    testWidgets('is a slider with a readable value and arrow-sized steps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final seeks = <Duration>[];
      await tester.pumpWidget(
        _host(
          PlayerSeekBar(
            position: const Duration(minutes: 12, seconds: 34),
            duration: const Duration(minutes: 45),
            onSeek: seeks.add,
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Playback position')),
        matchesSemantics(
          label: 'Playback position',
          value: '12:34 of 45:00',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      tester.semantics.increase(find.semantics.byLabel('Playback position'));
      expect(seeks, [
        const Duration(minutes: 12, seconds: 44),
      ], reason: 'increase is the ten seconds the right arrow seeks');

      seeks.clear();
      tester.semantics.decrease(find.semantics.byLabel('Playback position'));
      expect(seeks, [
        const Duration(minutes: 12, seconds: 24),
      ], reason: 'decrease is the ten seconds the left arrow seeks');

      handle.dispose();
    });
  });

  group('the volume track', () {
    testWidgets('is a slider whose value is the percentage', (tester) async {
      final handle = tester.ensureSemantics();

      final changes = <double>[];
      await tester.pumpWidget(
        _host(
          PlayerVolumeControl(
            volume: 0.70,
            isMuted: false,
            onVolumeChanged: changes.add,
            onToggleMute: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')),
        matchesSemantics(
          label: 'Volume',
          value: 'Volume 70%',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      tester.semantics.increase(find.semantics.byLabel('Volume'));
      expect(changes, [
        0.75,
      ], reason: 'increase is the five percent the up arrow raises');

      changes.clear();
      tester.semantics.decrease(find.semantics.byLabel('Volume'));
      expect(changes, [
        0.65,
      ], reason: 'decrease is the five percent the down arrow lowers');

      handle.dispose();
    });

    testWidgets('a muted track reads zero', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          PlayerVolumeControl(
            volume: 0.70,
            isMuted: true,
            onVolumeChanged: (_) {},
            onToggleMute: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')),
        matchesSemantics(
          label: 'Volume',
          value: 'Volume 0%',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      handle.dispose();
    });
  });

  group('200% text scale', () {
    testWidgets('a card lays out without overflow', (tester) async {
      await tester.pumpWidget(
        _hostAt200PercentText(MovieCard(movie: _movie(), onTap: () {})),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a card is readable at 200% text scale too',
      );
    });

    testWidgets('the transport lays out without overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: app!,
          ),
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PlayerTransport(
                  isPlaying: false,
                  position: const Duration(minutes: 12, seconds: 34),
                  duration: const Duration(minutes: 45),
                  volume: 0.7,
                  isMuted: false,
                  playbackRate: 1.0,
                  isSubtitlesActive: false,
                  isSubSyncActive: false,
                  isAudioActive: false,
                  isFullscreen: false,
                  onPlayPause: () {},
                  onSeek: (_) {},
                  onSeekBack10: () {},
                  onSeekForward10: () {},
                  onVolumeChanged: (_) {},
                  onToggleMute: () {},
                  onToggleAspectMenu: () {},
                  onToggleSpeedMenu: () {},
                  onToggleAudioMenu: () {},
                  onToggleSubtitleMenu: () {},
                  onToggleSubSync: () {},
                  onToggleFullscreen: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the transport is readable at 200% text scale too',
      );
    });
  });
}
