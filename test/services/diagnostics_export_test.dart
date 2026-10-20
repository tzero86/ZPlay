import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/diagnostics/crash_breadcrumbs.dart';
import 'package:zplay/services/diagnostics/diagnostics_export.dart';
import 'package:zplay/services/storage/secret_keys.dart';

/// Distinctive fake credentials, so a leaked one is identifiable in the text.
/// Mirrors the fixtures `backup_restore_test.dart` uses: the diagnostic report
/// draws the same boundary, so it has to survive the same probe.
const Map<String, String> _secrets = <String, String>{
  SecretKeys.traktAccessToken: 'trakt-access-secret',
  SecretKeys.simklAccessToken: 'simkl-access-secret',
  SecretKeys.tmdbApiKey: 'tmdb-secret',
  SecretKeys.realDebridToken: 'rd-secret-token',
  SecretKeys.torboxApiKey: 'torbox-secret',
  SecretKeys.qobuzEclipseEndpoint: 'https://qobuz.example/u/qobuz-path-secret',
  'service_key_wyzie': 'wyzie-secret',
};

const String _portal = 'http://portal.example/?user=me&pass=portal-password';
const String _playlist =
    '[{"url":"http://example/playlist.m3u?token=m3u-token"}]';
const String _favourite = 'http://favourite.example|me|favourite-password';
const String _addonUrl =
    'https://torrentio.example.test/realdebrid=addon-secret/manifest.json';

const String _breadcrumbUrl =
    'HTTP 401 from https://panel.example/player_api.php?username=me&password=portal-password';

PackageInfo _info() => PackageInfo(
  appName: 'ZPlay',
  packageName: 'io.github.tzero86.zplay',
  version: '9.9.9',
  buildNumber: '4242',
);

/// A fixed instant, so every section of a report carries the same stamp and a
/// filename assertion is deterministic.
final DateTime _at = DateTime.utc(2026, 10, 19, 12, 34, 56);

List<Breadcrumb> _defaultBreadcrumbs() => <Breadcrumb>[
  Breadcrumb(1, _at, 'route', 'push DetailsPage', 120.5, const <String, String>{
    'page': 'DetailsPage',
  }),
  Breadcrumb(2, _at, 'stream', 'stream.open', null),
];

DiagnosticsExport _export({
  Future<PackageInfo> Function()? packageInfo,
  Future<SharedPreferences?> Function()? preferences,
  Future<Directory?> Function()? reportDirectory,
  List<Breadcrumb> Function()? breadcrumbs,
}) {
  return DiagnosticsExport(
    packageInfo: packageInfo ?? () async => _info(),
    preferences: preferences ?? () async => SharedPreferences.getInstance(),
    reportDirectory: reportDirectory ?? () async => null,
    breadcrumbs: breadcrumbs ?? _defaultBreadcrumbs,
    torrentEngineState: () => 'stopped',
    clock: () => _at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('report contents', () {
    test('carries app info, device facts and the breadcrumb tail', () async {
      final report = await _export().collect();

      expect(report['localOnly'], isTrue);
      expect(report['secretsExcluded'], isTrue);
      expect((report['app']! as Map)['version'], '9.9.9');
      expect((report['app']! as Map)['build'], '4242');
      expect((report['app']! as Map)['buildMode'], isNotEmpty);
      expect((report['device']! as Map)['formFactor'], isNotNull);
      expect((report['player']! as Map)['engine'], isNotEmpty);
      expect((report['streamEngine']! as Map)['torrentEngine'], 'stopped');

      final breadcrumbs = report['breadcrumbs']! as Map;
      expect(breadcrumbs['count'], 2);
      expect((breadcrumbs['entries']! as List).length, 2);
      expect(
        (breadcrumbs['entries']! as List).first,
        containsPair('message', 'push DetailsPage'),
      );
    });

    test('keeps only the newest breadcrumbs', () async {
      final export = _export(
        breadcrumbs: () => <Breadcrumb>[
          for (var i = 1; i <= DiagnosticsExport.maxBreadcrumbs + 20; i++)
            Breadcrumb(i, _at, 'route', 'push Page$i', null),
        ],
      );

      final breadcrumbs = (await export.collect())['breadcrumbs']! as Map;
      final entries = breadcrumbs['entries']! as List;

      expect(breadcrumbs['count'], DiagnosticsExport.maxBreadcrumbs + 20);
      expect(entries.length, DiagnosticsExport.maxBreadcrumbs);
      expect(
        (entries.last as Map)['message'],
        'push Page${DiagnosticsExport.maxBreadcrumbs + 20}',
      );
      expect((entries.first as Map)['message'], 'push Page21');
    });

    test('reports the remembered IPTV failures as a count only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pt_iptv_dead_urls': jsonEncode(<String, Object?>{
          'http://portal.example/live/1.ts?user=me&pass=dupe':
              <String, Object?>{},
        }),
      });

      final report = await _export().collect();
      expect((report['iptv']! as Map)['rememberedFailures'], 1);
      expect(jsonEncode(report), isNot(contains('portal.example/live')));
    });
  });

  group('redaction', () {
    test(
      'no secret, portal, playlist or addon value reaches the report',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ..._secrets,
          'installed_addons_v5': '[{"baseUrl":"$_addonUrl"}]',
          'iptv_custom_portals': _portal,
          'iptv_m3u_playlists': _playlist,
          'pt_iptv_m3u_playlists_v1': _playlist,
          'iptv_favorite_portals': _favourite,
          'pt_iptv_favorite_portal_keys': _favourite,
          'pt_iptv_ch_boxing':
              '[{"pu":"$_portal","uu":"portal-user",'
              '"pp":"portal-password","url":"$_portal"}]',
          'pt_iptv_verified_portals': _portal,
          'theme_mode': 'dark',
        });

        final text = await _export(
          breadcrumbs: () => <Breadcrumb>[
            Breadcrumb(1, _at, 'error', _breadcrumbUrl, null),
          ],
        ).buildReportString();

        for (final secret in _secrets.values) {
          expect(
            text,
            isNot(contains(secret)),
            reason: 'credential value "$secret" leaked into the report',
          );
        }
        for (final key in _secrets.keys) {
          expect(
            text,
            isNot(contains(key)),
            reason: 'credential key "$key" leaked into the report',
          );
        }
        for (final value in <String>[
          'portal-password',
          'portal-user',
          'm3u-token',
          'favourite-password',
          'addon-secret',
          'installed_addons_v5',
          'iptv_custom_portals',
          'iptv_m3u_playlists',
          'pt_iptv_m3u_playlists_v1',
          'iptv_favorite_portals',
          'pt_iptv_favorite_portal_keys',
        ]) {
          expect(
            text,
            isNot(contains(value)),
            reason: 'credential-bearing value "$value" leaked into the report',
          );
        }

        // Ordinary settings survive, so the report is still useful.
        expect(text, contains('theme_mode'));
        expect(text, contains('dark'));
        // A URL inside free text keeps its host and loses the path.
        expect(text, contains('https://panel.example/[redacted]'));
        expect(text, isNot(contains('username=me')));
      },
    );

    test('isExcludedKey draws the same boundary as the profile export', () {
      for (final key in <String>[
        ...SecretKeys.values,
        'service_key_anything',
        'installed_addons_v5',
        'iptv_custom_portals',
        'iptv_m3u_playlists',
        'pt_iptv_m3u_playlists_v1',
        'iptv_favorite_portals',
        'pt_iptv_favorite_portal_keys',
        'pt_iptv_ch_boxing',
        'pt_iptv_verified_portals',
        'pt_iptv_dead_urls',
        'theme_mode__backup',
        'theme_mode__corrupt',
      ]) {
        expect(DiagnosticsExport.isExcludedKey(key), isTrue, reason: key);
      }
      for (final key in <String>['theme_mode', 'renderer_backend']) {
        expect(DiagnosticsExport.isExcludedKey(key), isFalse, reason: key);
      }
    });

    test('scrubText reduces any URL to its origin', () {
      expect(
        DiagnosticsExport.scrubText(
          'failed http://u:p@host.example:8080/a/b?token=abc',
        ),
        'failed http://host.example:8080/[redacted]',
      );
      expect(DiagnosticsExport.scrubText('no urls here'), 'no urls here');
      expect(
        DiagnosticsExport.scrubText('magnet:?xt=urn:btih:abc'),
        'magnet:?xt=urn:btih:abc',
      );
    });
  });

  group('file write', () {
    test('writes a timestamped json under ZPlay/diagnostics', () async {
      final temp = Directory.systemTemp.createTempSync(
        'zplay_diagnostics_test',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      final export = _export(reportDirectory: () async => temp);
      final path = await export.saveReport();

      expect(path, isNotNull);
      final saved = path!;
      final parts = p.split(saved);
      expect(parts, contains('ZPlay'));
      expect(parts, contains('diagnostics'));
      expect(
        p.basename(saved),
        matches(RegExp(r'^zplay-diagnostics-\d{8}-\d{6}\.json$')),
      );

      final decoded = jsonDecode(File(saved).readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      expect(
        (decoded as Map<String, dynamic>)['schemaVersion'],
        DiagnosticsExport.schemaVersion,
      );
      expect(decoded['app']['version'], '9.9.9');
    });

    test('copyText is the same readable JSON', () async {
      final export = _export();
      expect(await export.copyText(), await export.buildReportString());
    });
  });

  group('degraded platforms', () {
    test('missing plugins and no directory still produce a report', () async {
      final export = DiagnosticsExport(
        packageInfo: () async =>
            throw MissingPluginException('no package info'),
        preferences: () async => throw MissingPluginException('no prefs'),
        reportDirectory: () async => null,
        breadcrumbs: () => const <Breadcrumb>[],
        torrentEngineState: () => null,
        clock: () => _at,
      );

      final report = jsonDecode(await export.buildReportString()) as Map;
      expect(report['app'], isA<Map<String, dynamic>>());
      expect((report['app'] as Map)['version'], isNull);
      expect((report['settings'] as Map)['available'], isFalse);
      expect((report['iptv'] as Map)['rememberedFailures'], isNull);
      expect((report['breadcrumbs'] as Map)['count'], 0);
      expect(await export.saveReport(), isNull);
    });
  });
}
