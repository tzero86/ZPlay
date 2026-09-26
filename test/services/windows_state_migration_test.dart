import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/profiles/windows_state_migration.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('zplay_windows_migration');
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  String pathIn([String a = '', String b = '']) {
    final first = '${sandbox.path}${Platform.pathSeparator}$a';
    return b.isEmpty ? first : '$first${Platform.pathSeparator}$b';
  }

  /// Creates `shared_preferences.json` plus a nested app-support subdirectory,
  /// matching the shape of a real profile (prefs file at the root, TorrServer
  /// data and shader/font caches one level down).
  void writeLegacyProfile(String legacyPath) {
    Directory(legacyPath).createSync(recursive: true);
    File('$legacyPath${Platform.pathSeparator}shared_preferences.json')
        .writeAsStringSync('{"flutter.renderer_backend":"skia"}');
    final torrserver = Directory(
      '$legacyPath${Platform.pathSeparator}torrserver_data',
    )..createSync(recursive: true);
    File('${torrserver.path}${Platform.pathSeparator}config.db')
        .writeAsStringSync('torrent-state');
  }

  group('planWindowsStateMigration', () {
    test('copies when the legacy profile exists and the destination is absent', () {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');

      expect(
        planWindowsStateMigration(
          legacyPath: legacyPath,
          destinationPath: destinationPath,
        ),
        WindowsStateMigrationAction.copy,
      );
    });

    test('skips when the destination already exists, even with a legacy profile', () {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');
      Directory(destinationPath).createSync(recursive: true);

      expect(
        planWindowsStateMigration(
          legacyPath: legacyPath,
          destinationPath: destinationPath,
        ),
        WindowsStateMigrationAction.skipDestinationExists,
      );
    });

    test('no-ops when no legacy profile exists', () {
      expect(
        planWindowsStateMigration(
          legacyPath: pathIn('com.example', 'playtorrio'),
          destinationPath: pathIn('tzero86', 'zplay'),
        ),
        WindowsStateMigrationAction.noLegacyProfile,
      );
    });

    test('an empty legacy profile is nothing worth copying', () {
      final legacyPath = pathIn('com.example', 'playtorrio');
      Directory(legacyPath).createSync(recursive: true);

      expect(
        planWindowsStateMigration(
          legacyPath: legacyPath,
          destinationPath: pathIn('tzero86', 'zplay'),
        ),
        WindowsStateMigrationAction.emptyLegacyProfile,
      );
    });

    test('an existing destination wins over an empty legacy profile', () {
      final legacyPath = pathIn('com.example', 'playtorrio');
      Directory(legacyPath).createSync(recursive: true);
      final destinationPath = pathIn('tzero86', 'zplay');
      Directory(destinationPath).createSync(recursive: true);

      expect(
        planWindowsStateMigration(
          legacyPath: legacyPath,
          destinationPath: destinationPath,
        ),
        WindowsStateMigrationAction.skipDestinationExists,
      );
    });
  });

  group('migrateWindowsProfile', () {
    test('copies the whole tree and leaves the source in place', () async {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');

      final action = await migrateWindowsProfile(
        legacyPath: legacyPath,
        destinationPath: destinationPath,
      );

      expect(action, WindowsStateMigrationAction.copy);
      expect(
        File('$destinationPath${Platform.pathSeparator}shared_preferences.json')
            .readAsStringSync(),
        contains('renderer_backend'),
      );
      expect(
        File(
          '$destinationPath${Platform.pathSeparator}torrserver_data'
          '${Platform.pathSeparator}config.db',
        ).existsSync(),
        isTrue,
      );
      // Requirement: the source survives as a fallback.
      expect(
        File('$legacyPath${Platform.pathSeparator}shared_preferences.json')
            .existsSync(),
        isTrue,
      );
    });

    test('leaves no staging directory behind', () async {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');

      await migrateWindowsProfile(
        legacyPath: legacyPath,
        destinationPath: destinationPath,
      );

      expect(Directory('$destinationPath.migrating').existsSync(), isFalse);
    });

    test('does not overwrite or merge into an existing destination', () async {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');
      final destination = Directory(destinationPath)..createSync(recursive: true);
      File(
        '${destination.path}${Platform.pathSeparator}shared_preferences.json',
      ).writeAsStringSync('{"flutter.theme":"dark"}');

      final action = await migrateWindowsProfile(
        legacyPath: legacyPath,
        destinationPath: destinationPath,
      );

      expect(action, WindowsStateMigrationAction.skipDestinationExists);
      expect(
        File(
          '$destinationPath${Platform.pathSeparator}shared_preferences.json',
        ).readAsStringSync(),
        '{"flutter.theme":"dark"}',
        reason: 'the destination holds the state the user just configured',
      );
      expect(
        Directory(
          '$destinationPath${Platform.pathSeparator}torrserver_data',
        ).existsSync(),
        isFalse,
        reason: 'skipping must not merge the legacy profile in',
      );
    });

    test('a second run is a no-op now that the destination exists', () async {
      final legacyPath = pathIn('com.example', 'playtorrio');
      writeLegacyProfile(legacyPath);
      final destinationPath = pathIn('tzero86', 'zplay');

      expect(
        await migrateWindowsProfile(
          legacyPath: legacyPath,
          destinationPath: destinationPath,
        ),
        WindowsStateMigrationAction.copy,
      );

      // The user edits the migrated profile; a relaunch must not revert it.
      File(
        '$destinationPath${Platform.pathSeparator}shared_preferences.json',
      ).writeAsStringSync('edited-after-migration');

      expect(
        await migrateWindowsProfile(
          legacyPath: legacyPath,
          destinationPath: destinationPath,
        ),
        WindowsStateMigrationAction.skipDestinationExists,
      );
      expect(
        File(
          '$destinationPath${Platform.pathSeparator}shared_preferences.json',
        ).readAsStringSync(),
        'edited-after-migration',
      );
    });

    test('writes nothing when the legacy profile is absent', () async {
      final destinationPath = pathIn('tzero86', 'zplay');

      final action = await migrateWindowsProfile(
        legacyPath: pathIn('com.example', 'playtorrio'),
        destinationPath: destinationPath,
      );

      expect(action, WindowsStateMigrationAction.noLegacyProfile);
      expect(Directory(destinationPath).existsSync(), isFalse);
    });
  });
}
