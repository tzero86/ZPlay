import 'package:flutter/material.dart';
import '../palette_picker.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/manga/manga_settings.dart';
import '../../../widgets/common/animated_ambient_background.dart';
import '../../../widgets/common/segmented_tabs.dart';
import '../../../widgets/settings/settings_app_bar.dart';

class MangaSettingsPage extends StatefulWidget {
  const MangaSettingsPage({super.key});

  @override
  State<MangaSettingsPage> createState() => _MangaSettingsPageState();
}

class _MangaSettingsPageState extends State<MangaSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'Manga UI & Reader Atmosphere'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
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

              // ── 3. Discovery & Cards ──
              _buildSectionHeader('DISCOVERY & POSTER CARDS'),
              const SizedBox(height: 12),
              _buildCardsConfigCard(palette),

              const SizedBox(height: 28),

              // ── 4. Manga Reader Customization ──
              _buildSectionHeader('MANGA READER & CHAPTER VIEWER'),
              const SizedBox(height: 12),
              _buildReaderConfigCard(palette),

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
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.enableAmbientLights,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Moving Ambient Lighting',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                subtitle: Text(
                  'Soft flowing glowing orbs and aurora waves themed to ${palette.name}',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setEnableAmbientLights(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          // Pattern selector
          Text(
            'Lighting Flow Pattern',
            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AmbientLightPattern>(
            valueListenable: MangaSettings.ambientLightPattern,
            builder: (context, currentPattern, _) {
              return SegmentedTabs<AmbientLightPattern>(
                selected: currentPattern,
                onSelected: (p) {
                  MangaSettings.setAmbientLightPattern(p);
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
            valueListenable: MangaSettings.ambientLightIntensity,
            builder: (context, intensity, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Glow Strength / Opacity', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                      Text('${(intensity * 100).round()}%', style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: intensity,
                      min: 0.08,
                      max: 0.60,
                      divisions: 26,
                      onChanged: (val) => MangaSettings.setAmbientLightIntensity(val),
                    ),
                  ),
                ],
              );
            },
          ),

          // Speed Slider
          ValueListenableBuilder<double>(
            valueListenable: MangaSettings.ambientLightSpeed,
            builder: (context, speed, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Motion Drift Speed', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                      Text('${speed.toStringAsFixed(1)}x', style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: speed,
                      min: 0.2,
                      max: 3.0,
                      divisions: 14,
                      onChanged: (val) => MangaSettings.setAmbientLightSpeed(val),
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
              border: Border.fromBorderSide(tokens.hairline),
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
                        color: tokens.bg.withValues(alpha: ZplayOpacity.textSecondary),
                        borderRadius: ZplayRadius.lgAll,
                        border: Border.fromBorderSide(tokens.hairlineStrong),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: palette.primaryColor, size: 14),
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

  // ── 3. Discovery & Cards Config Card ──
  Widget _buildCardsConfigCard(AppThemePalette palette) {
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
            valueListenable: MangaSettings.showContinueReading,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show "Continue Reading" Slider', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Display your active reading history at the top of the Manga page', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowContinueReading(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderDefault),
          const SizedBox(height: 12),

          Text('Manga Poster Card Density', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaCardDensity>(
            valueListenable: MangaSettings.cardDensity,
            builder: (context, currentDensity, _) {
              return SegmentedTabs<MangaCardDensity>(
                selected: currentDensity,
                onSelected: (d) {
                  MangaSettings.setCardDensity(d);
                },
                options: [
                  for (final d in MangaCardDensity.values)
                    SegmentedTabOption(value: d, label: d.label),
                ],
              );
            },
          ),

          const SizedBox(height: 14),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showContentTypeBadge,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Content Type Badge (Manga/Manhwa)', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowContentTypeBadge(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showMangaYear,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Publication Year on Cards', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowMangaYear(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.ambientCardGlow,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Poster Card Hover Glow Effect', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setAmbientCardGlow(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showScrollTrack,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Desktop Scroll Track', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowScrollTrack(val),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 4. Reader Configuration Card ──
  Widget _buildReaderConfigCard(AppThemePalette palette) {
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
          // Default Reading Mode
          Text('Default Reading Mode', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReadingMode>(
            valueListenable: MangaSettings.defaultReadingMode,
            builder: (context, currentMode, _) {
              return SegmentedTabs<MangaReadingMode>(
                selected: currentMode,
                onSelected: (m) {
                  MangaSettings.setDefaultReadingMode(m);
                },
                options: [
                  for (final m in MangaReadingMode.values)
                    SegmentedTabOption(value: m, label: m.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Reader Max Width
          Text('Page Reading Width Constraint', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReaderMaxWidth>(
            valueListenable: MangaSettings.readerMaxWidth,
            builder: (context, currentWidth, _) {
              return SegmentedTabs<MangaReaderMaxWidth>(
                selected: currentWidth,
                onSelected: (w) {
                  MangaSettings.setReaderMaxWidth(w);
                },
                options: [
                  for (final w in MangaReaderMaxWidth.values)
                    SegmentedTabOption(value: w, label: w.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Reader Background Color
          Text('Reader Background Atmosphere', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReaderBackground>(
            valueListenable: MangaSettings.readerBackground,
            builder: (context, currentBg, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaReaderBackground.values.map((b) {
                  final isSelected = b == currentBg;
                  return ChoiceChip(
                    avatar: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: b.color,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: Colors.white.withValues(alpha: ZplayOpacity.textDisabled),
                          ),
                        ),
                      ),
                    ),
                    label: Text(b.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: tokens.surface,
                    labelStyle: ZplayType.label.toStyle(
                      color: isSelected ? palette.primaryColor : tokens.textEmphasis,
                    ),
                    side: BorderSide(
                      color: isSelected ? palette.primaryColor.withValues(alpha: 0.6) : tokens.borderDefault,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setReaderBackground(b);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Control Bar Style
          Text('Control Toolbar Style', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaControlBarStyle>(
            valueListenable: MangaSettings.readerControlBarStyle,
            builder: (context, currentStyle, _) {
              return SegmentedTabs<MangaControlBarStyle>(
                selected: currentStyle,
                onSelected: (s) {
                  MangaSettings.setReaderControlBarStyle(s);
                },
                options: [
                  for (final s in MangaControlBarStyle.values)
                    SegmentedTabOption(value: s, label: s.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Page Gap slider (for webtoon mode)
          ValueListenableBuilder<double>(
            valueListenable: MangaSettings.pageGap,
            builder: (context, gap, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Vertical Page Gap', style: ZplayType.subtitle.toStyle(color: tokens.textPrimary)),
                      Text('${gap.round()} px', style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: gap,
                      min: 0,
                      max: 24,
                      divisions: 12,
                      onChanged: (val) => MangaSettings.setPageGap(val),
                    ),
                  ),
                ],
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showPageDeck,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Page Deck / Thumbnail Previews', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Interactive visual tray of thumbnail previews for instant page jumping', style: ZplayType.caption.toStyle(color: tokens.textSecondary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowPageDeck(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showPageScrubber,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Show Page Scrubber Slider', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowPageScrubber(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.enableNextChapterDeck,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Enable Next Chapter Preview Card Deck', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                subtitle: Text('Rich glass deck card at the end of each chapter with chapter art and direct launch', style: ZplayType.caption.toStyle(color: tokens.textSecondary)),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setEnableNextChapterDeck(val),
              );
            },
          ),
        ],
      ),
    );
  }
}
