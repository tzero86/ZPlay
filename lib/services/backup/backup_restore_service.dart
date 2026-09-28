import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addon/addon_manager.dart';
import '../config/service_credentials.dart';
import '../metadata/tmdb_service.dart';
import '../theme/app_theme_service.dart';
import '../home/home_page_settings.dart';
import '../theme/custom_background_service.dart';
import '../debrid/debrid_service.dart';

class BackupRestoreService {
  static const String appVersion = '1.1.6';

  /// Exports all app settings, installed addons, IPTV portals/playlists,
  /// theme preferences, and credentials into a formatted JSON string.
  static Future<String> exportSettingsJson() async {
    final prefs = await SharedPreferences.getInstance();

    final exportData = <String, dynamic>{
      'version': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'settings': {},
      'theme': {},
      'iptv': {},
      'addons': {},
    };

    // 1. SharedPreferences dump of core settings
    final allKeys = prefs.getKeys();
    final settingsMap = <String, dynamic>{};
    for (final key in allKeys) {
      final val = prefs.get(key);
      if (val is String || val is int || val is double || val is bool || val is List<String>) {
        settingsMap[key] = val;
      }
    }
    // Debrid provider keys are plain string preferences, so they ride along in
    // this map. There is deliberately no separate debrid object to read.
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

    // 3. IPTV Custom Portals & Playlists
    try {
      final customPortals = prefs.getStringList('iptv_custom_portals') ?? [];
      final m3uPlaylists = prefs.getString('iptv_m3u_playlists') ?? '[]';
      final favPortals = prefs.getStringList('iptv_favorite_portals') ?? [];

      exportData['iptv'] = {
        'customPortals': customPortals,
        'm3uPlaylists': m3uPlaylists,
        'favoritePortals': favPortals,
      };
    } catch (_) {}

    // 4. Installed Addons
    try {
      final installedAddons = AddonManager.instance.addons
          .map((a) => {
                'baseUrl': a.baseUrl,
                'enabled': a.enabled,
                'enableCatalogs': a.enableCatalogs,
                'enableSearch': a.enableSearch,
                'enableStreams': a.enableStreams,
                'enableSubtitles': a.enableSubtitles,
              })
          .toList();

      exportData['addons'] = {
        'installed': installedAddons,
      };
    } catch (_) {}

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Imports from a file already on the device, for a profile too large to paste.
  ///
  /// The paste path is the right one for a handful of settings and unusable for
  /// a whole profile: a real export is around 200 KB of JSON with addons, rails
  /// and credentials in it, and typing that into a television with a remote is
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
        jsonDecode(contents);
      } catch (_) {
        continue;
      }
      return importSettingsJson(contents);
    }
    throw const FileSystemException(
      'No readable settings file at any of:',
    );
  }

  static Future<String> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('not found', path);
    }
    return file.readAsString();
  }

  /// Where a pushed profile is looked for.
  ///
  /// `/sdcard/Download` is where `adb push` and most share sheets land, and
  /// the app's own external files directory is the only other place the app can
  /// reach without a storage permission it does not otherwise ask for.
  static const List<String> importSearchPaths = <String>[
    '/sdcard/Download/zplay_profile.json',
    '/storage/emulated/0/Download/zplay_profile.json',
  ];
  static Future<String> importSettingsJson(String jsonStr) async {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup format: root must be a JSON object.');
    }

    final prefs = await SharedPreferences.getInstance();
    int restoredItems = 0;

    // 1. Restore SharedPreferences
    if (decoded.containsKey('settings') && decoded['settings'] is Map) {
      final settings = decoded['settings'] as Map;
      for (final entry in settings.entries) {
        final key = entry.key.toString();
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

    // 2. Restore Theme
    if (decoded.containsKey('theme') && decoded['theme'] is Map) {
      final theme = decoded['theme'] as Map;
      final paletteId = theme['paletteId']?.toString();
      if (paletteId != null) {
        final found = AppThemeService.palettes.firstWhere(
          (p) => p.id == paletteId,
          orElse: () => AppThemeService.palettes.first,
        );
        await AppThemeService.setPalette(found);
      }

      if (theme['customBg'] is Map) {
        final bgMap = Map<String, dynamic>.from(theme['customBg'] as Map);
        if (bgMap['imageUrl'] != null && bgMap['imageUrl'].toString().isNotEmpty) {
          await CustomBackgroundService.setImageUrl(bgMap['imageUrl'].toString());
        }
        if (bgMap['opacity'] is num) {
          await CustomBackgroundService.setOpacity((bgMap['opacity'] as num).toDouble());
        }
        if (bgMap['blur'] is num) {
          await CustomBackgroundService.setBlur((bgMap['blur'] as num).toDouble());
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

    // 3b. The settings map went straight into storage, and the credential
    // readers hydrated themselves once at startup (see `main.dart`). Left
    // alone they keep serving the values the device had before the import:
    // Settings shows the Debrid keys the export carried as unset and the TMDb
    // key as "Not set", and every caller of those readers keeps using the old
    // credential until the app is restarted. Re-run the startup reads here, so
    // an imported profile is live the moment this returns.
    await ServiceCredentials.reload();
    await TmdbService.reload();

    // 4. Restore Addons
    if (decoded.containsKey('addons') && decoded['addons'] is Map) {
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
    // `installed_addons_v5` is a plain setting, so the list a real profile
    // carries arrived in the map above and only the stored copy of it has been
    // replaced so far. Without this the in-memory list keeps the pre-import
    // addons - the profile looks like it did not transfer - and the next save
    // would write that stale list back over the imported one.
    await AddonManager.instance.reload();

    // 5. Restore IPTV
    if (decoded.containsKey('iptv') && decoded['iptv'] is Map) {
      final iptvObj = decoded['iptv'] as Map;
      if (iptvObj['customPortals'] is List) {
        final list = (iptvObj['customPortals'] as List).map((e) => e.toString()).toList();
        await prefs.setStringList('iptv_custom_portals', list);
      }
      if (iptvObj['m3uPlaylists'] is String) {
        await prefs.setString('iptv_m3u_playlists', iptvObj['m3uPlaylists'] as String);
      }
      if (iptvObj['favoritePortals'] is List) {
        final list = (iptvObj['favoritePortals'] as List).map((e) => e.toString()).toList();
        await prefs.setStringList('iptv_favorite_portals', list);
      }
    }

    return 'Successfully restored configuration ($restoredItems settings, addons & portals restored).';
  }
}
