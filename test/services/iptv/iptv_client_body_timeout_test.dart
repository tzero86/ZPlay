@Tags(['network'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/iptv/iptv_models.dart';
import 'package:zplay/services/iptv/iptv_network.dart';

/// Localhost only, but it opens real sockets, so it carries the same tag as the
/// other live-network tests and stays out of the default suite.
class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _AllowAllHttpOverrides();
  });

  test('a portal that stalls mid-body is given up on, not waited on', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      // Headers and one byte, then a promise the server never keeps: the
      // response stays open with four kilobytes still owed.
      req.response.headers.contentType = ContentType.json;
      req.response.headers.contentLength = 4096;
      req.response.write('[');
      unawaited(req.response.flush());
    });

    final portal = IptvPortal(
      url: 'http://127.0.0.1:${server.port}',
      username: 'stalled',
      password: 'stalled',
      source: 'test',
    );

    final elapsed = Stopwatch()..start();
    final info =
        await IptvClient.login(portal, timeout: const Duration(seconds: 1));
    elapsed.stop();

    expect(info, isNull);
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 8)),
      reason: 'the stalled body was waited on instead of being abandoned',
    );

    await server.close(force: true);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
