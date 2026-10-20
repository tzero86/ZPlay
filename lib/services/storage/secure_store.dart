import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The storage surface [SecureStore] needs from a platform keystore.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [SecureKeyValueStore] backed by the platform keystore. Android uses
/// EncryptedSharedPreferences, Apple the Keychain, Windows DPAPI, Linux
/// libsecret.
class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Credential storage that prefers the platform keystore.
///
/// A keystore is not always there: unit tests have no plugin, a Linux desktop
/// without libsecret cannot open one, and a locked keychain can refuse a read.
/// None of those may make a saved credential disappear, so every operation
/// degrades to [SharedPreferences] under the same key, and a value found only
/// in preferences is migrated into the keystore on the first successful read.
abstract final class SecureStore {
  static final SecureKeyValueStore _platformStore =
      PlatformSecureKeyValueStore();

  /// Stands in for the platform keystore in tests.
  @visibleForTesting
  static SecureKeyValueStore? storeOverride;

  static bool _warned = false;

  static SecureKeyValueStore get _store => storeOverride ?? _platformStore;

  /// True under `flutter test` with no explicit fake keystore.
  ///
  /// The plugin has no method handler in a unit test, and the call does not
  /// fail fast there: it leaves a pending future and, with the timeout below,
  /// a pending timer that outlives the widget tree. Tests that need to exercise
  /// the keystore install [storeOverride]; every other test reads and writes
  /// the same preferences the legacy path uses.
  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  static bool get _bypassPlatformStore =>
      storeOverride == null && _isFlutterTest;

  /// Restores the platform keystore and clears the one-time warning, so each
  /// test starts from the same place.
  @visibleForTesting
  static void resetForTesting() {
    storeOverride = null;
    _warned = false;
  }

  /// A keystore call that does not answer must not hold startup, a settings
  /// page or a background sync open. The platform implementations answer in
  /// milliseconds; this is long enough for a cold keychain and short enough
  /// that a locked or missing one degrades to preferences immediately.
  static const Duration _platformTimeout = Duration(milliseconds: 500);

  /// The stored value for [key], or null.
  ///
  /// A legacy plaintext preference is migrated on the first successful read:
  /// the value is written to the keystore, then removed from preferences.
  static Future<String?> read(String key) async {
    if (_bypassPlatformStore) return _legacyRead(key);

    final String? value;
    try {
      value = await _store.read(key).timeout(_platformTimeout);
    } catch (error) {
      _warn('read', error);
      return _legacyRead(key);
    }

    if (value != null) {
      // A plaintext copy left over from before the migration must not
      // outlive the encrypted one.
      await _removeLegacy(key);
      return value;
    }

    return _migrateLegacy(key);
  }

  /// Stores [value] in the keystore, falling back to [SharedPreferences].
  ///
  /// A successful keystore write removes the plaintext preference, so the
  /// secret does not exist in two places at once.
  static Future<void> write(String key, String value) async {
    if (_bypassPlatformStore) {
      await _legacyWrite(key, value);
      return;
    }

    try {
      await _store.write(key, value).timeout(_platformTimeout);
    } catch (error) {
      _warn('write', error);
      await _legacyWrite(key, value);
      return;
    }
    await _removeLegacy(key);
  }

  /// Removes [key] from the keystore and from [SharedPreferences].
  ///
  /// Both locations are cleared because either may hold the only copy, and a
  /// deleted credential must not come back on the next read.
  static Future<void> delete(String key) async {
    if (_bypassPlatformStore) {
      await _removeLegacy(key);
      return;
    }

    try {
      await _store.delete(key).timeout(_platformTimeout);
    } catch (error) {
      _warn('delete', error);
    }
    await _removeLegacy(key);
  }

  static Future<String?> _legacyRead(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (error) {
      _warn('read fallback', error);
      return null;
    }
  }

  static Future<void> _legacyWrite(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (error) {
      _warn('write fallback', error);
    }
  }

  static Future<String?> _migrateLegacy(String key) async {
    final String? legacy;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      legacy = prefs.getString(key);
    } catch (error) {
      _warn('migrate', error);
      return null;
    }
    if (legacy == null) return null;

    try {
      await _store.write(key, legacy).timeout(_platformTimeout);
    } catch (error) {
      // The keystore refused the value, so the plaintext copy stays the only
      // readable one and is left where it is.
      _warn('migrate', error);
      return legacy;
    }
    await prefs.remove(key);
    return legacy;
  }

  static Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(key)) await prefs.remove(key);
    } catch (error) {
      _warn('remove legacy copy', error);
    }
  }

  /// One warning per process: a keystore that is missing fails on every
  /// credential at startup, and eight identical stack traces help nobody.
  static void _warn(String operation, Object error) {
    if (_warned) return;
    _warned = true;
    debugPrint(
      '[SecureStore] $operation fell back to SharedPreferences: $error',
    );
  }
}

/// A keystore stand-in for tests, so the secure path can be exercised without
/// a plugin.
@visibleForTesting
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
