import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/theme/app_theme_service.dart';
import '../common/focusable_card.dart';
import '../../services/audiobook/audiobook_settings.dart';
import '../../services/theme/design_tokens.dart';

class AudiobookWaveformSeekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool isPlaying;
  final AudiobookSeekbarStyle style;

  const AudiobookWaveformSeekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.isPlaying = false,
    this.style = AudiobookSeekbarStyle.audioWaveformCanvas,
  });

  @override
  State<AudiobookWaveformSeekbar> createState() =>
      _AudiobookWaveformSeekbarState();
}

class _AudiobookWaveformSeekbarState extends State<AudiobookWaveformSeekbar>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  double _dragProgress = 0.0;
  late final AnimationController _waveAnimController;

  // Stable procedural waveform bar heights
  static final List<double> _waveSamples = List.generate(70, (i) {
    final s1 = math.sin(i * 0.28).abs();
    final s2 = math.cos(i * 0.45).abs();
    final s3 = math.sin(i * 0.12 + 1.2).abs();
    return ((s1 * 0.5 + s2 * 0.35 + s3 * 0.4) * 0.75 + 0.25).clamp(0.2, 1.0);
  });

  @override
  void initState() {
    super.initState();
    _waveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _waveAnimController.dispose();
    super.dispose();
  }

  double get _currentProgress {
    if (_isDragging) return _dragProgress;
    if (widget.duration.inMilliseconds <= 0) return 0.0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final mins = (d.inMinutes % 60).toString().padLeft(2, '0');
      final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$hours:$mins:$secs';
    }
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _handleSeek(double localX, double totalWidth) {
    if (totalWidth <= 0) return;
    final progress = (localX / totalWidth).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = progress;
    });
    final targetMs = (progress * widget.duration.inMilliseconds).round();
    widget.onSeek(Duration(milliseconds: targetMs));
  }

  /// Set while the bar holds focus, so the ring is drawn by a `CardFocusRing`
  /// rather than guessed from the art underneath.
  bool _seekbarFocused = false;

  /// Maps the arrow keys to a relative seek.
  ///
  /// Long enough to be usable on a remote where each press is deliberate, and
  /// the same 10 s the rewind and forward buttons use, so the two ways of
  /// moving through a book agree. Held keys repeat through the normal key
  /// repeat, so this scrubs rather than jumping.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.arrowLeft ||
        logical == LogicalKeyboardKey.arrowRight) {
      final forward = logical == LogicalKeyboardKey.arrowRight;
      if (widget.duration <= Duration.zero) return KeyEventResult.handled;
      const step = Duration(seconds: 10);
      final target = widget.position + (forward ? step : -step);
      // Clamped rather than wrapped: seeking past either end of a book should
      // stop, not jump to the opposite end.
      final bounded = target < Duration.zero
          ? Duration.zero
          : (target > widget.duration ? widget.duration : target);
      widget.onSeek(bounded);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final posDuration = _isDragging
        ? Duration(
            milliseconds: (_dragProgress * widget.duration.inMilliseconds)
                .round(),
          )
        : widget.position;

    return Focus(
      // The two non-Slider styles are a bare `GestureDetector`: a remote could
      // not seek at all in the audiobook player, in any of the five presets, and
      // seeking is the one thing the screen is for. The `standardSlider` style
      // is a real `Slider` and already answers the arrow keys, so this wrapper
      // is what makes every style agree.
      //
      // The focus ring is drawn as a border around the whole bar rather than
      // replacing the artwork: a `Slider` cannot draw a waveform and one is the
      // default here, so the shape stays and only a ring is added.
      canRequestFocus: true,
      skipTraversal: false,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (has) {
        if (_seekbarFocused != has) {
          setState(() => _seekbarFocused = has);
        }
      },
      child: CardFocusRing(
        focused: _seekbarFocused,
        radius: ZplayRadius.smAll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. Interactive Seek Canvas / Slider ──
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                if (widget.style == AudiobookSeekbarStyle.standardSlider) {
                  return SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                      thumbColor: palette.primaryColor,
                      overlayColor: palette.primaryColor.withValues(alpha: 0.2),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: _currentProgress,
                      onChanged: (val) {
                        setState(() {
                          _isDragging = true;
                          _dragProgress = val;
                        });
                      },
                      onChangeEnd: (val) {
                        setState(() => _isDragging = false);
                        final ms = (val * widget.duration.inMilliseconds)
                            .round();
                        widget.onSeek(Duration(milliseconds: ms));
                      },
                    ),
                  );
                }

                if (widget.style == AudiobookSeekbarStyle.gradientProgress) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      setState(() => _isDragging = true);
                      _handleSeek(details.localPosition.dx, width);
                    },
                    onHorizontalDragUpdate: (details) {
                      _handleSeek(details.localPosition.dx, width);
                    },
                    onHorizontalDragEnd: (_) {
                      setState(() => _isDragging = false);
                    },
                    onTapDown: (details) {
                      _handleSeek(details.localPosition.dx, width);
                    },
                    child: Container(
                      height: 28,
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Inactive bar
                          Container(
                            height: 6,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          // Active gradient bar
                          Container(
                            height: 6,
                            width: width * _currentProgress,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  palette.primaryColor,
                                  palette.accentColor,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: palette.primaryColor.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          // Scrubber Thumb
                          Positioned(
                            left: (width * _currentProgress - 8).clamp(
                              0.0,
                              width - 16,
                            ),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.primaryColor.withValues(
                                      alpha: 0.7,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Default: AudiobookSeekbarStyle.audioWaveformCanvas
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() => _isDragging = true);
                    _handleSeek(details.localPosition.dx, width);
                  },
                  onHorizontalDragUpdate: (details) {
                    _handleSeek(details.localPosition.dx, width);
                  },
                  onHorizontalDragEnd: (_) {
                    setState(() => _isDragging = false);
                  },
                  onTapDown: (details) {
                    _handleSeek(details.localPosition.dx, width);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedBuilder(
                      animation: _waveAnimController,
                      builder: (context, _) {
                        return CustomPaint(
                          size: Size(width, 48),
                          painter: _WaveformPainter(
                            progress: _currentProgress,
                            samples: _waveSamples,
                            primaryColor: palette.primaryColor,
                            accentColor: palette.accentColor,
                            isPlaying: widget.isPlaying,
                            animValue: _waveAnimController.value,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 6),

            // ── 2. Duration Readouts ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(posDuration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _formatDuration(widget.duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final List<double> samples;
  final Color primaryColor;
  final Color accentColor;
  final bool isPlaying;
  final double animValue;

  _WaveformPainter({
    required this.progress,
    required this.samples,
    required this.primaryColor,
    required this.accentColor,
    required this.isPlaying,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = samples.length;
    final totalSpacing = size.width / barCount;
    final barWidth = math.max(2.5, totalSpacing * 0.65);
    final midY = size.height / 2;

    final playedPaint = Paint()
      ..shader = LinearGradient(
        colors: [primaryColor, accentColor],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final unplayedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final x = i * totalSpacing + (totalSpacing - barWidth) / 2;
      final barProgress = i / barCount;
      final isPlayed = barProgress <= progress;

      // Animate bar bounce when playing
      double waveScale = samples[i];
      if (isPlaying && isPlayed) {
        final phase = math.sin((animValue * 2 * math.pi) + (i * 0.45));
        waveScale = (waveScale + phase * 0.15).clamp(0.2, 1.0);
      }

      final barHeight = (size.height * 0.85) * waveScale;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, midY),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(3),
      );

      canvas.drawRRect(rect, isPlayed ? playedPaint : unplayedPaint);
    }

    // Draw active scrubber indicator line
    final currentX = size.width * progress;
    final indicatorPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(currentX, 4),
      Offset(currentX, size.height - 4),
      indicatorPaint,
    );

    // Thumb dot
    final dotPaint = Paint()..color = primaryColor;
    canvas.drawCircle(Offset(currentX, midY), 4.5, dotPaint);
    canvas.drawCircle(
      Offset(currentX, midY),
      2.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animValue != animValue;
  }
}
