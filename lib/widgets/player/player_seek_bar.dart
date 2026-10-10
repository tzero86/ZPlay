import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/player/skip_segment_model.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';
import '../common/focusable_card.dart';

/// Timeline scrubber with buffered progress and interactive hover / drag preview.
class PlayerSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final ValueListenable<Duration>? positionListenable;
  final ValueListenable<Duration?>? bufferedListenable;
  final List<MediaSkipSegment> skipSegments;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrubbingChanged;

  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered,
    this.positionListenable,
    this.bufferedListenable,
    this.skipSegments = const [],
    required this.onSeek,
    this.onScrubbingChanged,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  bool _isHovered = false;
  bool _isScrubbing = false;
  double? _scrubFraction;
  double? _hoverFraction;
  bool _showRemainingTime = true;

  /// The track's own focus, so a remote can scrub it.
  ///
  /// `GestureDetector` is pointer-only: it is not a `Focus` widget, so no key,
  /// remote or D-pad event can reach it, and the timeline is the control a
  /// viewer reaches for most. Arrows step it and commit, which is the ten-foot
  /// equivalent of a drag and means no separate seek buttons are needed.
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerSeekBar');

  /// Whether [_focusNode] holds focus, mirrored into state so the ring is drawn
  /// on the frame focus changes rather than whenever the position stream happens
  /// to rebuild this widget next.
  bool _hasFocus = false;

  /// How far one arrow press moves. Ten seconds matches the skip buttons
  /// elsewhere in the transport, so the D-pad and the on-screen controls agree.
  static const Duration _arrowStep = Duration(seconds: 10);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Seeks relative to the current position, clamped to the media.
  void _stepBy(Duration delta) {
    if (widget.duration.inMilliseconds <= 0) return;
    final target = widget.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > widget.duration ? widget.duration : target);
    widget.onSeek(clamped);
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) {
      return '-${_formatDuration(-d)}';
    }
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '${d.inMinutes}:$seconds';
  }

  void _updateScrub(double localX, double width) {
    if (width <= 0) return;
    final frac = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _scrubFraction = frac;
    });
  }

  void _commitSeek() {
    if (_scrubFraction != null && widget.duration.inMilliseconds > 0) {
      final targetMs = (_scrubFraction! * widget.duration.inMilliseconds).round();
      widget.onSeek(Duration(milliseconds: targetMs));
    }
    setState(() {
      _isScrubbing = false;
      _scrubFraction = null;
    });
    widget.onScrubbingChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.positionListenable != null) {
      return ValueListenableBuilder<Duration>(
        valueListenable: widget.positionListenable!,
        builder: (context, pos, _) {
          if (widget.bufferedListenable != null) {
            return ValueListenableBuilder<Duration?>(
              valueListenable: widget.bufferedListenable!,
              builder: (context, buf, _) => _buildRow(context, pos, buf),
            );
          }
          return _buildRow(context, pos, widget.buffered);
        },
      );
    }
    return _buildRow(context, widget.position, widget.buffered);
  }

  Widget _buildRow(BuildContext context, Duration currentPosition, Duration? currentBuffered) {
    final tokens = context.tokens;
    final totalMs = widget.duration.inMilliseconds;
    final currentMs = currentPosition.inMilliseconds;
    final currentFraction = totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final bufferedMs = currentBuffered?.inMilliseconds ?? 0;
    final bufferedFraction = totalMs > 0 ? (bufferedMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final activeFraction = _scrubFraction ?? currentFraction;

    final remainingDuration = widget.duration - currentPosition;

    return Row(
      children: [
        // Time Start
        Container(
          constraints: const BoxConstraints(minWidth: 46),
          child: Text(
            _formatDuration(_scrubFraction != null
                ? Duration(milliseconds: (_scrubFraction! * totalMs).round())
                : currentPosition),
            style: ZplayType.labelNumeric.toStyle(color: PlayerTheme.inkMuted),
          ),
        ),

        const SizedBox(width: ZplaySpacing.s12),

        // Scrubber Track
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (e) => setState(() {
                  _isHovered = true;
                  _hoverFraction = (e.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                }),
                onHover: (e) => setState(() {
                  _hoverFraction = (e.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                }),
                onExit: (_) => setState(() {
                  _isHovered = false;
                  _hoverFraction = null;
                }),
                // Wrapped in a `Focus` so a remote can drive it. `GestureDetector`
                // is pointer-only: it is not a `Focus` widget, so no key, remote
                // or D-pad event can reach it, and the track is the one control a
                // viewer reaches for constantly. Left and right step by
                // [_arrowStep] and commit, which is the ten-foot equivalent of a
                // drag and needs no separate seek buttons.
                child: Focus(
                  focusNode: _focusNode,
                  onFocusChange: (hasFocus) {
                    if (mounted) setState(() => _hasFocus = hasFocus);
                  },
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _stepBy(-_arrowStep);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      _stepBy(_arrowStep);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                  onHorizontalDragStart: (e) {
                    setState(() {
                      _isScrubbing = true;
                    });
                    widget.onScrubbingChanged?.call(true);
                    _updateScrub(e.localPosition.dx, trackWidth);
                  },
                  onHorizontalDragUpdate: (e) {
                    _updateScrub(e.localPosition.dx, trackWidth);
                  },
                  onHorizontalDragEnd: (_) => _commitSeek(),
                  onTapDown: (e) {
                    setState(() {
                      _isScrubbing = true;
                    });
                    widget.onScrubbingChanged?.call(true);
                    _updateScrub(e.localPosition.dx, trackWidth);
                  },
                  onTapUp: (_) => _commitSeek(),
                  child: Container(
                    // The focus ring, so a remote user can see the track holds
                    // focus before pressing an arrow. A pointer user never sees
                    // it, because a track is only focusable once a key lands on
                    // it.
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(
                        color: _hasFocus
                            ? tokens.accent
                            : Colors.transparent,
                        // 3 dp, matching CardFocusRing: a 2 dp ring read as too
                        // subtle on a television.
                        width: 3,
                      ),
                      borderRadius: ZplayRadius.xsAll,
                    ),
                    height: 36,
                    alignment: Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        // Track Background
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: (_isHovered || _isScrubbing) ? 8 : 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: tokens.textPrimary
                                .withValues(alpha: ZplayOpacity.overlayHover),
                            borderRadius: ZplayRadius.fullAll,
                          ),
                          child: Stack(
                            children: [
                              // Buffered Track
                              if (bufferedFraction > 0)
                                FractionallySizedBox(
                                  widthFactor: bufferedFraction,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: tokens.textPrimary.withValues(alpha: 0.30),
                                      borderRadius: ZplayRadius.fullAll,
                                    ),
                                  ),
                                ),

                              // Skip Segments Highlights (Intro, Recap, Credits)
                              if (totalMs > 0 && widget.skipSegments.isNotEmpty)
                                ...widget.skipSegments.map((seg) {
                                  final sFrac = ((seg.startMs ?? 0) / totalMs).clamp(0.0, 1.0);
                                  final eFrac = ((seg.endMs ?? totalMs) / totalMs).clamp(0.0, 1.0);
                                  final segWidth = ((eFrac - sFrac) * trackWidth).clamp(2.0, trackWidth);
                                  final isCredits = seg.type == 'credits';
                                  final color = isCredits
                                      ? tokens.success.withValues(alpha: 0.60)
                                      : tokens.warning.withValues(alpha: 0.60);

                                  return Positioned(
                                    left: sFrac * trackWidth,
                                    width: segWidth,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: ZplayRadius.xsAll,
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),

                        // Played Progress Bar (Gradient)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: (_isHovered || _isScrubbing) ? 8 : 6,
                          width: trackWidth * activeFraction,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [PlayerTheme.accent, tokens.accentHover],
                            ),
                            borderRadius: ZplayRadius.fullAll,
                            boxShadow: [
                              BoxShadow(
                                color: PlayerTheme.accent.withValues(alpha: 0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),

                        // Interactive Scrubber Thumb Dot
                        Positioned(
                          left: (trackWidth * activeFraction - ((_isHovered || _isScrubbing) ? 8 : 6))
                              .clamp(0.0, trackWidth - 16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: (_isHovered || _isScrubbing) ? 16 : 12,
                            height: (_isHovered || _isScrubbing) ? 16 : 12,
                            decoration: BoxDecoration(
                              color: tokens.textPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.bg.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: PlayerTheme.accent.withValues(alpha: 0.8),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Floating Timestamp Preview Bubble on Hover / Scrub
                        if ((_isHovered || _isScrubbing) && (_hoverFraction != null || _scrubFraction != null)) ...[
                          Positioned(
                            left: (trackWidth * (_scrubFraction ?? _hoverFraction!) - 28)
                                .clamp(0.0, trackWidth - 56),
                            top: -32,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ZplaySpacing.s8,
                                vertical: ZplaySpacing.s4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceOverlay.withValues(alpha: 0.94),
                                borderRadius: ZplayRadius.xsAll,
                                border: Border.all(color: PlayerTheme.edge),
                                boxShadow: [
                                  BoxShadow(
                                    color: tokens.bg.withValues(alpha: 0.54),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                _formatDuration(
                                  Duration(
                                    milliseconds:
                                        ((_scrubFraction ?? _hoverFraction!) * totalMs).round(),
                                  ),
                                ),
                                style: ZplayType.caption
                                    .toStyle(color: tokens.textPrimary, tabular: true)
                                    .copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(width: ZplaySpacing.s12),

        // Time End / Remaining Toggle
        FocusableCard(
          onTap: () => setState(() => _showRemainingTime = !_showRemainingTime),
          builder: (context, _) {
            return Container(
              constraints: const BoxConstraints(minWidth: 46),
              alignment: Alignment.centerRight,
              child: Text(
                _showRemainingTime
                    ? (_formatDuration(-remainingDuration))
                    : _formatDuration(widget.duration),
                style: ZplayType.labelNumeric.toStyle(color: PlayerTheme.inkMuted),
              ),
            );
          },
        ),
      ],
    );
  }
}
