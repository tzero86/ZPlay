import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../palette_picker.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/custom_background_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/collections/collections_service.dart';
import '../../../services/my_list/my_list_service.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/trakt/trakt_service.dart';
import '../../../widgets/common/animated_ambient_background.dart';
import '../../../widgets/common/segmented_tabs.dart';
import 'custom_background_settings_page.dart';

class HomeUiSettingsPage extends StatefulWidget {
  const HomeUiSettingsPage({super.key});

  @override
  State<HomeUiSettingsPage> createState() => _HomeUiSettingsPageState();
}

class _HomeUiSettingsPageState extends State<HomeUiSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final myListCount = MyListService.items.value.length;

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
          'Home Page UI & Themes',
          style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── 1. Color Schemes & Themes ──
              Text(
                'COLOR THEMES & ACCENTS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildThemesGrid(),

              const SizedBox(height: 28),

              // ── 2. Ambient Background Lighting & Moving Glows ──
              Text(
                'AMBIENT BACKGROUND LIGHTING & MOVING GLOWS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildAmbientLightsCard(),

              const SizedBox(height: 28),

              // ── 2b. Custom Wallpaper & Background Photo ──
              Text(
                'CUSTOM BACKGROUND & WALLPAPER',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<CustomBackgroundData>(
                valueListenable: CustomBackgroundService.notifier,
                builder: (context, customBg, _) {
                  final hasWallpaper = customBg.hasCustomBackground;
                  final palette = AppThemeService.currentPalette.value;

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomBackgroundSettingsPage(),
                        ),
                      );
                    },
                    borderRadius: ZplayRadius.mdAll,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(
                          color: hasWallpaper
                              ? palette.primaryColor.withValues(alpha: 0.40)
                              : tokens.borderDefault,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                              borderRadius: ZplayRadius.smAll,
                            ),
                            child: Icon(
                              Icons.wallpaper_rounded,
                              color: palette.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Custom Wallpaper & Lighting Blend',
                                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  hasWallpaper
                                      ? 'Custom background active with ambient light blending'
                                      : 'Upload photos or choose curated dark wallpapers',
                                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, color: tokens.textMuted, size: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // ── 3. "Because you have on your list" Section ──
              Text(
                'SMART RECOMMENDATIONS ("BECAUSE YOU HAVE ON YOUR LIST")',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildSimilarRecommendationsCard(myListCount),

              const SizedBox(height: 28),

              // ── 3b. Curated Collections ──
              Text(
                'CURATED COLLECTIONS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildCollectionsCard(),

              const SizedBox(height: 28),

              // ── 4. Hero Carousel & Spotlight ──
              Text(
                'HERO BANNER & SPOTLIGHT',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildHeroControlsCard(),

              const SizedBox(height: 28),

              // ── 5. Card Layout & Poster Density ──
              Text(
                'POSTER CARDS & DENSITY',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildCardDensityCard(),

              const SizedBox(height: 28),

              // ── 6. Feature Shortcuts & Buttons ──
              Text(
                'HEADER SHORTCUTS & BUTTONS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildFeatureTogglesCard(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemesGrid() => const PalettePicker();

  Widget _buildAmbientLightsCard() {
    final tokens = context.tokens;
    final palette = AppThemeService.currentPalette.value;

    return ValueListenableBuilder<bool>(
      valueListenable: HomePageSettings.enableAmbientLights,
      builder: (context, enabled, _) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: enabled
                  ? palette.primaryColor.withValues(alpha: 0.35)
                  : tokens.borderDefault,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Interactive Mini Preview
              ClipRRect(
                borderRadius: ZplayRadius.smAll,
                child: SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: AnimatedAmbientBackground(),
                      ),
                      Positioned(
                        left: 14,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tokens.bg.withValues(alpha: 0.55),
                            borderRadius: ZplayRadius.smAll,
                            border: Border.all(color: tokens.borderStrong),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_motion_rounded, size: 14, color: palette.primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'LIVE LIGHTING ENGINE PREVIEW',
                                style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Master Switch
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: palette.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      Icons.blur_linear_rounded,
                      color: palette.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Moving Ambient Lights & Glows',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Drifting faded light waves & floating color orbs in background',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    activeColor: palette.primaryColor,
                    onChanged: (val) {
                      HomePageSettings.setEnableAmbientLights(val);
                      setState(() {});
                    },
                  ),
                ],
              ),

              if (enabled) ...[
                const SizedBox(height: 16),
                Divider(color: tokens.borderSubtle),
                const SizedBox(height: 12),

                // Lighting Pattern / Position
                Text(
                  'Lighting Pattern & Position',
                  style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<AmbientLightPattern>(
                  valueListenable: HomePageSettings.ambientLightPattern,
                  builder: (context, currentPattern, _) {
                    return SegmentedTabs<AmbientLightPattern>(
                      selected: currentPattern,
                      onSelected: (pat) {
                        HomePageSettings.setAmbientLightPattern(pat);
                        setState(() {});
                      },
                      options: [
                        for (final pat in AmbientLightPattern.values)
                          SegmentedTabOption(value: pat, label: pat.label),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),
                Divider(color: tokens.borderSubtle),
                const SizedBox(height: 12),

                // Strength / Intensity Slider
                ValueListenableBuilder<double>(
                  valueListenable: HomePageSettings.ambientLightIntensity,
                  builder: (context, intensity, _) {
                    final percent = (intensity * 200).round();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Glow Strength / Intensity',
                              style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                            ),
                            Text(
                              '$percent%',
                              style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: palette.primaryColor,
                            inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                            thumbColor: palette.primaryColor,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: intensity,
                            min: 0.05,
                            max: 0.50,
                            divisions: 18,
                            onChanged: (val) => HomePageSettings.setAmbientLightIntensity(val),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Motion Speed Slider
                ValueListenableBuilder<double>(
                  valueListenable: HomePageSettings.ambientLightSpeed,
                  builder: (context, speed, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Motion Flow Speed',
                              style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                            ),
                            Text(
                              '${speed.toStringAsFixed(1)}x',
                              style: ZplayType.labelNumeric.toStyle(color: palette.primaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: palette.primaryColor,
                            inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                            thumbColor: palette.primaryColor,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: speed,
                            min: 0.4,
                            max: 2.5,
                            divisions: 21,
                            onChanged: (val) => HomePageSettings.setAmbientLightSpeed(val),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimilarRecommendationsCard(int myListCount) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: AppThemeService.currentPalette.value.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Recommendations',
                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure personalized & algorithmic recommendation sliders',
                      style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 8),

          // 1. Because You Have... (My List)
          _buildRecommendationToggleRow(
            title: '"Because You Have..." (My List)',
            subtitle: 'BestSimilar recommendations based on titles saved in My List',
            listenable: HomePageSettings.enableSimilar,
            onChanged: (val) {
              HomePageSettings.setEnableSimilar(val);
              setState(() {});
            },
          ),

          // 2. Because You're Watching... (Continue Watching)
          _buildRecommendationToggleRow(
            title: '"Because You\'re Watching..."',
            subtitle: 'BestSimilar recommendations based on active Continue Watching titles',
            listenable: HomePageSettings.enableWatchingSimilar,
            onChanged: (val) {
              HomePageSettings.setEnableWatchingSimilar(val);
              setState(() {});
            },
          ),

          // 3. Trakt Recommendations
          FutureBuilder<bool>(
            future: TraktService.instance.isAuthenticated(),
            builder: (context, snapshot) {
              final isAuthed = snapshot.data ?? false;
              return _buildRecommendationToggleRow(
                title: 'Trakt Recommendations',
                subtitle: isAuthed
                    ? 'Personalized recommendations computed by Trakt'
                    : 'Requires Trakt login in Settings -> Trakt',
                listenable: HomePageSettings.enableTraktRecommendations,
                trailingExtra: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAuthed
                        ? const Color(0xFFED1C24).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
                    borderRadius: ZplayRadius.xsAll,
                    border: Border.all(
                      color: isAuthed
                            ? const Color(0xFFED1C24).withValues(alpha: 0.4)
                            : tokens.borderStrong,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isAuthed ? 'CONNECTED' : 'DISCONNECTED',
                    style: ZplayType.overline.toStyle(color: isAuthed ? const Color(0xFFFF5252) : tokens.textMuted),
                  ),
                ),
                onChanged: (val) {
                  HomePageSettings.setEnableTraktRecommendations(val);
                  setState(() {});
                },
              );
            },
          ),

          // 4. Simkl Recommendations
          FutureBuilder<bool>(
            future: SimklService.instance.isAuthenticated(),
            builder: (context, snapshot) {
              final isAuthed = snapshot.data ?? false;
              return _buildRecommendationToggleRow(
                title: 'Simkl Recommendations',
                subtitle: isAuthed
                    ? 'Top-rated & personalized suggestions from Simkl'
                    : 'Requires Simkl login in Settings -> Simkl',
                listenable: HomePageSettings.enableSimklRecommendations,
                trailingExtra: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAuthed
                        ? const Color(0xFF00B2FF).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: ZplayOpacity.borderStrong),
                    borderRadius: ZplayRadius.xsAll,
                    border: Border.all(
                      color: isAuthed
                            ? const Color(0xFF00B2FF).withValues(alpha: 0.4)
                            : tokens.borderStrong,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isAuthed ? 'CONNECTED' : 'DISCONNECTED',
                    style: ZplayType.overline.toStyle(color: isAuthed ? const Color(0xFF40C4FF) : tokens.textMuted),
                  ),
                ),
                onChanged: (val) {
                  HomePageSettings.setEnableSimklRecommendations(val);
                  setState(() {});
                },
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // Position Dropdown
          Text(
            'Recommendation Sliders Position on Home Page',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<SimilarSectionPosition>(
            valueListenable: HomePageSettings.similarPosition,
            builder: (context, pos, _) {
              return DropdownButtonFormField<SimilarSectionPosition>(
                value: pos,
                dropdownColor: tokens.surfaceOverlay,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                ),
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                items: SimilarSectionPosition.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(p.label),
                  );
                }).toList(),
                onChanged: (newPos) {
                  if (newPos != null) {
                    HomePageSettings.setSimilarPosition(newPos);
                    setState(() {});
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationToggleRow({
    required String title,
    required String subtitle,
    required ValueListenable<bool> listenable,
    required ValueChanged<bool> onChanged,
    Widget? trailingExtra,
  }) {
    final tokens = context.tokens;
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, enabled, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                          ),
                        ),
                        if (trailingExtra != null) ...[
                          const SizedBox(width: 8),
                          trailingExtra,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: enabled,
                activeColor: AppThemeService.currentPalette.value.primaryColor,
                onChanged: onChanged,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionsCard() {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: _buildRecommendationToggleRow(
        title: 'Collections',
        subtitle: 'Show curated collection rails on the Home page',
        listenable: CollectionsService.showOnHome,
        onChanged: (val) {
          CollectionsService.showOnHome.value = val;
          setState(() {});
        },
      ),
    );
  }

  Widget _buildHeroControlsCard() {
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
          // Master Spotlight Switch
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableSpotlight,
            builder: (context, enabled, _) {
              return Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      Icons.movie_filter_rounded,
                      color: AppThemeService.currentPalette.value.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Hero Spotlight Banner',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Featured rotation banner at the top of the home page',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    activeColor: AppThemeService.currentPalette.value.primaryColor,
                    onChanged: (val) {
                      HomePageSettings.setEnableSpotlight(val);
                      setState(() {});
                    },
                  ),
                ],
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableSpotlight,
            builder: (context, enabled, _) {
              if (!enabled) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Divider(color: tokens.borderSubtle),
                  const SizedBox(height: 12),

                  // Hero Style Selector
                  Text(
                    'Spotlight Style',
                    style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<HeroStyle>(
                    valueListenable: HomePageSettings.heroStyle,
                    builder: (context, currentStyle, _) {
                      return SegmentedTabs<HeroStyle>(
                        selected: currentStyle,
                        onSelected: (style) {
                          HomePageSettings.setHeroStyle(style);
                          setState(() {});
                        },
                        options: [
                          for (final style in HeroStyle.values)
                            SegmentedTabOption(value: style, label: style.label),
                        ],
                      );
                    },
                  ),

          // Auto-Rotate Switch & Interval
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.heroAutoRotate,
            builder: (context, autoRotate, _) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-Rotate Spotlight',
                              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Cycles through featured titles automatically',
                              style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: autoRotate,
                        activeColor: AppThemeService.currentPalette.value.primaryColor,
                        onChanged: (val) {
                          HomePageSettings.setHeroAutoRotate(val);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  if (autoRotate) ...[
                    const SizedBox(height: 10),
                    ValueListenableBuilder<int>(
                      valueListenable: HomePageSettings.heroRotateSeconds,
                      builder: (context, seconds, _) {
                        return Row(
                          children: [
                            Text(
                              'Interval: ${seconds}s',
                              style: ZplayType.labelNumeric.toStyle(color: tokens.textEmphasis),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppThemeService.currentPalette.value.primaryColor,
                                  inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                                  thumbColor: AppThemeService.currentPalette.value.primaryColor,
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: seconds.toDouble(),
                                  min: 3,
                                  max: 15,
                                  divisions: 12,
                                  onChanged: (val) =>
                                      HomePageSettings.setHeroRotateSeconds(val.round()),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // Ambient Glow Switch
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.ambientGlow,
            builder: (context, glow, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ambient Backdrop Lighting',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Soft diffused color glow behind active hero poster',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: glow,
                    activeColor: AppThemeService.currentPalette.value.primaryColor,
                    onChanged: (val) {
                      HomePageSettings.setAmbientGlow(val);
                      setState(() {});
                    },
                  ),
                ],
              );
            },
          ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCardDensityCard() {
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
          Text(
            'Poster Size & Grid Density',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<CardDensity>(
            valueListenable: HomePageSettings.cardDensity,
            builder: (context, currentDensity, _) {
              return SegmentedTabs<CardDensity>(
                selected: currentDensity,
                onSelected: (density) {
                  HomePageSettings.setCardDensity(density);
                  setState(() {});
                },
                options: [
                  for (final density in CardDensity.values)
                    SegmentedTabOption(value: density, label: density.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // Rating Badges Switch
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.showRating,
            builder: (context, showRating, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show IMDB Rating Badges',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display rating star pill on poster corners',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showRating,
                    activeColor: AppThemeService.currentPalette.value.primaryColor,
                    onChanged: (val) {
                      HomePageSettings.setShowRating(val);
                      setState(() {});
                    },
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // Card Hover Zoom Strength
          ValueListenableBuilder<double>(
            valueListenable: HomePageSettings.cardHoverZoom,
            builder: (context, zoom, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Poster Hover Zoom Scale',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                      ),
                      Text(
                        '${zoom.toStringAsFixed(2)}x',
                        style: ZplayType.labelNumeric.toStyle(color: AppThemeService.currentPalette.value.primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppThemeService.currentPalette.value.primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderMedium),
                      thumbColor: AppThemeService.currentPalette.value.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: zoom,
                      min: 1.00,
                      max: 1.15,
                      divisions: 15,
                      onChanged: (val) => HomePageSettings.setCardHoverZoom(val),
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

  Widget _buildFeatureTogglesCard() {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TV Shows Airing Calendar
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableCalendar,
            builder: (context, enabled, _) {
              return Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.info.withValues(alpha: ZplayOpacity.overlayHover),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: tokens.info,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TV Airing Calendar',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Show TV Calendar buttons on Home bar & sliders',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    onChanged: (val) => HomePageSettings.setEnableCalendar(val),
                    activeColor: tokens.info,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle, height: 1),
          const SizedBox(height: 12),

          // AI Recommendation Quiz
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableAiQuiz,
            builder: (context, enabled, _) {
              return Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: tokens.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Recommendation Quiz',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Show AI Quiz button on Home & Search bars',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    onChanged: (val) => HomePageSettings.setEnableAiQuiz(val),
                    activeColor: tokens.accent,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
