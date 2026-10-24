import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/anime_arabic/mega_proxy.dart';

void main() {
  group('MegaProxy.isAllowedOrigin', () {
    test('allows loopback origins on any port', () {
      expect(MegaProxy.isAllowedOrigin('http://127.0.0.1:8080'), isTrue);
      expect(MegaProxy.isAllowedOrigin('http://localhost:3000'), isTrue);
      expect(MegaProxy.isAllowedOrigin('http://[::1]:9090'), isTrue);
    });

    test('rejects internet, null, and malformed origins', () {
      expect(MegaProxy.isAllowedOrigin('https://evil.example'), isFalse);
      expect(MegaProxy.isAllowedOrigin('null'), isFalse);
      expect(MegaProxy.isAllowedOrigin('not an origin'), isFalse);
      expect(MegaProxy.isAllowedOrigin('file://'), isFalse);
    });
  });
}
