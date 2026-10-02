import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';

/// The one background ramp in the app.
///
/// The picker moves the accent and nothing else, so the surfaces are declared
/// once here rather than per preset: no accent can put the app back on the
/// fork's near-blacks, and the raw [ThemeData] and the derived [ZplayTokens]
/// read the same three values so they cannot disagree. The ramp is Signal
/// Teal's original, not upstream's.
abstract final class ZplaySurfaces {
  /// Page background.
  static const Color bg = Color(0xFF0A0D12);

  /// Cards, tiles, sheets.
  static const Color surface = Color(0xFF111621);

  /// Bars on top of the page (app bar, dock).
  static const Color raised = Color(0xFF161C29);
}

/// A preset is an accent choice, never a colour scheme. The backgrounds
/// deliberately have no constructor parameter — see [ZplaySurfaces] — so a
/// palette cannot carry a background again.
class AppThemePalette {
  final String id;
  final String name;
  final Color primaryColor;
  final Color accentColor;

  /// Palette-independent; see [ZplaySurfaces.bg].
  Color get scaffoldBackgroundColor => ZplaySurfaces.bg;

  /// Palette-independent; see [ZplaySurfaces.surface].
  Color get cardBackgroundColor => ZplaySurfaces.surface;

  /// Palette-independent; see [ZplaySurfaces.raised].
  Color get appBarBackgroundColor => ZplaySurfaces.raised;

  /// Explicit hover/pressed states for [primaryColor]. Left null by every preset
  /// that pre-dates the token layer, in which case `ZplayTokens` derives them by
  /// lightening and darkening the accent. A palette with pinned brand states sets
  /// them instead of accepting the derived approximation.
  final Color? accentHoverColor;
  final Color? accentPressedColor;

  const AppThemePalette({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.accentColor,
    this.accentHoverColor,
    this.accentPressedColor,
  });
}

abstract final class AppThemeService {
  static const _storageKey = 'app_theme_id';

  static const List<AppThemePalette> palettes = [
    // The product's own palette, and therefore first: [currentPalette] seeds
    // from `palettes[0]`, and `initialize()` falls back to it for a stored id it
    // does not recognise. Every entry here is an accent choice only — the
    // backgrounds belong to [ZplaySurfaces] — so this one is the single teal
    // accent, with hover/pressed pinned by brand rather than derived.
    AppThemePalette(
      id: 'zplay',
      name: 'Signal Teal',
      primaryColor: Color(0xFF2FD0C0),
      accentColor: Color(0xFF5ADFD2),
      accentHoverColor: Color(0xFF5ADFD2),
      accentPressedColor: Color(0xFF22B3A5),
    ),
    AppThemePalette(
      id: 'amethyst',
      name: 'Amethyst Violet',
      primaryColor: Color(0xFF7C5CFF),
      accentColor: Color(0xFF00E5FF),
    ),
    AppThemePalette(
      id: 'cyberpunk',
      name: 'Cyberpunk Neon',
      primaryColor: Color(0xFFFF2A85),
      accentColor: Color(0xFF00F0FF),
    ),
    AppThemePalette(
      id: 'emerald',
      name: 'Emerald Aurora',
      primaryColor: Color(0xFF10B981),
      accentColor: Color(0xFF34D399),
    ),
    AppThemePalette(
      id: 'sunset',
      name: 'Sunset Crimson',
      primaryColor: Color(0xFFFF3366),
      accentColor: Color(0xFFFF9900),
    ),
    AppThemePalette(
      id: 'sapphire',
      name: 'Midnight Sapphire',
      primaryColor: Color(0xFF3B82F6),
      accentColor: Color(0xFF60A5FA),
    ),
    AppThemePalette(
      id: 'amber',
      name: 'Golden Amber',
      primaryColor: Color(0xFFF59E0B),
      accentColor: Color(0xFFFCD34D),
    ),
    AppThemePalette(
      id: 'vampire',
      name: 'Vampire Red',
      primaryColor: Color(0xFFE50914),
      accentColor: Color(0xFFFF4D4D),
    ),
    AppThemePalette(
      id: 'barbie',
      name: 'Pink Barbie',
      primaryColor: Color(0xFFFF1493),
      accentColor: Color(0xFFFF80BF),
    ),
    // ── Added for the television pass. Two things the original set could not
    // answer, both grounded in what a dim room and a cheap panel do.
    //
    // Signal Teal is the only existing preset whose `onAccent` holds 7:1 in
    // all three states. The presets that leave hover/pressed null derive a
    // 20% sink that drops the label below 4.5:1, and Vampire Red falls to
    // 4.04:1 — which is visible at ten feet, because that state is drawn
    // under `onAccent` text. So this preset pins its own states, the route
    // [AppThemePalette.accentHoverColor] already describes.
    AppThemePalette(
      id: 'ember',
      name: 'Ember Crimson',
      primaryColor: Color(0xFFF04E3C),
      accentColor: Color(0xFFF4745F),
      accentHoverColor: Color(0xFFF4745F),
      accentPressedColor: Color(0xFFE24334),
    ),
    // Chroma 0.15 against the existing presets' 0.63-1.00, at a luminance
    // none of the reds reach. A saturated accent blooms on a low-bit-depth
    // panel and washes out the artwork beside it; a warm neutral holds its
    // shape as a 2 px focus ring and still separates from the surface at
    // 8.4:1.
    AppThemePalette(
      id: 'bone',
      name: 'Studio Bone',
      primaryColor: Color(0xFFB8B0A0),
      accentColor: Color(0xFFC6C0B3),
    ),
  ];

  static final ValueNotifier<AppThemePalette> currentPalette =
      ValueNotifier<AppThemePalette>(palettes[0]);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_storageKey);
    if (id != null) {
      final found = palettes.firstWhere(
        (p) => p.id == id,
        orElse: () => palettes[0],
      );
      currentPalette.value = found;
    }
  }

  static Future<void> setPalette(AppThemePalette palette) async {
    currentPalette.value = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, palette.id);
  }

  /// The design-token set for [palette] — the semantic colours every screen can
  /// migrate onto. Derives from the five palette colours only, so all presets
  /// (including any added later) are supported without per-preset code.
  static ZplayTokens tokensFor(AppThemePalette palette) => ZplayTokens.derive(
    accent: palette.primaryColor,
    accentHover: palette.accentHoverColor,
    accentPressed: palette.accentPressedColor,
    bg: palette.scaffoldBackgroundColor,
    surface: palette.cardBackgroundColor,
    surfaceRaised: palette.appBarBackgroundColor,
  );

  /// Tokens for the active palette, for code without a `BuildContext`. Memoised
  /// on palette identity — [AppThemePalette] is immutable and every preset is a
  /// const, so the derivation runs once per palette switch instead of once per
  /// call.
  static ZplayTokens get currentTokens {
    final palette = currentPalette.value;
    if (!identical(_tokensFor, palette)) {
      _tokensFor = palette;
      _tokens = tokensFor(palette);
    }
    return _tokens;
  }

  static AppThemePalette? _tokensFor;
  static late ZplayTokens _tokens;

  /// The app's default typeface. Must match the `family: Poppins` block in
  /// `pubspec.yaml`; the bundle ships 400/500/600/700, which is exactly the
  /// set [ZplayTextToken.weight] is restricted to, so no token asks for a
  /// weight the family has to synthesise.
  static const String _fontFamily = 'Poppins';

  /// The Material type scale, mapped from [ZplayType] rather than restated.
  ///
  /// Every slot resolves to a role the token layer already defines, so the
  /// scale has exactly one definition. Colours follow the weighting measured
  /// across `lib/`: primary copy and titles on `textPrimary`, metadata on
  /// `textSecondary`, badges on `textMuted`.
  ///
  /// The family is deliberately absent here — [ThemeData] applies
  /// [ThemeData.fontFamily] to the default theme before this merges over it,
  /// so each token style inherits Poppins from the base instead of restating it.
  static TextTheme _textThemeFor(ZplayTokens tokens) => TextTheme(
    displayLarge: ZplayType.display.toStyle(color: tokens.textPrimary),
    displayMedium: ZplayType.display.toStyle(color: tokens.textPrimary),
    displaySmall: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
    headlineLarge: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
    headlineMedium: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
    headlineSmall: ZplayType.title.toStyle(color: tokens.textPrimary),
    titleLarge: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
    titleMedium: ZplayType.title.toStyle(color: tokens.textPrimary),
    titleSmall: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
    bodyLarge: ZplayType.body.toStyle(color: tokens.textPrimary),
    bodyMedium: ZplayType.body.toStyle(color: tokens.textPrimary),
    bodySmall: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
    labelLarge: ZplayType.label.toStyle(color: tokens.textPrimary),
    labelMedium: ZplayType.caption.toStyle(color: tokens.textSecondary),
    labelSmall: ZplayType.overline.toStyle(color: tokens.textMuted),
  );

  static ThemeData createThemeData(AppThemePalette palette) {
    final tokens = tokensFor(palette);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.scaffoldBackgroundColor,
      useMaterial3: true,
      colorSchemeSeed: palette.primaryColor,
      fontFamily: _fontFamily,
      textTheme: _textThemeFor(tokens),
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.cardBackgroundColor,
      ),
      // From here down, every text style names [fontFamily] explicitly. The
      // component sub-themes install their styles in a [DefaultTextStyle],
      // which replaces the ambient style outright rather than merging with it
      // — so a token style that omitted the family would render these in the
      // platform default instead of Poppins.
      //
      // Dialogs, sheets and menus float above cards, and every screen that
      // already draws one by hand reaches for `surfaceOverlay` + a radius
      // token. Stating it here is what lets those local overrides go away.
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.lgAll),
        titleTextStyle: ZplayType.title.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        contentTextStyle: ZplayType.body.toStyle(
          color: tokens.textSecondary,
          fontFamily: _fontFamily,
        ),
      ),
      // Text styles only. Supplying borders or a fill here would also land on
      // the ~26 borderless search fields that pass only `border:`, since
      // InputDecoration resolves the enabled/focused borders independently of
      // `border` and would paint an outline on top of their `InputBorder.none`.
      inputDecorationTheme: InputDecorationThemeData(
        labelStyle: ZplayType.body.toStyle(
          color: tokens.textEmphasis,
          fontFamily: _fontFamily,
        ),
        floatingLabelStyle: ZplayType.body.toStyle(
          color: tokens.accent,
          fontFamily: _fontFamily,
        ),
        hintStyle: ZplayType.body.toStyle(
          color: tokens.textMuted,
          fontFamily: _fontFamily,
        ),
        errorStyle: ZplayType.bodySmall.toStyle(
          color: tokens.danger,
          fontFamily: _fontFamily,
        ),
        counterStyle: ZplayType.caption.toStyle(
          color: tokens.textMuted,
          fontFamily: _fontFamily,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceOverlay,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
        contentTextStyle: ZplayType.body.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        actionTextColor: tokens.accent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surface,
        selectedColor: tokens.accentSubtle,
        side: tokens.hairline,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.fullAll),
        labelStyle: ZplayType.caption.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        secondaryLabelStyle: ZplayType.caption.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        checkmarkColor: tokens.accent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        titleTextStyle: ZplayType.subtitle.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        subtitleTextStyle: ZplayType.bodySmall.toStyle(
          color: tokens.textSecondary,
          fontFamily: _fontFamily,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.borderDefault,
        thickness: 1.0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surfaceOverlay,
        modalBackgroundColor: tokens.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.sheetTop),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return tokens.borderSubtle;
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.borderStrong;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return tokens.textDisabled;
          return states.contains(WidgetState.selected)
              ? tokens.onAccent
              : tokens.textSecondary;
        }),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.borderStrong,
        thumbColor: tokens.accent,
        overlayColor: tokens.accentSubtle,
      ),

      // A visible focus state for every Material button.
      //
      // `CardFocusRing` covers the app's own cards, and it is the only place
      // that draws a real indicator. Material's buttons fall back to their
      // default `overlayColor`, an 8% tint that is invisible on a dark surface
      // and certainly invisible at ten feet. The P2P advisory's three answers are
      // all Material buttons, so a remote user pressing right saw nothing move
      // and no button respond. Verified on a Chromecast with Google TV: four
      // presses through the dialog and not one visual change.
      //
      // Set at the theme rather than per button so every dialog, sheet and
      // `TextButton` inherits it; the per-site alternative is the same class of
      // miss as the settings rows having been bare `InkWell`s.
      //
      // `WidgetStateBorderSide` for the outline and a full-strength accent
      // overlay, because on an elevated button the overlay is the only thing that
      // changes and an 8% one is not a focus state a person can see.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll(tokens.accent),
          side: WidgetStateBorderSide.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.accent, width: 2);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll(tokens.accent),
          side: WidgetStateBorderSide.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.accent, width: 2);
            }
            return BorderSide(color: tokens.borderDefault);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return tokens.accent;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return tokens.accentSubtle;
            }
            return null;
          }),
        ),
      ),

      // Material's dark tooltip is a white slab with black text, which is the
      // one default that fights the shell outright; it takes the raised
      // surface and the app's de-emphasised copy instead.
      tooltipTheme: TooltipThemeData(
        textStyle: ZplayType.caption.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: ZplayRadius.xsAll,
          border: Border.fromBorderSide(tokens.hairline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: ZplayRadius.mdAll,
          side: tokens.hairline,
        ),
        textStyle: ZplayType.body.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tokens.textPrimary,
        unselectedLabelColor: tokens.textSecondary,
        indicatorColor: tokens.accent,
        dividerColor: Colors.transparent,
        labelStyle: ZplayType.label.toStyle(
          color: tokens.textPrimary,
          fontFamily: _fontFamily,
        ),
        unselectedLabelStyle: ZplayType.label.toStyle(
          color: tokens.textSecondary,
          fontFamily: _fontFamily,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
