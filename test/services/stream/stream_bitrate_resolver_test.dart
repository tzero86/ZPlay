import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/stream/stream_bitrate_resolver.dart';

void main() {
  group('StreamBitrateResolver.parseManifestKbps', () {
    test('picks the highest BANDWIDTH variant, not the first', () {
      const manifest =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2120000,RESOLUTION=960x540\n'
          'v540.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=4864000,RESOLUTION=1280x720\n'
          'v720.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=15480000,RESOLUTION=1920x1080\n'
          'v1080.m3u8\n';
      expect(StreamBitrateResolver.parseManifestKbps(manifest), 15480);
    });

    test('returns null for a media playlist without variants', () {
      const manifest =
          '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXTINF:10.0,\n'
          'segment1.ts\n';
      expect(StreamBitrateResolver.parseManifestKbps(manifest), isNull);
    });

    test('returns null when variants declare no BANDWIDTH', () {
      const manifest =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:RESOLUTION=1280x720\n'
          'v720.m3u8\n';
      expect(StreamBitrateResolver.parseManifestKbps(manifest), isNull);
    });

    test('returns null for empty or whitespace manifests', () {
      expect(StreamBitrateResolver.parseManifestKbps(''), isNull);
      expect(StreamBitrateResolver.parseManifestKbps(' \n\t '), isNull);
    });

    test('ignores a stray BANDWIDTH outside a variant declaration', () {
      // Only #EXT-X-STREAM-INF lines make a master playlist; a BANDWIDTH
      // attribute on anything else must not be reported as a variant.
      const manifest =
          '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXT-X-SOMETHING:BANDWIDTH=9000000\n'
          '#EXTINF:10.0,\n'
          'segment1.ts\n';
      expect(StreamBitrateResolver.parseManifestKbps(manifest), isNull);
    });
  });
}
