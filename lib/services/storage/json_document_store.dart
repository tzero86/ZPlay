import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Migrates one stored document from version `N` to `N + 1`.
///
/// The value handed in is the JSON-shaped document as it was stored, not the
/// typed model, so a migration can be written without loading model classes.
typedef JsonMigration = Object? Function(Object? value);

/// A typed, versioned JSON document persisted in [SharedPreferences] with
/// atomic-per-key writes and a last-known-good copy.
///
/// SharedPreferences already writes a single key atomically, but a raw
/// `jsonEncode` value has no recovery path: one truncated or hand-edited
/// string makes `jsonDecode` throw, and callers historically responded by
/// resetting the document to an empty list. This store wraps the payload in an
/// envelope carrying the schema version and a SHA-256 checksum, keeps the
/// previous valid envelope under `<key>__backup`, and quarantines a payload
/// that cannot be recovered as `<key>__corrupt` instead of discarding it.
///
/// A legacy bare JSON payload (the format every store used before this class)
/// is accepted as schema `0` and migrated through [migrations]; a successful
/// read rewrites it in the envelope format, so existing installs upgrade in
/// place.
class JsonDocumentStore<T> {
  JsonDocumentStore({
    required this.key,
    required this.version,
    required this.decode,
    required this.encode,
    this.migrations = const <int, JsonMigration>{},
  });

  /// Preference key holding the live document.
  final String key;

  /// Current schema version. A stored document at an older version runs every
  /// migration from its version up to this one.
  final int version;

  /// Turns a JSON-shaped document into the typed value the app uses.
  final T Function(Object? value) decode;

  /// Turns the typed value back into a JSON-encodable document.
  final Object? Function(T value) encode;

  /// `from version -> migration`, where each migration produces `from + 1`.
  /// A store reading legacy bare JSON must declare a migration from `0`.
  final Map<int, JsonMigration> migrations;

  static const String schemaField = r'$zplaySchema';
  static const String checksumField = r'$zplayChecksum';
  static const String dataField = 'data';
  static const String backupSuffix = '__backup';
  static const String quarantineSuffix = '__corrupt';

  static final Map<String, Future<void>> _writeChains =
      <String, Future<void>>{};

  String get backupKey => '$key$backupSuffix';
  String get quarantineKey => '$key$quarantineSuffix';

  /// Reads the document, recovering from the backup when the live copy cannot
  /// be verified, and returns `null` when neither copy is readable.
  ///
  /// A successful recovery rewrites the live copy so the next launch starts
  /// clean. An unrecoverable payload is left under [quarantineKey] for
  /// inspection rather than deleted.
  Future<T?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = prefs.getString(key);
    final backup = prefs.getString(backupKey);

    final ({T value, bool needsRewrite})? live;
    try {
      live = _parse(primary);
    } on _NewerSchemaException {
      // A newer build wrote this document. Never overwrite it with an older
      // backup: the user can still go back to that build.
      _reportRecovery('document schema is newer than this build; leaving it');
      return null;
    }
    if (live != null) {
      if (live.needsRewrite) {
        await prefs.setString(key, _envelope(live.value));
      }
      return live.value;
    }

    final ({T value, bool needsRewrite})? previous;
    try {
      previous = _parse(backup);
    } on _NewerSchemaException {
      return null;
    }
    if (previous != null) {
      await prefs.setString(key, _envelope(previous.value));
      if (primary != null && primary.isNotEmpty) {
        await prefs.setString(quarantineKey, primary);
      }
      _reportRecovery('recovered from backup');
      return previous.value;
    }

    if (primary != null && primary.isNotEmpty) {
      await prefs.setString(quarantineKey, primary);
      _reportRecovery('quarantined unreadable live copy');
    } else if (backup != null && backup.isNotEmpty) {
      await prefs.setString(quarantineKey, backup);
      _reportRecovery('quarantined unreadable backup copy');
    }
    return null;
  }

  /// Persists [value], preserving the previous valid document as the backup.
  ///
  /// Writes to the same key are serialized, so two callers arriving together
  /// cannot interleave the backup snapshot with the next write.
  Future<void> write(T value) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final ({T value, bool needsRewrite})? live;
      try {
        live = _parse(prefs.getString(key));
      } on _NewerSchemaException {
        _reportRecovery('refusing to overwrite a newer document');
        return;
      }
      if (live != null) {
        await prefs.setString(backupKey, _envelope(live.value));
      }
      await prefs.setString(key, _envelope(value));
    });
  }

  /// Removes the live document, its backup, and any quarantined copy.
  Future<void> clear() {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove(backupKey);
      await prefs.remove(quarantineKey);
    });
  }

  Future<void> _serialized(Future<void> Function() operation) {
    final previous = _writeChains[key] ?? Future<void>.value();
    final next = previous.then((_) => operation(), onError: (_) => operation());
    _writeChains[key] = next;
    void cleanup() {
      if (identical(_writeChains[key], next)) {
        _writeChains.remove(key);
      }
    }

    unawaited(
      next.then(
        (_) => cleanup(),
        onError: (Object _, StackTrace _) => cleanup(),
      ),
    );
    return next;
  }

  ({T value, bool needsRewrite})? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded.containsKey(schemaField)) {
        final schema = decoded[schemaField];
        if (schema is! int || schema < 1) {
          return null;
        }
        if (schema > version) {
          throw const _NewerSchemaException();
        }
        final data = decoded[dataField];
        final checksum = decoded[checksumField];
        if (checksum is! String || checksum != _checksum(data)) {
          return null;
        }
        return (value: _migrate(data, schema), needsRewrite: schema != version);
      }
      return (value: _migrate(decoded, 0), needsRewrite: true);
    } on _NewerSchemaException {
      rethrow;
    } catch (error) {
      debugPrint('[JsonDocumentStore] $key is unreadable: $error');
      return null;
    }
  }

  T _migrate(Object? data, int fromVersion) {
    var migrated = data;
    for (var version = fromVersion; version < this.version; version++) {
      final migration = migrations[version];
      if (migration == null) {
        throw FormatException('No migration from schema $version for "$key".');
      }
      migrated = migration(migrated);
    }
    return decode(migrated);
  }

  String _envelope(T value) {
    final data = encode(value);
    return jsonEncode(<String, Object?>{
      schemaField: version,
      checksumField: _checksum(data),
      dataField: data,
    });
  }

  static String _checksum(Object? data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  void _reportRecovery(String message) {
    debugPrint('[JsonDocumentStore] $key: $message');
  }
}

/// A document written by a newer build than the one reading it.
class _NewerSchemaException implements Exception {
  const _NewerSchemaException();
}
