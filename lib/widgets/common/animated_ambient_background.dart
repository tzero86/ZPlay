import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/custom_background_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/storage/app_image_cache.dart';

/// GPU-accelerated animated ambient background with moving soft-faded
/// light orbs, aurora waves, gradient meshes, and custom user wallpaper blending.
class AnimatedAmbientBackground extends StatefulWidget {
  final Widget? child;

  const AnimatedAmbientBackground({super.key, this.child});

  @override
  State<AnimatedAmbientBackground> createState() =>
      _AnimatedAmbientBackgroundState();
}

class _AnimatedAmbientBackgroundState extends State<AnimatedAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    CustomBackgroundService.notifier.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    CustomBackgroundService.notifier.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  Widget _buildWallpaperImage(CustomBackgroundData customBg) {
    Widget imageWidget;
    if (customBg.imagePath != null && customBg.imagePath!.isNotEmpty) {
      imageWidget = Image.file(
        File(customBg.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (customBg.imageUrl != null && customBg.imageUrl!.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: customBg.imageUrl!,
        cacheManager: AppImageCache.manager,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      return const SizedBox.shrink();
    }

    if (customBg.blur > 0.1) {
      imageWidget = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: customBg.blur,
          sigmaY: customBg.blur,
          tileMode: TileMode.clamp,
        ),
        child: imageWidget,
      );
    }

    return Opacity(opacity: customBg.opacity, child: imageWidget);
  }

  @override
  Widget build(BuildContext context) {
    // The glow is chrome, so it takes the semantic set rather than the raw
    // palette: one accent (the palette's second hue was the competing accent the
    // design audit flagged) and the page background.
    final tokens = ZplayTokens.of(context);

    return ValueListenableBuilder<CustomBackgroundData>(
      valueListenable: CustomBackgroundService.notifier,
      builder: (context, customBg, _) {
        final hasWallpaper = customBg.hasCustomBackground;

        return ValueListenableBuilder<bool>(
          valueListenable: HomePageSettings.enableAmbientLights,
          builder: (context, lightsEnabled, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Base solid scaffold background color
                Container(color: tokens.bg),

                // 2. Custom Background Wallpaper (if active)
                if (hasWallpaper) ...[
                  Positioned.fill(child: _buildWallpaperImage(customBg)),
                  // Theme color tint layer blending over the photo
                  Positioned.fill(
                    child: Container(
                      color: tokens.bg.withValues(
                        alpha: customBg.themeTintOpacity,
                      ),
                    ),
                  ),
                ],

                // 3. Moving Ambient Lights & Glows (GPU Canvas)
                if (lightsEnabled &&
                    (!hasWallpaper || customBg.blendThemeLights))
                  Positioned.fill(
                    // This painter animates for as long as the page is alive.
                    // Without a boundary it shares a layer with everything in
                    // the Stack below, so every one of its ~60 fps frames
                    // invalidated the whole page subtree — lists, cards and
                    // glass panels re-rasterized continuously. Isolating it
                    // keeps the animation on its own layer.
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final speed =
                              HomePageSettings.ambientLightSpeed.value;
                          final intensity =
                              HomePageSettings.ambientLightIntensity.value;
                          final pattern =
                              HomePageSettings.ambientLightPattern.value;
                          final t = (_controller.value * speed) % 1.0;

                          return CustomPaint(
                            isComplex: true,
                            willChange: true,
                            painter: _AmbientBackgroundPainter(
                              t: t,
                              tokens: tokens,
                              pattern: pattern,
                              intensity: intensity,
                              isOverlay: hasWallpaper,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 4. Foreground Content
                if (widget.child != null)
                  Positioned.fill(
                    // Keeps scrolling/paging inside the page from re-rasterizing
                    // the animated layers above it, and vice versa.
                    child: RepaintBoundary(child: widget.child!),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AmbientBackgroundPainter extends CustomPainter {
  final double t;
  final ZplayTokens tokens;
  final AmbientLightPattern pattern;
  final double intensity;
  final bool isOverlay;

  _AmbientBackgroundPainter({
    required this.t,
    required this.tokens,
    required this.pattern,
    required this.intensity,
    this.isOverlay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // If not acting as an overlay on top of a wallpaper, draw base deep background
    if (!isOverlay) {
      final bgPaint = Paint()..color = tokens.bg;
      canvas.drawRect(rect, bgPaint);
    }

    final angle = t * 2 * math.pi;
    final accent = tokens.accent;

    switch (pattern) {
      case AmbientLightPattern.dualOrbs:
        _drawDualOrbs(canvas, size, angle, accent);
        break;
      case AmbientLightPattern.topAurora:
        _drawTopAurora(canvas, size, angle, accent);
        break;
      case AmbientLightPattern.fullMesh:
        _drawFullMesh(canvas, size, angle, accent);
        break;
      case AmbientLightPattern.centerPulse:
        _drawCenterPulse(canvas, size, angle, accent);
        break;
    }
  }

  void _drawDualOrbs(Canvas canvas, Size size, double angle, Color accent) {
    // Orb 1 (Top-Left drifting diagonally)
    final cx1 = size.width * (0.22 + 0.12 * math.sin(angle));
    final cy1 = size.height * (0.18 + 0.10 * math.cos(angle * 0.8));
    final r1 = math.max(size.width, size.height) * 0.48;

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: intensity * 0.95),
          accent.withValues(alpha: intensity * 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx1, cy1), radius: r1));

    canvas.drawCircle(Offset(cx1, cy1), r1, paint1);

    // Orb 2 (Bottom-Right floating opposite)
    final cx2 = size.width * (0.80 - 0.14 * math.cos(angle * 0.9));
    final cy2 = size.height * (0.70 + 0.12 * math.sin(angle * 0.7));
    final r2 = math.max(size.width, size.height) * 0.52;

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: intensity * 0.85),
          accent.withValues(alpha: intensity * 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx2, cy2), radius: r2));

    canvas.drawCircle(Offset(cx2, cy2), r2, paint2);
  }

  void _drawTopAurora(Canvas canvas, Size size, double angle, Color accent) {
    final wave1 = math.sin(angle) * 0.15;
    final wave2 = math.cos(angle * 1.3) * 0.12;

    // Crest 1
    final c1 = Offset(
      size.width * (0.35 + wave1),
      size.height * (0.10 + wave2),
    );
    final r1 = size.width * 0.65;
    final p1 = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: intensity * 1.1),
          accent.withValues(alpha: intensity * 0.45),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c1, radius: r1));

    canvas.drawCircle(c1, r1, p1);

    // Crest 2
    final c2 = Offset(
      size.width * (0.75 - wave2),
      size.height * (0.15 - wave1),
    );
    final r2 = size.width * 0.60;
    final p2 = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: intensity * 0.90),
          accent.withValues(alpha: intensity * 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: c2, radius: r2));

    canvas.drawCircle(c2, r2, p2);
  }

  void _drawFullMesh(Canvas canvas, Size size, double angle, Color accent) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.45;
    final r = math.max(size.width, size.height) * 0.70;

    final p1 = Paint()
      ..shader = RadialGradient(
        center: Alignment(math.sin(angle) * 0.3, math.cos(angle * 0.7) * 0.25),
        colors: [
          accent.withValues(alpha: intensity * 0.85),
          accent.withValues(alpha: intensity * 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    canvas.drawRect(Offset.zero & size, p1);
  }

  void _drawCenterPulse(Canvas canvas, Size size, double angle, Color accent) {
    final pulse = 0.85 + 0.15 * math.sin(angle);
    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    final r = math.min(size.width, size.height) * 0.65 * pulse;

    final p = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: intensity * 1.25),
          accent.withValues(alpha: intensity * 0.50),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    canvas.drawCircle(Offset(cx, cy), r, p);
  }

  @override
  bool shouldRepaint(covariant _AmbientBackgroundPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.tokens != tokens ||
        oldDelegate.pattern != pattern ||
        oldDelegate.intensity != intensity ||
        oldDelegate.isOverlay != isOverlay;
  }
}
