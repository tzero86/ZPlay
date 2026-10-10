import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/audiobook/audiobook_settings.dart';
import '../../../widgets/audiobook/audiobook_interactive_physics_button.dart';
import '../../../widgets/audiobook/audiobook_waveform_seekbar.dart';
import '../../../widgets/common/animated_ambient_background.dart';

class AudiobookPlayerStudioPage extends StatefulWidget {
  const AudiobookPlayerStudioPage({super.key});

  @override
  State<AudiobookPlayerStudioPage> createState() => _AudiobookPlayerStudioPageState();
}

class _AudiobookPlayerStudioPageState extends State<AudiobookPlayerStudioPage> with SingleTickerProviderStateMixin {
  // Live Studio Preview State
  bool _previewIsPlaying = true;
  Duration _previewPosition = const Duration(minutes: 14, seconds: 32);
  final Duration _previewDuration = const Duration(minutes: 45, seconds: 00);
  double _previewSpeed = 1.0;
  double _previewVolume = 0.85;
  bool _showChaptersPreview = false;

  late AnimationController _discController;
  int _selectedStudioTab = 0; // 0: Layout Drag & Drop, 1: Seekbar Canvas, 2: Buttons & Physics, 3: Artwork & Atmosphere
  int _mobileViewMode = 0; // 0: Studio Designer, 1: Live Interactive Canvas

  @override
  void initState() {
    super.initState();
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    AudiobookSettings.changeNotifier.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AudiobookSettings.changeNotifier.removeListener(_onSettingsChanged);
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
                'Player Studio',
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
                    child: Icon(Icons.dashboard_customize_rounded, color: tokens.onAccent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Custom Audiobook Player Studio',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Drag components, transform seekbars, customize button physics',
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
              onPressed: () {
                AudiobookSettings.setSelectedPlayerPreset(AudiobookPlayerPreset.customStudio);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Custom Player Studio layout applied & set as active player!'),
                    backgroundColor: palette.primaryColor,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 24),
            )
          else
            TextButton.icon(
              onPressed: () {
                AudiobookSettings.setSelectedPlayerPreset(AudiobookPlayerPreset.customStudio);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Custom Player Studio layout applied & set as active player!'),
                    backgroundColor: palette.primaryColor,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: Icon(Icons.check_circle_rounded, color: tokens.onAccent, size: 18),
              label: Text('Apply As Active Player', style: ZplayType.label.toStyle(color: tokens.onAccent)),
              style: TextButton.styleFrom(
                backgroundColor: palette.primaryColor.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                    color: _mobileViewMode == 0
                                        ? tokens.textPrimary
                                        : tokens.textSecondary,
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
                                    color: _mobileViewMode == 1
                                        ? tokens.textPrimary
                                        : tokens.textSecondary,
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
                // Mobile Mode Viewport
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
                                icon: Icon(Icons.touch_app_rounded, color: tokens.onAccent, size: 18),
                                label: Text(
                                  'Test Live Canvas',
                                  style: ZplayType.label.toStyle(color: tokens.onAccent),
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

  // ═══════════════════════════════════════════════════════════════
  // ── LEFT: INTERACTIVE LIVE PLAYER CANVAS PREVIEW ──
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLivePlayerCanvas(AppThemePalette palette, {bool isDesktop = true}) {
    final tokens = context.tokens;
    final order = AudiobookSettings.componentOrder.value;
    final seekStyle = AudiobookSettings.customSeekbarStyle.value;
    final artStyle = AudiobookSettings.customArtworkStyle.value;

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
              color: palette.primaryColor.withValues(alpha: 0.12),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: const SizedBox.expand(),
          ),
        ),

        // Player Container
        Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
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
                              Icon(Icons.touch_app_rounded, color: palette.primaryColor, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'LIVE INTERACTIVE CANVAS',
                                style: ZplayType.overline.toStyle(color: palette.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'CUSTOM STUDIO',
                          style: ZplayType.overline.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Components Rendered according to Drag & Drop Order
                    ...order.map((key) => _buildPreviewComponent(key, palette, seekStyle, artStyle)),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Chapters Slide-in Drawer Preview Overlay
        if (_showChaptersPreview)
          Positioned.fill(
            child: _buildChaptersPreviewOverlay(palette),
          ),
      ],
    );
  }

  Widget _buildPreviewComponent(
    String key,
    AppThemePalette palette,
    AudiobookSeekbarStyle seekStyle,
    AudiobookArtworkStyle artStyle,
  ) {
    final tokens = context.tokens;
    switch (key) {
      case 'artwork':
        if (artStyle == AudiobookArtworkStyle.hidden) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildPreviewArtwork(palette, artStyle),
        );

      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              Text(
                'Chapter 4: The Secrets of the Night',
                textAlign: TextAlign.center,
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Chapter 4 of 24 • Harry Potter & The Sorcerer\'s Stone',
                textAlign: TextAlign.center,
                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );

      case 'seekbar':
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AudiobookWaveformSeekbar(
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
              _buildCanvasIconButton(Icons.skip_previous_rounded, 24, palette, () {}),
              _buildCanvasIconButton(
                Icons.replay_10_rounded,
                24,
                palette,
                () => setState(() => _previewPosition = Duration(seconds: max(0, _previewPosition.inSeconds - 10))),
              ),
              _buildCustomPlayPauseButton(palette),
              _buildCanvasIconButton(
                Icons.forward_10_rounded,
                24,
                palette,
                () => setState(() => _previewPosition = Duration(seconds: min(_previewDuration.inSeconds, _previewPosition.inSeconds + 10))),
              ),
              _buildCanvasIconButton(Icons.skip_next_rounded, 24, palette, () {}),
            ],
          ),
        );

      case 'secondaryControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speed Pill
              InkWell(
                onTap: () {
                  final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                  final next = speeds[(speeds.indexOf(_previewSpeed) + 1) % speeds.length];
                  setState(() => _previewSpeed = next);
                },
                borderRadius: ZplayRadius.smAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: ZplayRadius.smAll,
                    border: Border.all(color: tokens.borderDefault),
                  ),
                  child: Text(
                    '${_previewSpeed}x Speed',
                    style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Volume Icon
              Icon(Icons.volume_up_rounded, color: palette.primaryColor, size: 20),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    activeTrackColor: palette.primaryColor,
                    inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
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
            ],
          ),
        );

      case 'chaptersButton':
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _showChaptersPreview = true),
            icon: Icon(Icons.format_list_bulleted_rounded, color: palette.primaryColor, size: 16),
            label: Text('Premade Chapters Panel', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPreviewArtwork(AppThemePalette palette, AudiobookArtworkStyle artStyle) {
    final tokens = context.tokens;
    if (artStyle == AudiobookArtworkStyle.vinylDisc) {
      return AnimatedBuilder(
        animation: _discController,
        builder: (context, child) => Transform.rotate(
          angle: _previewIsPlaying ? _discController.value * 2 * pi : 0,
          child: child,
        ),
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
            border: Border.all(color: tokens.borderStrong, width: 3),
          ),
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.bg,
                border: Border.all(color: palette.primaryColor, width: 2),
              ),
            ),
          ),
        ),
      );
    }

    if (artStyle == AudiobookArtworkStyle.floatingCard) {
      return Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          gradient: LinearGradient(
            colors: [palette.primaryColor.withValues(alpha: 0.4), tokens.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: tokens.borderStrong),
        ),
        child: Icon(Icons.headphones_rounded, color: tokens.onAccent, size: 48),
      );
    }

    // Default: 3D Rounded Square
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Icon(Icons.menu_book_rounded, color: tokens.textEmphasis, size: 46),
    );
  }

  Widget _buildCustomPlayPauseButton(AppThemePalette palette) {
    final tokens = context.tokens;
    final style = AudiobookSettings.customPlayButtonStyle.value;
    final hoverEffect = AudiobookSettings.customHoverEffect.value;
    final icon = _previewIsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;

    Widget buttonCore;
    BorderRadius borderRadius;

    if (style == AudiobookPlayButtonStyle.liquidGlassNeo) {
      borderRadius = ZplayRadius.mdAll;
      final glassStyle = LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 18,
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
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: tokens.onAccent, size: 30),
        ),
      );
    } else if (style == AudiobookPlayButtonStyle.roundedSquare) {
      borderRadius = ZplayRadius.mdAll;
      buttonCore = Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
        ),
        child: Icon(icon, color: tokens.onAccent, size: 28),
      );
    } else if (style == AudiobookPlayButtonStyle.accentPill) {
      borderRadius = ZplayRadius.lgAll;
      buttonCore = Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.onAccent, size: 20),
            const SizedBox(width: 4),
            Text(
              _previewIsPlaying ? 'PAUSE' : 'PLAY',
              style: ZplayType.label.toStyle(color: tokens.onAccent),
            ),
          ],
        ),
      );
    } else {
      borderRadius = ZplayRadius.xlAll;
      buttonCore = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primaryColor,
        ),
        child: Icon(icon, color: tokens.onAccent, size: 32),
      );
    }

    return AudiobookInteractivePhysicsButton(
      effect: hoverEffect,
      glowColor: palette.primaryColor,
      borderRadius: borderRadius,
      onTap: _togglePlayPause,
      child: buttonCore,
    );
  }

  Widget _buildCanvasIconButton(IconData icon, double size, AppThemePalette palette, VoidCallback onTap) {
    final tokens = context.tokens;
    return AudiobookInteractivePhysicsButton(
      effect: AudiobookSettings.customHoverEffect.value,
      glowColor: palette.primaryColor,
      borderRadius: BorderRadius.circular(size),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: size, color: tokens.textEmphasis),
      ),
    );
  }

  Widget _buildChaptersPreviewOverlay(AppThemePalette palette) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: () => setState(() => _showChaptersPreview = false),
      child: Container(
        color: tokens.bg.withValues(alpha: 0.7),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: ZplayRadius.sheetTop,
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Column(
                children: [
                  Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 6), decoration: BoxDecoration(color: tokens.textDisabled, borderRadius: ZplayRadius.xsAll)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Premade Chapters Panel Preview', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 18),
                          onPressed: () => setState(() => _showChaptersPreview = false),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: [
                        _buildSampleChapterTile(1, 'Chapter 1: The Boy Who Lived', false, palette),
                        _buildSampleChapterTile(2, 'Chapter 2: The Vanishing Glass', false, palette),
                        _buildSampleChapterTile(3, 'Chapter 3: The Letters from No One', false, palette),
                        _buildSampleChapterTile(4, 'Chapter 4: The Keeper of the Keys', true, palette),
                        _buildSampleChapterTile(5, 'Chapter 5: Diagon Alley', false, palette),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSampleChapterTile(int num, String title, bool isCurrent, AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? palette.primaryColor.withValues(alpha: 0.22) : tokens.surface,
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: isCurrent ? palette.primaryColor : tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: isCurrent ? palette.primaryColor : tokens.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: ZplayType.bodySmall.toStyle(color: isCurrent ? tokens.textPrimary : tokens.textEmphasis),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ── RIGHT: STUDIO CUSTOMIZATION CONTROLS PANEL ──
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStudioControlsPanel(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      color: tokens.bg,
      child: Column(
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
                _buildTabChip(3, Icons.image_rounded, 'Artwork & Frame', palette),
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
                if (_selectedStudioTab == 3) _buildArtworkFrameSection(palette),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index, IconData icon, String label, AppThemePalette palette) {
    final tokens = context.tokens;
    final isSelected = _selectedStudioTab == index;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, color: isSelected ? tokens.onAccent : tokens.textSecondary, size: 16),
        label: Text(label),
        selected: isSelected,
        selectedColor: palette.primaryColor,
        backgroundColor: tokens.surface,
        labelStyle: ZplayType.label.toStyle(
          color: isSelected ? tokens.onAccent : tokens.textEmphasis,
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
      'artwork': 'Artwork & Vinyl Frame',
      'title': 'Chapter & Book Titles',
      'seekbar': 'Seek Bar Scrubber Canvas',
      'mainControls': 'Primary Controls (Play, Pause, Skip ±10s)',
      'secondaryControls': 'Secondary Controls (Speed Pill & Volume)',
      'chaptersButton': 'Premade Chapters Panel Button',
    };

    final componentIcons = {
      'artwork': Icons.image_rounded,
      'title': Icons.title_rounded,
      'seekbar': Icons.graphic_eq_rounded,
      'mainControls': Icons.play_circle_filled_rounded,
      'secondaryControls': Icons.tune_rounded,
      'chaptersButton': Icons.format_list_bulleted_rounded,
    };

    return ValueListenableBuilder<List<String>>(
      valueListenable: AudiobookSettings.componentOrder,
      builder: (context, order, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.drag_indicator_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Drag & Drop Component Arranger',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Hold and drag any block to reorder the vertical layout of your audio player in real-time.',
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),

            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) {
                AudiobookSettings.reorderComponents(oldIdx, newIdx);
              },
              children: List.generate(order.length, (index) {
                final key = order[index];
                final name = componentNames[key] ?? key;
                final icon = componentIcons[key] ?? Icons.widgets_rounded;

                return ReorderableDelayedDragStartListener(
                  key: ValueKey(key),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle_rounded, color: palette.primaryColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: palette.primaryColor, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                              ),
                              Text(
                                'Position #${index + 1}',
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // ── Tab 1: Seekbar Canvas Styles ──
  Widget _buildSeekbarCanvasSection(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<AudiobookSeekbarStyle>(
      valueListenable: AudiobookSettings.customSeekbarStyle,
      builder: (context, currentStyle, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Seek Bar Canvas & Scrubber Styles',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select how your progress bar and scrubber render inside your custom player canvas.',
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),

            ...AudiobookSeekbarStyle.values.map((s) {
              final isSelected = s == currentStyle;
              return InkWell(
                onTap: () => AudiobookSettings.setCustomSeekbarStyle(s),
                borderRadius: ZplayRadius.mdAll,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? palette.primaryColor.withValues(alpha: 0.16) : tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.all(
                      color: isSelected ? palette.primaryColor : tokens.borderDefault,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? palette.primaryColor : tokens.borderSubtle,
                        ),
                        child: Icon(
                          s == AudiobookSeekbarStyle.audioWaveformCanvas
                              ? Icons.graphic_eq_rounded
                              : s == AudiobookSeekbarStyle.gradientProgress
                                  ? Icons.linear_scale_rounded
                                  : s == AudiobookSeekbarStyle.standardSlider
                                      ? Icons.tune_rounded
                                      : Icons.radio_button_checked_rounded,
                          color: isSelected ? tokens.onAccent : tokens.textEmphasis,
                          size: 20,
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
            Icon(Icons.touch_app_rounded, color: palette.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Play / Pause Button Style',
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<AudiobookPlayButtonStyle>(
          valueListenable: AudiobookSettings.customPlayButtonStyle,
          builder: (context, currentBtnStyle, _) {
            return Column(
              children: AudiobookPlayButtonStyle.values.map((b) {
                final isSelected = b == currentBtnStyle;
                return InkWell(
                  onTap: () => AudiobookSettings.setCustomPlayButtonStyle(b),
                  borderRadius: ZplayRadius.mdAll,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? palette.primaryColor.withValues(alpha: 0.16) : tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: isSelected ? palette.primaryColor : tokens.borderDefault,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: isSelected ? palette.primaryColor : tokens.textMuted,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          b.label,
                          style: ZplayType.label.toStyle(
                            color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Icon(Icons.animation_rounded, color: palette.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Hover & Touch Physics',
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<AudiobookHoverEffect>(
          valueListenable: AudiobookSettings.customHoverEffect,
          builder: (context, currentHover, _) {
            return Column(
              children: AudiobookHoverEffect.values.map((h) {
                final isSelected = h == currentHover;
                return InkWell(
                  onTap: () => AudiobookSettings.setCustomHoverEffect(h),
                  borderRadius: ZplayRadius.mdAll,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? palette.primaryColor.withValues(alpha: 0.16) : tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: isSelected ? palette.primaryColor : tokens.borderDefault,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? palette.primaryColor : tokens.textMuted,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          h.label,
                          style: ZplayType.label.toStyle(
                            color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 20),

        // Live Touch & Hover Physics Playground
        ValueListenableBuilder<AudiobookHoverEffect>(
          valueListenable: AudiobookSettings.customHoverEffect,
          builder: (context, currentHover, _) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.touch_app_rounded, color: palette.primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Live Touch & Hover Physics Playground',
                        style: ZplayType.label.toStyle(color: tokens.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hover your cursor or tap below to feel "${currentHover.label}" in real-time:',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: AudiobookInteractivePhysicsButton(
                      effect: currentHover,
                      glowColor: palette.primaryColor,
                      borderRadius: ZplayRadius.lgAll,
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [palette.primaryColor, palette.accentColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: ZplayRadius.lgAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded, color: tokens.onAccent, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              'Test "${currentHover.label}"',
                              style: ZplayType.label.toStyle(color: tokens.onAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Tab 3: Artwork & Frame Styles ──
  Widget _buildArtworkFrameSection(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<AudiobookArtworkStyle>(
      valueListenable: AudiobookSettings.customArtworkStyle,
      builder: (context, currentArtStyle, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.image_rounded, color: palette.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Artwork Display Mode',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 14),

            ...AudiobookArtworkStyle.values.map((a) {
              final isSelected = a == currentArtStyle;
              return InkWell(
                onTap: () => AudiobookSettings.setCustomArtworkStyle(a),
                borderRadius: ZplayRadius.mdAll,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? palette.primaryColor.withValues(alpha: 0.16) : tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.all(
                      color: isSelected ? palette.primaryColor : tokens.borderDefault,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? palette.primaryColor : tokens.borderSubtle,
                        ),
                        child: Icon(
                          a == AudiobookArtworkStyle.square3D
                              ? Icons.crop_square_rounded
                              : a == AudiobookArtworkStyle.vinylDisc
                                  ? Icons.album_rounded
                                  : a == AudiobookArtworkStyle.floatingCard
                                      ? Icons.layers_rounded
                                      : Icons.visibility_off_rounded,
                          color: isSelected ? tokens.onAccent : tokens.textEmphasis,
                          size: 20,
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
