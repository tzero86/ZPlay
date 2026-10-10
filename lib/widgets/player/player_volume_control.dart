import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// Interactive volume slider with high-gain boost support (up to 250%).
class PlayerVolumeControl extends StatefulWidget {
  final double volume; // 0.0 to 2.50 (250%)
  final bool isMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  static const double maxVolume = 2.50;

  const PlayerVolumeControl({
    super.key,
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  State<PlayerVolumeControl> createState() => _PlayerVolumeControlState();
}

class _PlayerVolumeControlState extends State<PlayerVolumeControl> {
  bool _isHovered = false;
  static const double _trackWidth = 96.0;

  /// The slider's own focus, so a remote can change the volume.
  ///
  /// The track was a bare `GestureDetector`, which is pointer-only: it is not a
  /// `Focus` widget, so no key, remote or D-pad event could reach it and a
  /// television had no way to set the volume at all - the mute button beside it
  /// was the whole control.
  ///
  /// Up and down step it, the same pair the arrow keys mean on a pointer device,
  /// and the step matches the `+/-0.05` those keys use. Left and right are left
  /// alone: the track sits in the middle of the transport row, and a control that
  /// eats an arrow along the row is a hole in the row - the aspect, speed, audio,
  /// subtitle and fullscreen buttons on the far side of it would only be
  /// reachable by leaving the row and coming back down.
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerVolumeSlider');

  /// Mirrored into state so the ring is drawn on the frame focus changes rather
  /// than on the next rebuild some other notifier happens to trigger.
  bool _hasFocus = false;

  /// One arrow press. Five percent is a small move, and holding the key
  /// auto-repeats through the framework's key events.
  static const double _arrowStep = 0.05;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _stepBy(double delta) {
    final next = (widget.volume + delta).clamp(0.0, PlayerVolumeControl.maxVolume);
    widget.onVolumeChanged((next * 100).round() / 100.0);
  }

  IconData _getVolumeIcon() {
    if (widget.isMuted || widget.volume == 0) {
      return Icons.volume_off_rounded;
    }
    if (widget.volume > 1.0) {
      return Icons.volume_up_rounded;
    }
    if (widget.volume < 0.5) {
      return Icons.volume_down_rounded;
    }
    return Icons.volume_up_rounded;
  }

  Color _getBoostColor(ZplayTokens tokens) {
    if (widget.volume <= 1.0) return tokens.textPrimary;
    if (widget.volume > 1.75) return tokens.danger; // Deep Flame Orange/Red
    return tokens.warning; // Amber/Orange
  }

  void _updateFromPosition(double localX) {
    final fraction = (localX / _trackWidth).clamp(0.0, 1.0);
    double newVol;
    if (fraction <= 0.55) {
      newVol = (fraction / 0.55) * 1.0;
    } else {
      newVol = 1.0 + ((fraction - 0.55) / 0.45) * 1.50;
    }
    widget.onVolumeChanged((newVol * 100).round() / 100.0);
  }

  double _getFractionFromVolume(double v) {
    if (widget.isMuted) return 0.0;
    if (v <= 1.0) {
      return (v * 0.55).clamp(0.0, 0.55);
    }
    return (0.55 + ((v - 1.0) / 1.50) * 0.45).clamp(0.55, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final effectiveVol = widget.isMuted ? 0.0 : widget.volume;
    final fillFraction = _getFractionFromVolume(effectiveVol);
    final isBoosting = !widget.isMuted && widget.volume > 1.001;
    final boostColor = _getBoostColor(tokens);
    final pct = (effectiveVol * 100).round();

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          final delta = pointerSignal.scrollDelta.dy < 0 ? 0.05 : -0.05;
          final next = (widget.volume + delta).clamp(0.0, PlayerVolumeControl.maxVolume);
          widget.onVolumeChanged((next * 100).round() / 100.0);
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mute / Unmute Button
            PlayerIconButton(
              size: 40,
              iconSize: 22,
              icon: Icon(
                _getVolumeIcon(),
                color: isBoosting ? boostColor : (widget.isMuted ? PlayerTheme.inkSubtle : tokens.textPrimary),
              ),
              tooltip: widget.isMuted ? 'Unmute' : 'Mute',
              onPressed: widget.onToggleMute,
            ),

            const SizedBox(width: ZplaySpacing.s4),

            // Volume Slider Track
            Focus(
              focusNode: _focusNode,
              onFocusChange: (hasFocus) {
                if (mounted) setState(() => _hasFocus = hasFocus);
              },
              onKeyEvent: (node, event) {
                // Up and down step the volume. Left and right are left to the
                // focus system: they are how a remote walks the transport row,
                // and this track is in the middle of it.
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _stepBy(_arrowStep);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _stepBy(-_arrowStep);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                // The focus ring, so a remote user can see the track holds focus
                // before pressing an arrow. Painted on the foreground rather than
                // wrapped around, so the row keeps the height it had.
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: _hasFocus ? tokens.accent : Colors.transparent,
                    // 3 dp, matching CardFocusRing: a 2 dp ring read as too
                    // subtle on a television.
                    width: 3,
                  ),
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (e) => _updateFromPosition(e.localPosition.dx),
                  onTapDown: (e) => _updateFromPosition(e.localPosition.dx),
                  child: Container(
                    width: _trackWidth,
                    height: 32,
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                    // Background track
                    Container(
                      height: 6,
                      width: _trackWidth,
                      decoration: BoxDecoration(
                        color: tokens.textPrimary
                            .withValues(alpha: ZplayOpacity.overlayHover),
                        borderRadius: ZplayRadius.fullAll,
                      ),
                    ),

                    // 100% Threshold Notch Line
                    Positioned(
                      left: _trackWidth * 0.55 - 0.75,
                      child: Container(
                        width: 1.5,
                        height: 9,
                        decoration: BoxDecoration(
                          color: tokens.textMuted,
                          borderRadius: ZplayRadius.xsAll,
                        ),
                      ),
                    ),

                    // Filled track
                    Container(
                      height: 6,
                      width: _trackWidth * fillFraction,
                      decoration: BoxDecoration(
                        gradient: isBoosting
                          ? LinearGradient(
                              colors: [
                                tokens.textPrimary,
                                tokens.warning,
                                if (widget.volume > 1.75) tokens.danger,
                              ],
                            )
                          : null,
                        color: isBoosting ? null : tokens.textPrimary,
                        borderRadius: ZplayRadius.fullAll,
                      ),
                    ),

                    // Thumb dot
                    Positioned(
                      left: (_trackWidth * fillFraction - 6).clamp(0.0, _trackWidth - 12),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isBoosting ? boostColor : tokens.textPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: isBoosting
                                  ? boostColor.withValues(alpha: 0.6)
                                  : tokens.bg.withValues(alpha: 0.54),
                              blurRadius: isBoosting ? 6 : 4,
                              spreadRadius: isBoosting ? 1 : 0,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

            // Percentage Readout
            if (isBoosting || _isHovered || _hasFocus) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 38),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBoosting)
                      Padding(
                        padding: const EdgeInsets.only(right: ZplaySpacing.s2),
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 13,
                          color: boostColor,
                        ),
                      ),
                    Text(
                      '$pct%',
                      style: ZplayType.caption
                          .toStyle(
                            color: isBoosting ? boostColor : PlayerTheme.inkMuted,
                            tabular: true,
                          )
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
