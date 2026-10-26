import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/stream/stream_model.dart';

void main() {
  group('StreamSource', () {
    group('quality detection', () {
      test('detects 4K from title', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.2160p.WEB-DL.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.quality, anyOf('4K', '2160p'));
      });
      test('detects 1080p from title', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.1080p.BluRay.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.quality, '1080p');
      });
      test('detects 720p from title', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.720p.HDTV.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.quality, '720p');
      });
    });
    group('HDR detection', () {
      test('detects Dolby Vision', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.2160p.DV.HDR.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.isHDR, true);
      });
      test('returns false for SDR', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.1080p.SDR.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.isHDR, false);
      });
    });
    group('codec detection', () {
      test('detects HEVC/x265', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.2160p.x265.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.codec, anyOf('HEVC', 'x265'));
      });
      test('detects H.264/x264', () {
        final source = StreamSource(
          addonName: 'TestAddon',
          name: 'Test',
          title: 'Movie.2024.1080p.x264.mkv\nScraper',
          url: 'https://x.com',
        );
        expect(source.codec, anyOf('AVC', 'H.264', 'x264'));
      });
    });
    group('qualityRank', () {
      test('4K ranks higher than 1080p', () {
        final fourK = StreamSource(
          addonName: 'TestAddon',
          name: 'A',
          title: '4K.Movie.mkv\nA',
          url: '',
        );
        final hd = StreamSource(
          addonName: 'TestAddon',
          name: 'B',
          title: '1080p.Movie.mkv\nB',
          url: '',
        );
        expect(fourK.qualityRank, isNotNull);
        expect(hd.qualityRank, isNotNull);
      });
    });

    group('provider label', () {
      // The label the source row and the player's top bar both show. One rule,
      // because the two surfaced different names for the same stream: the row
      // said 'ZPlayHTTP · A111477' while the chip over the video said the raw
      // group tag '111477', which reads as leftover debug chrome.
      test(
        'names the ZPlayHTTP provider rather than the scraped group tag',
        () {
          final source = StreamSource(
            addonName: 'ZPlayHTTP',
            name: '111477',
            providerName: 'A111477',
            url: 'https://x.com',
          );
          expect(source.providerLabel, 'ZPlayHTTP · A111477');
        },
      );

      test('keeps an addon stream name as it is', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          name: 'Torrentio',
          url: 'https://x.com',
        );
        expect(source.providerLabel, 'Torrentio');
      });

      test('falls back to the addon name when the source names nothing', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          url: 'https://x.com',
        );
        expect(source.providerLabel, 'Torrentio');
      });

      test('a ZPlayHTTP source with no provider still names itself', () {
        final source = StreamSource(
          addonName: 'zplayhttp',
          name: 'Cinejoy',
          url: 'https://x.com',
        );
        expect(source.providerLabel, 'Cinejoy');
      });
    });

    group('audio language detection (Spanish Castilian & Latin American)', () {
      test('detects Castilian Spanish from Castellano tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Gladiator.2000.1080p.BluRay.x264.Castellano.AC3',
          url: 'https://example.com',
        );
        final langs = source.getAudioLanguages();
        expect(langs.contains('spanish_castilian'), isTrue);
        expect(langs.contains('spanish'), isTrue);
        expect(langs.contains('spanish_latino'), isFalse);
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Castilian Spanish from [CAST] tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Gladiator.2000.1080p.[CAST].mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Castilian Spanish from ES-ES tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.WEB-DL.ES-ES.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Latin American Spanish from Latino tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Avengers.Endgame.2019.1080p.Dual.Audio.Latino-English.mkv',
          url: 'https://example.com',
        );
        final langs = source.getAudioLanguages();
        expect(langs.contains('spanish_latino'), isTrue);
        expect(langs.contains('spanish'), isTrue);
        expect(langs.contains('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects Latin American Spanish from [LAT] tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Dune.Part.Two.2024.1080p.[LAT].mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects Latin American Spanish from ES-419 tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.WEB-DL.ES-419.AAC.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects both Castilian and Latin American when both present', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Interstellar.2014.1080p.BluRay.Castellano.Latino.Eng.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST / 🇲🇽 LAT');
      });

      test('detects generic Spanish and badges as SPA', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.Spanish.AAC5.1.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
        expect(source.getAudioBadge(), '🇪🇸 SPA');
      });

      test('does not match subtitles listing as audio language', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.BluRay.x264\nSubs: Spanish, English, French',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish'), isFalse);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
      });
    });

    group('addon request headers', () {
      test('keeps media headers and drops credential-bearing ones', () {
        final source = StreamSource.fromJson({
          'url': 'https://cdn.example/video.m3u8',
          'headers': {
            'User-Agent': 'Test UA',
            'Referer': 'https://example.com/',
            'Origin': 'https://example.com',
            'Range': 'bytes=0-1',
            'Cookie': 'session=secret',
            'Authorization': 'Bearer secret',
            'Host': 'internal.example',
            'X-Api-Key': 'secret',
          },
        }, 'Addon');

        expect(source.headers, {
          'User-Agent': 'Test UA',
          'Referer': 'https://example.com/',
          'Origin': 'https://example.com',
          'Range': 'bytes=0-1',
        });
      });

      test('removes raw proxy headers from behavior hints', () {
        final source = StreamSource.fromJson({
          'url': 'https://cdn.example/video.m3u8',
          'behaviorHints': {
            'isLive': true,
            'proxyHeaders': {
              'request': {
                'Referer': 'https://example.com/',
                'Cookie': 'session=secret',
              },
            },
          },
        }, 'Addon');

        expect(source.headers, {'Referer': 'https://example.com/'});
        expect(source.behaviorHints?['proxyHeaders'], isNull);
        expect(source.behaviorHints?['isLive'], isTrue);
      });
    });
  });
}
