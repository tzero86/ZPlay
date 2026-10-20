import 'package:flutter/material.dart';

import '../storage/json_document_store.dart';

enum ReaderTheme { light, sepia, dark, amoled }

enum ReaderMode { scroll, paginated }

enum MarginPreset { compact, balanced, wide }

class ReaderSettingsData {
  final double fontSize;
  final String fontFamily;
  final double lineSpacing;
  final double letterSpacing;
  final double paragraphSpacing;
  final bool firstLineIndent;
  final MarginPreset marginPreset;
  final ReaderTheme theme;
  final ReaderMode mode;
  final TextAlign textAlign;
  final double brightness; // 0.2 to 1.0 (in-app dimming)
  final bool focusModeActive;
  final ReaderTheme? savedThemeBeforeFocus;

  const ReaderSettingsData({
    this.fontSize = 18.0,
    this.fontFamily = 'Georgia',
    this.lineSpacing = 1.55,
    this.letterSpacing = 0.0,
    this.paragraphSpacing = 16.0,
    this.firstLineIndent = false,
    this.marginPreset = MarginPreset.balanced,
    this.theme = ReaderTheme.dark,
    this.mode = ReaderMode.scroll,
    this.textAlign = TextAlign.left,
    this.brightness = 1.0,
    this.focusModeActive = false,
    this.savedThemeBeforeFocus,
  });

  double get marginHorizontal {
    switch (marginPreset) {
      case MarginPreset.compact:
        return 16.0;
      case MarginPreset.balanced:
        return 32.0;
      case MarginPreset.wide:
        return 48.0;
    }
  }

  ReaderSettingsData copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? paragraphSpacing,
    bool? firstLineIndent,
    MarginPreset? marginPreset,
    ReaderTheme? theme,
    ReaderMode? mode,
    TextAlign? textAlign,
    double? brightness,
    bool? focusModeActive,
    ReaderTheme? savedThemeBeforeFocus,
  }) {
    return ReaderSettingsData(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      marginPreset: marginPreset ?? this.marginPreset,
      theme: theme ?? this.theme,
      mode: mode ?? this.mode,
      textAlign: textAlign ?? this.textAlign,
      brightness: brightness ?? this.brightness,
      focusModeActive: focusModeActive ?? this.focusModeActive,
      savedThemeBeforeFocus:
          savedThemeBeforeFocus ?? this.savedThemeBeforeFocus,
    );
  }

  Color get backgroundColor {
    if (focusModeActive) return const Color(0xFF0D0D11);
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFFAFAFA);
      case ReaderTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReaderTheme.dark:
        return const Color(0xFF141419);
      case ReaderTheme.amoled:
        return Colors.black;
    }
  }

  Color get textColor {
    if (focusModeActive) return const Color(0xFFFFFFFF);
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFF1F2328);
      case ReaderTheme.sepia:
        return const Color(0xFF382717);
      case ReaderTheme.dark:
        return const Color(0xFFE6E8ED);
      case ReaderTheme.amoled:
        return const Color(0xFFE5E5E5);
    }
  }

  Color get secondaryTextColor {
    if (focusModeActive) return const Color(0xFF71717A);
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFF57606A);
      case ReaderTheme.sepia:
        return const Color(0xFF6B5742);
      case ReaderTheme.dark:
        return const Color(0xFF9CA3AF);
      case ReaderTheme.amoled:
        return const Color(0xFF9E9E9E);
    }
  }

  Color get surfaceColor {
    if (focusModeActive) return const Color(0xFF18181F);
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFF0F3F6);
      case ReaderTheme.sepia:
        return const Color(0xFFE6DCBE);
      case ReaderTheme.dark:
        return const Color(0xFF1C1E26);
      case ReaderTheme.amoled:
        return const Color(0xFF121212);
    }
  }

  Color get accentColor {
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFF6366F1);
      case ReaderTheme.sepia:
        return const Color(0xFF8A4810);
      case ReaderTheme.dark:
        return const Color(0xFF8B5CF6);
      case ReaderTheme.amoled:
        return const Color(0xFFA78BFA);
    }
  }

  Color get borderColor {
    if (focusModeActive) return Colors.white12;
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFD0D7DE);
      case ReaderTheme.sepia:
        return const Color(0xFFD4C8B0);
      case ReaderTheme.dark:
        return const Color(0xFF2A2E3D);
      case ReaderTheme.amoled:
        return const Color(0xFF262626);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'lineSpacing': lineSpacing,
      'letterSpacing': letterSpacing,
      'paragraphSpacing': paragraphSpacing,
      'firstLineIndent': firstLineIndent,
      'marginPreset': marginPreset.name,
      'theme': theme.name,
      'mode': mode.name,
      'textAlign': textAlign == TextAlign.justify ? 'justify' : 'left',
      'brightness': brightness,
    };
  }

  factory ReaderSettingsData.fromJson(Map<String, dynamic> json) {
    return ReaderSettingsData(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      fontFamily: (json['fontFamily'] as String?) ?? 'Georgia',
      lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.55,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 16.0,
      firstLineIndent: (json['firstLineIndent'] as bool?) ?? false,
      marginPreset: MarginPreset.values.firstWhere(
        (m) => m.name == json['marginPreset'],
        orElse: () => MarginPreset.balanced,
      ),
      theme: ReaderTheme.values.firstWhere(
        (t) => t.name == json['theme'],
        orElse: () => ReaderTheme.dark,
      ),
      mode: ReaderMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => ReaderMode.scroll,
      ),
      textAlign: json['textAlign'] == 'justify'
          ? TextAlign.justify
          : TextAlign.left,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class ReaderSettings {
  static const String _storageKey = 'zplay_reader_settings_v3';

  static final JsonDocumentStore<ReaderSettingsData> _store =
      JsonDocumentStore<ReaderSettingsData>(
        key: _storageKey,
        version: 1,
        decode: (value) =>
            ReaderSettingsData.fromJson(value as Map<String, dynamic>),
        encode: (settings) => settings.toJson(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  static final ValueNotifier<ReaderSettingsData> settingsNotifier =
      ValueNotifier<ReaderSettingsData>(const ReaderSettingsData());

  static ReaderSettingsData get current => settingsNotifier.value;

  static Future<void> initialize() => init();

  static Future<void> init() async {
    try {
      final stored = await _store.read();
      if (stored != null) {
        settingsNotifier.value = stored;
      }
    } catch (_) {}
  }

  /// Re-reads the stored settings into [settingsNotifier].
  ///
  /// Used after a profile import so the reader picks up the restored values
  /// without the app being restarted.
  static Future<void> reload() => init();

  static Future<void> _save() async {
    try {
      await _store.write(settingsNotifier.value);
    } catch (_) {}
  }

  static void updateFontSize(double size) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      fontSize: size.clamp(12.0, 36.0),
    );
    _save();
  }

  static void updateFontFamily(String family) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      fontFamily: family,
    );
    _save();
  }

  static void updateLineSpacing(double spacing) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      lineSpacing: spacing.clamp(1.2, 2.4),
    );
    _save();
  }

  static void updateLetterSpacing(double spacing) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      letterSpacing: spacing.clamp(-0.5, 1.5),
    );
    _save();
  }

  static void updateParagraphSpacing(double spacing) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      paragraphSpacing: spacing.clamp(8.0, 36.0),
    );
    _save();
  }

  static void updateFirstLineIndent(bool indent) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      firstLineIndent: indent,
    );
    _save();
  }

  static void updateMarginPreset(MarginPreset preset) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      marginPreset: preset,
    );
    _save();
  }

  static void updateTheme(ReaderTheme theme) {
    settingsNotifier.value = settingsNotifier.value.copyWith(theme: theme);
    _save();
  }

  static void updateMode(ReaderMode mode) {
    settingsNotifier.value = settingsNotifier.value.copyWith(mode: mode);
    _save();
  }

  static void updateTextAlign(TextAlign align) {
    settingsNotifier.value = settingsNotifier.value.copyWith(textAlign: align);
    _save();
  }

  static void updateBrightness(double brightness) {
    settingsNotifier.value = settingsNotifier.value.copyWith(
      brightness: brightness.clamp(0.2, 1.0),
    );
    _save();
  }

  static void toggleFocusMode() {
    final active = settingsNotifier.value.focusModeActive;
    if (!active) {
      // Activating Focus Mode: save previous theme and activate
      settingsNotifier.value = settingsNotifier.value.copyWith(
        focusModeActive: true,
        savedThemeBeforeFocus: settingsNotifier.value.theme,
      );
    } else {
      // Deactivating Focus Mode: restore saved theme
      settingsNotifier.value = settingsNotifier.value.copyWith(
        focusModeActive: false,
        theme:
            settingsNotifier.value.savedThemeBeforeFocus ??
            settingsNotifier.value.theme,
      );
    }
  }

  static void exitFocusMode() {
    if (settingsNotifier.value.focusModeActive) {
      settingsNotifier.value = settingsNotifier.value.copyWith(
        focusModeActive: false,
        theme:
            settingsNotifier.value.savedThemeBeforeFocus ??
            settingsNotifier.value.theme,
      );
    }
  }

  static void resetToDefaults() {
    settingsNotifier.value = const ReaderSettingsData();
    _save();
  }
}
