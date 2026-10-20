import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/backup/backup_restore_service.dart';
import 'package:zplay/services/storage/secret_keys.dart';

/// Distinctive fake credentials, so a leaked one is identifiable in the JSON.
const Map<String, String> _secrets = <String, String>{
  SecretKeys.traktAccessToken: 'trakt-access-secret',
  SecretKeys.traktRefreshToken: 'trakt-refresh-secret',
  SecretKeys.simklAccessToken: 'simkl-access-secret',
  SecretKeys.tmdbApiKey: 'tmdb-secret',
  SecretKeys.realDebridToken: 'rd-secret-token',
  SecretKeys.allDebridApiKey: 'alldebrid-secret',
  SecretKeys.premiumizeApiKey: 'premiumize-secret',
  SecretKeys.debridLinkApiKey: 'debridlink-secret',
  SecretKeys.torboxApiKey: 'torbox-secret',
  SecretKeys.qobuzEclipseToken: 'qobuz-session-secret',
  SecretKeys.qobuzEclipseEndpoint: 'https://qobuz.example/u/qobuz-path-secret',
  SecretKeys.qobuzEclipseManifestUrl:
      'https://qobuz.example/u/qobuz-path-secret/manifest.json',
  'service_key_wyzie': 'wyzie-secret',
  'service_key_trakt_secret': 'trakt-client-secret',
};

const String _portal = 'http://portal.example/?user=me&pass=portal-password';
const String _playlist =
    '[{"url":"http://example/playlist.m3u?token=m3u-token"}]';
const String _favourite = 'http://favourite.example|me|favourite-password';
const String _addonUrl =
    'https://torrentio.example.test/realdebrid=addon-secret/manifest.json';

String _addonDoc(String baseUrl) => jsonEncode([
  {
    'baseUrl': baseUrl,
    'enabled': true,
    'enableCatalogs': false,
    'enableSearch': true,
    'enableStreams': true,
    'enableSubtitles': false,
    'manifest': {
      'id': 'com.example.addon',
      'name': 'Example Addon',
      'version': '1.0.0',
      'resources': ['stream'],
      'types': ['movie'],
      'catalogs': <Object>[],
    },
  },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('an export carries no credential, backup or corrupt value', () async {
    SharedPreferences.setMockInitialValues({
      ..._secrets,
      'my_list_v1__backup': '{"schema":1}',
      'my_list_v1__corrupt': 'garbage',
      'installed_addons_v5': _addonDoc(_addonUrl),
      'pt_iptv_m3u_playlists_v1': _playlist,
      'pt_iptv_favorite_portal_keys': <String>[_favourite],
      'iptv_custom_portals': <String>[_portal],
      'iptv_m3u_playlists': _playlist,
      'iptv_favorite_portals': <String>[_favourite],
      'debrid_service': 'Real-Debrid',
      'use_debrid_for_streams': true,
    });

    final exported = await BackupRestoreService.exportSettingsJson();

    for (final secret in _secrets.values) {
      expect(
        exported,
        isNot(contains(secret)),
        reason:
            'a profile is a file that gets copied around; it must not '
            'carry an account credential',
      );
    }
    expect(exported, isNot(contains('portal-password')));
    expect(exported, isNot(contains('m3u-token')));
    expect(exported, isNot(contains('favourite-password')));
    expect(
      exported,
      isNot(contains('addon-secret')),
      reason:
          'an addon base URL embeds the provider key it was configured '
          'with',
    );

    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    expect(decoded['secretsExcluded'], isTrue);
    expect(decoded['schemaVersion'], BackupRestoreService.profileSchema);
    expect(
      decoded.containsKey('addons'),
      isFalse,
      reason:
          'an addon list without base URLs would restore nothing, and with '
          'them it would leak the keys',
    );

    final settings = decoded['settings'] as Map<String, dynamic>;
    for (final key in _secrets.keys) {
      expect(settings.containsKey(key), isFalse, reason: key);
    }
    expect(settings.containsKey('my_list_v1__backup'), isFalse);
    expect(settings.containsKey('my_list_v1__corrupt'), isFalse);
    expect(settings.containsKey('installed_addons_v5'), isFalse);
    expect(settings.containsKey('pt_iptv_m3u_playlists_v1'), isFalse);
    expect(settings.containsKey('pt_iptv_favorite_portal_keys'), isFalse);
    expect(settings.containsKey('iptv_custom_portals'), isFalse);
    expect(settings.containsKey('iptv_m3u_playlists'), isFalse);
    expect(settings.containsKey('iptv_favorite_portals'), isFalse);

    // Ordinary settings still travel.
    expect(settings['debrid_service'], 'Real-Debrid');
    expect(settings['use_debrid_for_streams'], isTrue);

    final iptv = decoded['iptv'] as Map<String, dynamic>;
    expect(iptv, isEmpty);
  });

  test(
    'importing a redacted profile leaves local credentials untouched',
    () async {
      // The destination device, already paired and holding its own addons and
      // IPTV accounts.
      SharedPreferences.setMockInitialValues({
        SecretKeys.realDebridToken: 'local-rd-token',
        SecretKeys.tmdbApiKey: 'local-tmdb-key',
        'service_key_wyzie': 'local-wyzie-key',
        SecretKeys.traktAccessToken: 'local-trakt-token',
        SecretKeys.qobuzEclipseToken: 'local-qobuz-token',
        'installed_addons_v5': _addonDoc(
          'https://local.example/realdebrid=local-addon-token',
        ),
        'pt_iptv_m3u_playlists_v1': '[{"url":"http://local.example/list.m3u"}]',
        'pt_iptv_favorite_portal_keys': <String>[
          'http://local.example|me|local',
        ],
        'iptv_custom_portals': <String>[
          'http://local.example/?user=me&pass=local',
        ],
        'iptv_m3u_playlists': '[{"url":"http://local.example/list.m3u"}]',
        'iptv_favorite_portals': <String>['http://local-favourite.example/'],
        'debrid_service': 'Real-Debrid',
      });
      await AddonManager.instance.reload();

      // What a redacted export looks like even if a hand-edited file still
      // carries the keys: blank values that would otherwise unpair the device.
      final redacted = const JsonEncoder.withIndent('  ').convert({
        'version': '1.1.6',
        'platform': 'android',
        'secretsExcluded': true,
        'settings': {
          for (final key in _secrets.keys) key: '',
          'installed_addons_v5': _addonDoc(
            'https://imported.example/realdebrid=imported-token',
          ),
          'pt_iptv_m3u_playlists_v1': '[]',
          'pt_iptv_favorite_portal_keys': <String>[],
          'iptv_custom_portals': <String>[],
          'iptv_m3u_playlists': '[]',
          'iptv_favorite_portals': <String>[],
          'debrid_service': 'TorBox',
          'use_debrid_for_streams': false,
        },
        'iptv': {
          'customPortals': <String>[],
          'm3uPlaylists': '[]',
          'favoritePortals': <String>['http://imported-favourite.example/'],
        },
        'addons': {
          'installed': [
            {'baseUrl': 'https://imported.example/realdebrid=imported-token'},
          ],
        },
      });

      final message = await BackupRestoreService.importSettingsJson(redacted);
      expect(
        message,
        contains('stay on this device'),
        reason:
            'a redacted restore must not promise addons or portals it did '
            'not carry',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SecretKeys.realDebridToken), 'local-rd-token');
      expect(prefs.getString(SecretKeys.tmdbApiKey), 'local-tmdb-key');
      expect(prefs.getString('service_key_wyzie'), 'local-wyzie-key');
      expect(prefs.getString(SecretKeys.traktAccessToken), 'local-trakt-token');
      expect(
        prefs.getString(SecretKeys.qobuzEclipseToken),
        'local-qobuz-token',
      );
      expect(
        prefs.getString('pt_iptv_m3u_playlists_v1'),
        '[{"url":"http://local.example/list.m3u"}]',
      );
      expect(prefs.getStringList('pt_iptv_favorite_portal_keys'), [
        'http://local.example|me|local',
      ]);
      expect(prefs.getStringList('iptv_custom_portals'), [
        'http://local.example/?user=me&pass=local',
      ]);
      expect(
        prefs.getString('iptv_m3u_playlists'),
        '[{"url":"http://local.example/list.m3u"}]',
      );
      expect(prefs.getStringList('iptv_favorite_portals'), [
        'http://local-favourite.example/',
      ]);

      // Non-secret settings still restore.
      expect(prefs.getString('debrid_service'), 'TorBox');
      expect(prefs.getBool('use_debrid_for_streams'), isFalse);

      // The running addon list is the destination's, not one built from the
      // imported base URL.
      final urls = AddonManager.instance.addons.map((a) => a.baseUrl).toList();
      expect(
        urls,
        contains('https://local.example/realdebrid=local-addon-token'),
      );
      expect(
        urls,
        isNot(contains('https://imported.example/realdebrid=imported-token')),
      );
    },
  );

  test('a profile from a newer app is refused, not half-applied', () async {
    SharedPreferences.setMockInitialValues({'debrid_service': 'Real-Debrid'});

    final newer = jsonEncode({
      'schemaVersion': BackupRestoreService.profileSchema + 1,
      'settings': {'debrid_service': 'TorBox'},
    });

    await expectLater(
      BackupRestoreService.importSettingsJson(newer),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('newer version'), contains('Update the app')),
        ),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('debrid_service'),
      'Real-Debrid',
      reason: 'a refused profile must not have written any setting',
    );
  });

  test('a profile with no schema version still imports', () async {
    SharedPreferences.setMockInitialValues({});

    await BackupRestoreService.importSettingsJson(
      jsonEncode({
        'settings': {'debrid_service': 'TorBox'},
      }),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('debrid_service'), 'TorBox');
  });

  test(
    'an older backup without the redaction flag still imports credentials',
    () async {
      final legacy = const JsonEncoder.withIndent('  ').convert({
        'version': '1.1.6',
        'platform': 'android',
        'settings': {
          'rd_access_token': 'legacy-token',
          'tmdb_api_key': 'legacy-tmdb',
          'service_key_wyzie': 'legacy-wyzie',
          'debrid_service': 'Real-Debrid',
        },
        'debrid': {
          'selectedService': 'Real-Debrid',
          'rdKey': '',
          'torboxKey': '',
          'alldebridKey': '',
          'premiumizeKey': '',
          'debridlinkKey': '',
        },
        'iptv': {'customPortals': <String>[], 'favoritePortals': <String>[]},
      });

      SharedPreferences.setMockInitialValues({});
      await BackupRestoreService.importSettingsJson(legacy);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rd_access_token'), 'legacy-token');
      expect(prefs.getString('tmdb_api_key'), 'legacy-tmdb');
      expect(prefs.getString('service_key_wyzie'), 'legacy-wyzie');
      expect(prefs.getString('debrid_service'), 'Real-Debrid');
    },
  );

  test(
    'a legacy backup still restores its IPTV portals and favourites',
    () async {
      final legacy = const JsonEncoder.withIndent('  ').convert({
        'version': '1.1.6',
        'settings': <String, Object?>{},
        'iptv': {
          'customPortals': <String>['http://legacy.example/?user=me'],
          'm3uPlaylists': '[{"url":"http://legacy.example/list.m3u"}]',
          'favoritePortals': <String>['http://legacy.example|me|legacy'],
        },
      });

      SharedPreferences.setMockInitialValues({});
      await BackupRestoreService.importSettingsJson(legacy);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('iptv_custom_portals'), [
        'http://legacy.example/?user=me',
      ]);
      expect(
        prefs.getString('iptv_m3u_playlists'),
        '[{"url":"http://legacy.example/list.m3u"}]',
      );
      expect(prefs.getStringList('iptv_favorite_portals'), [
        'http://legacy.example|me|legacy',
      ]);
    },
  );
}
