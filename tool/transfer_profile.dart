// Build a BackupRestoreService-compatible export from the Windows profile.
//
// The app's own export is clipboard-only, which means moving a profile to a
// television means reading it out of the UI by hand. The format is just the
// same JSON over the same SharedPreferences, so it can be produced from the
// profile file directly and imported by pasting into Settings -> Import.
//
// Reads:  %APPDATA%\tzero86\zplay\shared_preferences.json
// Writes: tv_transfer.json
//
// SharedPreferences prefixes every key with `flutter.` in the on-disk file and
// `getKeys()` reports the bare name, so the prefix is stripped to match what
// `importSettingsJson` expects - it writes through the same API.
//
// Values that are not str/int/double/bool/List<String> are skipped, which is the
// same filter `exportSettingsJson` applies.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final home = Platform.environment['APPDATA'];
  if (home == null) {
    stderr.writeln('APPDATA not set');
    exit(2);
  }
  final source = File(
    '$home\\tzero86\\zplay\\shared_preferences.json',
  );
  if (!source.existsSync()) {
    stderr.writeln('no profile at ${source.path}');
    exit(2);
  }

  final raw = (jsonDecode(source.readAsStringSync()) as Map).cast<String, Object?>();
  final settings = <String, Object?>{};
  var skipped = 0;
  for (final entry in raw.entries) {
    final name = entry.key.startsWith('flutter.')
        ? entry.key.substring('flutter.'.length)
        : entry.key;
    final v = entry.value;
    final ok = v is String ||
        v is int ||
        v is double ||
        v is bool ||
        (v is List && v.every((e) => e is String));
    if (ok) {
      settings[name] = v;
    } else {
      skipped++;
    }
  }

  final out = <String, Object?>{
    'version': '1.3.1',
    'exportedAt': DateTime.now().toIso8601String(),
    'platform': 'windows-profile',
    'settings': settings,
    // The app fills these from live state; an import that carries them empty
    // falls back to the target device's own, which is what we want.
    'theme': <String, Object?>{},
    'iptv': <String, Object?>{},
    'addons': <String, Object?>{},
  };

  File('tv_transfer.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );

  // Report the credentials that made it across, with values masked, so a
  // transfer can be verified without printing secrets into a log.
  const secrets = [
    'tmdb_api_key',
    'rd_access_token',
    'service_key_wyzie',
    'qobuz_eclipse_token',
    'debrid_service',
  ];
  stdout.writeln('keys exported: ${settings.length} (skipped $skipped)');
  for (final s in secrets) {
    final v = settings[s];
    if (v == null) {
      stdout.writeln('  $s: MISSING');
      continue;
    }
    final s2 = v.toString();
    final masked = s2.length > 8
        ? '${s2.substring(0, 4)}...${s2.substring(s2.length - 4)}'
        : '***';
    stdout.writeln('  $s: $masked (len ${s2.length})');
  }
}
