import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/music/convertytmp3_client.dart';

void main() {
  group('Convertytmp3Client.isTrustedApiUrl', () {
    test('accepts the conversion API domains over HTTPS', () {
      expect(
        Convertytmp3Client.isTrustedApiUrl(
          'https://epsilon.epsiloncloud.org/api/v1/auth',
        ),
        isTrue,
      );
      expect(
        Convertytmp3Client.isTrustedApiUrl('https://convertytmp3.org/api'),
        isTrue,
      );
    });

    test('rejects cleartext, other hosts, suffix tricks, and userinfo', () {
      for (final url in [
        'http://epsilon.epsiloncloud.org/api',
        'https://epsiloncloud.org.evil.example/api',
        'https://evil.example/api',
        'https://user:pass@epsilon.epsiloncloud.org/api',
        'https:///api',
      ]) {
        expect(Convertytmp3Client.isTrustedApiUrl(url), isFalse, reason: url);
      }
    });
  });

  group('Convertytmp3Client.isSafeDownloadUrl', () {
    test('accepts a public HTTP(S) download target', () {
      expect(
        Convertytmp3Client.isSafeDownloadUrl('https://cdn.example.com/a.mp3'),
        isTrue,
      );
      expect(
        Convertytmp3Client.isSafeDownloadUrl('http://cdn.example.com/a.mp3'),
        isTrue,
      );
    });

    test('rejects local, non-HTTP, and credential-bearing targets', () {
      for (final url in [
        'http://127.0.0.1/a.mp3',
        'http://10.0.0.1/a.mp3',
        'http://169.254.1.1/a.mp3',
        'file:///etc/passwd',
        'https://user:pass@cdn.example.com/a.mp3',
      ]) {
        expect(Convertytmp3Client.isSafeDownloadUrl(url), isFalse, reason: url);
      }
    });
  });
}
