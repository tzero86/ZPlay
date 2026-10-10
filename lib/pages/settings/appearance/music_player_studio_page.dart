import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/music/music_settings.dart';
import '../../../widgets/common/animated_ambient_background.dart';
import '../../../widgets/common/segmented_tabs.dart';
import '../../../widgets/music/music_interactive_physics_button.dart';
import '../../../widgets/music/music_waveform_seekbar.dart';

class MusicPlayerStudioPage extends StatefulWidget {
  const MusicPlayerStudioPage({super.key});

  @override
  State<MusicPlayerStudioPage> createState() => _MusicPlayerStudioPageState();
}

class _MusicPlayerStudioPageState extends State<MusicPlayerStudioPage> with SingleTickerProviderStateMixin {
  // Live Studio Preview State
  bool _previewIsPlaying = true;
  Duration _previewPosition = const Duration(minutes: 1, seconds: 48);
  final Duration _previewDuration = const Duration(minutes: 3, seconds: 52);
  double _previewVolume = 0.85;
  bool _previewIsLiked = true;
  bool _showLyricsPreview = false;
  bool _showQueuePreview = false;

  late AnimationController _discController;
  int _selectedStudioTab = 0; // 0: Drag & Drop Arranger, 1: Seekbar Canvas, 2: Buttons & Physics, 3: Artwork & Turntable
  int _mobileViewMode = 0; // 0: Studio Designer, 1: Live Interactive Canvas

  @override
  void initState() {
    super.initState();
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    MusicSettings.changeNotifier.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MusicSettings.changeNotifier.removeListener(_onSettingsChanged);
    _discController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _previewIsPlaying = !_previewIsPlaying;
      if (_previewIsPlaying) {
        _discController.repeat();
      } else {
        _discController.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;
    final screenW = MediaQuery.sizeOf(context).width;
    final isDesktop = screenW >= 960;

    return AnimatedAmbientBackground(child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        // Transparent, no hairline: the page's own canvas is the band, exactly
        // as `SettingsAppBar` does it for the pages that share a bare header.
        // This page only hand-rolls its bar because its title carries a second
        // line and a glyph, which `SettingsAppBar`'s single `String` cannot hold.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: screenW < 600
            ? Text(
                'Music Player Studio',
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [palette.primaryColor, palette.accentColor],
                      ),
                    ),
                    child: Icon(Icons.dashboard_customize_rounded, color: tokens.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Custom Music Player Studio',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Design the fullscreen player, drag components, customize physics & liquid glass',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (screenW < 520)
            IconButton(
              tooltip: 'Apply As Active Player',
              onPressed: _applyAsActivePlayer,
              icon: Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 24),
            )
          else
            TextButton.icon(
              onPressed: _applyAsActivePlayer,
              icon: Icon(Icons.check_circle_rounded, color: tokens.textPrimary, size: 18),
              label: Text('Apply Active', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
              style: TextButton.styleFrom(
                backgroundColor: palette.primaryColor.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                // Left Panel: Interactive Live Player Canvas Preview
                Expanded(
                  flex: 5,
                  child: _buildLivePlayerCanvas(palette, isDesktop: true),
                ),
                VerticalDivider(width: 1, color: tokens.borderDefault),
                // Right Panel: Customizer Studio Controls
                Expanded(
                  flex: 6,
                  child: _buildStudioControlsPanel(palette),
                ),
              ],
            )
          : Column(
              children: [
                // Mobile Mode Switcher Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mobileViewMode = 0),
                          borderRadius: ZplayRadius.smAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _mobileViewMode == 0 ? palette.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: ZplayRadius.smAll,
                              border: Border.all(
                                color: _mobileViewMode == 0 ? palette.primaryColor : tokens.borderSubtle,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 15,
                                  color: _mobileViewMode == 0 ? palette.primaryColor : tokens.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Studio Designer',
                                  style: ZplayType.label.toStyle(
                                    color: _mobileViewMode == 0 ? tokens.textPrimary : tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _mobileViewMode = 1),
                          borderRadius: ZplayRadius.smAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _mobileViewMode == 1 ? palette.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: ZplayRadius.smAll,
                              border: Border.all(
                                color: _mobileViewMode == 1 ? palette.primaryColor : tokens.borderSubtle,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 15,
                                  color: _mobileViewMode == 1 ? palette.primaryColor : tokens.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Live Preview Canvas',
                                  style: ZplayType.label.toStyle(
                                    color: _mobileViewMode == 1 ? tokens.textPrimary : tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Mobile View Content
                Expanded(
                  child: _mobileViewMode == 0
                      ? Stack(
                          children: [
                            _buildStudioControlsPanel(palette),
                            Positioned(
                              bottom: 16,
                              right: 16,
                              child: FloatingActionButton.extended(
                                onPressed: () => setState(() => _mobileViewMode = 1),
                                backgroundColor: palette.primaryColor,
                                icon: Icon(Icons.touch_app_rounded, color: tokens.textPrimary, size: 18),
                                label: Text(
                                  'Test Live Canvas',
                                  style: ZplayType.label.toStyle(color: tokens.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          children: [
                            _buildLivePlayerCanvas(palette, isDesktop: false),
                            Positioned(
                              bottom: 16,
                              left: 16,
                              child: FloatingActionButton.extended(
                                onPressed: () => setState(() => _mobileViewMode = 0),
                                backgroundColor: tokens.surfaceRaised,
                                icon: Icon(Icons.arrow_back_rounded, color: palette.primaryColor, size: 18),
                                label: Text(
                                  'Back to Customizer',
                                  style: ZplayType.label.toStyle(color: tokens.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    ));
  }

  void _applyAsActivePlayer() {
    final palette = AppThemeService.currentPalette.value;
    MusicSettings.setSelectedFullscreenPreset(MusicFullscreenPreset.customStudio);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Custom Fullscreen Player Studio layout set as active player!'),
        backgroundColor: palette.primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ── LEFT: INTERACTIVE LIVE PLAYER CANVAS PREVIEW ──
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLivePlayerCanvas(AppThemePalette palette, {bool isDesktop = true}) {
    // No page-chrome panel: the ambient canvas behind the scaffold is the band,
    // so only the simulated player itself is drawn here.
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background ambient light orb
        Positioned(
          top: 40,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.primaryColor.withValues(alpha: 0.14),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: const SizedBox.expand(),
          ),
        ),

        // Player Container Sandbox
        Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _buildFullscreenPlayerCard(palette, isDesktop),
            ),
          ),
        ),

        // Synced Lyrics Preview Overlay
        if (_showLyricsPreview)
          Positioned.fill(
            child: _buildLyricsPreviewOverlay(palette),
          ),

        // Queue Preview Overlay
        if (_showQueuePreview)
          Positioned.fill(
            child: _buildQueuePreviewOverlay(palette),
          ),
      ],
    );
  }

  Widget _buildFullscreenPlayerCard(AppThemePalette palette, bool isDesktop) {
    final tokens = context.tokens;
    final order = MusicSettings.componentOrderFullscreen.value;
    final seekStyle = MusicSettings.customSeekbarStyle.value;
    final artStyle = MusicSettings.customArtworkStyle.value;

    return Container(
      padding: EdgeInsets.all(isDesktop ? 22 : 14),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.9),
        borderRadius: ZplayRadius.xlAll,
        border: Border.all(
          color: palette.primaryColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.primaryColor.withValues(alpha: 0.2),
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note_rounded, color: palette.primaryColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'FULLSCREEN LIVE STUDIO',
                      style: ZplayType.overline.toStyle(color: palette.primaryColor),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _previewIsLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _previewIsLiked ? tokens.accent : tokens.textEmphasis,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _previewIsLiked = !_previewIsLiked),
                  ),
                  IconButton(
                    icon: Icon(Icons.format_quote_rounded, color: _showLyricsPreview ? palette.primaryColor : tokens.textEmphasis, size: 20),
                    onPressed: () => setState(() => _showLyricsPreview = !_showLyricsPreview),
                  ),
                  IconButton(
                    icon: Icon(Icons.queue_music_rounded, color: _showQueuePreview ? palette.primaryColor : tokens.textEmphasis, size: 20),
                    onPressed: () => setState(() => _showQueuePreview = !_showQueuePreview),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Dynamic Components Rendered according to Drag & Drop Order
          ...order.map((key) => _buildFullscreenPreviewComponent(key, palette, seekStyle, artStyle)),
        ],
      ),
    );
  }

  Widget _buildFullscreenPreviewComponent(
    String key,
    AppThemePalette palette,
    MusicSeekbarStyle seekStyle,
    MusicArtworkStyle artStyle,
  ) {
    final tokens = context.tokens;
    switch (key) {
      case 'artwork':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildPreviewArtwork(palette, artStyle),
        );

      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            children: [
              Text(
                'Starboy (feat. Daft Punk)',
                textAlign: TextAlign.center,
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'The Weeknd • Starboy (Deluxe)',
                textAlign: TextAlign.center,
                style: ZplayType.body.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );

      case 'qualityBadge':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.info.withValues(alpha: 0.15),
              borderRadius: ZplayRadius.xsAll,
              border: Border.all(color: tokens.info.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.diamond_rounded, size: 12, color: tokens.info),
                const SizedBox(width: 4),
                Text(
                  'FLAC 24-BIT / 96KHZ LOSSLESS',
                  style: ZplayType.overline.toStyle(color: tokens.info),
                ),
              ],
            ),
          ),
        );

      case 'seekbar':
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: MusicWaveformSeekbar(
            position: _previewPosition,
            duration: _previewDuration,
            isPlaying: _previewIsPlaying,
            style: seekStyle,
            onSeek: (pos) => setState(() => _previewPosition = pos),
          ),
        );

      case 'mainControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCanvasIconButton(Icons.shuffle_rounded, 22, palette, () {}),
              _buildCanvasIconButton(Icons.skip_previous_rounded, 28, palette, () {}),
              _buildCustomPlayPauseButton(palette),
              _buildCanvasIconButton(Icons.skip_next_rounded, 28, palette, () {}),
              _buildCanvasIconButton(Icons.repeat_rounded, 22, palette, () {}),
            ],
          ),
        );

      case 'secondaryControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.volume_down_rounded, color: tokens.textSecondary, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    activeTrackColor: palette.primaryColor,
                    inactiveTrackColor: Colors.white.withValues(
                      alpha: ZplayOpacity.borderMedium,
                    ),
                    thumbColor: tokens.textPrimary,
                  ),
                  child: Slider(
                    value: _previewVolume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => setState(() => _previewVolume = v),
                  ),
                ),
              ),
              Icon(Icons.volume_up_rounded, color: tokens.textSecondary, size: 18),
            ],
          ),
        );

      case 'extraActions':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _showLyricsPreview = true),
                icon: Icon(Icons.format_quote_rounded, color: palette.primaryColor, size: 15),
                label: Text('Synced Lyrics', style: ZplayType.caption.toStyle(color: tokens.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showQueuePreview = true),
                icon: Icon(Icons.queue_music_rounded, color: palette.primaryColor, size: 15),
                label: Text('Playing Queue', style: ZplayType.caption.toStyle(color: tokens.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPreviewArtwork(AppThemePalette palette, MusicArtworkStyle artStyle) {
    final tokens = context.tokens;
    if (artStyle == MusicArtworkStyle.vinylSpinningDisc) {
      return AnimatedBuilder(
        animation: _discController,
        builder: (context, child) => Transform.rotate(
          angle: _previewIsPlaying ? _discController.value * 2 * pi : 0,
          child: child,
        ),
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
            border: Border.all(
              color: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
              width: 3.5,
            ),
          ),
          child: Center(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [palette.primaryColor, palette.accentColor],
                ),
                border: Border.all(color: tokens.textPrimary, width: 2),
              ),
              child: Icon(Icons.music_note_rounded, color: tokens.textPrimary, size: 20),
            ),
          ),
        ),
      );
    }

    if (artStyle == MusicArtworkStyle.floatingCard3D) {
      return Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.lgAll,
          gradient: LinearGradient(
            colors: [palette.primaryColor.withValues(alpha: 0.45), tokens.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
          ),
        ),
        child: Icon(Icons.album_rounded, color: tokens.textPrimary, size: 54),
      );
    }

    if (artStyle == MusicArtworkStyle.glowSphere) {
      return Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              palette.primaryColor.withValues(alpha: 0.8),
              palette.accentColor.withValues(alpha: 0.3),
              tokens.surface,
            ],
          ),
          border: Border.all(color: palette.primaryColor, width: 2),
        ),
        child: Icon(Icons.graphic_eq_rounded, color: tokens.textPrimary, size: 48),
      );
    }

    // Default: 3D Rounded Square
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.lgAll,
        border: Border.all(color: palette.primaryColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Icon(Icons.music_note_rounded, color: tokens.textPrimary, size: 52),
    );
  }

  Widget _buildCustomPlayPauseButton(AppThemePalette palette) {
    final tokens = context.tokens;
    final style = MusicSettings.customPlayButtonStyle.value;
    final hoverEffect = MusicSettings.customHoverEffect.value;
    final icon = _previewIsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    const size = 54.0;
    const iconSize = 32.0;

    Widget buttonCore;
    BorderRadius borderRadius;

    if (style == MusicPlayButtonStyle.liquidGlassNeo) {
      borderRadius = ZplayRadius.mdAll;
      final glassStyle = LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: ZplayRadius.md,
          clipQuality: LiquidGlassClipQuality.exact,
          borderWidth: 1.5,
          lightIntensity: 1.5,
          lightColor: Colors.white.withValues(alpha: ZplayOpacity.textPrimary),
          lightDirection: 115,
          borderType: const OpticalBorder(
            borderSaturation: 1.5,
            ambientIntensity: 1.2,
            borderSolidity: 0.2,
            lightSpread: 0.7,
          ),
        ),
        appearance: LiquidGlassAppearance(
          color: palette.primaryColor.withValues(alpha: 0.15),
          saturation: 1.2,
          blur: const LiquidGlassBlur(sigmaX: 3.0, sigmaY: 3.0),
          shadow: LiquidGlassShadow(
            blur: 16,
            opacity: 0.4,
            color: palette.primaryColor,
          ),
        ),
        refraction: const LiquidGlassRefraction(
          magnification: 1.04,
          chromaticAberration: 0.0035,
          refractionType: OpticalRefraction(
            refraction: 1.55,
            refractionWidth: 22,
            depth: 0.8,
          ),
        ),
      );

      buttonCore = LiquidGlassLens(
        style: glassStyle,
        visibility: true,
        useImpellerBackdrop: true,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: tokens.textPrimary, size: iconSize),
        ),
      );
    } else if (style == MusicPlayButtonStyle.neonSquare) {
      borderRadius = ZplayRadius.mdAll;
      buttonCore = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [palette.primaryColor, palette.accentColor],
          ),
        ),
        child: Icon(icon, color: tokens.textPrimary, size: iconSize),
      );
    } else if (style == MusicPlayButtonStyle.pillPulse) {
      borderRadius = ZplayRadius.fullAll;
      buttonCore = Container(
        width: 72,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: palette.primaryColor,
        ),
        child: Icon(icon, color: tokens.textPrimary, size: iconSize),
      );
    } else {
      // Circle (the fallback core shape).
      borderRadius = ZplayRadius.fullAll;
      buttonCore = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [palette.primaryColor, palette.accentColor],
          ),
        ),
        child: Icon(icon, color: tokens.textPrimary, size: iconSize),
      );
    }

    return MusicInteractivePhysicsButton(
      effect: hoverEffect,
      glowColor: palette.primaryColor,
      borderRadius: borderRadius,
      onTap: _togglePlayPause,
      child: buttonCore,
    );
  }

  Widget _buildCanvasIconButton(IconData icon, double size, AppThemePalette palette, VoidCallback onTap) {
    final tokens = context.tokens;
    return MusicInteractivePhysicsButton(
      effect: MusicSettings.customHoverEffect.value,
      glowColor: palette.primaryColor,
      borderRadius: ZplayRadius.smAll,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: tokens.textPrimary, size: size),
      ),
    );
  }

  Widget _buildLyricsPreviewOverlay(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      // Full-bleed dim scrim over the canvas this panel previews.
      color: tokens.bg.withValues(alpha: 0.8),
      child: Center(
        child: Container(
          width: 380,
          height: 320,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: ZplayRadius.lgAll,
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Synced Lyrics Sandbox', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: tokens.textEmphasis, size: 18),
                    onPressed: () => setState(() => _showLyricsPreview = false),
                  ),
                ],
              ),
              Divider(color: tokens.borderStrong),
              Expanded(
                child: ListView(
                  children: [
                    Text('I\'m tryna put you in the worst mood, ah', style: ZplayType.body.toStyle(color: tokens.textMuted)),
                    const SizedBox(height: 12),
                    Text('P1 cleaner than your church shoes, ah', style: ZplayType.title.toStyle(color: palette.primaryColor)),
                    const SizedBox(height: 12),
                    Text('Milli point two just to hurt you, ah', style: ZplayType.body.toStyle(color: tokens.textMuted)),
                    const SizedBox(height: 12),
                    Text('All red Lamb\' just to tease you, ah', style: ZplayType.body.toStyle(color: tokens.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueuePreviewOverlay(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      // Full-bleed dim scrim over the canvas this panel previews.
      color: tokens.bg.withValues(alpha: 0.8),
      child: Center(
        child: Container(
          width: 380,
          height: 320,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: ZplayRadius.lgAll,
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Playing Queue Sandbox (4 Tracks)', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: tokens.textEmphasis, size: 18),
                    onPressed: () => setState(() => _showQueuePreview = false),
                  ),
                ],
              ),
              Divider(color: tokens.borderStrong),
              Expanded(
                child: ListView(
                  children: [
                    _buildQueueItem(1, 'Starboy', 'The Weeknd', true, palette),
                    _buildQueueItem(2, 'Party Monster', 'The Weeknd', false, palette),
                    _buildQueueItem(3, 'False Alarm', 'The Weeknd', false, palette),
                    _buildQueueItem(4, 'Reminder', 'The Weeknd', false, palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueItem(int num, String title, String artist, bool active, AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? palette.primaryColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: ZplayOpacity.borderFaint),
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: active ? palette.primaryColor : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(active ? Icons.equalizer_rounded : Icons.music_note_rounded, color: active ? palette.primaryColor : tokens.textSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$title • $artist', style: ZplayType.bodySmall.toStyle(color: active ? tokens.textPrimary : tokens.textEmphasis)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ── RIGHT: STUDIO CUSTOMIZATION CONTROLS PANEL ──
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStudioControlsPanel(AppThemePalette palette) {
    // No page-chrome panel: the ambient canvas behind the scaffold is the band.
    return Column(
      children: [
        // Studio Sub-Tabs
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildTabChip(0, Icons.drag_indicator_rounded, 'Drag & Drop Layout', palette),
              _buildTabChip(1, Icons.graphic_eq_rounded, 'Seek Bar Canvas', palette),
              _buildTabChip(2, Icons.touch_app_rounded, 'Play Button & Physics', palette),
              _buildTabChip(3, Icons.album_rounded, 'Artwork & Turntable', palette),
            ],
          ),
        ),

        // Active Tab Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            physics: const BouncingScrollPhysics(),
            children: [
              if (_selectedStudioTab == 0) _buildDragAndDropLayoutSection(palette),
              if (_selectedStudioTab == 1) _buildSeekbarCanvasSection(palette),
              if (_selectedStudioTab == 2) _buildPlayButtonPhysicsSection(palette),
              if (_selectedStudioTab == 3) _buildArtworkTurntableSection(palette),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabChip(int index, IconData icon, String label, AppThemePalette palette) {
    final tokens = context.tokens;
    final isSelected = _selectedStudioTab == index;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, color: isSelected ? tokens.textPrimary : tokens.textSecondary, size: 16),
        label: Text(label),
        selected: isSelected,
        selectedColor: palette.primaryColor,
        backgroundColor: tokens.surface,
        labelStyle: ZplayType.label.toStyle(
          color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
        ),
        side: BorderSide(color: isSelected ? palette.primaryColor : tokens.borderDefault),
        onSelected: (val) {
          if (val) setState(() => _selectedStudioTab = index);
        },
      ),
    );
  }

  // ── Tab 0: Drag & Drop Reorderable Components ──
  Widget _buildDragAndDropLayoutSection(AppThemePalette palette) {
    final tokens = context.tokens;
    final componentNames = {
      'artwork': 'Album Art & Vinyl Turntable',
      'title': 'Track, Artist & Album Titles',
      'trackInfo': 'Track Title & Quality Badge',
      'qualityBadge': 'Lossless Hi-Res Audio Quality Badge',
      'seekbar': 'Seek Bar Scrubber Canvas',
      'mainControls': 'Primary Controls (Play, Pause, Skip, Shuffle, Repeat)',
      'secondaryControls': 'Secondary Controls (Volume Slider)',
      'extraActions': 'Synced Lyrics & Queue Quick Buttons',
    };

    final componentIcons = {
      'artwork': Icons.album_rounded,
      'title': Icons.title_rounded,
      'trackInfo': Icons.music_note_rounded,
      'qualityBadge': Icons.diamond_rounded,
      'seekbar': Icons.graphic_eq_rounded,
      'mainControls': Icons.play_circle_filled_rounded,
      'secondaryControls': Icons.volume_up_rounded,
      'extraActions': Icons.extension_rounded,
    };

    return ValueListenableBuilder<List<String>>(
      valueListenable: MusicSettings.componentOrderFullscreen,
      builder: (context, order, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.drag_indicator_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Fullscreen Player Drag & Drop Arranger',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Hold and drag any block to reorder the layout of your fullscreen player in real-time.',
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),

            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) {
                MusicSettings.reorderFullscreenComponents(oldIdx, newIdx);
              },
              children: List.generate(order.length, (index) {
                final key = order[index];
                final name = componentNames[key] ?? key;
                final icon = componentIcons[key] ?? Icons.widgets_rounded;

                return ReorderableDelayedDragStartListener(
                  key: ValueKey(key),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(Icons.drag_handle_rounded, color: palette.primaryColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: palette.primaryColor.withValues(alpha: 0.15),
                              borderRadius: ZplayRadius.smAll,
                            ),
                            child: Icon(icon, color: palette.primaryColor, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: ZplayType.label.toStyle(color: tokens.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 1: Seekbar Canvas Section ──
  Widget _buildSeekbarCanvasSection(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<MusicSeekbarStyle>(
      valueListenable: MusicSettings.customSeekbarStyle,
      builder: (context, activeStyle, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Seek Bar Canvas Scrubber Engine',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select how audio waveforms and scrubbing tracks render across your music player.',
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),

            ...MusicSeekbarStyle.values.map((s) {
              final isSelected = activeStyle == s;
              return InkWell(
                onTap: () => MusicSettings.setCustomSeekbarStyle(s),
                borderRadius: ZplayRadius.mdAll,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? tokens.accentSubtle : tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.all(
                      color: isSelected ? palette.primaryColor : tokens.borderDefault,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? palette.primaryColor : tokens.borderDefault,
                          borderRadius: ZplayRadius.smAll,
                        ),
                        child: Icon(
                          s == MusicSeekbarStyle.waveformEqualizer
                              ? Icons.graphic_eq_rounded
                              : s == MusicSeekbarStyle.neonGradient
                                  ? Icons.linear_scale_rounded
                                  : s == MusicSeekbarStyle.liquidGlassSlider
                                      ? Icons.blur_on_rounded
                                      : s == MusicSeekbarStyle.radialDial
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.tune_rounded,
                          color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              style: ZplayType.label.toStyle(color: tokens.textPrimary),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.description,
                              style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 20),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ── Tab 2: Play Button & Hover Physics ──
  Widget _buildPlayButtonPhysicsSection(AppThemePalette palette) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.play_circle_filled_rounded, color: palette.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Play Button Aesthetic & Style',
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ValueListenableBuilder<MusicPlayButtonStyle>(
          valueListenable: MusicSettings.customPlayButtonStyle,
          builder: (context, activeBtnStyle, _) {
            return SegmentedTabs<MusicPlayButtonStyle>(
              selected: activeBtnStyle,
              onSelected: (b) {
                MusicSettings.setCustomPlayButtonStyle(b);
              },
              options: [
                for (final b in MusicPlayButtonStyle.values)
                  SegmentedTabOption(value: b, label: b.label),
              ],
            );
          },
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.touch_app_rounded, color: palette.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Hover & Touch Physics Engine',
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Select the interactive physics feedback applied when hovering or pressing controls.',
          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: 12),

        ValueListenableBuilder<MusicHoverEffect>(
          valueListenable: MusicSettings.customHoverEffect,
          builder: (context, activeHover, _) {
            return SegmentedTabs<MusicHoverEffect>(
              selected: activeHover,
              onSelected: (h) {
                MusicSettings.setCustomHoverEffect(h);
              },
              options: [
                for (final h in MusicHoverEffect.values)
                  SegmentedTabOption(value: h, label: h.label),
              ],
            );
          },
        ),

        const SizedBox(height: 24),
        // Live Physics Testing Pad
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Live Physics Testing Pad',
                style: ZplayType.label.toStyle(color: palette.primaryColor),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCanvasIconButton(Icons.skip_previous_rounded, 24, palette, () {}),
                  _buildCustomPlayPauseButton(palette),
                  _buildCanvasIconButton(Icons.skip_next_rounded, 24, palette, () {}),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 3: Artwork & Turntable Section ──
  Widget _buildArtworkTurntableSection(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<MusicArtworkStyle>(
      valueListenable: MusicSettings.customArtworkStyle,
      builder: (context, activeArt, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.album_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Artwork & Turntable Presentation',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select how album covers, vinyl turntable animations, and cards display in the player.',
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),

            ...MusicArtworkStyle.values.map((a) {
              final isSelected = activeArt == a;
              return InkWell(
                onTap: () => MusicSettings.setCustomArtworkStyle(a),
                borderRadius: ZplayRadius.mdAll,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? tokens.accentSubtle : tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.all(
                      color: isSelected ? palette.primaryColor : tokens.borderDefault,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? palette.primaryColor : tokens.borderDefault,
                          borderRadius: ZplayRadius.smAll,
                        ),
                        child: Icon(
                          a == MusicArtworkStyle.vinylSpinningDisc
                              ? Icons.album_rounded
                              : a == MusicArtworkStyle.floatingCard3D
                                  ? Icons.view_carousel_rounded
                                  : a == MusicArtworkStyle.glowSphere
                                      ? Icons.blur_on_rounded
                                      : Icons.crop_square_rounded,
                          color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          a.label,
                          style: ZplayType.label.toStyle(color: tokens.textPrimary),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 20),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
