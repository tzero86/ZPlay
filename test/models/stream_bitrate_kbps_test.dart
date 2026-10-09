import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/stream/stream_model.dart';

void main() {
  group('StreamSource.bitrateKbps', () {
    test('parses Mb/s from the release name', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.WEB-DL.12.4 Mb/s.x264.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, 12400);
      expect(source.bitrateLabel, '12.4 Mb/s');
    });

    test('parses kb/s from the release name', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.720p.WEBRip.850 kb/s.x264.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, 850);
      expect(source.bitrateLabel, '850 kb/s');
    });

    test('parses comma-decimal Mbps', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.WEB-DL.12,4 Mbps.x264.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, 12400);
    });

    test('rejects audio-only rates below the floor', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.AAC.128kbps.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, isNull);
      expect(source.bitrateLabel, isNull);
    });

    test('reads the video rate even when an audio rate is listed first', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.AAC.128kbps.8.5Mb/s.x264.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, 8500);
    });

    test('returns null when no bitrate is stated', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.BluRay.x264.mkv',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, isNull);
      expect(source.bitrateLabel, isNull);
    });

    test('reads the rate from name and description too', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        name: 'Movie.2024.1080p',
        description: 'WEB-DL, video 8500 kbps, x264',
        url: 'https://example.com',
      );
      expect(source.bitrateKbps, 8500);
    });
  });

  group('StreamSource.estimatedBitrateKbps', () {
    test('derives from file size and runtime', () {
      // 2 GiB over 90 min -> (2147483648 * 8) / 5400s ~= 3181 kbps.
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.2.0 GB.mkv',
        url: 'https://example.com',
      );
      expect(source.estimatedBitrateKbps(90), 3181);
    });

    test('prefers the stated rate over the estimate', () {
      final source = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.2.0 GB.12Mb/s.mkv',
        url: 'https://example.com',
      );
      expect(source.estimatedBitrateKbps(90), 12000);
    });

    test('returns null when size or runtime is missing', () {
      final noSize = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.mkv',
        url: 'https://example.com',
      );
      expect(noSize.estimatedBitrateKbps(null), isNull);
      expect(noSize.estimatedBitrateKbps(90), isNull);

      final noRuntime = StreamSource(
        addonName: 'Torrentio',
        title: 'Movie.2024.1080p.2.0 GB.mkv',
        url: 'https://example.com',
      );
      expect(noRuntime.estimatedBitrateKbps(null), isNull);
      expect(noRuntime.estimatedBitrateKbps(0), isNull);
    });
  });

  group('StreamSource.formatBitrate', () {
    test('switches units at 1000 kbps', () {
      expect(StreamSource.formatBitrate(999), '999 kb/s');
      expect(StreamSource.formatBitrate(1000), '1.0 Mb/s');
      expect(StreamSource.formatBitrate(850), '850 kb/s');
      expect(StreamSource.formatBitrate(12400), '12.4 Mb/s');
    });
  });
}
