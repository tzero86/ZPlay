import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadPathHelper {
  static const String _customPathKey = 'custom_downloads_directory';
  static const String _customPathHistoryKey =
      'custom_downloads_directory_history';
  static const int _maxRememberedDirectories = 10;

  /// Launches the native system folder picker so user can pick where to save downloads.
  static Future<String?> pickDownloadsDirectory() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Downloads Folder',
      );
      if (selected != null && selected.isNotEmpty) {
        await setCustomDownloadsDirectoryPath(selected);
        return selected;
      }
    } catch (e) {
      debugPrint('[DownloadPathHelper] Folder picker error: $e');
    }
    return null;
  }

  /// Returns the configured downloads directory path.
  static Future<String> getDownloadsDirectoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_customPathKey);
    if (custom != null && custom.isNotEmpty) {
      final customDir = Directory(custom);
      if (await customDir.exists() || await _tryCreate(customDir)) {
        return custom;
      }
    }

    final defaultPath = await getDefaultDownloadsDirectoryPath();
    final defaultDir = Directory(defaultPath);
    if (!await defaultDir.exists()) {
      await defaultDir.create(recursive: true);
    }
    return defaultPath;
  }

  /// Sets a custom user downloads directory.
  static Future<void> setCustomDownloadsDirectoryPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customPathKey, path);

    // Keep a bounded history of user-picked folders so downloads started in a
    // previously selected folder can still be validated and resumed after the
    // user picks a different one.
    final normalized = p.normalize(p.absolute(path));
    final history = prefs.getStringList(_customPathHistoryKey) ?? const [];
    final updated = <String>[normalized];
    for (final previous in history) {
      final previousNormalized = p.normalize(p.absolute(previous));
      if (previousNormalized != normalized &&
          !updated.contains(previousNormalized)) {
        updated.add(previousNormalized);
      }
      if (updated.length >= _maxRememberedDirectories) break;
    }
    await prefs.setStringList(_customPathHistoryKey, updated);
  }

  /// Download roots the app itself recorded, used to validate persisted task
  /// paths without trusting the task file's own directory string.
  static Future<List<String>> getTrustedDownloadDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    final roots = <String>{
      await getDownloadsDirectoryPath(),
      await getDefaultDownloadsDirectoryPath(),
    };

    final current = prefs.getString(_customPathKey);
    if (current != null && current.isNotEmpty) roots.add(current);

    final history = prefs.getStringList(_customPathHistoryKey) ?? const [];
    roots.addAll(history.where((path) => path.isNotEmpty));

    return roots.toList();
  }

  /// Returns the platform default download directory.
  static Future<String> getDefaultDownloadsDirectoryPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final publicDownload = Directory('/storage/emulated/0/Download/ZPlay');
        if (await publicDownload.exists() || await _tryCreate(publicDownload)) {
          return publicDownload.path;
        }

        final extDirs = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (extDirs != null && extDirs.isNotEmpty) {
          final target = Directory(p.join(extDirs.first.path, 'ZPlay'));
          if (await target.exists() || await _tryCreate(target)) {
            return target.path;
          }
        }
      } catch (_) {}
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final target = Directory(p.join(downloadsDir.path, 'ZPlay'));
          if (await target.exists() || await _tryCreate(target)) {
            return target.path;
          }
        }
      } catch (_) {}
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final fallback = Directory(p.join(appDocDir.path, 'Downloads'));
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback.path;
  }

  static Future<bool> _tryCreate(Directory dir) async {
    try {
      await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sanitizes a filename removing forbidden filesystem characters.
  static String sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
