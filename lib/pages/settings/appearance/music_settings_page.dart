import 'package:flutter/material.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/music/music_settings.dart';
import '../../../widgets/common/segmented_tabs.dart';
import '../../../widgets/music/music_waveform_seekbar.dart';
import '../../../widgets/settings/settings_app_bar.dart';
import 'music_player_studio_page.dart';

class MusicSettingsPage extends StatefulWidget {
  const MusicSettingsPage({super.key});

  @override
  State<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends State<MusicSettingsPage> {
  final bool _previewIsPlaying = false;
  Duration _previewPos = const Duration(minutes: 1, seconds: 20);

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'Music UI & Player Atmosphere'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            physics: const BouncingScrollPhysics(),
            children: [
              // 1. Enter Music Player Studio Banner
              _buildEnterPlayerStudioBanner(palette),
              const SizedBox(height: 28),

              // 2. Visual Theme Palette
              _buildSectionHeader('VISUAL THEME PALETTE'),
              const SizedBox(height: 12),
              _buildThemesGrid(),
              const SizedBox(height: 28),

              // 3. Ambient Moving Background Lights
              _buildSectionHeader('AMBIENT ATMOSPHERE & GLOW'),
              const SizedBox(height: 12),
              _buildAmbientLightsCard(palette),
              const SizedBox(height: 28),

              // 4. Discovery & Layout Settings
              _buildSectionHeader('DISCOVERY & CATALOG CONFIGURATION'),
              const SizedBox(height: 12),
              _buildDiscoveryConfigCard(palette),
              const SizedBox(height: 28),

              // 5. Fullscreen Player Presets
              _buildSectionHeader('FULLSCREEN PLAYER PRESETS'),
              const SizedBox(height: 12),
              _buildFullscreenPlayerPresetSelector(palette),
              const SizedBox(height: 28),

              // 6. Custom Player Quick Customizer
              _buildSectionHeader('CUSTOM PLAYER ENGINE DESIGNER'),
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

  Widget _buildThemesGrid() {
    final tokens = context.tokens;
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, currentPalette, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final int crossAxisCount = w < 400 ? 1 : (w < 700 ? 2 : 3);
            final double childAspectRatio = w < 400 ? 4.2 : 2.6;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: AppThemeService.palettes.length,
              itemBuilder: (context, index) {
                final theme = AppThemeService.palettes[index];
                final isSelected = theme.name == currentPalette.name;

                return InkWell(
                  onTap: () {
                    AppThemeService.setPalette(theme);
                    setState(() {});
                  },
                  borderRadius: ZplayRadius.mdAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: isSelected
                            ? currentPalette.primaryColor
                            : tokens.borderDefault,
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [theme.primaryColor, theme.accentColor],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: isSelected
                              ? Icon(Icons.check_rounded, color: tokens.textPrimary, size: 15)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            theme.name,
                            style: ZplayType.label.toStyle(
                              color: isSelected
                                  ? tokens.textPrimary
                                  : tokens.textEmphasis,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAmbientLightsCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: MusicSettings.enableAmbientLights,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Moving Background Ambient Lighting',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                subtitle: Text(
                  'Dynamic moving glowing orbs reacting with your theme accent colors',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => MusicSettings.setEnableAmbientLights(val),
              );
            },
          ),
          const SizedBox(height: 12),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          Text(
            'Ambient Light Pattern',
            style: ZplayType.label.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AmbientLightPattern>(
            valueListenable: MusicSettings.ambientLightPattern,
            builder: (context, currentPattern, _) {
              return SegmentedTabs<AmbientLightPattern>(
                selected: currentPattern,
                onSelected: (p) {
                  MusicSettings.setAmbientLightPattern(p);
                },
                options: [
                  for (final p in AmbientLightPattern.values)
                    SegmentedTabOption(value: p, label: p.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          ValueListenableBuilder<double>(
            valueListenable: MusicSettings.ambientLightIntensity,
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
                      inactiveTrackColor: Colors.white.withValues(
                        alpha: ZplayOpacity.borderMedium,
                      ),
                      thumbColor: tokens.textPrimary,
                    ),
                    child: Slider(
                      value: intensity,
                      min: 0.05,
                      max: 0.6,
                      onChanged: (v) => MusicSettings.setAmbientLightIntensity(v),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryConfigCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: MusicSettings.enableSpotlight,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Hero Spotlight Showcase', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Featured bestselling album & track showcase at the top of the music page', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => MusicSettings.setEnableSpotlight(val),
              );
            },
          ),
          Divider(color: tokens.borderDefault),
          ValueListenableBuilder<bool>(
            valueListenable: MusicSettings.showLosslessBadge,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Lossless Hi-Res Audio Badges', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Displays FLAC / Hi-Res lossless stream indicators on music cards and player', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => MusicSettings.setShowLosslessBadge(val),
              );
            },
          ),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 8),
          Text('Music Card & Grid Density', style: ZplayType.label.toStyle(color: tokens.textEmphasis)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MusicCardDensity>(
            valueListenable: MusicSettings.cardDensity,
            builder: (context, density, _) {
              return SegmentedTabs<MusicCardDensity>(
                selected: density,
                onSelected: (d) {
                  MusicSettings.setCardDensity(d);
                },
                options: [
                  for (final d in MusicCardDensity.values)
                    SegmentedTabOption(value: d, label: d.label),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenPlayerPresetSelector(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<MusicFullscreenPreset>(
      valueListenable: MusicSettings.selectedFullscreenPreset,
      builder: (context, selectedPreset, _) {
        return Column(
          children: MusicFullscreenPreset.values.map((preset) {
            final isSelected = selectedPreset == preset;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accentSubtle : tokens.surface,
                borderRadius: ZplayRadius.mdAll,
                border: Border.all(
                  color: isSelected ? palette.primaryColor : tokens.borderDefault,
                  width: isSelected ? 1.8 : 1.0,
                ),
              ),
              child: ListTile(
                onTap: () => MusicSettings.setSelectedFullscreenPreset(preset),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected ? palette.primaryColor : tokens.borderSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    preset == MusicFullscreenPreset.vinylStudio
                        ? Icons.album_rounded
                        : preset == MusicFullscreenPreset.cyberWaveform
                            ? Icons.graphic_eq_rounded
                            : preset == MusicFullscreenPreset.liquidGlassNeo
                                ? Icons.blur_on_rounded
                                : preset == MusicFullscreenPreset.cinematicArtwork
                                    ? Icons.fullscreen_rounded
                                    : Icons.dashboard_customize_rounded,
                    color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                    size: 20,
                  ),
                ),
                title: Text(
                  preset.label,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                subtitle: Text(
                  preset.description,
                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded, color: palette.primaryColor, size: 22)
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEnterPlayerStudioBanner(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.lgAll,
        gradient: LinearGradient(
          colors: [
            palette.primaryColor.withValues(alpha: 0.3),
            tokens.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: palette.primaryColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primaryColor.withValues(alpha: 0.25),
            blurRadius: 28,
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
              child: Icon(Icons.dashboard_customize_rounded, color: tokens.textPrimary, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Custom Music Player Studio',
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.primaryColor.withValues(alpha: 0.25),
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          'FULL PLAYER ENGINE',
                          style: ZplayType.overline.toStyle(color: palette.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Customize the Fullscreen Player. Drag & drop blocks, waveform equalizers, vinyl turntable & liquid glass buttons.',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MusicPlayerStudioPage()),
                      );
                    },
                    icon: Icon(Icons.tune_rounded, size: 18, color: tokens.textPrimary),
                    label: Text(
                      'Enter Custom Player Studio',
                      style: ZplayType.label.toStyle(color: tokens.textPrimary),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryColor,
                      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
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

  Widget _buildCustomPlayerStudioCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Customizer Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Live Waveform & Controls Preview', style: ZplayType.label.toStyle(color: palette.primaryColor)),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MusicPlayerStudioPage()),
                  );
                },
                child: Text('Open Full Studio ➔', style: ZplayType.label.toStyle()),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Mini preview bar
          MusicWaveformSeekbar(
            position: _previewPos,
            duration: const Duration(minutes: 3, seconds: 30),
            isPlaying: _previewIsPlaying,
            style: MusicSettings.customSeekbarStyle.value,
            onSeek: (p) => setState(() => _previewPos = p),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MusicPlayerStudioPage()),
              );
            },
            icon: Icon(Icons.dashboard_customize_rounded, size: 18, color: tokens.textPrimary),
            label: Text('Launch Full Custom Player Studio', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.primaryColor,
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              padding: const EdgeInsets.symmetric(vertical: 13),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }
}
