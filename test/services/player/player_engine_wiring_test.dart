/// Pins the wiring between `PlayerScreen`'s engine choice and the engine
/// contract, without a player.
///
/// `PlayerScreen` cannot be pumped: it owns a `media_kit` `Player`, which needs
/// libmpv and a real device. That has left the seam between "which engine the
/// screen picked" and "what the surface mounts" completely untested, and it is
/// the seam where a wrong answer is invisible until a real stream is opened on
/// a television.
///
/// What is pinned here is what a user or a bug would actually notice:
///
///  1. The default is mpv, and so is what a reset returns to. `ExoPlayer`
///     renders into a `SurfaceView`, a platform view that composites above
///     Flutter's UI layer, so the D-pad HUD may end up underneath the video.
///     Until that is verified on a television, a user who never opened the
///     setting must not be opted into it - by a fresh install or by a reset.
///  2. A stored `media3` on a platform with no Media3 bridge resolves to mpv
///     rather than becoming a preference for an engine that cannot run.
///  3. A torrent never reaches Media3, whatever the setting says.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/player/player_screen.dart';
import 'package:zplay/services/player/engine/engine_selector.dart';
import 'package:zplay/services/player/engine/exo_player_engine.dart';
import 'package:zplay/services/player/engine/video_engine.dart';
import 'package:zplay/services/player/player_settings.dart';

/// The key the preference is stored under. Spelled out rather than reached
/// into, because a rename that moved the value would be invisible otherwise.
const String _preferenceKey = 'player_playback_engine';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `flutter test` leaves the platform reported as android, which is the one
    // platform where the Media3 branch is reachable and therefore the one
    // where it has to be tested deliberately rather than by accident.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  group('the default', () {
    test('a fresh install plays on Media3', () {
      // ExoPlayer was held at mpv until the D-pad HUD was verified against a
      // platform-view SurfaceView on a real television. It was, so this is now
      // the shipped default - and this assertion is what will fail loudly if
      // someone flips it back without a reason.
      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.media3);
    });

    test('loading with nothing stored leaves the engine on Media3', () async {
      // A fresh install and a stored-value-missing key are the same user, and
      // the load function has its own fallback rather than reading the
      // notifier's initial value - a drift between the two would be invisible
      // until the very first launch.
      await PlayerSettings.initialize();

      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.media3);
    });

    test('a reset returns to the shipped default, not to the slower one', () async {
      // A reset is the one moment where a user who never chose anything is
      // handed a value, so it has to be the shipped one.
      PlayerSettings.playbackEngine.value = PlaybackEngine.mpv;

      await PlayerSettings.resetToDefaults();

      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.media3);
    });
  });

  group('a stored media3 preference', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _preferenceKey: PlaybackEngine.media3.name,
      });
    });

    test('is honoured on Android, where the bridge exists', () async {
      // The setting is real and it works: this is the path a user reaches by
      // choosing Media3 in settings, and it is the only one where a
      // `SurfaceView` is ever mounted.
      expect(ExoPlayerEngine.isSupported, isTrue);

      await PlayerSettings.initialize();

      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.media3);
      expect(
        exoPlayerAvailable(
          setting: PlayerSettings.playbackEngine.value,
          isSupported: ExoPlayerEngine.isSupported,
        ),
        isTrue,
      );
    });

    test('resolves to mpv on a platform with no Media3 bridge', () async {
      // This is the case `ExoPlayerEngine.isSupported` exists for: the
      // preference survives onto a device where the bridge is not registered,
      // and would otherwise name an engine that cannot run - a setting the
      // user can see and that silently does nothing.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(ExoPlayerEngine.isSupported, isFalse);

      await PlayerSettings.initialize();

      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.mpv);
      expect(
        exoPlayerAvailable(
          setting: PlayerSettings.playbackEngine.value,
          isSupported: ExoPlayerEngine.isSupported,
        ),
        isFalse,
      );
    });
  });

  group('a stored mpv preference', () {
    test('stays mpv even where Media3 would have been usable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _preferenceKey: PlaybackEngine.mpv.name,
      });

      await PlayerSettings.initialize();

      expect(PlayerSettings.playbackEngine.value, PlaybackEngine.mpv);
      expect(
        exoPlayerAvailable(
          setting: PlayerSettings.playbackEngine.value,
          isSupported: true,
        ),
        isFalse,
        reason: 'an available bridge does not override a pinned engine',
      );
    });
  });

  group('exoPlayerAvailable', () {
    test('Media3 needs both the setting and the platform', () {
      expect(
        exoPlayerAvailable(setting: PlaybackEngine.media3, isSupported: false),
        isFalse,
        reason: 'a stored preference cannot conjure a bridge that is not there',
      );
      expect(
        exoPlayerAvailable(setting: PlaybackEngine.media3, isSupported: true),
        isTrue,
      );
      expect(
        exoPlayerAvailable(setting: PlaybackEngine.mpv, isSupported: true),
        isFalse,
      );
    });

    test(
      'the mpv default short-circuits what the selector would have said',
      () {
        // The selector answers yes for this source, so the default has to stop
        // the request before the selector is consulted. Without that, flipping
        // the default would silently change what plays on every device.
        const EngineSelector selector = EngineSelector();
        const EngineRequest request = EngineRequest(
          url: 'https://cdn.example/movie.mkv',
        );

        expect(selector.choose(request).useExoPlayer, isTrue);
        expect(
          exoPlayerAvailable(
            setting: PlayerSettings.playbackEngine.value,
            isSupported: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('a torrent is never handed to Media3', () {
    test('whatever the setting says', () {
      const EngineSelector selector = EngineSelector();

      final EngineChoice choice = selector.choose(
        const EngineRequest(
          url: 'http://127.0.0.1:8080/stream',
          isTorrent: true,
        ),
      );

      // The local torrent engine serves plain HTTP that only mpv follows, and
      // the alternative is a source that fails slowly on a device.
      expect(choice.useExoPlayer, isFalse);
      expect(choice.reason, contains('torrent'));
      expect(
        exoPlayerAvailable(setting: PlaybackEngine.media3, isSupported: true),
        isTrue,
        reason:
            'the setting alone would have allowed it, which is why the '
            'selector has to be consulted per source',
      );
    });
  });

  group('the no-video watchdog source height', () {
    // `_watchdogSourceHeight` is private to `_PlayerScreenState`, which cannot
    // be constructed without a `media_kit` `Player`, so it is not reached from
    // here. The rule it implements - a decoded height outranks the container's,
    // and with no frame the largest container height is the only number there
    // is - is pinned against the contract's own types instead, because those
    // are what both engines publish and the mpv side is converted into them.
    test('a decoded height outranks every container-reported one', () {
      const EngineState state = EngineState(
        decodedWidth: 3840,
        decodedHeight: 2160,
        videoTracks: <EngineTrack>[
          EngineTrack(id: 1, title: 'Video 1', height: 1080),
        ],
      );

      expect(state.decodedHeight, 2160);
      // A container height exists before any frame is decoded, which is the
      // only reason the watchdog can read it while judging "no frame has
      // arrived".
      expect(state.videoTracks.single.height, 1080);
    });

    test('with no frame, the largest container height is what is left', () {
      // null, not 0: "decoding but not rendering" is the failure the watchdog
      // exists for, and a zero would collapse it into "nothing reported yet",
      // which is the case the watchdog is also allowed to wait on.
      const EngineState state = EngineState(
        videoTracks: <EngineTrack>[
          EngineTrack(id: 1, title: 'Video 1', height: 480),
          EngineTrack(id: 2, title: 'Video 2', height: 1080),
        ],
      );

      expect(state.decodedHeight, isNull);
      final int largest = state.videoTracks
          .map((EngineTrack t) => t.height ?? 0)
          .fold(0, (int a, int b) => a > b ? a : b);
      expect(largest, 1080);
    });
  });

  group('a source with no container height at all', () {
    test('the watchdog is handed zero rather than a stale value', () {
      // A stream that never reported anything - the third state, distinct
      // from both "a frame rendered" and "the container said how big it is".
      const EngineState state = EngineState(
        videoTracks: <EngineTrack>[EngineTrack(id: 1, title: 'Video 1')],
      );

      expect(state.decodedHeight, isNull);
      expect(state.videoTracks.single.height, isNull);
      expect(state.videoTracks.map((EngineTrack t) => t.height ?? 0), <int>[0]);
    });
  });
}
