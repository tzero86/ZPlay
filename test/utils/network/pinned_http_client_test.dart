import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/network/pinned_http_client.dart';

void main() {
  group('PinnedHttpClient.connectionFactory', () {
    test('rejects a hostname that resolves to loopback', () async {
      final factory = PinnedHttpClient.connectionFactory(
        resolve: (_) async => [InternetAddress('127.0.0.1')],
      );

      await expectLater(
        factory(Uri.parse('https://rebind.example/segment.ts'), null, null),
        throwsA(isA<SocketException>()),
      );
    });

    test('rejects a hostname when any answer is private', () async {
      final factory = PinnedHttpClient.connectionFactory(
        resolve: (_) async => [
          InternetAddress('93.184.216.34'),
          InternetAddress('10.0.0.5'),
        ],
      );

      await expectLater(
        factory(Uri.parse('https://mixed.example/segment.ts'), null, null),
        throwsA(isA<SocketException>()),
      );
    });

    test('rejects proxied connections', () async {
      final factory = PinnedHttpClient.connectionFactory(
        resolve: (_) async => [InternetAddress('93.184.216.34')],
      );

      await expectLater(
        factory(Uri.parse('https://example.com/'), 'proxy.example', 8080),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
