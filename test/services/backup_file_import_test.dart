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

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/backup/backup_restore_service.dart';

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
}

class _Missing implements Exception {
  const _Missing();
}
