import 'package:flutter/material.dart';
import '../palette_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/audiobook/audiobook_settings.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../widgets/audiobook/audiobook_interactive_physics_button.dart';
import '../../../widgets/audiobook/audiobook_waveform_seekbar.dart';
import '../../../widgets/common/animated_ambient_background.dart';
import '../../../widgets/common/focusable_card.dart';
import '../../../widgets/common/segmented_tabs.dart';
import 'audiobook_player_studio_page.dart';

class AudiobookSettingsPage extends StatefulWidget {
  const AudiobookSettingsPage({super.key});

  @override
  State<AudiobookSettingsPage> createState() => _AudiobookSettingsPageState();
}

class _AudiobookSettingsPageState extends State<AudiobookSettingsPage> {
  // Mock player states for live interactive studio preview
  bool _previewIsPlaying = false;
  Duration _previewPosition = const Duration(minutes: 14, seconds: 20);
  final Duration _previewDuration = const Duration(minutes: 42, seconds: 15);
  double _previewSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        surfaceTintColor: Colors.transparent,
        // The shell family draws this header as an opaque palette band with a
        // bottom hairline rather than a translucent wash over the page.
        shape: Border(bottom: tokens.hairline),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Audiobook UI & Player Studio',
          style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── 1. Color Themes & Accents ──
              _buildSectionHeader('COLOR THEMES & ACCENTS'),
              const SizedBox(height: 12),
              _buildThemesGrid(),

              const SizedBox(height: 28),

              // ── 2. Ambient Background Lighting ──
              _buildSectionHeader('AMBIENT BACKGROUND LIGHTING & MOVING GLOWS'),
              const SizedBox(height: 12),
              _buildAmbientLightsCard(palette),

              const SizedBox(height: 28),

              // ── 3. Discovery & Posters ──
              _buildSectionHeader('DISCOVERY & AUDIOBOOK POSTERS'),
              const SizedBox(height: 12),
              _buildDiscoveryConfigCard(palette),

              const SizedBox(height: 28),

              // ── Enter Visual Player Studio Banner ──
              _buildEnterPlayerStudioBanner(palette),

              const SizedBox(height: 28),

              // ── 4. Player Presets ──
              _buildSectionHeader('CHOOSE AUDIO PLAYER PRESET'),
              const SizedBox(height: 12),
              _buildPlayerPresetSelector(palette),

              const SizedBox(height: 28),

              // ── 5. Make Your Custom Player Studio ──
              _buildSectionHeader('MAKE YOUR CUSTOM AUDIOBOOK PLAYER (DRAG & DROP STUDIO)'),
              const SizedBox(height: 12),
              _buildCustomPlayerStudioCard(palette),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final tokens = context.tokens;
    return Text(
      title,
      style: ZplayType.overline.toStyle(color: tokens.textMuted),
    );
  }

  // ── 1. Themes Grid ──
  Widget _buildThemesGrid() => const PalettePicker();

  // ── 2. Ambient Lighting Card ──
  Widget _buildAmbientLightsCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.enableAmbientLights,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Moving Ambient Atmosphere',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                subtitle: Text(
                  'Soft flowing glowing orbs and aurora waves themed to ${palette.name}',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setEnableAmbientLights(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          Text(
            'Lighting Flow Pattern',
            style: ZplayType.label.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AmbientLightPattern>(
            valueListenable: AudiobookSettings.ambientLightPattern,
            builder: (context, currentPattern, _) {
              return SegmentedTabs<AmbientLightPattern>(
                selected: currentPattern,
                onSelected: (p) {
                  AudiobookSettings.setAmbientLightPattern(p);
                },
                options: [
                  for (final p in AmbientLightPattern.values)
                    SegmentedTabOption(value: p, label: p.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Intensity Slider
          ValueListenableBuilder<double>(
            valueListenable: AudiobookSettings.ambientLightIntensity,
            builder: (context, intensity, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Glow Strength / Opacity', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
                      Text('${(intensity * 100).round()}%', style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: intensity,
                      min: 0.08,
                      max: 0.60,
                      divisions: 26,
                      onChanged: (val) => AudiobookSettings.setAmbientLightIntensity(val),
                    ),
                  ),
                ],
              );
            },
          ),

          // Speed Slider
          ValueListenableBuilder<double>(
            valueListenable: AudiobookSettings.ambientLightSpeed,
            builder: (context, speed, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Motion Drift Speed', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
                      Text('${speed.toStringAsFixed(1)}x', style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: speed,
                      min: 0.2,
                      max: 3.0,
                      divisions: 14,
                      onChanged: (val) => AudiobookSettings.setAmbientLightSpeed(val),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          // Atmosphere Live Preview Box
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: ZplayRadius.smAll,
              border: Border.all(color: tokens.borderDefault),
            ),
            child: ClipRRect(
              borderRadius: ZplayRadius.smAll,
              child: Stack(
                children: [
                  const Positioned.fill(child: AnimatedAmbientBackground()),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.5),
                        borderRadius: ZplayRadius.lgAll,
                        border: Border.all(color: tokens.borderStrong),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.headphones_rounded, color: palette.primaryColor, size: 14),
                          const SizedBox(width: 6),
                          Text('Live Atmosphere Preview', style: ZplayType.caption.toStyle(color: tokens.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Discovery & Posters Config Card ──
  Widget _buildDiscoveryConfigCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.enableSpotlight,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Hero Spotlight Carousel', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Featured bestselling audiobook showcase at the top of the hub', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setEnableSpotlight(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showContinueListening,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show "Continue Listening" Carousel', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Quick resume cards with chapter progress bar and direct play', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowContinueListening(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          Text('Audiobook Poster Card Density', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<AudiobookCardDensity>(
            valueListenable: AudiobookSettings.cardDensity,
            builder: (context, currentDensity, _) {
              return SegmentedTabs<AudiobookCardDensity>(
                selected: currentDensity,
                onSelected: (d) {
                  AudiobookSettings.setCardDensity(d);
                },
                options: [
                  for (final d in AudiobookCardDensity.values)
                    SegmentedTabOption(value: d, label: d.label),
                ],
              );
            },
          ),

          const SizedBox(height: 14),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showCategoryPills,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Quick Genre & Category Badges', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowCategoryPills(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showDurationBadge,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Audiobook Runtime / Total Duration', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowDurationBadge(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.cardHoverGlow,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Poster Card Hover Glow & Elevation', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setCardHoverGlow(val),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 4. Player Presets Selector ──
  Widget _buildPlayerPresetSelector(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<AudiobookPlayerPreset>(
      valueListenable: AudiobookSettings.selectedPlayerPreset,
      builder: (context, selectedPreset, _) {
        return Column(
          children: AudiobookPlayerPreset.values.map((preset) {
            final isSelected = preset == selectedPreset;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected ? palette.primaryColor.withValues(alpha: 0.12) : tokens.surface,
                borderRadius: ZplayRadius.mdAll,
                border: Border.all(
                  color: isSelected ? palette.primaryColor : tokens.borderDefault,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ListTile(
                onTap: () => AudiobookSettings.setSelectedPlayerPreset(preset),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected ? palette.primaryColor : tokens.borderSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    preset == AudiobookPlayerPreset.modernGlass
                        ? Icons.blur_on_rounded
                        : preset == AudiobookPlayerPreset.vinylStudio
                            ? Icons.album_rounded
                            : preset == AudiobookPlayerPreset.minimalCapsule
                                ? Icons.view_compact_rounded
                                : preset == AudiobookPlayerPreset.immersiveCanvas
                                    ? Icons.fullscreen_rounded
                                    : Icons.dashboard_customize_rounded,
                    color: isSelected ? tokens.onAccent : tokens.textEmphasis,
                    size: 22,
                  ),
                ),
                title: Text(
                  preset.label,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                subtitle: Text(
                  preset.description,
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (preset == AudiobookPlayerPreset.customStudio)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AudiobookPlayerStudioPage()),
                            );
                          },
                          icon: Icon(Icons.tune_rounded, size: 14, color: palette.primaryColor),
                          label: Text(
                            'Open Studio',
                            style: ZplayType.label.toStyle(color: palette.primaryColor),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                          ),
                        ),
                      ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 22),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ── Enter Visual Player Studio Banner ──
  Widget _buildEnterPlayerStudioBanner(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.lgAll,
        gradient: LinearGradient(
          colors: [
            palette.primaryColor.withValues(alpha: 0.28),
            palette.accentColor.withValues(alpha: 0.15),
            tokens.bg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: palette.primaryColor.withValues(alpha: 0.5),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primaryColor.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [palette.primaryColor, palette.accentColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primaryColor.withValues(alpha: 0.5),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Icon(Icons.dashboard_customize_rounded, color: tokens.onAccent, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Visual Custom Player Studio',
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.primaryColor.withValues(alpha: 0.3),
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          'FULL STUDIO',
                          style: ZplayType.overline.toStyle(color: palette.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Drag & drop layout elements, procedural waveform canvases, liquid glass buttons, and premade chapters panel in real-time.',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AudiobookPlayerStudioPage()),
                      );
                    },
                    icon: Icon(Icons.tune_rounded, size: 18, color: tokens.onAccent),
                    label: Text(
                      'Enter Custom Player Studio',
                      style: ZplayType.label.toStyle(color: tokens.onAccent),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryColor,
                      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      elevation: 4,
                      shadowColor: palette.primaryColor.withValues(alpha: 0.5),
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

  // ── 5. Make Your Custom Player Studio ──
  Widget _buildCustomPlayerStudioCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Interactive Player Studio Preview Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.bg,
              borderRadius: ZplayRadius.mdAll,
              border: Border.all(color: palette.primaryColor.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: palette.primaryColor.withValues(alpha: 0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_fix_high_rounded, color: palette.primaryColor, size: 16),
                        const SizedBox(width: 6),
                        Text('Interactive Studio Preview', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: palette.primaryColor.withValues(alpha: 0.2),
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Text(
                        'LIVE',
                        style: ZplayType.overline.toStyle(color: palette.primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Artwork Preview
                ValueListenableBuilder<AudiobookArtworkStyle>(
                  valueListenable: AudiobookSettings.customArtworkStyle,
                  builder: (context, artStyle, _) {
                    if (artStyle == AudiobookArtworkStyle.hidden) {
                      return const SizedBox.shrink();
                    }
                    if (artStyle == AudiobookArtworkStyle.vinylDisc) {
                      return Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.surface,
                          border: Border.all(color: tokens.textDisabled, width: 3),
                          boxShadow: [
                            BoxShadow(color: palette.primaryColor.withValues(alpha: 0.35), blurRadius: 16),
                          ],
                        ),
                        child: Center(
                          child: Icon(Icons.graphic_eq_rounded, color: palette.primaryColor, size: 36),
                        ),
                      );
                    }
                    return Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: ZplayRadius.mdAll,
                        gradient: LinearGradient(
                          colors: [palette.primaryColor, palette.accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: palette.primaryColor.withValues(alpha: 0.4), blurRadius: 16),
                        ],
                      ),
                      child: Center(
                        child: Icon(Icons.headphones_rounded, color: tokens.onAccent, size: 36),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                Text(
                  'The Way of Kings',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Brandon Sanderson • Chapter 1: Stormblessed',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),

                const SizedBox(height: 14),

                // Live Seekbar Canvas
                ValueListenableBuilder<AudiobookSeekbarStyle>(
                  valueListenable: AudiobookSettings.customSeekbarStyle,
                  builder: (context, seekStyle, _) {
                    return AudiobookWaveformSeekbar(
                      position: _previewPosition,
                      duration: _previewDuration,
                      isPlaying: _previewIsPlaying,
                      style: seekStyle,
                      onSeek: (pos) => setState(() => _previewPosition = pos),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Live Action Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rewind 10s
                    IconButton(
                      icon: Icon(Icons.replay_10_rounded, color: tokens.textEmphasis, size: 24),
                      onPressed: () {
                        setState(() {
                          final p = _previewPosition - const Duration(seconds: 10);
                          _previewPosition = p < Duration.zero ? Duration.zero : p;
                        });
                      },
                    ),
                    const SizedBox(width: 12),

                    // Custom Styled Play/Pause Button
                    ValueListenableBuilder<AudiobookPlayButtonStyle>(
                      valueListenable: AudiobookSettings.customPlayButtonStyle,
                      builder: (context, playBtnStyle, _) {
                        return FocusableCard(
                          onTap: () => setState(() => _previewIsPlaying = !_previewIsPlaying),
                          builder: (_, state) => _buildCustomPlayButtonWidget(playBtnStyle, palette, _previewIsPlaying),
                        );
                      },
                    ),

                    const SizedBox(width: 12),

                    // Forward 10s
                    IconButton(
                      icon: Icon(Icons.forward_10_rounded, color: tokens.textEmphasis, size: 24),
                      onPressed: () {
                        setState(() {
                          final p = _previewPosition + const Duration(seconds: 10);
                          _previewPosition = p > _previewDuration ? _previewDuration : p;
                        });
                      },
                    ),

                    const SizedBox(width: 16),

                    // Speed Pill
                    InkWell(
                      onTap: () {
                        setState(() {
                          _previewSpeed = _previewSpeed >= 2.0 ? 1.0 : _previewSpeed + 0.25;
                        });
                      },
                      borderRadius: ZplayRadius.smAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: tokens.borderDefault,
                          borderRadius: ZplayRadius.smAll,
                          border: Border.all(color: tokens.borderStrong),
                        ),
                        child: Text(
                          '${_previewSpeed.toStringAsFixed(2)}x',
                          style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Customize Seek Bar Style ──
          Text('Seek Bar / Scrubber Style', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<AudiobookSeekbarStyle>(
            valueListenable: AudiobookSettings.customSeekbarStyle,
            builder: (context, currentStyle, _) {
              return SegmentedTabs<AudiobookSeekbarStyle>(
                selected: currentStyle,
                onSelected: (s) {
                  AudiobookSettings.setCustomSeekbarStyle(s);
                },
                options: [
                  for (final s in AudiobookSeekbarStyle.values)
                    SegmentedTabOption(value: s, label: s.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Customize Play / Pause Button Style ──
          Text('Play / Pause Button Styling', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<AudiobookPlayButtonStyle>(
            valueListenable: AudiobookSettings.customPlayButtonStyle,
            builder: (context, currentStyle, _) {
              return SegmentedTabs<AudiobookPlayButtonStyle>(
                selected: currentStyle,
                onSelected: (s) {
                  AudiobookSettings.setCustomPlayButtonStyle(s);
                },
                options: [
                  for (final s in AudiobookPlayButtonStyle.values)
                    SegmentedTabOption(value: s, label: s.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Customize Artwork Display ──
          Text('Artwork Display Style', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<AudiobookArtworkStyle>(
            valueListenable: AudiobookSettings.customArtworkStyle,
            builder: (context, currentStyle, _) {
              return SegmentedTabs<AudiobookArtworkStyle>(
                selected: currentStyle,
                onSelected: (s) {
                  AudiobookSettings.setCustomArtworkStyle(s);
                },
                options: [
                  for (final s in AudiobookArtworkStyle.values)
                    SegmentedTabOption(value: s, label: s.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Hover & Touch Physics ──
          Text('Button Hover & Touch Physics', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<AudiobookHoverEffect>(
            valueListenable: AudiobookSettings.customHoverEffect,
            builder: (context, currentEffect, _) {
              return SegmentedTabs<AudiobookHoverEffect>(
                selected: currentEffect,
                onSelected: (e) {
                  AudiobookSettings.setCustomHoverEffect(e);
                },
                options: [
                  for (final e in AudiobookHoverEffect.values)
                    SegmentedTabOption(value: e, label: e.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 16),

          // ── Drag & Drop Component Arranger ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Player Layout Components (Drag to Arrange)',
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
              Icon(Icons.drag_indicator_rounded, color: palette.primaryColor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hold and drag any block to reorder how controls appear inside your player',
            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: 10),

          ValueListenableBuilder<List<String>>(
            valueListenable: AudiobookSettings.componentOrder,
            builder: (context, order, _) {
              return ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) {
                  final list = List<String>.from(order);
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = list.removeAt(oldIndex);
                  list.insert(newIndex, item);
                  AudiobookSettings.setComponentOrder(list);
                },
                children: order.map((key) {
                  final label = _getComponentLabel(key);
                  final icon = _getComponentIcon(key);
                  return Container(
                    key: ValueKey(key),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(icon, color: palette.primaryColor, size: 18),
                      title: Text(label, style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                      trailing: Icon(Icons.drag_handle_rounded, color: tokens.textMuted, size: 18),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 14),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.enableLiquidGlass,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Liquid Glass Player Blur & Refraction', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setEnableLiquidGlass(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showSpeedControl,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Playback Speed Selector (0.5x - 2.5x)', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowSpeedControl(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showSkip10Buttons,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Skip Forward/Rewind Buttons (±10s)', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowSkip10Buttons(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: AudiobookSettings.showChaptersQuickButton,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Quick Chapters Sliding Drawer Button', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => AudiobookSettings.setShowChaptersQuickButton(val),
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AudiobookPlayerStudioPage()),
                );
              },
              icon: Icon(Icons.dashboard_customize_rounded, size: 18, color: tokens.onAccent),
              label: Text(
                'Launch Full Custom Player Studio',
                style: ZplayType.label.toStyle(color: tokens.onAccent),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomPlayButtonWidget(AudiobookPlayButtonStyle style, AppThemePalette palette, bool isPlaying) {
    final tokens = context.tokens;
    final icon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final hoverEffect = AudiobookSettings.customHoverEffect.value;

    Widget buttonCore;
    BorderRadius borderRadius;

    if (style == AudiobookPlayButtonStyle.liquidGlassNeo) {
      borderRadius = ZplayRadius.mdAll;
      final glassStyle = LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 18,
          clipQuality: LiquidGlassClipQuality.exact,
          borderWidth: 1.5,
          lightIntensity: 1.4,
          lightColor: Colors.white.withValues(alpha: ZplayOpacity.textPrimary),
          lightDirection: 115,
          borderType: const OpticalBorder(
            borderSaturation: 1.5,
            ambientIntensity: 1.15,
            borderSolidity: 0.18,
            lightSpread: 0.7,
          ),
        ),
        appearance: LiquidGlassAppearance(
          color: palette.primaryColor.withValues(alpha: 0.15),
          saturation: 1.2,
          blur: const LiquidGlassBlur(sigmaX: 3.0, sigmaY: 3.0),
          shadow: LiquidGlassShadow(
            blur: 14,
            opacity: 0.35,
            color: palette.primaryColor,
          ),
        ),
        refraction: const LiquidGlassRefraction(
          magnification: 1.035,
          chromaticAberration: 0.003,
          refractionType: OpticalRefraction(
            refraction: 1.54,
            refractionWidth: 20,
            depth: 0.75,
          ),
        ),
      );

      buttonCore = LiquidGlassLens(
        style: glassStyle,
        visibility: true,
        useImpellerBackdrop: true,
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          child: Icon(icon, color: tokens.onAccent, size: 30),
        ),
      );
    } else if (style == AudiobookPlayButtonStyle.roundedSquare) {
      borderRadius = ZplayRadius.mdAll;
      buttonCore = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.5),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: tokens.onAccent, size: 28),
      );
    } else if (style == AudiobookPlayButtonStyle.accentPill) {
      borderRadius = ZplayRadius.lgAll;
      buttonCore = Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.onAccent, size: 22),
            const SizedBox(width: 6),
            Text(
              isPlaying ? 'PAUSE' : 'PLAY',
              style: ZplayType.label.toStyle(color: tokens.onAccent),
            ),
          ],
        ),
      );
    } else {
      borderRadius = ZplayRadius.xlAll;
      buttonCore = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primaryColor,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.6),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: tokens.onAccent, size: 32),
      );
    }

    return AudiobookInteractivePhysicsButton(
      effect: hoverEffect,
      glowColor: palette.primaryColor,
      borderRadius: borderRadius,
      child: buttonCore,
    );
  }

  String _getComponentLabel(String key) {
    switch (key) {
      case 'artwork':
        return 'Audiobook Cover Artwork Deck';
      case 'title':
        return 'Title, Author & Chapter Label';
      case 'seekbar':
        return 'Seek Bar & Waveform Canvas Scrubber';
      case 'mainControls':
        return 'Main Play / Pause / Skip (±10s) Cluster';
      case 'secondaryControls':
        return 'Speed Selector & Volume Controls';
      case 'chaptersButton':
        return 'Premade Sliding Chapters Panel Trigger';
      default:
        return key;
    }
  }

  IconData _getComponentIcon(String key) {
    switch (key) {
      case 'artwork':
        return Icons.image_rounded;
      case 'title':
        return Icons.title_rounded;
      case 'seekbar':
        return Icons.graphic_eq_rounded;
      case 'mainControls':
        return Icons.play_circle_filled_rounded;
      case 'secondaryControls':
        return Icons.speed_rounded;
      case 'chaptersButton':
        return Icons.format_list_bulleted_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }
}
