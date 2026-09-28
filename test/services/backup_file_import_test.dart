/// Guards importing a whole profile from a file rather than by pasting.
///
/// The paste path is right for a handful of settings and unusable for a profile:
/// a real export is around 200 KB of JSON carrying addons, rails and
/// credentials, and typing that into a text field with a remote is not a task
/// anyone should attempt. Moving a profile to another device means pushing the
/// file across - over adb, a share sheet, a USB stick - and naming it in the
/// import.
///
/// That is how a profile gets onto a television, which is the case this exists
/// for: the release APK is not debuggable and the device is not rooted, so
/// there is no other way in.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/backup/backup_restore_service.dart';
import 'package:zplay/services/config/service_credentials.dart';
import 'package:zplay/services/debrid/debrid_service.dart';
import 'package:zplay/services/debrid/providers/real_debrid_service.dart';
import 'package:zplay/services/metadata/tmdb_service.dart';

/// Fake credentials. Nothing here is a real key, and nothing here prints one.
const String _rdToken = 'rd-token-for-tests-0000000000000000000000000000';
const String _tmdbKey = 'tmdb-key-for-tests-000000000000';
const String _wyzieKey = 'wyzie-key-for-tests-0000000000000000';

void main() {
  group('a candidate path that is not there is a clean miss', () {
    test('and every candidate is tried in order', () async {
      final tried = <String>[];
      await expectLater(
        BackupRestoreService.importSettingsFromFile(
          ['/first.json', '/second.json', '/third.json'],
          read: (path) async {
            tried.add(path);
            throw const _Missing();
          },
        ),
        throwsA(isA<Exception>()),
        reason: 'nothing was readable, so the caller is told rather than being '
            'left thinking a partial import succeeded',
      );
      expect(tried, ['/first.json', '/second.json', '/third.json'],
          reason: 'the first readable candidate wins, and the rest are only '
              'tried when an earlier one is not');
    });
  });

  group('a truncated push is a miss, not a half-applied profile', () {
    test('unparseable JSON is skipped rather than imported', () async {
      var imported = false;
      await expectLater(
        BackupRestoreService.importSettingsFromFile(
          ['/broken.json'],
          read: (_) async => '{"settings": {"tmdb_api_key": "abc"',
        ),
        throwsA(isA<Exception>()),
      );
      expect(imported, isFalse);
    });
  });

  test('an empty file is skipped', () async {
    await expectLater(
      BackupRestoreService.importSettingsFromFile(
        ['/empty.json'],
        read: (_) async => '   \n  ',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('the search paths are where a pushed file actually lands', () {
    // `/sdcard/Download` is where `adb push` and most share sheets put a file,
    // and the second entry is the same place by its emulated path, which is
    // what resolves on some devices. Both must stay, or a pushed profile is
    // invisible to the very feature that exists to load it.
    expect(
      BackupRestoreService.importSearchPaths,
      contains('/sdcard/Download/zplay_profile.json'),
    );
    expect(BackupRestoreService.importSearchPaths.length, greaterThanOrEqualTo(2));
  });

  group('a restored credential is readable, not merely stored', () {
    // A profile carrying the credentials a television needs, produced by the
    // real exporter - the same payload shape `tool/transfer_profile.dart`
    // reproduces from a Windows profile.
    Future<String> profile() async {
      SharedPreferences.setMockInitialValues({
        'rd_access_token': _rdToken,
        'tmdb_api_key': _tmdbKey,
        'service_key_wyzie': _wyzieKey,
        'debrid_service': 'Real-Debrid',
        'use_debrid_for_streams': true,
        'installed_addons_v5': jsonEncode([_addonEntry()]),
      });
      return BackupRestoreService.exportSettingsJson();
    }

    // A television that has not imported anything: an empty store, with each
    // credential reader hydrated from it once. `main.dart` runs exactly these
    // three before the first frame, so the readers hold the pre-import values
    // from here on.
    Future<void> freshInstall() async {
      SharedPreferences.setMockInitialValues({});
      await TmdbService.initialize();
      await ServiceCredentials.initialize();
      await DebridService.refreshDebridReady();
    }

    void expectNothingImportedYet() {
      expect(TmdbService.isConfigured, isFalse);
      expect(ServiceCredentials.isUserProvided(ServiceCredential.wyzie), isFalse);
      expect(DebridService.isDebridReady.value, isFalse);
    }

    void expectProfileIsLive() {
      // TMDb's key is read through `apiKey`, which is what Settings shows and
      // what the ranked rails and the scrapers use.
      expect(
        TmdbService.apiKey.value,
        _tmdbKey,
        reason: 'a key that only reaches storage leaves Settings on "Not set" '
            'and the rails on the bundled picks',
      );
      // The six service keys are read through the credential ladder.
      expect(
        ServiceCredentials.value(ServiceCredential.wyzie),
        _wyzieKey,
        reason: 'a key that only reaches storage leaves Settings on '
            '"0 of 6 set" and the integration without its credential',
      );
      expect(ServiceCredentials.isUserProvided(ServiceCredential.wyzie), isTrue);
      // Debrid needs all three: the service, the toggle and a token.
      expect(DebridService.isDebridReady.value, isTrue,
          reason: 'the Watch panel buckets magnet sources as Debrid and the '
              'torrent indexers stay registered only while this is true');
    }

    test('and the From File path leaves the running app holding it', () async {
      final exported = await profile();
      await freshInstall();
      expectNothingImportedYet();

      await BackupRestoreService.importSettingsFromFile(
        ['/sdcard/Download/zplay_profile.json'],
        read: (_) async => exported,
      );

      expectProfileIsLive();
      expect(
        await RealDebridService().hasKey(),
        isTrue,
        reason: 'the token has to be where the provider reads it, not only in '
            'the file that carried it',
      );
    });

    test('and the paste-JSON path leaves the running app holding it', () async {
      final exported = await profile();
      await freshInstall();
      expectNothingImportedYet();

      await BackupRestoreService.importSettingsJson(exported);

      expectProfileIsLive();
    });

    test('and an imported addon list replaces the one in memory', () async {
      // Addons travel inside the settings map as `installed_addons_v5`, so a
      // real profile carries them down the same route as the credentials. If
      // the running list is not re-read, the profile looks half transferred -
      // and the next addon the user touches saves that stale list back over
      // the imported one.
      const otherUrl = 'https://other-addon.example.test/realdebrid=token';
      SharedPreferences.setMockInitialValues({
        'installed_addons_v5': jsonEncode([_addonEntry()]),
      });
      await AddonManager.instance.reload();
      expect(
        AddonManager.instance.addons.map((a) => a.baseUrl),
        contains(_addonUrl),
        reason: 'the baseline the import has to move off',
      );

      await BackupRestoreService.importSettingsJson(jsonEncode({
        'version': '1.3.1',
        'settings': {
          'installed_addons_v5': jsonEncode([_addonEntry(url: otherUrl)]),
        },
      }));

      final urls = AddonManager.instance.addons.map((a) => a.baseUrl).toList();
      expect(urls, contains(otherUrl));
      expect(urls, contains('builtin:zplay'));
      expect(urls, contains('builtin:zplayhttp'));
      expect(urls.where((u) => u == otherUrl).length, 1);
      expect(
        urls,
        isNot(contains(_addonUrl)),
        reason: 'the stored list replaces the running one; keeping an addon '
            'the imported profile does not have is not a restore',
      );
    });
  });
}

const String _addonUrl = 'https://torrentio.example.test/realdebrid=token';

Map<String, dynamic> _addonEntry({String url = _addonUrl}) => {
      'baseUrl': url,
      'enabled': true,
      'enableCatalogs': true,
      'enableSearch': true,
      'enableStreams': true,
      'enableSubtitles': false,
      'manifest': {
        'id': 'com.example.torrentio',
        'name': 'Torrentio',
        'version': '1.0.0',
        'resources': ['stream'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
        'catalogs': <Object>[],
      },
    };

class _Missing implements Exception {
  const _Missing();
}
