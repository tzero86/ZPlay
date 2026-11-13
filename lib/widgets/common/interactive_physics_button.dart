import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/audiobook/audiobook_settings.dart';
import '../../services/music/music_settings.dart';
import '../../services/theme/app_theme_service.dart';
import 'focusable_card.dart';

/// The one implementation of the player's pointer "physics" button.
///
/// Both players had this widget already: the same tilt maths, the same ripple
/// controller, the same four effects behind four names, and the same press and
/// hover plumbing. They differed in two things only — how a missing `onTap`
/// disables the button, and whether the button draws the app's focus ring — so
/// both live in a [_PhysicsLook] and everything else is shared.
///
/// It is built on [FocusableCard], because a `MouseRegion` around a
/// `GestureDetector` is pointer-only: no key, remote or D-pad event can reach
/// it. [FocusableCard] supplies hover, press, activation, cursor and focus,
/// which `WidgetsApp`'s default shortcuts bind to the remote's centre button.
/// The `MouseRegion` stays for `tilt3D`, which needs the raw hover position,
/// and it is also where the ripple beat starts on enter.
class InteractivePhysicsButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? glowColor;
  final bool enabled;
  final BorderRadius? borderRadius;

  final _PhysicsLook _look;

  /// Whichever player's settings enum this instance was built with; the
  /// constructor guarantees it matches [_look] and that the other is null.
  final MusicHoverEffect? _musicEffect;
  final AudiobookHoverEffect? _bookEffect;

  const InteractivePhysicsButton.music({
    super.key,
    required this.child,
    this.onTap,
    MusicHoverEffect? effect,
    this.glowColor,
    this.enabled = true,
    this.borderRadius,
  }) : _look = _PhysicsLook.music,
       _musicEffect = effect,
       _bookEffect = null;

  const InteractivePhysicsButton.audiobook({
    super.key,
    required this.child,
    this.onTap,
    AudiobookHoverEffect? effect,
    this.glowColor,
    this.enabled = true,
    this.borderRadius,
  }) : _look = _PhysicsLook.audiobook,
       _musicEffect = null,
       _bookEffect = effect;

  _PhysicsEffect get _effect {
    if (_look.kind == _LookKind.music) {
      return switch (_musicEffect ?? MusicSettings.customHoverEffect.value) {
        MusicHoverEffect.scaleBounce => _PhysicsEffect.scaleBounce,
        MusicHoverEffect.glowAura => _PhysicsEffect.glowAura,
        MusicHoverEffect.glassRipple => _PhysicsEffect.glassRipple,
        MusicHoverEffect.tilt3D => _PhysicsEffect.tilt3D,
      };
    }
    return switch (_bookEffect ?? AudiobookSettings.customHoverEffect.value) {
      AudiobookHoverEffect.scaleBounce => _PhysicsEffect.scaleBounce,
      AudiobookHoverEffect.glowAura => _PhysicsEffect.glowAura,
      AudiobookHoverEffect.glassRipple => _PhysicsEffect.glassRipple,
      AudiobookHoverEffect.tilt3D => _PhysicsEffect.tilt3D,
    };
  }

  @override
  State<InteractivePhysicsButton> createState() =>
      _InteractivePhysicsButtonState();
}

enum _LookKind { music, audiobook }

/// The four effects, under one name. The two settings enums stay separate
/// because each player's settings page lists its own vocabulary.
enum _PhysicsEffect { scaleBounce, glowAura, glassRipple, tilt3D }

class _PhysicsLook {
  const _PhysicsLook({
    required this.kind,
    required this.nullTapDisables,
    required this.focusRing,
  });

  final _LookKind kind;

  /// Whether a button with no `onTap` is *not* a focus stop.
  ///
  /// In the music player a null `onTap` is how callers disable a step button,
  /// so it must not become a focus stop that does nothing when activated. The
  /// audiobook player keeps it focusable and simply has no action to run.
  final bool nullTapDisables;

  /// Whether the button draws `CardFocusRing` for focus.
  final bool focusRing;

  static const _PhysicsLook music = _PhysicsLook(
    kind: _LookKind.music,
    nullTapDisables: true,
    focusRing: false,
  );

  static const _PhysicsLook audiobook = _PhysicsLook(
    kind: _LookKind.audiobook,
    nullTapDisables: false,
    focusRing: true,
  );
}

class _InteractivePhysicsButtonState extends State<InteractivePhysicsButton>
    with SingleTickerProviderStateMixin {
  double _tiltX = 0.0;
  double _tiltY = 0.0;

  late final AnimationController _rippleAnimController;
  late final Animation<double> _rippleCurve;

  @override
  void initState() {
    super.initState();
    _rippleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _rippleCurve = CurvedAnimation(
      parent: _rippleAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _rippleAnimController.dispose();
    super.dispose();
  }

  void _onPointerHover(PointerHoverEvent event, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final offset = event.localPosition - center;
    final targetX = (offset.dx / (size.width / 2)).clamp(-1.0, 1.0);
    final targetY = (offset.dy / (size.height / 2)).clamp(-1.0, 1.0);

    // Only update if difference is noticeable to avoid rebuild spam
    if ((targetX - _tiltX).abs() > 0.05 || (targetY - _tiltY).abs() > 0.05) {
      setState(() {
        _tiltX = targetX;
        _tiltY = targetY;
      });
    }
  }

  void _onPointerExit() {
    setState(() {
      _tiltX = 0.0;
      _tiltY = 0.0;
    });
    _rippleAnimController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget._effect;
    final palette = AppThemeService.currentPalette.value;
    final glow = widget.glowColor ?? palette.primaryColor;
    final hasAction = widget.onTap != null;
    final interactive =
        widget.enabled && (hasAction || !widget._look.nullTapDisables);

    return FocusableCard(
      onTap: widget.enabled ? widget.onTap : null,
      enabled: interactive,
      cursor: widget.enabled && hasAction
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      builder: (context, state) => MouseRegion(
        // Pointer-only: [FocusableCard] owns tap, activation and the cursor, but
        // `tilt3D` needs the raw hover position and the tilt has to reset when
        // the pointer leaves.
        onEnter: (_) {
          if (!widget.enabled) return;
          if (effect == _PhysicsEffect.glassRipple) {
            _rippleAnimController.forward(from: 0.0);
          }
        },
        onHover: (event) {
          if (!widget.enabled || effect != _PhysicsEffect.tilt3D) return;
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            _onPointerHover(event, renderBox.size);
          }
        },
        onExit: (_) => _onPointerExit(),
        child: Listener(
          // Pointer-only: the ripple beat that starts on the way down has no
          // keyboard equivalent, so it keeps its own raw pointer hook.
          onPointerDown: (_) {
            if (!widget.enabled) return;
            if (effect == _PhysicsEffect.glassRipple) {
              _rippleAnimController.forward(from: 0.0);
            }
          },
          child: _buildPhysicsTransform(effect, glow, state),
        ),
      ),
    );
  }

  /// The one focus marker: a crisp 3 dp accent [CardFocusRing], drawn *inside*
  /// the physics transform so it follows the button's own hover/focus scale
  /// instead of sitting at the layout box while the glyph swells past it.
  ///
  /// The hover effects are a pointer affordance that focus reuses, so a D-pad
  /// user sees the same highlight a mouse would - but that highlight is a fill,
  /// a scale or a glow, and none of those says "this is what the remote is on"
  /// the way the app's single ring does.
  Widget _ringed(Widget child, bool focused) => CardFocusRing(
    focused: focused,
    radius: widget.borderRadius ?? BorderRadius.circular(30),
    child: child,
  );

  /// The card body, ringed where this player wants the ring.
  Widget _body(CardInteraction state) => widget._look.focusRing
      ? _ringed(widget.child, state.focused)
      : widget.child;

  Widget _buildPhysicsTransform(
    _PhysicsEffect effect,
    Color glow,
    CardInteraction state,
  ) {
    switch (effect) {
      case _PhysicsEffect.scaleBounce:
        final scale = state.pressed ? 0.88 : (state.highlighted ? 1.15 : 1.0);
        return AnimatedScale(
          scale: scale,
          duration: Duration(milliseconds: state.pressed ? 80 : 220),
          curve: state.pressed ? Curves.easeIn : Curves.elasticOut,
          child: _body(state),
        );

      case _PhysicsEffect.glowAura:
        final scale = state.pressed ? 0.92 : (state.highlighted ? 1.08 : 1.0);
        return AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(30),
              boxShadow: state.highlighted
                  ? [
                      BoxShadow(
                        color: glow.withValues(
                          alpha: state.pressed ? 0.85 : 0.6,
                        ),
                        blurRadius: state.pressed ? 30 : 22,
                        spreadRadius: state.pressed ? 3 : 1,
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(
                          alpha: state.pressed ? 0.35 : 0.18,
                        ),
                        blurRadius: 8,
                      ),
                    ]
                  : const [],
            ),
            child: _body(state),
          ),
        );

      case _PhysicsEffect.glassRipple:
        final scale = state.pressed ? 0.93 : (state.highlighted ? 1.07 : 1.0);
        final radius = widget.borderRadius ?? BorderRadius.circular(24);

        return AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedBuilder(
            animation: _rippleCurve,
            builder: (context, child) {
              final rippleVal = _rippleCurve.value;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: state.highlighted
                      ? [
                          BoxShadow(
                            color: glow.withValues(
                              alpha: 0.35 * (1.0 - rippleVal * 0.3),
                            ),
                            blurRadius: 16 + (rippleVal * 12),
                            spreadRadius: rippleVal * 2,
                          ),
                        ]
                      : const [],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Stable Refraction Highlight Border (no recursive backdrop shader invalidation)
                    if (state.highlighted || _rippleAnimController.isAnimating)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: state.highlighted ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: radius,
                                border: Border.all(
                                  color: Color.lerp(
                                    glow.withValues(alpha: 0.8),
                                    Colors.white.withValues(alpha: 0.9),
                                    rippleVal * 0.6,
                                  )!,
                                  width: 1.5 + (rippleVal * 0.8),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: 0.35 * (1.0 - rippleVal * 0.4),
                                    ),
                                    glow.withValues(alpha: 0.15),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    child!,
                  ],
                ),
              );
            },
            child: _body(state),
          ),
        );

      case _PhysicsEffect.tilt3D:
        final scale = state.pressed ? 0.90 : (state.highlighted ? 1.10 : 1.0);
        final rotateX = -_tiltY * (math.pi / 10);
        final rotateY = _tiltX * (math.pi / 10);

        return AnimatedContainer(
          duration: Duration(milliseconds: state.highlighted ? 60 : 250),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0025)
            ..rotateX(rotateX)
            ..rotateY(rotateY)
            ..scale(scale),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(30),
            boxShadow: state.highlighted
                ? [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: Offset(_tiltX * 8, _tiltY * 8),
                    ),
                  ]
                : const [],
          ),
          child: _body(state),
        );
    }
  }
}
