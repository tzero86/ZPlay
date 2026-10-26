import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/security/addon_headers.dart';

void main() {
  group('AddonHeaders.sanitize', () {
    test('keeps media request headers and canonicalizes their names', () {
      final headers = AddonHeaders.sanitize({
        'user-agent': 'Test UA',
        'referer': 'https://example.com/',
        'origin': 'https://example.com',
        'range': 'bytes=0-1023',
      });

      expect(headers, {
        'User-Agent': 'Test UA',
        'Referer': 'https://example.com/',
        'Origin': 'https://example.com',
        'Range': 'bytes=0-1023',
      });
    });

    test('drops credential-bearing, routing, and unknown headers', () {
      final headers = AddonHeaders.sanitize({
        'User-Agent': 'Test UA',
        'Cookie': 'session=secret',
        'Authorization': 'Bearer secret',
        'Proxy-Authorization': 'Basic secret',
        'Host': 'internal.example',
        'X-Api-Key': 'secret',
        'Set-Cookie': 'session=secret',
      });

      expect(headers, {'User-Agent': 'Test UA'});
    });

    test('drops values containing a line break', () {
      final headers = AddonHeaders.sanitize({
        'Referer': 'https://example.com/\r\nX-Injected: yes',
        'Accept': '*/*',
      });

      expect(headers, {'Accept': '*/*'});
    });

    test('returns null when no safe headers remain', () {
      expect(AddonHeaders.sanitize({'Cookie': 'x'}), isNull);
      expect(AddonHeaders.sanitize(null), isNull);
      expect(AddonHeaders.sanitize(const {}), isNull);
    });
  });

  group('AddonHeaders.stripRequestHeaderHints', () {
    test('removes raw request maps and keeps other hints', () {
      final hints = AddonHeaders.stripRequestHeaderHints({
        'isLive': true,
        'proxyHeaders': {
          'request': {'Cookie': 'secret'},
        },
        'requestHeaders': {'Authorization': 'Bearer secret'},
      });

      expect(hints, {'isLive': true});
    });

    test('returns null when only request maps remain', () {
      final hints = AddonHeaders.stripRequestHeaderHints({
        'proxyHeaders': {
          'request': {'Cookie': 'secret'},
        },
      });

      expect(hints, isNull);
    });
  });
}
