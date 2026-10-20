import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addon/addon_manager.dart';
import '../anime/anime_library_service.dart';
import '../books/continue_reading_service.dart';
import '../books/reader_settings.dart';
import '../config/service_credentials.dart';
import '../continue_watching/continue_watching_service.dart';
import '../metadata/tmdb_service.dart';
import '../music/music_download_service.dart';
import '../my_list/my_list_service.dart';
import '../theme/app_theme_service.dart';
import '../home/home_page_settings.dart';
import '../theme/custom_background_service.dart';
import '../debrid/debrid_service.dart';
import '../storage/secret_keys.dart';
import 'profile_cipher.dart';
import 'profile_secrets.dart';

class BackupRestoreService {
  /// Version of the profile document this build writes and understands.
  ///
  /// Bumped when the shape changes in a way an older importer could misread.
  /// A file that declares a newer number is refused rather than partly
  /// applied; files with no `schemaVersion` predate this field and import
  /// through the legacy path.
  static const int profileSchema = 2;

  /// Settings whose contents embed credentials rather than merely configure
  /// the app: portal URLs carry a username and password, M3U links carry a
  /// token, a favourite portal key is `url|username|password`, and an addon
  /// base URL carries whatever provider key the addon was configured with.
  static const List<String> _credentialBearingKeys = <String>[
    'installed_addons_v5',
    'iptv_custom_portals',
    'iptv_m3u_playlists',
    'pt_iptv_m3u_playlists_v1',
    'iptv_favorite_portals',
    'pt_iptv_favorite_portal_keys',
  ];

  /// Whether a preference key must be left out of an export.
  static bool _isExcluded(String key) =>
      SecretKeys.isSecret(key) ||
      key.endsWith('__backup') ||
      key.endsWith('__corrupt') ||
      _credentialBearingKeys.contains(key);

  /// Exports a profile.
  ///
  /// With no [passphrase] this is the redacted profile: credentials, IPTV
  /// portal keys/playlists/favourites and addon URLs are deliberately absent,
  /// because a profile is a file that gets copied, shared and pushed to a
  /// television. With a passphrase the same profile is exported in full -
  /// including the credential set, portals and addons - and the whole document
  /// is encrypted with AES-256-GCM under a PBKDF2-derived key, so a full
  /// profile is never written in plaintext.
  static Future<String> exportSettingsJson({String? passphrase}) async {
    final prefs = await SharedPreferences.getInstance();
    final full = passphrase != null && passphrase.isNotEmpty;

    final exportData = <String, dynamic>{
      'schemaVersion': profileSchema,
      'exportedAt': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'secretsExcluded': !full,
      'settings': {},
      'theme': {},
      'iptv': {},
    };

    // 1. SharedPreferences dump of core settings
    final allKeys = prefs.getKeys();
    final settingsMap = <String, dynamic>{};
    for (final key in allKeys) {
      if (key.endsWith('__backup') || key.endsWith('__corrupt')) continue;
      if (full) {
        // Credentials travel in the encrypted `secrets` object below; every
        // other preference (portals, playlists, addons, library documents)
        // belongs in the full profile.
        if (SecretKeys.isSecret(key)) continue;
      } else if (_isExcluded(key)) {
        continue;
      }
      final val = prefs.get(key);
      if (val is String ||
          val is int ||
          val is double ||
          val is bool ||
          val is List<String>) {
        settingsMap[key] = val;
      }
    }
    exportData['settings'] = settingsMap;

    // 2. Current Theme & Background
    final currentBg = CustomBackgroundService.current;
    exportData['theme'] = {
      'paletteId': AppThemeService.currentPalette.value.id,
      'customBg': {
        'imagePath': currentBg.imagePath,
        'imageUrl': currentBg.imageUrl,
        'opacity': currentBg.opacity,
        'blur': currentBg.blur,
        'blendThemeLights': currentBg.blendThemeLights,
        'themeTintOpacity': currentBg.themeTintOpacity,
      },
      'ambientLightsEnabled': HomePageSettings.enableAmbientLights.value,
      'ambientPattern': HomePageSettings.ambientLightPattern.value.name,
      'ambientIntensity': HomePageSettings.ambientLightIntensity.value,
      'ambientSpeed': HomePageSettings.ambientLightSpeed.value,
    };

    if (full) {
      // Addons and IPTV travel in `settings` as their normal preference values,
      // which is exactly what the importer restores. The credential set is
      // read from the keystore because most of it no longer lives in
      // preferences at all.
      exportData['secrets'] = await ProfileSecrets.export();
      final plain = const JsonEncoder.withIndent('  ').convert(exportData);
      return ProfileCipher.encrypt(plain, passphrase);
    }

    // 3. No IPTV portals, playlists or favourites, and no addons. Each one
    // embeds account credentials in its URL or key, so those preferences are
    // filtered out of the settings map above and both sections stay empty.
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Imports from a file already on the device, for a profile too large to paste.
  ///
  /// The paste path is the right one for a handful of settings and unusable for
  /// a whole profile: a real export is tens of kilobytes of JSON with rails
  /// and settings in it, and typing that into a television with a remote is
  /// not a task anyone should attempt. Moving a profile to another device
  /// means pushing the file across - over adb, a share sheet, or a USB stick -
  /// and naming it here.
  ///
  /// [candidates] are absolute paths to try in order. The first that exists and
  /// parses wins, so one call can cover the common places a pushed file lands
  /// without the caller having to know where it went.
  static Future<String> importSettingsFromFile(
    List<String> candidates, {
    Future<String> Function(String path)? read,
    String? passphrase,
  }) async {
    final load = read ?? _readFile;
    for (final path in candidates) {
      final String contents;
      try {
        contents = await load(path);
      } catch (_) {
        // Not there, or not readable. Try the next one.
        continue;
      }
      if (contents.trim().isEmpty) continue;
      // Parsed before imported, so a truncated push is a clean miss on this
      // candidate rather than a half-applied profile.
      try {
        if (!ProfileCipher.isEncrypted(contents)) {
          jsonDecode(contents);
        }
      } catch (_) {
        continue;
      }
      return importSettingsJson(contents, passphrase: passphrase);
    }
    throw FileSystemException(_nothingReadable(candidates));
  }

  /// Why nothing was imported, naming every location that was looked in.
  ///
  /// The usual reason a profile does not load is that it is sitting somewhere
  /// the app is not allowed to read - under Android 14 scoped storage that is
  /// everything outside the app's own directory - so the message says where it
  /// looked and where the app can actually reach.
  static String _nothingReadable(List<String> candidates) {
    final tried = candidates.map((path) => '  - $path').join('\n');
    return 'No readable settings file. Looked in:\n'
        '$tried\n'
        'ZPlay can only read its own app directory without a storage '
        'permission, so push the profile there, or choose it with "From File".';
  }

  static Future<String> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('not found', path);
    }
    return file.readAsString();
  }

  /// Imports a profile a person chose through the system file picker.
  ///
  /// On Android the picker grants access to a SAF document and returns its
  /// bytes: the URI is not a filesystem path this process may open, so the
  /// bytes are the readable copy and re-opening a path is the failure this
  /// replaces. Desktop pickers return a real path instead, which is why the
  /// path is accepted as a fallback rather than ignored.
  static Future<String> importPickedProfile({
    Uint8List? bytes,
    String? path,
    String? name,
    String? passphrase,
  }) async {
    final String contents;
    if (bytes != null && bytes.isNotEmpty) {
      contents = utf8.decode(bytes);
    } else if (path != null && path.isNotEmpty) {
      contents = await _readFile(path);
    } else {
      throw const FileSystemException(
        'The chosen file could not be read. Choose it again with "From File".',
      );
    }
    if (contents.trim().isEmpty) {
      throw FileSystemException(
        'The chosen profile file is empty.',
        name ?? '',
      );
    }
    // Parsed before imported, so a file that is not a profile fails here
    // rather than half-applying whatever could be read from it.
    return importSettingsJson(contents, passphrase: passphrase);
  }

  /// The file name a profile is given wherever it is moved to.
  static const String importFileName = 'zplay_profile.json';

  /// Where a pushed profile is looked for, most readable first.
  ///
  /// The app's own external files directory leads the list. It is
  /// `/storage/emulated/0/Android/data/<package>/files`: `adb push` can write
  /// there and the app can read it with no storage permission at all, which is
  /// the only place that works unprompted under scoped storage. The package is
  /// resolved at runtime, so the debug build finds its own directory.
  ///
  /// `/sdcard/Download` stays on the list as a last resort so desktop and any
  /// device that does allow it keep working, but it is no longer the only
  /// place looked in - which is what left this feature unable to read a file
  /// on Android 14.
  ///
  /// [externalStorage] is injectable so a test can stand in for the platform
  /// lookup; a device uses [getExternalStorageDirectory].
  static Future<List<String>> importSearchPaths({
    Future<Directory?> Function()? externalStorage,
  }) async {
    final paths = <String>[];
    final own = await _ownProfilePath(
      externalStorage ?? getExternalStorageDirectory,
    );
    if (own != null) paths.add(own);
    paths.addAll(legacyImportSearchPaths);
    return paths;
  }

  /// The locations a pushed profile has historically been looked for in.
  ///
  /// Kept as the fallback described on [importSearchPaths].
  static const List<String> legacyImportSearchPaths = <String>[
    '/sdcard/Download/zplay_profile.json',
    '/storage/emulated/0/Download/zplay_profile.json',
  ];

  /// The profile inside the app's own external files directory, or null where
  /// there is no such directory (desktop, or no plugin behind the call).
  static Future<String?> _ownProfilePath(
    Future<Directory?> Function() externalStorage,
  ) async {
    try {
      final dir = await externalStorage();
      if (dir == null) return null;
      if (!kIsWeb && Platform.isAndroid) {
        // A push needs a directory that exists. Android creates this one on
        // demand; making sure of it here means the target named in the failure
        // message is there before anything else has written to it.
        try {
          await dir.create(recursive: true);
        } catch (_) {}
      }
      return p.join(dir.path, importFileName);
    } catch (_) {
      return null;
    }
  }

  static Future<String> importSettingsJson(
    String jsonStr, {
    String? passphrase,
  }) async {
    final encrypted = ProfileCipher.isEncrypted(jsonStr);
    if (encrypted) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const ProfileCipherException(
          'This profile is encrypted. Enter its passphrase to restore it.',
        );
      }
      jsonStr = ProfileCipher.decrypt(jsonStr, passphrase);
    }

    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid backup format: root must be a JSON object.',
      );
    }

    final declaredSchema = decoded['schemaVersion'];
    if (declaredSchema is num && declaredSchema > profileSchema) {
      throw FormatException(
        'This profile was written by a newer version of ZPlay '
        '(schema ${declaredSchema.toInt()}; this build understands up to '
        '$profileSchema). Update the app and try again.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    int restoredItems = 0;

    // An export produced by a build that redacted credentials says so. Even if
    // a hand-edited file still carries the keys, they are ignored: restoring
    // blanks over the local tokens would silently unpair every integration.
    final secretsExcluded = decoded['secretsExcluded'] == true;
    final secrets = decoded['secrets'];
    final hasSecretMap = secrets is Map<String, dynamic>;
    if (hasSecretMap) {
      // A full, encrypted profile carries its credentials here rather than in
      // the plain preference map.
      await ProfileSecrets.import(secrets);
    }

    // 1. Restore SharedPreferences
    if (decoded.containsKey('settings') && decoded['settings'] is Map) {
      final settings = decoded['settings'] as Map;
      for (final entry in settings.entries) {
        final key = entry.key.toString();
        if (secretsExcluded && _isExcluded(key)) continue;
        // Credentials from a full profile live in the keystore, not here.
        if (hasSecretMap && SecretKeys.isSecret(key)) continue;
        final dynamic val = entry.value;

        if (val is String) {
          await prefs.setString(key, val);
          restoredItems++;
        } else if (val is int) {
          await prefs.setInt(key, val);
          restoredItems++;
        } else if (val is double) {
          await prefs.setDouble(key, val);
          restoredItems++;
        } else if (val is bool) {
          await prefs.setBool(key, val);
          restoredItems++;
        } else if (val is List) {
          final strList = val.map((e) => e.toString()).toList();
          await prefs.setStringList(key, strList);
          restoredItems++;
        }
      }
    }

    // 1b. The settings map above replaced each service's durable document.
    // A running app keeps its own in-memory copy, so re-read those documents
    // here; without this the restored profile only takes effect on the next
    // launch. None of these touch the network.
    await MyListService.reloadLocal();
    await ContinueWatchingService.reloadLocal();
    await AnimeLibraryService.instance.reloadLocal();
    await ContinueReadingService.reload();
    await ReaderSettings.reload();
    await MusicDownloadService.instance.reload();

    // 2. Restore Theme
    if (decoded.containsKey('theme') && decoded['theme'] is Map) {
      final theme = decoded['theme'] as Map;
      final paletteId = theme['paletteId']?.toString();
      if (paletteId != null) {
        final found = AppThemeService.palettes.firstWhere(
          (p) => p.id == paletteId,
          // The same fallback as a fresh install, rather than whichever preset
          // happens to sit first in the list - otherwise restoring a backup from
          // an older version lands on a palette the user never chose.
          orElse: () => AppThemeService.defaultPalette,
        );
        await AppThemeService.setPalette(found);
      }

      if (theme['customBg'] is Map) {
        final bgMap = Map<String, dynamic>.from(theme['customBg'] as Map);
        if (bgMap['imageUrl'] != null &&
            bgMap['imageUrl'].toString().isNotEmpty) {
          await CustomBackgroundService.setImageUrl(
            bgMap['imageUrl'].toString(),
          );
        }
        if (bgMap['opacity'] is num) {
          await CustomBackgroundService.setOpacity(
            (bgMap['opacity'] as num).toDouble(),
          );
        }
        if (bgMap['blur'] is num) {
          await CustomBackgroundService.setBlur(
            (bgMap['blur'] as num).toDouble(),
          );
        }
      }
    }

    // 3. Older backups also carry a debrid object. Its provider keys are string
    // preferences restored by the settings map above, so only the selected
    // service is applied here.
    if (decoded.containsKey('debrid') && decoded['debrid'] is Map) {
      final sel = (decoded['debrid'] as Map)['selectedService']?.toString();
      if (sel != null && sel.isNotEmpty) {
        await DebridService().saveSelectedService(sel);
      }
    }
    await DebridService.refreshDebridReady();

    // 3b. A legacy profile's settings map went straight into storage, and the
    // credential readers hydrated themselves once at startup (see `main.dart`).
    // Left alone they keep serving the values the device had before the import:
    // Settings shows the Debrid keys the export carried as unset and the TMDb
    // key as "Not set", and every caller of those readers keeps using the old
    // credential until the app is restarted. Re-run the startup reads here, so
    // an imported profile is live the moment this returns. A redacted profile
    // has written no credential, so this simply re-reads the local ones.
    await ServiceCredentials.reload();
    await TmdbService.reload();

    // 4. Restore Addons
    if (!secretsExcluded &&
        decoded.containsKey('addons') &&
        decoded['addons'] is Map) {
      final addonsObj = decoded['addons'] as Map;
      if (addonsObj['installed'] is List) {
        final list = addonsObj['installed'] as List;
        for (final item in list) {
          if (item is Map && item['baseUrl'] != null) {
            final url = item['baseUrl'].toString();
            try {
              final added = await AddonManager.instance.addAddon(url);
              await AddonManager.instance.updateAddonFeature(
                addonId: added.manifest.id,
                enableCatalogs: item['enableCatalogs'] as bool?,
                enableSearch: item['enableSearch'] as bool?,
                enableStreams: item['enableStreams'] as bool?,
                enableSubtitles: item['enableSubtitles'] as bool?,
              );
            } catch (_) {}
          }
        }
      }
    }
    // A legacy profile's `installed_addons_v5` arrived in the settings map and
    // its addons were installed above; the running list has to pick both up.
    // A redacted profile leaves that preference alone, and this reload keeps
    // the destination's own list rather than a half-applied one.
    await AddonManager.instance.reload();

    // 5. Restore IPTV
    if (decoded.containsKey('iptv') && decoded['iptv'] is Map) {
      final iptvObj = decoded['iptv'] as Map;
      // A redacted profile has no portals, playlists or favourites to
      // restore. A legacy one that still carries them is imported, since that
      // was the contract when it was written.
      if (!secretsExcluded) {
        if (iptvObj['customPortals'] is List) {
          final list = (iptvObj['customPortals'] as List)
              .map((e) => e.toString())
              .toList();
          await prefs.setStringList('iptv_custom_portals', list);
        }
        if (iptvObj['m3uPlaylists'] is String) {
          await prefs.setString(
            'iptv_m3u_playlists',
            iptvObj['m3uPlaylists'] as String,
          );
        }
        if (iptvObj['favoritePortals'] is List) {
          final list = (iptvObj['favoritePortals'] as List)
              .map((e) => e.toString())
              .toList();
          await prefs.setStringList('iptv_favorite_portals', list);
        }
      }
    }

    if (encrypted) {
      return 'Successfully restored full profile ($restoredItems settings, '
          'credentials and portals).';
    }
    if (secretsExcluded) {
      return 'Successfully restored configuration ($restoredItems settings). '
          'Credentials, portals and addons stay on this device.';
    }
    return 'Successfully restored configuration ($restoredItems settings, addons & portals restored).';
  }
}
