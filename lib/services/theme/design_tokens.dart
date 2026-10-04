/// ZPlay design tokens.
///
/// `docs/DESIGN_AUDIT.md` measured 421 distinct hardcoded `0x` colours, 14 corner
/// radii, 18 font sizes in half-pixel steps and 12+ ad-hoc white alphas across
/// `lib/`. This file is the replacement vocabulary: five pure-number scales plus
/// one semantic colour set that is derived per palette, so a screen restyle
/// becomes "swap literals for tokens" instead of "invent a colour".
///
/// Layers:
///
/// 1. [ZplayOpacity] / [ZplaySpacing] / [ZplayRadius] / [ZplayType] / [ZplayMotion]
///    — palette-independent numbers and motion constants.
/// 2. [ZplayTokens] — the semantic colour set for the active palette. Installed as a
///    [ThemeExtension] by `AppThemeService.createThemeData`, read as `context.tokens`.
/// 3. `AppThemeService.tokensFor(palette)` — the derivation from the 5-colour
///    `AppThemePalette` into a full [ZplayTokens], used by widget and non-widget code.
///
/// Nothing here renders on its own; adopting a token in a screen is a separate,
/// behaviour-changing edit. The accent is always a parameter — the tokens never
/// carry a hardcoded brand hue.
library;

import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. OPACITY SCALE
// ══════════════════════════════════════════════════════════════════════════════

/// White-alpha steps, grouped by the role they were being used for.
///
/// The audit found five alphas (0.05/0.06/0.08/0.10/0.12) all meaning "hairline
/// border" and five more (0.35/0.40/0.45/0.50/0.80) all meaning "secondary text".
/// The steps are named rather than collapsed so a migration can keep the current
/// emphasis (0.05 → [borderFaint]) and collapse later if it wants to.
abstract final class ZplayOpacity {
  // ── Borders / dividers ─────────────────────────────────────────────────────
  /// Faintest divider, 62 uses in the audit.
  static const double borderFaint = 0.05;

  /// 102 uses.
  static const double borderSubtle = 0.06;

  /// The default hairline border, 275 uses — by far the most common border.
  static const double borderDefault = 0.08;

  /// 84 uses; for borders that must stay visible over a raised surface.
  static const double borderMedium = 0.10;

  /// Divider between two stacked surfaces, 76 uses.
  static const double borderStrong = 0.12;

  // ── Text ───────────────────────────────────────────────────────────────────
  /// Disabled / non-interactive text.
  static const double textDisabled = 0.30;

  /// De-emphasised text (56 uses at 0.35; the 0.40 and 0.45 steps fold here).
  static const double textMuted = 0.35;

  /// Supporting text next to a primary label, 48 uses at 0.50.
  static const double textSecondary = 0.50;

  /// Body text that should read as primary without shouting, 43 uses at 0.80.
  static const double textEmphasis = 0.80;

  /// Primary text (the 0.90 step; nothing in the app used true white for body copy).
  static const double textPrimary = 0.90;

  // ── Overlays ───────────────────────────────────────────────────────────────
  /// Hover / selected surface wash. This is the audit's unmatched 0.15 step
  /// (57 uses) — it is a fill, not a border, so it gets its own group.
  static const double overlayHover = 0.15;

  /// Fill for a control that floats *over artwork* and must stay readable on
  /// both a bright still and a dark one. [overlayHover] is a wash for a flat
  /// surface: drawn over a photograph it has no edge at all, which is why the
  /// hero's secondary action used to read as a naked text link.
  static const double overlayControl = 0.72;
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. SPACING SCALE
// ══════════════════════════════════════════════════════════════════════════════

/// 4-based spacing scale. Constant names carry the raw pixel value so a computed
/// gap or padding can be audited against the scale at a glance.
///
/// T-shirt equivalents: `s4` xs, `s8` sm, `s12` md, `s16` lg, `s24` xl, `s32` section.
abstract final class ZplaySpacing {
  /// Zero, for symmetry when a gap is conditional.
  static const double s0 = 0.0;

  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
  static const double s48 = 48.0;
  static const double s64 = 64.0;
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. RADIUS SCALE
// ══════════════════════════════════════════════════════════════════════════════

/// The 14 observed radii collapsed to five steps plus a pill.
///
/// Legacy mapping: 2/4/6 → [xs], 8/10/12 → [sm], 14/16/18 → [md], 20/24 → [lg],
/// 28 → [xl], 999 → [full].
abstract final class ZplayRadius {
  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double full = 999.0;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));

  /// Pill / fully round (chips, avatars, progress bars).
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));

  /// Bottom sheets and drawers, which only round their top corners.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 4. TYPE SCALE
// ══════════════════════════════════════════════════════════════════════════════

/// One step of the type scale: metrics only, no colour and no font family.
@immutable
class ZplayTextToken {
  const ZplayTextToken({
    required this.size,
    required this.weight,
    required this.height,
    this.letterSpacing = 0.0,
    this.tabular = false,
  });

  final double size;

  /// Restricted to the four weights the bundle ships (Poppins 400/500/600/700),
  /// so a token renders as designed instead of being synthesised.
  final FontWeight weight;

  /// Line-height multiplier.
  final double height;

  final double letterSpacing;

  /// Locks digits to a fixed advance width — for rows whose numbers must not
  /// jitter as they animate (timers, bitrates, sizes, episode counts).
  final bool tabular;

  ZplayTextToken copyWith({
    double? size,
    FontWeight? weight,
    double? height,
    double? letterSpacing,
    bool? tabular,
  }) => ZplayTextToken(
    size: size ?? this.size,
    weight: weight ?? this.weight,
    height: height ?? this.height,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    tabular: tabular ?? this.tabular,
  );

  /// Builds a [TextStyle] from this step. The family is normally inherited
  /// from the ambient theme; only colour and decoration are layered on here.
  ///
  /// [fontFamily] exists for the component sub-themes, which install their
  /// styles in a [DefaultTextStyle] — that *replaces* the ambient style rather
  /// than merging with it, so a style handed to one loses the theme's family
  /// unless it names it. Leave it null for widget code and the family resolves
  /// from the theme as usual.
  TextStyle toStyle({
    Color? color,
    double? opacity,
    TextDecoration? decoration,
    TextDecorationStyle? decorationStyle,
    Color? decorationColor,
    bool? tabular,
    String? fontFamily,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: opacity == null ? color : color?.withValues(alpha: opacity),
    decoration: decoration,
    decorationStyle: decorationStyle,
    decorationColor: decorationColor,
    fontFeatures: (tabular ?? this.tabular)
        ? const [FontFeature.tabularFigures()]
        : null,
  );
}

/// Nine display/body roles replacing the 18 ad-hoc sizes (9 … 22 in half-pixel
/// steps), plus tabular variants for data-heavy rows.
abstract final class ZplayType {
  /// Splash and detail-page headlines (was 22–28).
  static const ZplayTextToken display = ZplayTextToken(
    size: 28.0,
    weight: FontWeight.w700,
    height: 1.12,
    letterSpacing: -0.5,
  );

  /// Screen titles (was 18–20).
  static const ZplayTextToken titleLarge = ZplayTextToken(
    size: 22.0,
    weight: FontWeight.w700,
    height: 1.18,
    letterSpacing: -0.4,
  );

  /// Section headers and dialog titles (was 16–18).
  static const ZplayTextToken title = ZplayTextToken(
    size: 18.0,
    weight: FontWeight.w600,
    height: 1.24,
    letterSpacing: -0.2,
  );

  /// Card titles and dense list primaries (was 15–16).
  static const ZplayTextToken subtitle = ZplayTextToken(
    size: 15.0,
    weight: FontWeight.w600,
    height: 1.30,
  );

  /// Long-form copy (was 13–14).
  static const ZplayTextToken body = ZplayTextToken(
    size: 14.0,
    weight: FontWeight.w400,
    height: 1.40,
  );

  /// Secondary copy, metadata paragraphs (was 11.5–12.5).
  static const ZplayTextToken bodySmall = ZplayTextToken(
    size: 12.0,
    weight: FontWeight.w400,
    height: 1.40,
    letterSpacing: 0.1,
  );

  /// Buttons, tabs and pills (was 12.5–13.5).
  static const ZplayTextToken label = ZplayTextToken(
    size: 13.0,
    weight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0.2,
  );

  /// Card metadata, badges (was 10.5–11.5).
  static const ZplayTextToken caption = ZplayTextToken(
    size: 11.0,
    weight: FontWeight.w500,
    height: 1.30,
    letterSpacing: 0.2,
  );

  /// All-caps group labels (was 9–10).
  static const ZplayTextToken overline = ZplayTextToken(
    size: 10.0,
    weight: FontWeight.w600,
    height: 1.20,
    letterSpacing: 1.2,
  );

  /// [body] with tabular figures — two-line data rows.
  static const ZplayTextToken bodyNumeric = ZplayTextToken(
    size: 14.0,
    weight: FontWeight.w500,
    height: 1.30,
    tabular: true,
  );

  /// [label] with tabular figures — timers, bitrates, counters.
  static const ZplayTextToken labelNumeric = ZplayTextToken(
    size: 13.0,
    weight: FontWeight.w600,
    height: 1.20,
    letterSpacing: 0.1,
    tabular: true,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 5. MOTION
// ══════════════════════════════════════════════════════════════════════════════

/// Durations and curves for interactive feedback. The app has no reduced-motion
/// branch yet; a caller that has one should collapse every duration to
/// [Duration.zero] and keep the curve.
abstract final class ZplayMotion {
  /// Tap feedback: ripple, chip select, icon toggle.
  static const Duration fast = Duration(milliseconds: 120);

  /// Default: fades, hovers, expand/collapse, theme crossfade.
  static const Duration base = Duration(milliseconds: 200);

  /// Deliberate motion: sheet and route transitions, layout reflow.
  static const Duration slow = Duration(milliseconds: 320);

  /// Entering and settling; the default for almost everything.
  static const Curve standard = Curves.easeOutCubic;

  /// Symmetric in/out movement.
  static const Curve emphasized = Curves.easeInOutCubic;

  /// Material 3 emphasised deceleration, for large surface transitions.
  static const Curve emphasizedDecelerate = Curves.easeInOutCubicEmphasized;

  /// Entering the viewport.
  static const Curve decelerate = Curves.decelerate;

  /// Leaving the viewport.
  static const Curve accelerate = Curves.easeInCubic;

  /// Progress and indeterminate indicators.
  static const Curve linear = Curves.linear;

  /// Slight overshoot, for elements that pop into place under the pointer —
  /// dock items swelling, the active pill expanding.
  static const Curve spring = Curves.easeOutBack;
}

// ══════════════════════════════════════════════════════════════════════════════
// 6. SEMANTIC COLOURS
// ══════════════════════════════════════════════════════════════════════════════

/// The semantic colour set for the active palette, carried as a [ThemeExtension].
///
/// Derivation (see [ZplayTokens.derive] and `AppThemeService.tokensFor`):
///
/// - surfaces come from the palette's `scaffoldBackgroundColor` (bg),
///   `cardBackgroundColor` (surface) and `appBarBackgroundColor` (surfaceRaised);
///   [surfaceOverlay] is the lighter of the two raised surfaces, lifted 8% toward
///   white — menus and dialogs sit above cards.
/// - the accent family comes from `primaryColor`; [accentHover] and [accentPressed]
///   are a lighten/darken of it, [accentSubtle] is the surface blended 16% toward
///   it (opaque, so it composites once instead of every frame).
/// - text and border colours are white at the [ZplayOpacity] scale — no new greys.
/// - pure black is never emitted: a pure-black input is remapped to a near-black
///   floor tinted toward the accent (halation on OLED; the audit flags the 20
///   literal `#000000`s in `lib/`).
///
/// `AppThemePalette.accentColor` is deliberately **not** surfaced here: the audit
/// found three competing accents, and a token layer that ships two would keep the
/// problem. Screens migrating off the hardcoded green/cyan should pick a status
/// colour or the single accent.
@immutable
class ZplayTokens extends ThemeExtension<ZplayTokens> {
  const ZplayTokens({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.textEmphasis,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSubtle,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  /// Page background.
  final Color bg;

  /// Cards, tiles, sheets.
  final Color surface;

  /// Bars sitting on top of the page (app bar, dock).
  final Color surfaceRaised;

  /// Menus, dialogs and popovers above [surface]/[surfaceRaised].
  final Color surfaceOverlay;

  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  /// Body text that reads as primary without shouting ([ZplayOpacity.textEmphasis]).
  final Color textEmphasis;

  /// The single brand accent — always sourced from `AppThemePalette.primaryColor`.
  final Color accent;
  final Color accentHover;
  final Color accentPressed;

  /// Accent-tinted container fill (selected chip, active row, badge background).
  final Color accentSubtle;

  /// Foreground for content drawn on top of [accent].
  final Color onAccent;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Status colours are palette-independent semantics; these are the hues
  /// `lib/` already uses for them (audit findings 2).
  static const Color _successHue = Color(0xFF10B981);
  static const Color _warningHue = Color(0xFFF59E0B);
  static const Color _dangerHue = Color(0xFFEF4444);
  static const Color _infoHue = Color(0xFF00D2EF);

  /// Near-black floor for pressed states and remapped pure black. Cool, slightly
  /// above true black so it survives OLED smearing.
  static const Color _shadowFloor = Color(0xFF05070A);

  /// How far [accentHover] lifts off the accent and [accentPressed] sinks into it.
  static const double _accentLift = 0.20;
  static const double _accentSink = 0.20;

  /// Surface blend used for [accentSubtle].
  static const double _accentSubtleMix = 0.16;

  /// Builds the semantic set from four raw colours. [accentHover] and
  /// [accentPressed] may be supplied by a palette that specifies its own state
  /// colours; otherwise they are derived from [accent].
  factory ZplayTokens.derive({
    required Color accent,
    required Color bg,
    required Color surface,
    required Color surfaceRaised,
    Color? accentHover,
    Color? accentPressed,
  }) {
    final cleanBg = _neutral(bg, accent);
    final cleanSurface = _neutral(surface, accent);
    final cleanRaised = _neutral(surfaceRaised, accent);
    final overlay = Color.lerp(
      _lighterOf(cleanSurface, cleanRaised),
      Colors.white,
      0.08,
    )!;

    return ZplayTokens(
      bg: cleanBg,
      surface: cleanSurface,
      surfaceRaised: cleanRaised,
      surfaceOverlay: _neutral(overlay, accent),
      borderSubtle: Colors.white.withValues(alpha: ZplayOpacity.borderSubtle),
      borderDefault: Colors.white.withValues(alpha: ZplayOpacity.borderDefault),
      borderStrong: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
      textPrimary: Colors.white.withValues(alpha: ZplayOpacity.textPrimary),
      textEmphasis: Colors.white.withValues(alpha: ZplayOpacity.textEmphasis),
      textSecondary: Colors.white.withValues(alpha: ZplayOpacity.textSecondary),
      textMuted: Colors.white.withValues(alpha: ZplayOpacity.textMuted),
      textDisabled: Colors.white.withValues(alpha: ZplayOpacity.textDisabled),
      accent: accent,
      accentHover:
          accentHover ?? _shadeAccent(accent, Colors.white, _accentLift),
      accentPressed:
          accentPressed ?? _shadeAccent(accent, _shadowFloor, _accentSink),
      accentSubtle: Color.lerp(cleanSurface, accent, _accentSubtleMix)!,
      onAccent: _onAccentFor(accent),
      success: _successHue,
      warning: _warningHue,
      danger: _dangerHue,
      info: _infoHue,
    );
  }

  /// A 1px border in the default hairline role (the audit's 275-use 0.08 step).
  BorderSide get hairline => BorderSide(color: borderDefault, width: 1.0);

  /// A 1px border in the strong divider role.
  BorderSide get hairlineStrong => BorderSide(color: borderStrong, width: 1.0);

  /// Reads the tokens installed by `AppThemeService.createThemeData`. Outside a
  /// themed [MaterialApp] (plain widget tests, an out-of-tree `MaterialApp`) the
  /// set is derived from the ambient [ThemeData] instead of throwing.
  static ZplayTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ZplayTokens>() ?? fromThemeData(theme);
  }

  /// Derives tokens from a bare [ThemeData] — the fallback used by [of] and by
  /// tests that build a [ThemeData] directly.
  static ZplayTokens fromThemeData(ThemeData theme) {
    final bg = theme.scaffoldBackgroundColor;
    return ZplayTokens.derive(
      accent: theme.colorScheme.primary,
      bg: bg,
      surface: theme.cardTheme.color ?? bg,
      surfaceRaised: theme.appBarTheme.backgroundColor ?? bg,
    );
  }

  /// Foreground for content drawn on top of [accent], e.g. a filled button label.
  ///
  /// Chosen by comparing contrast, not by a luminance threshold. A threshold
  /// gets bright-but-mid accents wrong: Signal Teal `#2FD0C0` has a relative
  /// luminance of ~0.50, so a `> 0.55` rule hands it white at **1.93:1** —
  /// effectively unreadable on buttons and chips — where dark text scores
  /// ~10.9:1. Comparing both candidates is correct for every accent hue.
  static Color _onAccentFor(Color accent) {
    final dark = _neutral(_shadowFloor, accent);
    return _contrastRatio(accent, dark) > _contrastRatio(accent, Colors.white)
        ? dark
        : Colors.white;
  }

  /// WCAG relative-contrast ratio between two opaque colours.
  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Shades [accent] toward [target], keeping the accent's own alpha so a
  /// translucent accent stays translucent in its hover/pressed states.
  static Color _shadeAccent(Color accent, Color target, double amount) =>
      Color.lerp(accent, target, amount)!.withValues(alpha: accent.a);

  /// Pure black halates and smears on OLED, so any pure-black input is remapped
  /// onto [_shadowFloor] tinted toward the accent. Every other colour passes
  /// through untouched, which is what keeps the shipped presets pixel-identical.
  static Color _neutral(Color base, Color accent) =>
      base == Colors.black ? Color.lerp(_shadowFloor, accent, 0.06)! : base;

  static Color _lighterOf(Color a, Color b) =>
      a.computeLuminance() >= b.computeLuminance() ? a : b;

  @override
  ZplayTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? textEmphasis,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentSubtle,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) => ZplayTokens(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderDefault: borderDefault ?? this.borderDefault,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textDisabled: textDisabled ?? this.textDisabled,
    textEmphasis: textEmphasis ?? this.textEmphasis,
    accent: accent ?? this.accent,
    accentHover: accentHover ?? this.accentHover,
    accentPressed: accentPressed ?? this.accentPressed,
    accentSubtle: accentSubtle ?? this.accentSubtle,
    onAccent: onAccent ?? this.onAccent,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
  );

  /// Interpolates all 21 colour fields, so a palette switch animates instead of
  /// snapping. A no-op lerp here would freeze `ThemeData.lerp` mid-transition.
  @override
  ZplayTokens lerp(covariant ZplayTokens? other, double t) {
    if (other == null) return this;
    return ZplayTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textEmphasis: Color.lerp(textEmphasis, other.textEmphasis, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

/// `context.tokens.bg` — the ergonomic read for widget code.
extension ZplayTokensBuildContext on BuildContext {
  ZplayTokens get tokens => ZplayTokens.of(this);
}
