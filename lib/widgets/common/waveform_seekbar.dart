import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/audiobook/audiobook_settings.dart';
import '../../services/music/music_settings.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// The player progress bar, drawn once for both the music and the audiobook
/// players.
///
/// The two players grew the same seekbar separately, and it is the same widget
/// either way: the drag state, the seek mapping, the timecode formatting and
/// the five style shapes are identical. What is *not* identical is the look —
/// the two players were designed apart, so the bar count, the bar width, the
/// played/unplayed paints, the scrubber indicator and the readout type all
/// differ by a number.
///
/// Those differences live in a [_SeekbarLook], chosen by the named
/// constructors, so neither side had to be flattened into the other: each call
/// site keeps exactly the appearance it had. Anything that is genuinely shared
/// is shared, and anything that only one player draws is a field here rather
/// than a branch picked for one of them.
class WaveformSeekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool isPlaying;

  /// Hides the timecode readout row and shrinks the artwork on the music
  /// player. The audiobook bar is always full size.
  final bool compact;

  final _SeekbarLook _look;

  /// Whichever player's settings enum this instance was built with; the
  /// constructor guarantees it matches [_look].
  final Object _style;

  WaveformSeekbar.music({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.isPlaying = false,
    MusicSeekbarStyle style = MusicSeekbarStyle.waveformEqualizer,
    this.compact = false,
  }) : _look = _SeekbarLook.music,
       _style = style;

  WaveformSeekbar.audiobook({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.isPlaying = false,
    AudiobookSeekbarStyle style = AudiobookSeekbarStyle.audioWaveformCanvas,
  }) : _look = _SeekbarLook.audiobook,
       _style = style,
       compact = false;

  _SeekbarVariant get _variant {
    if (_look.kind == _LookKind.music) {
      return switch (_style as MusicSeekbarStyle) {
        MusicSeekbarStyle.standardSlider => _SeekbarVariant.slider,
        MusicSeekbarStyle.neonGradient => _SeekbarVariant.linearGradient,
        MusicSeekbarStyle.liquidGlassSlider => _SeekbarVariant.liquidGlass,
        MusicSeekbarStyle.radialDial => _SeekbarVariant.radialDial,
        MusicSeekbarStyle.waveformEqualizer => _SeekbarVariant.waveform,
      };
    }
    return switch (_style as AudiobookSeekbarStyle) {
      AudiobookSeekbarStyle.standardSlider => _SeekbarVariant.slider,
      AudiobookSeekbarStyle.gradientProgress => _SeekbarVariant.linearGradient,
      // `circularRing` has no painter behind it in this bar and always fell
      // through to the waveform canvas; it still does.
      AudiobookSeekbarStyle.audioWaveformCanvas ||
      AudiobookSeekbarStyle.circularRing => _SeekbarVariant.waveform,
    };
  }

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  double _dragProgress = 0.0;
  late final AnimationController _waveAnimController;

  @override
  void initState() {
    super.initState();
    _waveAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget._look.waveAnimationMs),
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
    final look = widget._look;
    final palette = AppThemeService.currentPalette.value;
    final posDuration = _isDragging
        ? Duration(
            milliseconds: (_dragProgress * widget.duration.inMilliseconds)
                .round(),
          )
        : widget.position;

    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 1. Interactive Seek Canvas / Slider ──
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            switch (widget._variant) {
              case _SeekbarVariant.slider:
                return _buildSlider(palette);
              case _SeekbarVariant.waveform:
                return _buildWaveform(width, palette);
              case _SeekbarVariant.linearGradient:
                return _buildGradientBar(width, palette);
              case _SeekbarVariant.liquidGlass:
                return _buildLiquidGlass(width, palette);
              case _SeekbarVariant.radialDial:
                return _buildRadialDial(width, palette);
            }
          },
        ),

        // ── 2. Duration Readouts ──
        if (!widget.compact || look.labelsWhenCompact) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(posDuration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: look.labelStartAlpha),
                    fontSize: look.labelSize,
                    fontWeight: look.labelStartWeight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _formatDuration(widget.duration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: look.labelEndAlpha),
                    fontSize: look.labelSize,
                    fontWeight: look.labelEndWeight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!look.focusedSeeking) return bar;

    return Focus(
      // The non-Slider styles are a bare `GestureDetector`: a remote could not
      // seek at all in the audiobook player, in any of the five presets, and
      // seeking is the one thing that screen is for. The `standardSlider` style
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
        child: bar,
      ),
    );
  }

  Widget _buildSlider(AppThemePalette palette) {
    final look = widget._look;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: palette.primaryColor,
        inactiveTrackColor: Colors.white.withValues(
          alpha: look.sliderInactiveAlpha,
        ),
        thumbColor: look.sliderAccentThumb
            ? palette.primaryColor
            : Colors.white,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: look.sliderThumbRadius,
        ),
        trackHeight: 4,
        overlayColor: palette.primaryColor.withValues(alpha: 0.2),
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
          final targetMs = (val * widget.duration.inMilliseconds).round();
          widget.onSeek(Duration(milliseconds: targetMs));
        },
      ),
    );
  }

  Widget _buildWaveform(double width, AppThemePalette palette) {
    final look = widget._look;
    final height = widget.compact
        ? look.waveformCompactHeight
        : look.waveformHeight;

    Widget canvas = AnimatedBuilder(
      animation: _waveAnimController,
      builder: (context, _) {
        return CustomPaint(
          size: Size(width, height),
          painter: _WaveformPainter(
            samples: look.waveSamples,
            progress: _currentProgress,
            primaryColor: palette.primaryColor,
            accentColor: palette.accentColor,
            isPlaying: widget.isPlaying,
            animPhase: _waveAnimController.value * 2 * math.pi,
            look: look,
          ),
        );
      },
    );

    if (look.clickCursor) {
      canvas = MouseRegion(cursor: SystemMouseCursors.click, child: canvas);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        setState(() => _isDragging = true);
        if (look.seekOnDragStart) {
          _handleSeek(details.localPosition.dx, width);
        }
      },
      onHorizontalDragUpdate: (details) {
        _handleSeek(details.localPosition.dx, width);
      },
      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
      onTapDown: (details) {
        _handleSeek(details.localPosition.dx, width);
      },
      child: Container(
        height: height,
        alignment: Alignment.center,
        child: canvas,
      ),
    );
  }

  Widget _buildGradientBar(double width, AppThemePalette palette) {
    final look = widget._look;
    final height = widget.compact
        ? look.gradientCompactHeight
        : look.gradientHeight;
    final barHeight = widget.compact
        ? look.gradientCompactBarHeight
        : look.gradientBarHeight;
    final thumbSize = look.gradientThumbSize;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        setState(() => _isDragging = true);
        if (look.seekOnDragStart) {
          _handleSeek(details.localPosition.dx, width);
        }
      },
      onHorizontalDragUpdate: (details) {
        _handleSeek(details.localPosition.dx, width);
      },
      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
      onTapDown: (details) {
        _handleSeek(details.localPosition.dx, width);
      },
      child: Container(
        height: height,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Inactive bar
            Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: look.gradientInactiveAlpha,
                ),
                borderRadius: BorderRadius.circular(look.gradientRadius),
              ),
            ),
            // Active gradient bar
            FractionallySizedBox(
              widthFactor: _currentProgress,
              child: Container(
                height: barHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.primaryColor,
                      palette.accentColor,
                      if (look.gradientWhiteTip) Colors.white,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(look.gradientRadius),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primaryColor.withValues(
                        alpha: look.gradientGlowAlpha,
                      ),
                      blurRadius: 10,
                      spreadRadius: look.gradientGlowSpread,
                    ),
                  ],
                ),
              ),
            ),
            // Scrubber Thumb
            Positioned(
              left: (width * _currentProgress - thumbSize / 2).clamp(
                0.0,
                math.max(0.0, width - thumbSize),
              ),
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primaryColor.withValues(
                        alpha: look.gradientThumbGlowAlpha,
                      ),
                      blurRadius: 8,
                      spreadRadius: look.gradientThumbGlowSpread,
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

  Widget _buildLiquidGlass(double width, AppThemePalette palette) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => setState(() => _isDragging = true),
      onHorizontalDragUpdate: (d) => _handleSeek(d.localPosition.dx, width),
      onHorizontalDragEnd: (d) => setState(() => _isDragging = false),
      onTapDown: (d) => _handleSeek(d.localPosition.dx, width),
      child: Container(
        height: widget.compact ? 24 : 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            FractionallySizedBox(
              widthFactor: _currentProgress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.primaryColor.withValues(alpha: 0.35),
                      palette.primaryColor.withValues(alpha: 0.65),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              left: (width * _currentProgress - 10).clamp(
                0.0,
                math.max(0.0, width - 20),
              ),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: palette.primaryColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primaryColor.withValues(alpha: 0.7),
                      blurRadius: 10,
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

  Widget _buildRadialDial(double width, AppThemePalette palette) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => setState(() => _isDragging = true),
      onHorizontalDragUpdate: (d) => _handleSeek(d.localPosition.dx, width),
      onHorizontalDragEnd: (d) => setState(() => _isDragging = false),
      onTapDown: (d) => _handleSeek(d.localPosition.dx, width),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size(56, 56),
          painter: _RadialDialSeekPainter(
            progress: _currentProgress,
            primaryColor: palette.primaryColor,
            accentColor: palette.accentColor,
          ),
        ),
      ),
    );
  }
}

enum _LookKind { music, audiobook }

enum _SeekbarVariant {
  slider,
  waveform,
  linearGradient,
  liquidGlass,
  radialDial,
}

/// Every number that differs between the two players' seekbars, in one place.
///
/// Two instances only: one per player. The widget takes the sound structure
/// from the shared implementation and the appearance from here, which is why
/// the merge did not have to choose a winner for any of these.
class _SeekbarLook {
  const _SeekbarLook({
    required this.kind,
    required this.waveSamples,
    required this.waveAnimationMs,
    required this.seekOnDragStart,
    required this.focusedSeeking,
    required this.clickCursor,
    required this.waveformHeight,
    required this.waveformCompactHeight,
    required this.minBarWidth,
    required this.barWidthFactor,
    required this.inactiveAlpha,
    required this.perBarGradient,
    required this.gradientAccentFirst,
    required this.rippleAmplitude,
    required this.rippleAbsolute,
    required this.scrubber,
    required this.labelStartAlpha,
    required this.labelEndAlpha,
    required this.labelSize,
    required this.labelStartWeight,
    required this.labelEndWeight,
    required this.labelsWhenCompact,
    required this.sliderAccentThumb,
    required this.sliderInactiveAlpha,
    required this.sliderThumbRadius,
    required this.gradientHeight,
    required this.gradientCompactHeight,
    required this.gradientBarHeight,
    required this.gradientCompactBarHeight,
    required this.gradientRadius,
    required this.gradientInactiveAlpha,
    required this.gradientWhiteTip,
    required this.gradientGlowAlpha,
    required this.gradientGlowSpread,
    required this.gradientThumbSize,
    required this.gradientThumbGlowAlpha,
    required this.gradientThumbGlowSpread,
  });

  final _LookKind kind;
  final List<double> waveSamples;
  final int waveAnimationMs;

  /// Whether a drag that begins on the bar also seeks to where it began, or
  /// waits for the first move.
  final bool seekOnDragStart;

  /// Whether the bar is a focus stop with its own arrow-key seeking and a
  /// `CardFocusRing`. Only the audiobook player needs those.
  final bool focusedSeeking;
  final bool clickCursor;
  final double waveformHeight;
  final double waveformCompactHeight;
  final double minBarWidth;
  final double barWidthFactor;
  final double inactiveAlpha;

  /// Per-bar shaders give every bar the whole accent→primary run, so the bars
  /// read as individual lamps; one canvas-wide shader instead slices that run
  /// across the height, which is the quieter look.
  final bool perBarGradient;
  final bool gradientAccentFirst;
  final double rippleAmplitude;
  final bool rippleAbsolute;
  final bool scrubber;
  final double labelStartAlpha;
  final double labelEndAlpha;
  final double labelSize;
  final FontWeight labelStartWeight;
  final FontWeight labelEndWeight;
  final bool labelsWhenCompact;
  final bool sliderAccentThumb;
  final double sliderInactiveAlpha;
  final double sliderThumbRadius;
  final double gradientHeight;
  final double gradientCompactHeight;
  final double gradientBarHeight;
  final double gradientCompactBarHeight;
  final double gradientRadius;
  final double gradientInactiveAlpha;
  final bool gradientWhiteTip;
  final double gradientGlowAlpha;
  final double gradientGlowSpread;
  final double gradientThumbSize;
  final double gradientThumbGlowAlpha;
  final double gradientThumbGlowSpread;

  /// Stable procedural waveform bar heights.
  static final _SeekbarLook music = _SeekbarLook(
    kind: _LookKind.music,
    waveSamples: List.generate(64, (i) {
      final s1 = math.sin(i * 0.32).abs();
      final s2 = math.cos(i * 0.52).abs();
      final s3 = math.sin(i * 0.18 + 1.4).abs();
      return ((s1 * 0.55 + s2 * 0.3 + s3 * 0.4) * 0.75 + 0.25).clamp(0.2, 1.0);
    }),
    waveAnimationMs: 1400,
    seekOnDragStart: false,
    focusedSeeking: false,
    clickCursor: false,
    waveformHeight: 48,
    waveformCompactHeight: 32,
    minBarWidth: 1.8,
    barWidthFactor: 0.55,
    inactiveAlpha: 0.15,
    perBarGradient: true,
    gradientAccentFirst: true,
    rippleAmplitude: 0.25,
    rippleAbsolute: true,
    scrubber: false,
    labelStartAlpha: 0.6,
    labelEndAlpha: 0.4,
    labelSize: 11.5,
    labelStartWeight: FontWeight.w600,
    labelEndWeight: FontWeight.w600,
    labelsWhenCompact: false,
    sliderAccentThumb: false,
    sliderInactiveAlpha: 0.12,
    sliderThumbRadius: 6,
    gradientHeight: 32,
    gradientCompactHeight: 20,
    gradientBarHeight: 6,
    gradientCompactBarHeight: 4,
    gradientRadius: 4,
    gradientInactiveAlpha: 0.1,
    gradientWhiteTip: true,
    gradientGlowAlpha: 0.6,
    gradientGlowSpread: 1,
    gradientThumbSize: 12,
    gradientThumbGlowAlpha: 1.0,
    gradientThumbGlowSpread: 2,
  );

  static final _SeekbarLook audiobook = _SeekbarLook(
    kind: _LookKind.audiobook,
    waveSamples: List.generate(70, (i) {
      final s1 = math.sin(i * 0.28).abs();
      final s2 = math.cos(i * 0.45).abs();
      final s3 = math.sin(i * 0.12 + 1.2).abs();
      return ((s1 * 0.5 + s2 * 0.35 + s3 * 0.4) * 0.75 + 0.25).clamp(0.2, 1.0);
    }),
    waveAnimationMs: 1600,
    seekOnDragStart: true,
    focusedSeeking: true,
    clickCursor: true,
    waveformHeight: 48,
    waveformCompactHeight: 48,
    minBarWidth: 2.5,
    barWidthFactor: 0.65,
    inactiveAlpha: 0.16,
    perBarGradient: false,
    gradientAccentFirst: false,
    rippleAmplitude: 0.15,
    rippleAbsolute: false,
    scrubber: true,
    labelStartAlpha: 0.8,
    labelEndAlpha: 0.45,
    labelSize: 12,
    labelStartWeight: FontWeight.w600,
    labelEndWeight: FontWeight.w500,
    labelsWhenCompact: true,
    sliderAccentThumb: true,
    sliderInactiveAlpha: 0.15,
    sliderThumbRadius: 7,
    gradientHeight: 28,
    gradientCompactHeight: 28,
    gradientBarHeight: 6,
    gradientCompactBarHeight: 6,
    gradientRadius: 3,
    gradientInactiveAlpha: 0.15,
    gradientWhiteTip: false,
    gradientGlowAlpha: 0.5,
    gradientGlowSpread: 0,
    gradientThumbSize: 16,
    gradientThumbGlowAlpha: 0.7,
    gradientThumbGlowSpread: 0,
  );
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color primaryColor;
  final Color accentColor;
  final bool isPlaying;
  final double animPhase;
  final _SeekbarLook look;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
    required this.isPlaying,
    required this.animPhase,
    required this.look,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0) return;

    final count = samples.length;
    final totalSpacing = size.width / count;
    final barWidth = math.max(
      look.minBarWidth,
      totalSpacing * look.barWidthFactor,
    );
    final midY = size.height / 2;

    final playedPaint = Paint()..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = Colors.white.withValues(alpha: look.inactiveAlpha)
      ..style = PaintingStyle.fill;

    final activeColors = look.gradientAccentFirst
        ? [accentColor, primaryColor]
        : [primaryColor, accentColor];
    if (!look.perBarGradient) {
      playedPaint.shader = LinearGradient(
        colors: activeColors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }

    for (int i = 0; i < count; i++) {
      final x = i * totalSpacing + (totalSpacing - barWidth) / 2;
      final barProgress = i / count;
      final isPlayed = barProgress <= progress;

      double sample = samples[i];
      if (isPlaying && isPlayed) {
        final beat = math.sin(animPhase + (i * 0.45));
        sample =
            (sample +
                    (look.rippleAbsolute ? beat.abs() : beat) *
                        look.rippleAmplitude)
                .clamp(0.2, 1.0);
      }

      final h = sample * size.height * 0.85;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY - h / 2, barWidth, h),
        const Radius.circular(3),
      );

      if (isPlayed) {
        if (look.perBarGradient) {
          // Per-bar shader: every bar shows the whole gradient, so the bars
          // read as individual lamps rather than as slices of one wash.
          playedPaint.shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: activeColors,
          ).createShader(Rect.fromLTWH(x, midY - h / 2, barWidth, h));
        }
        canvas.drawRRect(rect, playedPaint);
      } else {
        canvas.drawRRect(rect, unplayedPaint);
      }
    }

    if (!look.scrubber) return;

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
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class _RadialDialSeekPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;

  _RadialDialSeekPainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    final bgPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..shader = SweepGradient(
        colors: [primaryColor, accentColor, primaryColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadialDialSeekPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primaryColor != primaryColor;
}
