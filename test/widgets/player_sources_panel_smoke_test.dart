/// Smoke run for the in-player sources panel.
///
/// The service-level fan-out is covered in
/// `test/services/stream/panel_all_providers_test.dart`. What is not covered
/// there is the panel itself: that it opens, renders a row per source, and
/// reports what it loaded back to its host.
///
/// Two stub addons are served over loopback and deliberately labelled so the
/// rendered text tells us whether both providers reached the visible list —
/// the user-visible half of the bug, where the panel showed only the addon
/// already playing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie_detail.dart';
import 'package:zplay/models/movie/video.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/widgets/player/player_sources_panel.dart';

void main() {
  late HttpServer server;

  // `testWidgets` installs an HttpOverrides that answers every request with
  // 400. The stub addons live on loopback, so real clients are handed out
  // there; everything else keeps the binding's rejecting client, which keeps
  // the built-in scrapers from reaching the network and stalling the test.
  setUp(() async {
    // The binding re-installs its rejecting overrides around every test, so
    // ours has to go in per test rather than once at suite start.
    HttpOverrides.global = _LoopbackOverrides();
    SharedPreferences.setMockInitialValues({});

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final isA = request.uri.path.startsWith('/a/');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'streams': [
            {
              'name': isA ? 'Addon A' : 'Addon B',
              // A stated rate, so the badge draws from the name alone. Without
              // one each card probes the manifest, and that request is still in
              // flight when the tree goes down and trips the pending-timer
              // invariant. This test is about which providers the panel
              // reaches, not about the network.
              'title': isA ? 'Addon A 1080p 8.5 Mb/s' : 'Addon B 720p 4.2 Mb/s',
              'url': isA
                  ? 'https://cdn.example.test/a.m3u8'
                  : 'https://cdn.example.test/b.m3u8',
            }
          ]
        }));
      await request.response.close();
    });

    AddonManager.readStoredForTesting = () async => jsonEncode([
          _entry('http://127.0.0.1:${server.port}/a', 'Addon A'),
          _entry('http://127.0.0.1:${server.port}/b', 'Addon B'),
        ]);

    await AddonManager.instance.initialize();
    await AddonManager.instance.reload();
  });

  tearDown(() async {
    AddonManager.readStoredForTesting = null;
    await server.close(force: true);
  });

  testWidgets('the panel lists sources from every provider, not only the '
      'playing one', (tester) async {
    List<StreamSource>? reported;

    // The scrape needs real socket I/O, which `testWidgets` only allows inside
    // `runAsync`: the fan-out covers the built-in scrapers as well as the stub
    // addons, and those resolve outside the fake-async clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerSourcesPanel(
            episode: Video(id: 'tt0903747:1:1', title: 'Pilot', season: 1, episode: 1),
            detail: MovieDetail(id: 'tt0903747', type: 'tv', name: 'Breaking Bad', year: '2008'),
            // The provider already playing. The panel must still surface others.
            currentAddonName: 'Addon A',
            onSourcesLoaded: (sources) => reported = sources,
            onPlaySource: (_, __) {},
            onBackToEpisodes: () {},
            onClose: () {},
          ),
        ),
      );

      // `pumpAndSettle` cannot be used: the panel shows a spinner for as long as
      // it is loading, so the tree never goes idle. Wait for the panel to report
      // its sources instead, then let the list render.
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (reported == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    await tester.pump();

    expect(reported, isNotNull, reason: 'the panel must report what it loaded');

    expect(
      reported!.map((s) => s.addonName),
      contains('Addon A'),
      reason: 'the playing provider must remain listed',
    );
    expect(
      reported!.map((s) => s.addonName),
      contains('Addon B'),
      reason: 'the panel is for finding alternatives; if Addon B is missing the '
          'user is again shown only the provider already in use',
    );

    expect(reported, isNotNull, reason: 'the panel must report what it loaded');
    expect(
      reported!.map((s) => s.addonName),
      contains('Addon B'),
    );
  });
}

Map<String, dynamic> _entry(String url, String name) => {
      'baseUrl': url,
      'enabled': true,
      'enableCatalogs': false,
      'enableSearch': false,
      'enableStreams': true,
      'enableSubtitles': false,
      'manifest': {
        'id': 'stub.${name.toLowerCase().replaceAll(' ', '-')}',
        'name': name,
        'version': '1.0.0',
        'resources': ['stream'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
        'catalogs': <Object>[],
      },
    };

/// Routes loopback to the stub addons and blackholes everything else.
///
/// `HttpOverrides.createHttpClient` is not given the request URI, so the split
/// has to happen in the proxy callback, where it is: loopback goes DIRECT and
/// is served by the local `HttpServer`, while any other host is pointed at an
/// unroutable proxy so the built-in scrapers fail fast instead of reaching the
/// network or hanging the test on a real timeout.
class _LoopbackOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) =>
        uri.host == '127.0.0.1' || uri.host == 'localhost'
            ? 'DIRECT'
            : 'PROXY 127.0.0.1:1';
    return client;
  }
}
