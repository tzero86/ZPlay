import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/theme/app_theme_service.dart';
import '../common/focusable_card.dart';
import '../../services/audiobook/audiobook_settings.dart';

class AudiobookInteractivePhysicsButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final AudiobookHoverEffect? effect;
  final Color? glowColor;
  final bool enabled;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const AudiobookInteractivePhysicsButton({
    super.key,
    required this.child,
    this.onTap,
    this.effect,
    this.glowColor,
    this.enabled = true,
    this.borderRadius,
    this.padding,
  });

  @override
  State<AudiobookInteractivePhysicsButton> createState() =>
      _AudiobookInteractivePhysicsButtonState();
}

class _AudiobookInteractivePhysicsButtonState
    extends State<AudiobookInteractivePhysicsButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  /// Whether the current highlight came from the remote rather than a pointer.
  ///
  /// Needed because a `MouseRegion` only reports a real pointer. Without this
  /// the button would light up for a mouse and stay flat for a D-pad, which is
  /// the exact case where the user has no other way to tell what is selected.
  bool _isFocusedFromKey = false;
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
      _isHovered = false;
      _tiltX = 0.0;
      _tiltY = 0.0;
    });
    _rippleAnimController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final activeEffect =
        widget.effect ?? AudiobookSettings.customHoverEffect.value;
    final palette = AppThemeService.currentPalette.value;
    final glow = widget.glowColor ?? palette.primaryColor;

    return FocusableCard(
      // Pointer-only before this: a `MouseRegion` wrapping a `GestureDetector`,
      // with no `Focus` node anywhere in the subtree. Arrow keys could not land
      // on it and the centre button dispatched `ActivateIntent` to whatever held
      // focus, so every `_PlayerIconButton` in the audiobook player - close,
      // chapters, previous, rewind, next, forward, volume, customise - was
      // unreachable from a remote. The music player has the same widget and
      // already does this; this one was the outlier.
      //
      // The `MouseRegion` stays for the tilt effect, which needs the raw hover
      // position, and `_isHovered` keeps driving it so the pointer look is
      // unchanged. Focus feeds the same highlight, because a remote has no
      // pointer to set that flag and the button would otherwise give no sign
      // of being selected.
      enabled: widget.enabled,
      onTap: widget.enabled ? widget.onTap : null,
      builder: (context, state) {
        if (state.focused && !_isFocusedFromKey) {
          _isFocusedFromKey = true;
          setState(() => _isHovered = true);
        } else if (!state.focused && _isFocusedFromKey) {
          _isFocusedFromKey = false;
          setState(() => _isHovered = false);
        }
        return MouseRegion(
          cursor: widget.enabled && widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) {
            if (!widget.enabled) return;
            setState(() => _isHovered = true);
            if (activeEffect == AudiobookHoverEffect.glassRipple) {
              _rippleAnimController.forward(from: 0.0);
            }
          },
          onHover: (event) {
            if (!widget.enabled ||
                activeEffect != AudiobookHoverEffect.tilt3D) {
              return;
            }
            final renderBox = context.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              _onPointerHover(event, renderBox.size);
            }
          },
          onExit: (_) => _onPointerExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              if (!widget.enabled) return;
              setState(() => _isPressed = true);
              if (activeEffect == AudiobookHoverEffect.glassRipple) {
                _rippleAnimController.forward(from: 0.0);
              }
            },
            onTapUp: (_) {
              if (!widget.enabled) return;
              setState(() => _isPressed = false);
            },
            onTapCancel: () {
              if (!widget.enabled) return;
              setState(() => _isPressed = false);
            },
            // Activation itself belongs to FocusableCard. The detector is left
            // for the press states only, so a tap still ripples and a centre
            // key still activates without doing the work twice.
            onTap: null,
            child: _buildPhysicsTransform(activeEffect, glow, state.focused),
          ),
        );
      },
    );
  }

  /// The one focus marker: a crisp 3 dp accent [CardFocusRing], drawn *inside*
  /// the physics transform so it follows the button's own hover/focus scale
  /// instead of sitting at the layout box while the glyph swells past it.
  ///
  /// The hover effects are a pointer affordance that focus reuses, so a D-pad
  /// user sees the same highlight a mouse would - but that highlight is a fill,
  /// a scale or a glow, and none of those says "this is what the remote is on"
  /// the way the app's single ring does. Every other control an audiobook page
  /// offers (the seekbar, the chapter rows, the shelf cards) already carries
  /// [CardFocusRing]; this button was the one that did not.
  Widget _ringed(Widget child, bool focused) => CardFocusRing(
        focused: focused,
        radius: widget.borderRadius ?? BorderRadius.circular(30),
        child: child,
      );

  Widget _buildPhysicsTransform(
    AudiobookHoverEffect effect,
    Color glow,
    bool focused,
  ) {
    switch (effect) {
      case AudiobookHoverEffect.scaleBounce:
        final scale = _isPressed ? 0.88 : (_isHovered ? 1.15 : 1.0);
        return AnimatedScale(
          scale: scale,
          duration: Duration(milliseconds: _isPressed ? 80 : 220),
          curve: _isPressed ? Curves.easeIn : Curves.elasticOut,
          child: _ringed(widget.child, focused),
        );

      case AudiobookHoverEffect.glowAura:
        final scale = _isPressed ? 0.92 : (_isHovered ? 1.08 : 1.0);
        return AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(30),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: glow.withValues(alpha: _isPressed ? 0.85 : 0.6),
                        blurRadius: _isPressed ? 30 : 22,
                        spreadRadius: _isPressed ? 3 : 1,
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(
                          alpha: _isPressed ? 0.35 : 0.18,
                        ),
                        blurRadius: 8,
                      ),
                    ]
                  : const [],
            ),
            child: _ringed(widget.child, focused),
          ),
        );

      case AudiobookHoverEffect.glassRipple:
        final scale = _isPressed ? 0.93 : (_isHovered ? 1.07 : 1.0);
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
                  boxShadow: _isHovered
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
                    if (_isHovered || _rippleAnimController.isAnimating)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _isHovered ? 1.0 : 0.0,
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
            child: _ringed(widget.child, focused),
          ),
        );

      case AudiobookHoverEffect.tilt3D:
        final scale = _isPressed ? 0.90 : (_isHovered ? 1.10 : 1.0);
        final rotateX = -_tiltY * (math.pi / 10);
        final rotateY = _tiltX * (math.pi / 10);

        return AnimatedContainer(
          duration: Duration(milliseconds: _isHovered ? 60 : 250),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0025)
            ..rotateX(rotateX)
            ..rotateY(rotateY)
            ..scale(scale),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(30),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: Offset(_tiltX * 8, _tiltY * 8),
                    ),
                  ]
                : const [],
          ),
          child: _ringed(widget.child, focused),
        );
    }
  }
}
