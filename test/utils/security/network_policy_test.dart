import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/security/network_policy.dart';

void main() {
  group('NetworkPolicy.isLocalHost', () {
    for (final host in [
      'localhost',
      'app.localhost',
      'printer.local',
      '127.0.0.1',
      '127.1',
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '169.254.10.20',
      '100.64.0.1',
      '0.0.0.0',
      '2130706433',
      '0x7f000001',
      '0177.0.0.1',
      '127.000.000.001',
      '0x7f.0.0.1',
      '127.0.0.256',
      '192.0.0.1',
      '192.0.2.1',
      '198.51.100.1',
      '203.0.113.1',
      '::1',
      'fe80::1',
      'fc00::1',
      '::ffff:127.0.0.1',
    ]) {
      test('treats $host as local', () {
        expect(NetworkPolicy.isLocalHost(host), isTrue);
      });
    }

    for (final host in [
      'example.com',
      '8.8.8.8',
      '172.32.0.1',
      '192.0.1.7',
      '192.169.0.1',
      '198.51.1.7',
      '203.0.1.7',
      '2606:4700:4700::1111',
    ]) {
      test('treats $host as public', () {
        expect(NetworkPolicy.isLocalHost(host), isFalse);
      });
    }
  });

  group('NetworkPolicy.isAllowedHttpUri', () {
    test('accepts public HTTP and HTTPS', () {
      expect(
        NetworkPolicy.isAllowedHttpUri(
          Uri.parse('https://example.com/playlist.m3u8'),
          allowLocal: false,
        ),
        isTrue,
      );
      expect(
        NetworkPolicy.isAllowedHttpUri(
          Uri.parse('http://example.com/playlist.m3u8'),
          allowLocal: false,
        ),
        isTrue,
      );
    });

    test('rejects non-HTTP schemes and an empty host', () {
      expect(
        NetworkPolicy.isAllowedHttpUri(
          Uri.parse('ftp://example.com/file'),
          allowLocal: false,
        ),
        isFalse,
      );
      expect(
        NetworkPolicy.isAllowedHttpUri(
          Uri.parse('https:///no-host'),
          allowLocal: false,
        ),
        isFalse,
      );
    });

    test('rejects local targets unless the source is local', () {
      final uri = Uri.parse('http://127.0.0.1/segment.ts');
      expect(NetworkPolicy.isAllowedHttpUri(uri, allowLocal: false), isFalse);
      expect(NetworkPolicy.isAllowedHttpUri(uri, allowLocal: true), isTrue);
    });
  });

  group('NetworkPolicy.resolveHttpUri', () {
    test('resolves a relative segment on a public source', () {
      expect(
        NetworkPolicy.resolveHttpUri(
          Uri.parse('https://example.com/path/master.m3u8'),
          'segments/1.ts',
          allowLocal: false,
        ),
        Uri.parse('https://example.com/path/segments/1.ts'),
      );
    });

    test('rejects a relative reference that reaches a local address', () {
      expect(
        () => NetworkPolicy.resolveHttpUri(
          Uri.parse('https://example.com/path/master.m3u8'),
          '//127.0.0.1/segment.ts',
          allowLocal: false,
        ),
        throwsFormatException,
      );
    });
  });
}
