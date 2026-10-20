import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_keys.dart';
import 'secure_store.dart';

class StorageService {
  static const _kTraktTokenExpiry = 'trakt_token_expiry_ms';
  static const _kTraktUsername = 'trakt_username';
  static const _kSimklUsername = 'simkl_username';

  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier<int>(0);

  // ── Trakt ─────────────────────────────────────────────────────────────────
  static Future<String?> getTraktAccessToken() =>
      SecureStore.read(SecretKeys.traktAccessToken);

  static Future<void> setTraktAccessToken(String token) =>
      SecureStore.write(SecretKeys.traktAccessToken, token);

  static Future<String?> getTraktRefreshToken() =>
      SecureStore.read(SecretKeys.traktRefreshToken);

  static Future<void> setTraktRefreshToken(String token) =>
      SecureStore.write(SecretKeys.traktRefreshToken, token);

  static Future<int?> getTraktTokenExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kTraktTokenExpiry);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTraktTokenExpiry, expiryMs);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTraktUsername);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTraktUsername, username);
  }

  static Future<bool> clearTraktAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStore.delete(SecretKeys.traktAccessToken);
    await SecureStore.delete(SecretKeys.traktRefreshToken);
    await prefs.remove(_kTraktTokenExpiry);
    await prefs.remove(_kTraktUsername);
    return true;
  }

  // ── Simkl ─────────────────────────────────────────────────────────────────
  static Future<String?> getSimklAccessToken() =>
      SecureStore.read(SecretKeys.simklAccessToken);

  static Future<void> setSimklAccessToken(String token) =>
      SecureStore.write(SecretKeys.simklAccessToken, token);

  static Future<String?> getSimklUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSimklUsername);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSimklUsername, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStore.delete(SecretKeys.simklAccessToken);
    await prefs.remove(_kSimklUsername);
  }
}
