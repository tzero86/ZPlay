import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/security/external_url_policy.dart';

void main() {
  group('ExternalUrlPolicy.parse', () {
    test('accepts HTTP and HTTPS links', () {
      expect(
        ExternalUrlPolicy.parse('https://example.com/trailer')?.host,
        'example.com',
      );
      expect(
        ExternalUrlPolicy.parse('http://example.com/trailer')?.host,
        'example.com',
      );
    });

    test('normalizes and accepts a stremio detail link', () {
      final uri = ExternalUrlPolicy.parse('stremio:///detail/movie/tt1234567');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'stremio');
      expect(uri.host, 'detail');
      expect(uri.pathSegments, ['movie', 'tt1234567']);
    });

    test('rejects executable and local-file schemes', () {
      for (final raw in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'data:text/html,<script>alert(1)</script>',
        'mailto:test@example.com',
      ]) {
        expect(ExternalUrlPolicy.parse(raw), isNull, reason: raw);
      }
    });

    test('rejects empty, relative, and hostless HTTP links', () {
      expect(ExternalUrlPolicy.parse(''), isNull);
      expect(ExternalUrlPolicy.parse('/relative/path'), isNull);
      expect(ExternalUrlPolicy.parse('https:///no-host'), isNull);
    });
  });
}
