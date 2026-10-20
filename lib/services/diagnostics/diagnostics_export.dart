import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout/device_profile.dart';
import '../player/player_settings.dart';
import '../storage/secret_keys.dart';
import '../stream/torrent_stream_service.dart';
import 'crash_breadcrumbs.dart';
import 'renderer_backend.dart';

/// Builds the local-only diagnostic report a user can paste into a bug report.
///
/// **Nothing here leaves the device.** The report is an in-memory string until
/// the user taps copy, or a file under the app's own support directory until
/// they tap save; there is no upload path, no analytics hook and no telemetry.
/// That is the same contract [CrashBreadcrumbs] keeps, and the reason this
/// class is allowed to read device facts at all.
///
/// **Redaction is the same boundary the profile export draws, plus one.** A
/// diagnostic report is a file people paste into public issue trackers, so it
/// must never carry a credential, a portal URL (they embed a username and
/// password), an M3U link (it embeds a token) or an addon base URL (it carries
/// whatever provider key the addon was configured with). The excluded set is
/// the one `BackupRestoreService._isExcluded` applies - that boundary is
/// already the app's answer to "what is a credential" - widened by the whole
/// `pt_iptv_` namespace, because its per-channel caches store a portal URL with
/// its username and password as three sibling strings, which URL scrubbing
/// alone would not hide. Any URL that survives into free text (a breadcrumb
/// message, an error string) is reduced to its origin, so the *host* stays
/// diagnosable and the path - where both kinds of token live - does not.
///
/// **Never throws.** A missing platform plugin, a failed directory lookup or a
/// read-only filesystem all degrade to "that field is absent" or "the file was
/// not written"; a diagnostics tool that crashes the app is worse than no
/// diagnostics tool. Every seam is injectable so the whole thing runs in a unit
/// test without `path_provider`, `package_info_plus` or a filesystem.
class DiagnosticsExport {
  DiagnosticsExport({
    Future<PackageInfo> Function()? packageInfo,
    Future<SharedPreferences?> Function()? preferences,
    Future<Directory?> Function()? reportDirectory,
    DateTime Function()? clock,
    List<Breadcrumb> Function()? breadcrumbs,
    String? Function()? torrentEngineState,
  }) : _packageInfo = packageInfo ?? _defaultPackageInfo,
       _preferences = preferences ?? _defaultPreferences,
       _reportDirectory = reportDirectory ?? _defaultReportDirectory,
       _clock = clock ?? DateTime.now,
       _breadcrumbs = breadcrumbs ?? (() => CrashBreadcrumbs.entries),
       _torrentEngineState = torrentEngineState ?? _defaultTorrentEngineState;

  /// The production instance. [DiagnosticsExport] is stateless apart from its
  /// injected seams, so one instance is enough and callers cannot accidentally
  /// fork the redaction boundary.
  static final DiagnosticsExport instance = DiagnosticsExport();

  /// Version of the report document. Bumped when a field changes shape, so a
  /// report attached to an old issue stays interpretable.
  static const int schemaVersion = 1;

  /// How many of the newest breadcrumbs a report carries. The log itself is
  /// capped at [CrashBreadcrumbs.maxEntries]; the report is a paste, so it is
  /// capped tighter than the buffer and always carries the tail.
  static const int maxBreadcrumbs = 50;

  /// Preference keys whose *contents* carry a credential, copied from
  /// `BackupRestoreService._credentialBearingKeys`. Keep the two lists equal:
  /// see the class comment for why this is duplicated rather than shared.
  static const List<String> _credentialBearingKeys = <String>[
    'installed_addons_v5',
    'iptv_custom_portals',
    'iptv_m3u_playlists',
    'pt_iptv_m3u_playlists_v1',
    'iptv_favorite_portals',
    'pt_iptv_favorite_portal_keys',
  ];

  /// `pt_iptv_dead_urls` (see `IptvDeadUrlStore`) holds one entry per stream
  /// URL that failed playback recently. Only its *count* is reported: the keys
  /// are portal URLs.
  static const String _iptvDeadUrlsKey = 'pt_iptv_dead_urls';

  /// The whole IPTV persistence namespace.
  ///
  /// `pt_iptv_ch_`, `pt_iptv_alive_`, `pt_iptv_verified_portals`,
  /// `pt_iptv_quick_channels` and the rest store portal records - URL, username
  /// and password side by side in one JSON string - so URL-only scrubbing would
  /// still print the two bare strings. The profile export's list names the
  /// settings it knows about; this prefix is what catches the per-channel caches
  /// it does not.
  static const String _iptvStoragePrefix = 'pt_iptv_';

  final Future<PackageInfo> Function() _packageInfo;
  final Future<SharedPreferences?> Function() _preferences;
  final Future<Directory?> Function() _reportDirectory;
  final DateTime Function() _clock;
  final List<Breadcrumb> Function() _breadcrumbs;
  final String? Function() _torrentEngineState;

  /// Whether [prefKey] must be left out of a report.
  ///
  /// The same predicate `BackupRestoreService` applies to a profile export:
  /// credentials, the store's own backup/quarantine copies, and the settings
  /// whose values embed credentials.
  static bool isExcludedKey(String prefKey) =>
      SecretKeys.isSecret(prefKey) ||
      prefKey.endsWith('__backup') ||
      prefKey.endsWith('__corrupt') ||
      prefKey.startsWith(_iptvStoragePrefix) ||
      _credentialBearingKeys.contains(prefKey);

  /// Collects the report as JSON-shaped data.
  Future<Map<String, Object?>> collect() async {
    final now = _clock();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'generatedAt': now.toIso8601String(),
      'localOnly': true,
      'secretsExcluded': true,
      'app': await _appSection(),
      'device': _deviceSection(),
      'player': _playerSection(),
      'streamEngine': <String, Object?>{
        'torrentEngine': _safe(_torrentEngineState),
      },
      'iptv': await _iptvSection(),
      'breadcrumbs': _breadcrumbSection(),
      'settings': await _settingsSection(),
    };
  }

  /// The report as indented JSON - readable on its own in a chat window or an
  /// issue tracker, which is the point of writing it as text rather than a
  /// table dump.
  Future<String> buildReportString() async =>
      const JsonEncoder.withIndent('  ').convert(await collect());

  /// What the "Copy report" controls put on the clipboard.
  ///
  /// Same bytes as [buildReportString]; named separately because that is the
  /// user-facing action and because a test seam here is what lets the Settings
  /// page and the player overlay be verified without a clipboard plugin.
  Future<String> copyText() => buildReportString();

  /// Writes a timestamped `.json` under `<app support>/ZPlay/diagnostics/`.
  ///
  /// Returns the written path, or null when no directory is available (a
  /// missing plugin, a platform with no writable support directory) or the
  /// write failed. Never throws.
  Future<String?> saveReport() async {
    try {
      final base = await _reportDirectory();
      if (base == null) return null;
      final directory = Directory(p.join(base.path, 'ZPlay', 'diagnostics'));
      await directory.create(recursive: true);
      final file = File(
        p.join(directory.path, 'zplay-diagnostics-${_stamp(_clock())}.json'),
      );
      await file.writeAsString(await buildReportString(), flush: true);
      return file.path;
    } catch (error) {
      debugPrint('[DiagnosticsExport] could not save report: $error');
      return null;
    }
  }

  Future<Map<String, Object?>> _appSection() async {
    PackageInfo? info;
    try {
      info = await _packageInfo();
    } catch (error) {
      debugPrint('[DiagnosticsExport] package info unavailable: $error');
    }
    return <String, Object?>{
      'version': info?.version,
      'build': info?.buildNumber,
      'packageName': info?.packageName,
      'buildMode': _buildMode(),
    };
  }

  Map<String, Object?> _deviceSection() {
    final television = DeviceProfile.isTelevision;
    return <String, Object?>{
      'targetPlatform': defaultTargetPlatform.name,
      'operatingSystem': _safe(() => Platform.operatingSystem),
      'operatingSystemVersion': _safe(() => Platform.operatingSystemVersion),
      'formFactor': television ? 'television' : 'pointer',
      'television': television,
      'rendererBackend': RendererBackendSettings.current.value.storageValue,
    };
  }

  Map<String, Object?> _playerSection() {
    return <String, Object?>{
      'engine': PlayerSettings.playbackEngine.value.name,
      'hardwareDecoding': PlayerSettings.hwdecMode.value.mpvValue,
      'surfaceProducer': PlayerSettings.enableSurfaceProducer.value,
      'autoRecoverBlackScreen': PlayerSettings.autoRecoverBlackScreen.value,
      'anime4k': PlayerSettings.anime4kPreset.value.name,
      'subtitleStyle': PlayerSettings.subStylePreset.value.name,
    };
  }

  Future<Map<String, Object?>> _iptvSection() async {
    final prefs = await _safePrefs();
    final raw = prefs?.getString(_iptvDeadUrlsKey);
    int? rememberedFailures;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) rememberedFailures = decoded.length;
      } catch (_) {
        // A corrupt store is itself worth reporting, as "unknown".
      }
    }
    return <String, Object?>{'rememberedFailures': rememberedFailures};
  }

  Map<String, Object?> _breadcrumbSection() {
    final entries = _safe(_breadcrumbs) ?? const <Breadcrumb>[];
    final tail = entries.length <= maxBreadcrumbs
        ? entries
        : entries.sublist(entries.length - maxBreadcrumbs);
    return <String, Object?>{
      'count': entries.length,
      'limit': maxBreadcrumbs,
      'entries': <Object?>[for (final entry in tail) _breadcrumbJson(entry)],
    };
  }

  Map<String, Object?> _breadcrumbJson(Breadcrumb entry) {
    return <String, Object?>{
      'seq': entry.seq,
      'at': entry.at.toIso8601String(),
      'category': entry.category,
      'message': scrubText(entry.message),
      if (entry.rssMb != null) 'rssMb': entry.rssMb,
      if (entry.data != null && entry.data!.isNotEmpty)
        'data': <String, String>{
          for (final pair in entry.data!.entries)
            pair.key: scrubText(pair.value),
        },
    };
  }

  Future<Map<String, Object?>> _settingsSection() async {
    final prefs = await _safePrefs();
    if (prefs == null) {
      return <String, Object?>{'available': false};
    }
    final settings = <String, Object?>{};
    var redacted = 0;
    for (final key in prefs.getKeys()) {
      if (isExcludedKey(key)) {
        redacted++;
        continue;
      }
      final value = prefs.get(key);
      if (value is String ||
          value is int ||
          value is double ||
          value is bool ||
          value is List<String>) {
        settings[key] = _scrubValue(value);
      }
    }
    final sortedKeys = settings.keys.toList()..sort();
    return <String, Object?>{
      'available': true,
      'redactedKeyCount': redacted,
      'values': <String, Object?>{
        for (final key in sortedKeys) key: settings[key],
      },
    };
  }

  Future<SharedPreferences?> _safePrefs() async {
    try {
      return await _preferences();
    } catch (error) {
      debugPrint('[DiagnosticsExport] preferences unavailable: $error');
      return null;
    }
  }

  String _buildMode() {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    return 'debug';
  }

  static String _stamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }

  static T? _safe<T>(T? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  static Object? _scrubValue(Object? value) {
    if (value is String) return scrubText(value);
    if (value is List<String>) {
      return <Object?>[for (final item in value) scrubText(item)];
    }
    return value;
  }

  /// Any `scheme://…` URL, up to the next whitespace or quote.
  static final RegExp _urlPattern = RegExp(
    r'''[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s"'<>\\]+''',
  );

  /// Rewrites every URL in [text] to its origin, dropping the path and query
  /// where an addon key, a portal username/password or an M3U token lives.
  ///
  /// A URL that cannot be parsed is replaced whole: an unreadable origin is not
  /// a reason to ship the string.
  @visibleForTesting
  static String scrubText(String text) {
    if (!text.contains('://')) return text;
    return text.replaceAllMapped(_urlPattern, (match) => _originOf(match[0]!));
  }

  static String _originOf(String raw) {
    final uri = Uri.tryParse(raw);
    final scheme = uri?.scheme;
    final host = uri?.host;
    if (uri == null || scheme == null || scheme.isEmpty) {
      return '[redacted-url]';
    }
    if (host == null || host.isEmpty) return '[redacted-url]';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$port/[redacted]';
  }

  static Future<PackageInfo> _defaultPackageInfo() =>
      PackageInfo.fromPlatform();

  static Future<SharedPreferences?> _defaultPreferences() async =>
      SharedPreferences.getInstance();

  static Future<Directory?> _defaultReportDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      try {
        return await getApplicationDocumentsDirectory();
      } catch (_) {
        return null;
      }
    }
  }

  /// The engine's lifecycle state is a plain field on the singleton, so this is
  /// a read with no HTTP call and no start. A device that never plays a torrent
  /// reports `stopped`, which is the truth rather than a failure.
  static String? _defaultTorrentEngineState() {
    try {
      return TorrentStreamService().state.name;
    } catch (_) {
      return null;
    }
  }
}
