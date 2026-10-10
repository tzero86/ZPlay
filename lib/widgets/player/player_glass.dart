import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';

/// The player family's colour vocabulary, bridged onto the contract token layer.
///
/// The player was written against a private palette — a violet accent, a
/// near-black panel, 12% and 7% white edges — none of which followed the user's
/// [AppThemePalette], so every preset rendered the same player. Each member now
/// resolves through [AppThemeService.currentTokens], which memoises one
/// [ZplayTokens] per palette value and re-derives it when [AppThemeService]
/// switches palette; a palette change therefore reaches all ~15 player widgets
/// without renaming anything they read.
///
/// The member names stay because those widgets spell them. The player family
/// will take `context.tokens` directly in a later pass; this bridge keeps a
/// single vocabulary until then. Nothing below is `const` any more — a
/// token-backed colour has no compile-time value, so a call site that needs a
/// constant must inline a literal instead.
class PlayerTheme {
  /// Memoised per palette value by [AppThemeService].
  static ZplayTokens get _tokens => AppThemeService.currentTokens;

  // Backgrounds & Surfaces
  /// Page background behind the video.
  static Color get canvas => _tokens.bg;

  /// Glass panel over the video: the palette's overlay surface, kept at the
  /// original 94% alpha so the backdrop blur still shows the picture through.
  static Color get elevated => _tokens.surfaceOverlay.withValues(alpha: 0.94);

  /// The 10% white pill/chip fill — the audit's [ZplayOpacity.borderMedium] step
  /// used as a fill rather than a border.
  static Color get raised =>
      _tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium);

  /// Hover / pressed wash on an interactive surface.
  static Color get surfaceHover =>
      _tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover);

  // Borders
  /// The strong hairline: raised surfaces that must stay separated over video.
  static Color get edge => _tokens.borderStrong;

  /// The default hairline on panels and menus.
  static Color get edgeSoft => _tokens.borderDefault;

  // Accents. Sourced from the palette rather than a literal: these were pinned
  // to a hard-coded violet, which is only one palette's primary, so choosing any
  // other palette left the whole player UI purple regardless.
  static Color get accent => _tokens.accent;
  static Color get accentSoft => _tokens.accent.withValues(alpha: 0.20);
  static Color get accentGlow => _tokens.accent.withValues(alpha: 0.40);
  static Color get danger => _tokens.danger;
  static Color get success => _tokens.success;
  static Color get warning => _tokens.warning;

  // Typography / Text Colors
  static Color get ink => _tokens.textPrimary;
  static Color get inkMuted => _tokens.textEmphasis;
  static Color get inkSubtle => _tokens.textMuted;
  static Color get inkDisabled => _tokens.textDisabled;

  // Shadows. The alphas are the original ones — a shadow over video is a scrim,
  // not a surface — but the hue is the palette background, so a warm palette no
  // longer casts a cold black shadow.
  static List<BoxShadow> get menuShadow => [
    BoxShadow(
      color: _tokens.bg.withValues(alpha: 0.80),
      offset: const Offset(0, 24),
      blurRadius: 60,
      spreadRadius: -18,
    ),
    BoxShadow(
      color: _tokens.bg.withValues(alpha: 0.25),
      offset: const Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -5,
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: _tokens.bg.withValues(alpha: 0.30),
      offset: const Offset(0, 4),
      blurRadius: 16,
    ),
  ];
}

/// Floating Frosted Glass Card for menus, dialogs, and popovers.
class PlayerGlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final List<BoxShadow>? shadows;
  final Color? backgroundColor;

  const PlayerGlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = ZplayRadius.lg,
    this.padding = EdgeInsets.zero,
    this.border,
    this.shadows,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows ?? PlayerTheme.menuShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? PlayerTheme.elevated,
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ?? Border.all(color: PlayerTheme.edge, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Interactive button with smooth hover effects, tooltips, and badges.
class PlayerIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;
  final Color? activeColor;
  final bool showActiveBadge;
  final Color? badgeColor;
  final Color? backgroundColor;
  final double borderRadius;

  /// Optional owner for the focus node, so the player can hand focus to a
  /// specific control when a remote raises the HUD.
  final FocusNode? focusNode;

  const PlayerIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.active = false,
    this.activeColor,
    this.showActiveBadge = false,
    this.badgeColor,
    this.backgroundColor,
    this.borderRadius = ZplayRadius.full,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onPressed,
      focusNode: focusNode,
      enabled: onPressed != null,
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, state) {
        // Focus is given the same treatment as hover. On a TV there is no hover
        // and no pointer, so this highlight is the only thing telling a remote
        // user which control is live.
        final highlighted = state.highlighted;

        return ValueListenableBuilder<bool>(
          valueListenable: GlassSettings.enabled,
          builder: (context, glassEnabled, _) {
            return ValueListenableBuilder<int>(
              valueListenable: GlassSettings.styleRevision,
              builder: (context, _, __) {
                final tokens = context.tokens;
                final hoverScaleVal = glassEnabled ? GlassSettings.hoverScale.value : 1.0;
                final effectiveScale = highlighted ? hoverScaleVal : 1.0;

                // Two washes, both off the text token: the active fill is
                // deliberately stronger than the focus/hover one, because on a TV
                // this highlight is the only signal of which control is live.
                final bg = active
                    ? (activeColor ?? tokens.textPrimary.withValues(alpha: 0.22))
                    : (highlighted
                        ? (backgroundColor ?? tokens.textPrimary.withValues(alpha: 0.12))
                        : (backgroundColor ?? Colors.transparent));

                final iconContent = Stack(
                  alignment: Alignment.center,
                  children: [
                    IconTheme(
                      data: IconThemeData(
                        color: active
                            ? tokens.textPrimary
                            : (highlighted ? tokens.textPrimary : PlayerTheme.inkMuted),
                        size: iconSize,
                      ),
                      child: icon,
                    ),
                    if (showActiveBadge)
                      Positioned(
                        top: size * 0.2,
                        right: size * 0.2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: badgeColor ?? PlayerTheme.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (badgeColor ?? PlayerTheme.accent).withValues(alpha: 0.8),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );

                Widget buttonBody;
                if (glassEnabled) {
                  final buttonStyle = GlassSettings.createButtonGlassStyle(
                    cornerRadius: borderRadius.clamp(0, size / 2),
                    customColor: active
                        ? (activeColor?.withValues(alpha: 0.35) ?? PlayerTheme.accent.withValues(alpha: 0.35))
                        : (highlighted
                            ? tokens.textPrimary.withValues(alpha: 0.22)
                            : tokens.textPrimary.withValues(alpha: 0.094)),
                  );

                  buttonBody = RepaintBoundary(
                    child: LiquidGlassLens(
                      style: buttonStyle,
                      useImpellerBackdrop: true,
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: iconContent,
                      ),
                    ),
                  );
                } else {
                  buttonBody = AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                    child: iconContent,
                  );
                }

                final Widget button = AnimatedScale(
                  scale: effectiveScale,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: buttonBody,
                );

                if (tooltip != null) {
                  return Tooltip(
                    message: tooltip!,
                    waitDuration: const Duration(milliseconds: 400),
                    decoration: BoxDecoration(
                      color: PlayerTheme.elevated,
                      borderRadius: BorderRadius.circular(ZplayRadius.sm),
                      border: Border.all(color: PlayerTheme.edgeSoft),
                    ),
                    textStyle: ZplayType.bodySmall.toStyle(
                      color: tokens.textPrimary,
                    ),
                    child: button,
                  );
                }

                return button;
              },
            );
          },
        );
      },
    );
  }
}

/// Rounded pill toggle chip for filters and options.
class PlayerToggleChip extends StatelessWidget {
  final bool active;
  final String label;
  final String? count;
  final VoidCallback onClick;
  final bool disabled;

  const PlayerToggleChip({
    super.key,
    required this.active,
    required this.label,
    this.count,
    required this.onClick,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onClick,
      enabled: !disabled,
      builder: (context, _) => AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: disabled ? 0.35 : 1.0,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? PlayerTheme.raised : Colors.transparent,
            borderRadius: ZplayRadius.fullAll,
            border: Border.all(
              color: active ? PlayerTheme.edge : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: ZplayType.caption
                    .copyWith(weight: active ? FontWeight.w600 : FontWeight.w500)
                    .toStyle(color: active ? PlayerTheme.ink : PlayerTheme.inkMuted),
              ),
              if (count != null) ...[
                const SizedBox(width: ZplaySpacing.s4),
                Text(
                  count!,
                  style: ZplayType.caption.toStyle(
                    color: PlayerTheme.inkSubtle,
                    tabular: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An [InkWell] a remote can see land on.
///
/// [InkWell] does install its own `Focus` node, so plain-InkWell controls are
/// *traversable* — but a bare one draws nothing on focus, because its only
/// highlight is the hover wash. That is the defect this file's siblings already
/// avoid: every transport button is a [FocusableCard], which raises
/// `onShowFocusHighlight` and paints [CardFocusRing]. The player's lists were
/// converted piecemeal and ~30 rows, season tabs, menu options and the skip
/// button stayed bare, so a D-pad could reach them and nothing changed on
/// screen — read as "navigation is broken" from the couch.
///
/// This wrapper keeps the `InkWell` call sites unchanged in shape — it forwards
/// `borderRadius`, `onTap`, `hoverColor`, `splashColor` and `child` — while
/// adding the focus node, the [ActivateIntent] binding and the ring. A
/// [FocusableCard] cannot be substituted here: its `builder` contract hands a
/// `CardInteraction` to a builder closure, whereas these rows build their own
/// decoration from a `Container` with their own `borderRadius`, so wrapping
/// would mean rewriting every row rather than converting it.
///
/// [enabled] mirrors `InkWell.enabled`; a disabled row stays focusable but inert,
/// matching the player's other rows.
class FocusableInkWell extends StatefulWidget {
  const FocusableInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? splashColor;
  final bool enabled;

  @override
  State<FocusableInkWell> createState() => _FocusableInkWellState();
}

class _FocusableInkWellState extends State<FocusableInkWell> {
  late final FocusNode _node = FocusNode(debugLabel: 'PlayerFocusableInkWell');
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _set(void Function() change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? ZplayRadius.fullAll;
    return FocusableActionDetector(
      focusNode: _node,
      enabled: widget.enabled,
      onShowFocusHighlight: (value) {
        if (_focused != value) _set(() => _focused = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (widget.enabled) widget.onTap?.call();
            return null;
          },
        ),
      },
      child: CardFocusRing(
        focused: _focused && widget.enabled,
        radius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: widget.borderRadius,
            hoverColor: widget.hoverColor,
            splashColor: widget.splashColor,
            canRequestFocus: false,
            onTap: widget.enabled ? widget.onTap : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
