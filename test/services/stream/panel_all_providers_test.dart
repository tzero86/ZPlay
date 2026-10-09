/// The in-player sources panel exists to offer alternatives to the source that
/// is currently playing.
///
/// It used to call the targeted entry point with the playing source's addon
/// name, so a title with two providers only ever saw the one already playing:
/// the other installed Stremio addon was never queried at all. This pins the
/// fan-out, with stub addons served over loopback so no external provider is
/// touched.
///
/// No `TestWidgetsFlutterBinding.ensureInitialized()` on purpose: it stubs every
/// `HttpClient` to return 400, which would leave the loopback addons unreachable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/stream/stream_service.dart';

void main() {
  late HttpServer server;
  late List<String> requestedPaths;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requestedPaths = <String>[];
  });

  tearDown(() async {
    AddonManager.readStoredForTesting = null;
    await server.close(force: true);
  });

  test('the panel entry point queries every installed stream addon, not just '
      'the one currently playing', () async {
    server = await _serveTwoAddons(requestedPaths);
    await _installStubs(server.port);

    final sources = await StreamService.fetchStreamsForTargetAddon(
      targetAddonName: 'Addon A',
      type: 'movie',
      id: 'tt0111161',
      title: 'The Shawshank Redemption',
      allProviders: true,
    ).toList();

    expect(
      sources.map((s) => s.addonName).toSet(),
      containsAll(<String>{'Addon A', 'Addon B'}),
      reason: 'targeting Addon A must not hide Addon B — that is the panel '
          'offering nothing but the provider already in use '
          '(requested: $requestedPaths)',
    );
  });

  test('a tv-typed title still reaches an addon that declares only series',
      () async {
    server = await _serveTwoAddons(requestedPaths);
    await _installStubs(server.port);

    final sources = await StreamService.fetchStreamsForTargetAddon(
      targetAddonName: 'Addon A',
      type: 'tv',
      id: 'tt0903747',
      title: 'Breaking Bad',
      allProviders: true,
    ).toList();

    expect(
      sources,
      isNotEmpty,
      reason: 'the internal `tv` alias must be normalized to the Stremio '
          '`series` route, or every addon is dropped in silence '
          '(requested: $requestedPaths)',
    );
  });

  test('without allProviders the targeted entry point queries only the named '
      'addon', () async {
    server = await _serveTwoAddons(requestedPaths);
    await _installStubs(server.port);

    final sources = await StreamService.fetchStreamsForTargetAddon(
      targetAddonName: 'Addon A',
      type: 'movie',
      id: 'tt0111161',
      title: 'The Shawshank Redemption',
    ).toList();

    expect(sources.map((s) => s.addonName).toSet(), <String>{'Addon A'});
    expect(
      requestedPaths.where((p) => p.startsWith('/b/')),
      isEmpty,
      reason: 'the targeted path is what the non-panel callers rely on',
    );
  });
}

/// Serves a minimal Stremio stream response on `/a` and `/b`.
Future<HttpServer> _serveTwoAddons(List<String> requestedPaths) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  server.listen((request) async {
    requestedPaths.add(request.uri.path);

    final isA = request.uri.path.startsWith('/a/');
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'streams': [
          {
            'name': isA ? 'Addon A' : 'Addon B',
            'title': '1080p',
            'url': isA
                ? 'https://cdn.example.test/a.m3u8'
                : 'https://cdn.example.test/b.m3u8',
          }
        ]
      }));
    await request.response.close();
  });

  return server;
}

Future<void> _installStubs(int port) async {
  AddonManager.readStoredForTesting = () async => jsonEncode([
        _entry('http://127.0.0.1:$port/a', 'Addon A'),
        _entry('http://127.0.0.1:$port/b', 'Addon B'),
      ]);

  await AddonManager.instance.initialize();
  await AddonManager.instance.reload();

  expect(
    AddonManager.instance.activeStreamAddons.map((a) => a.manifest.name),
    containsAll(<String>{'Addon A', 'Addon B'}),
    reason: 'both stubs must be installed and stream-enabled for this test to '
        'mean anything',
  );
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
