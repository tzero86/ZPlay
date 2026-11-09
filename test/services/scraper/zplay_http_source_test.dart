import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/services/scraper/sites/vidfast.dart';
import 'package:zplay/services/scraper/sites/zxcstream.dart';
import 'package:zplay/services/scraper/stream_scraper.dart';

void main() {
  test('converted scrapers keep their provider identity', () {
    final scraper = VidFastScraper();
    expect(scraper.name, 'ZPlayHTTP');
    expect(scraper, isA<HttpScraper>());

    // providerId/providerName key off runtimeType and must not have shifted.
    expect(scraper.providerId, 'vidfast');
    expect(scraper.providerName, 'VidFast');

    final other = ZxcStreamScraper();
    expect(other.name, 'ZPlayHTTP');
    expect(other.providerId, 'zxcstream');
  });

  test('zplayHttp mirrors headers into the proxy request', () {
    const headers = {
      'User-Agent': kZplayUserAgent,
      'Referer': 'https://example.test/',
      'Origin': 'https://example.test',
    };
    final source = StreamSource.zplayHttp(
      url: 'https://cdn.example.test/a.m3u8',
      title: 'Example · Direct · 1080p',
      description: 'Example Direct HLS',
      headers: headers,
    );

    expect(source.name, 'ZPlayHTTP');
    expect(source.addonName, 'ZPlayHTTP');
    expect(source.title, 'Example · Direct · 1080p');
    expect(source.headers, same(headers));
    expect(source.behaviorHints!['notWebReady'], isFalse);
    expect(
      (source.behaviorHints!['proxyHeaders'] as Map)['request'],
      headers,
      reason: 'the fetcher reads the request map, not the headers field',
    );
    // No provider metadata leaks in from the factory.
    expect(source.providerId, isNull);
    expect(source.infoHash, isNull);
  });

  test('zplayHttp without headers emits no empty proxy request', () {
    final source = StreamSource.zplayHttp(
      url: 'https://cdn.example.test/b.m3u8',
      title: 'No headers',
    );
    expect(source.headers, isNull);
    expect(source.behaviorHints!['notWebReady'], isFalse);
    expect(source.behaviorHints!.containsKey('proxyHeaders'), isFalse);
  });

  test('an explicit name and hints win over the defaults', () {
    final source = StreamSource.zplayHttp(
      url: 'https://cdn.example.test/c.m3u8',
      title: 'Named',
      name: 'Group 7',
      behaviorHints: const {'notWebReady': true},
    );
    expect(source.name, 'Group 7');
    expect(source.addonName, 'ZPlayHTTP');
    expect(source.behaviorHints, const {'notWebReady': true});
  });
}