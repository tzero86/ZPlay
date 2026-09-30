import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/player/engine/engine_selector.dart';
import 'package:zplay/services/player/engine/video_engine.dart';

/// The engine choice is the whole point of the second engine, and it is the one
/// piece of policy in it, so it is tested as policy rather than through a player.
void main() {
  const EngineSelector selector = EngineSelector();

  group('EngineSelector', () {
    test('sends a mainstream http stream to Media3', () {
      final EngineChoice choice = selector.choose(
        const EngineRequest(url: 'https://cdn.example/movie.mkv'),
      );

      expect(choice.useExoPlayer, isTrue);
    });

    test('sends a torrent stream to mpv, because Media3 cannot play it', () {
      final EngineChoice choice = selector.choose(
        const EngineRequest(
          url: 'http://127.0.0.1:8080/stream',
          isTorrent: true,
        ),
      );

      expect(choice.useExoPlayer, isFalse);
      expect(choice.reason, contains('torrent'));
    });

    test('keeps live streams on mpv until the IPTV surface can fall back', () {
      final EngineChoice choice = selector.choose(
        const EngineRequest(url: 'https://cdn.example/live.m3u8', isLive: true),
      );

      expect(choice.useExoPlayer, isFalse);
    });

    test('forceMpv overrides everything, including torrents', () {
      const EngineSelector forced = EngineSelector(forceMpv: true);

      expect(
        forced
            .choose(const EngineRequest(url: 'https://cdn.example/a.mkv'))
            .useExoPlayer,
        isFalse,
      );
      expect(
        forced
            .choose(
              const EngineRequest(
                url: 'https://cdn.example/live.m3u8',
                isLive: true,
              ),
            )
            .useExoPlayer,
        isFalse,
      );
    });

    test('every choice explains itself, so a fallback can be logged', () {
      final List<EngineRequest> requests = <EngineRequest>[
        const EngineRequest(url: 'https://cdn.example/a.mkv'),
        const EngineRequest(url: 'http://127.0.0.1:8080/s', isTorrent: true),
        const EngineRequest(url: 'https://cdn.example/live.m3u8', isLive: true),
      ];

      for (final EngineRequest request in requests) {
        expect(selector.choose(request).reason, isNotEmpty);
      }
    });
  });

  group('EngineRequest', () {
    test('only a torrent needs mpv', () {
      expect(const EngineRequest(url: 'https://a/b.mkv').needsMpv, isFalse);
      expect(
        const EngineRequest(
          url: 'http://127.0.0.1/s',
          isTorrent: true,
        ).needsMpv,
        isTrue,
      );
    });
  });

  group('EngineState', () {
    test('copyWith keeps fields it was not given', () {
      const EngineState original = EngineState(
        playing: true,
        position: Duration(seconds: 30),
        decodedWidth: 3840,
        decodedHeight: 2160,
      );

      final EngineState next = original.copyWith(playing: false);

      expect(next.playing, isFalse);
      expect(next.position, const Duration(seconds: 30));
      // A decoded size is the only signal the no-video watchdog has that a
      // frame actually arrived, so it must survive unrelated updates.
      expect(next.decodedWidth, 3840);
      expect(next.decodedHeight, 2160);
    });

    test('a copy cannot clear a decoded size, which is the safe direction', () {
      const EngineState original = EngineState(decodedWidth: 1920);

      expect(original.copyWith(playing: true).decodedWidth, 1920);
    });
  });
}
