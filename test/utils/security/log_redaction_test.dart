import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/security/log_redaction.dart';

void main() {
  group('redactUrl', () {
    test('drops userinfo, path, query, and fragment', () {
      expect(
        redactUrl(
          'https://user:pass@example.com:8443/live/user/pass/1.ts?token=secret#t',
        ),
        'https://example.com:8443',
      );
    });

    test('keeps the default port implicit', () {
      expect(redactUrl('https://example.com/path'), 'https://example.com');
    });

    test('returns a placeholder for non-URLs', () {
      expect(redactUrl('not a url'), '<redacted>');
      expect(redactUrl(null), '<redacted>');
      expect(redactUrl(''), '<redacted>');
    });
  });

  group('redactTextUrls', () {
    test('redacts every URL in a diagnostic message', () {
      expect(
        redactTextUrls(
          'GET https://user:pass@one.example/live/a.ts failed; '
          'retry http://two.example:8080/x?key=secret',
        ),
        'GET https://one.example failed; retry http://two.example:8080',
      );
    });

    test('leaves text without URLs alone', () {
      expect(redactTextUrls('timeout after 10s'), 'timeout after 10s');
    });
  });
}
