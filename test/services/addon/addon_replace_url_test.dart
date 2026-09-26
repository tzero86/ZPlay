import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/services/addon/addon_manager.dart';

/// `AddonManager.addAddon` refuses duplicate manifest ids, and a Debrid configured
/// addon keeps the same id as its plain form (Torrentio answers
/// `com.stremio.torrentio.addon` for every provider variant). Connecting Debrid
/// therefore has to replace the installed entry in place, which this pins down.
void main() {
  const addonId = 'com.stremio.torrentio.addon';
  late HttpServer server;
  late String plainUrl;
  late String debridUrl;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      // A configured addon reports its own name, which is how we tell that the
      // request carried the configured path. A different path serves a different
      // addon id, so the unknown-id fallback has something real to install.
      final path = req.uri.path;
      final configured = path.contains('rd');
      final other = path.contains('other');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'id': other ? 'com.example.other' : addonId,
        'name': other ? 'Other Addon' : (configured ? 'Torrentio RD' : 'Torrentio'),
        'version': '1.0.0',
        'resources': ['stream'],
        'types': ['movie', 'series'],
      }));
      await req.response.close();
    });
    plainUrl = 'http://127.0.0.1:${server.port}';
    debridUrl = 'http://127.0.0.1:${server.port}/rd';
  });

  tearDownAll(() async => server.close(force: true));

  Map<String, dynamic> installedRecord(String baseUrl) => {
        'baseUrl': baseUrl,
        'manifest': {
          'id': addonId,
          'name': 'Torrentio',
          'version': '1.0.0',
          'resources': ['stream'],
          'types': ['movie', 'series'],
        },
        'enabled': true,
        'enableCatalogs': false,
        'enableSearch': false,
        'enableSubtitles': false,
        'enableStreams': true,
        'adultRating': 'sfw',
      };

  test('connecting a configured URL replaces the installed addon in place', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.installed_addons_v5': jsonEncode([installedRecord(plainUrl)]),
    });
    final manager = AddonManager.instance;
    await manager.initialize();

    final before = manager.addons
        .where((a) => a.baseUrl == plainUrl)
        .toList();
    expect(before, hasLength(1), reason: 'the plain addon starts installed');

    final updated = await manager.replaceAddonUrl(addonId, debridUrl);

    expect(updated.baseUrl, debridUrl);
    expect(updated.manifest.name, 'Torrentio RD',
        reason: 'the manifest was refetched for the configured URL');
    expect(updated.enableStreams, isTrue, reason: 'streams stay enabled');
    expect(updated.enableCatalogs, isFalse, reason: 'catalog flag is preserved');
    expect(updated.enableSearch, isFalse, reason: 'search flag is preserved');
    expect(updated.enabled, isTrue, reason: 'the addon stays enabled');

    final matching = manager.addons.where((a) => a.manifest.id == addonId).toList();
    expect(matching, hasLength(1),
        reason: 'the entry is replaced, not duplicated');
    expect(matching.single.baseUrl, debridUrl);
  });

  test('disconnecting points the same entry back at the plain URL', () async {
    final manager = AddonManager.instance;

    final reverted = await manager.replaceAddonUrl(addonId, plainUrl);

    expect(reverted.baseUrl, plainUrl);
    expect(reverted.manifest.name, 'Torrentio');
    expect(manager.addons.where((a) => a.manifest.id == addonId), hasLength(1));
  });

  test('an unknown addon id falls through to a normal install', () async {
    final otherUrl = 'http://127.0.0.1:${server.port}/other';

    final install = await AddonManager.instance.replaceAddonUrl(
      'com.example.not.installed',
      otherUrl,
    );

    expect(install.baseUrl, otherUrl);
    expect(install.manifest.name, 'Other Addon');
    expect(install.manifest.id, 'com.example.other');
    expect(
      AddonManager.instance.addons.where((a) => a.manifest.id == 'com.example.other'),
      hasLength(1),
    );
  });

  test('pasted addon URLs keep placeholder braces intact', () async {
    final record = InstalledAddon.fromJson({
      'baseUrl': 'https://torrentio.strem.fun/realdebrid={realdebrid}',
      'manifest': {
        'id': addonId,
        'name': 'Torrentio RD',
        'version': '1.0.0',
        'resources': ['stream'],
      },
      'enabled': true,
    });

    expect(record.baseUrl.contains('{realdebrid}'), isTrue,
        reason: 'no key may be persisted into the addon record');
  });
}
