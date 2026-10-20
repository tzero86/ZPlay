import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app language choice. `null` follows the system.
abstract final class LocaleSettings {
  static const String _storageKey = 'zplay_locale';
  static const String systemCode = 'system';

  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// The stored choice, or [systemCode].
  static String get code =>
      locale.value == null ? systemCode : locale.value!.languageCode;

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      switch (stored) {
        case 'en':
          locale.value = const Locale('en');
        case 'ar':
          locale.value = const Locale('ar');
        default:
          locale.value = null;
      }
    } catch (_) {
      locale.value = null;
    }
  }

  /// Applies and persists a language. [systemCode] means follow the device.
  static Future<void> setLocale(String code) async {
    final next = switch (code) {
      'en' => const Locale('en'),
      'ar' => const Locale('ar'),
      _ => null,
    };
    locale.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove(_storageKey);
      } else {
        await prefs.setString(_storageKey, next.languageCode);
      }
    } catch (_) {}
  }
}
