import 'package:flutter/material.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/iptv/iptv_settings.dart';
import '../../../widgets/common/animated_ambient_background.dart';
import '../../../widgets/common/segmented_tabs.dart';
import '../../../widgets/settings/settings_app_bar.dart';

class LiveTvSettingsPage extends StatefulWidget {
  const LiveTvSettingsPage({super.key});

  @override
  State<LiveTvSettingsPage> createState() => _LiveTvSettingsPageState();
}

class _LiveTvSettingsPageState extends State<LiveTvSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final palette = AppThemeService.currentPalette.value;

    return AnimatedAmbientBackground(child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SettingsAppBar(title: 'Live TV & Sports UI'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── 1. Hero Spotlight Carousel ──
              Text(
                'LIVE SPOTLIGHT & HERO BANNER',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildHeroSpotlightCard(palette),

              const SizedBox(height: 28),

              // ── 2. Card Layout & Poster Density ──
              Text(
                'CHANNEL CARDS & POSTER DENSITY',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildCardDensityCard(palette),

              const SizedBox(height: 28),

              // ── 3. Category Visibility & Ordering ──
              Text(
                'SECTIONS & CATEGORY MANAGER',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildCategoryManagerCard(palette),

              const SizedBox(height: 28),

              // ── 4. Portals Modal Customization ──
              Text(
                'PORTALS & PLAYLISTS MODAL',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildPortalsModalCustomizerCard(palette),

              const SizedBox(height: 28),

              // ── 5. Portal Browser Customization ──
              Text(
                'PORTAL BROWSER & CHANNEL GUIDE',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              _buildPortalBrowserCustomizerCard(palette),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildHeroSpotlightCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<bool>(
      valueListenable: IptvSettings.enableSpotlight,
      builder: (context, enabled, _) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
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
              // Master Toggle
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
                      Icons.tv_rounded,
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
                          'Show Live Spotlight Banner',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Featured championship matches and top broadcast channels at the top',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    activeColor: palette.primaryColor,
                    onChanged: (val) {
                      IptvSettings.setEnableSpotlight(val);
                      setState(() {});
                    },
                  ),
                ],
              ),

              if (enabled) ...[
                const SizedBox(height: 16),
                Divider(color: tokens.borderSubtle),
                const SizedBox(height: 12),

                // Style Selection
                Text(
                  'Hero Banner Style',
                  style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<HeroStyle>(
                  valueListenable: IptvSettings.heroStyle,
                  builder: (context, currentStyle, _) {
                    return SegmentedTabs<HeroStyle>(
                      selected: currentStyle,
                      onSelected: (style) {
                        IptvSettings.setHeroStyle(style);
                        setState(() {});
                      },
                      options: [
                        for (final style in HeroStyle.values)
                          SegmentedTabOption(value: style, label: style.label),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),
                Divider(color: tokens.borderSubtle),
                const SizedBox(height: 12),

                // Auto Rotate
                ValueListenableBuilder<bool>(
                  valueListenable: IptvSettings.heroAutoRotate,
                  builder: (context, autoRotate, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto-Rotate Channels',
                                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Automatically cycle through featured live events',
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: autoRotate,
                          activeColor: palette.primaryColor,
                          onChanged: (val) => IptvSettings.setHeroAutoRotate(val),
                        ),
                      ],
                    );
                  },
                ),

                // Rotate Timer Slider
                ValueListenableBuilder<bool>(
                  valueListenable: IptvSettings.heroAutoRotate,
                  builder: (context, autoRotate, _) {
                    if (!autoRotate) return const SizedBox.shrink();
                    return ValueListenableBuilder<int>(
                      valueListenable: IptvSettings.heroRotateSeconds,
                      builder: (context, seconds, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Rotation Interval',
                                  style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                                ),
                                Text(
                                  '$seconds seconds',
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
                                value: seconds.toDouble(),
                                min: 3,
                                max: 15,
                                divisions: 12,
                                onChanged: (val) => IptvSettings.setHeroRotateSeconds(val.round()),
                              ),
                            ),
                          ],
                        );
                      },
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

  Widget _buildCardDensityCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Density Choice
          Text(
            'Channel Card Size',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<CardDensity>(
            valueListenable: IptvSettings.cardDensity,
            builder: (context, currentDensity, _) {
              return SegmentedTabs<CardDensity>(
                selected: currentDensity,
                onSelected: (density) {
                  IptvSettings.setCardDensity(density);
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

          // Hover Zoom Slider
          ValueListenableBuilder<double>(
            valueListenable: IptvSettings.cardHoverZoom,
            builder: (context, zoom, _) {
              final percent = ((zoom - 1.0) * 100).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Card Hover Scale Zoom',
                        style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                      ),
                      Text(
                        '+$percent%',
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
                      value: zoom,
                      min: 1.00,
                      max: 1.15,
                      divisions: 15,
                      onChanged: (val) => IptvSettings.setCardHoverZoom(val),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // HD Badge Toggle
          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showHdBadge,
            builder: (context, showHd, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show LIVE / HD Stream Badge',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display radiant live broadcast badge on channel corners',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showHd,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowHdBadge(val),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          // Category Tag Toggle
          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showCategoryTag,
            builder: (context, showTag, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Channel Category Tag',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Show category label below channel name',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showTag,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowCategoryTag(val),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryManagerCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return ValueListenableBuilder<List<String>>(
      valueListenable: IptvSettings.visibleCategories,
      builder: (context, visibleList, _) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Channel Categories & Sections',
                        style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Toggle visibility of Live TV rows',
                        style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => IptvSettings.resetCategories(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Reset All', style: ZplayType.label.toStyle()),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: tokens.borderSubtle),
              const SizedBox(height: 6),

              ...IptvSettings.defaultCategories.map((cat) {
                final isVisible = visibleList.contains(cat);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    cat,
                    style: ZplayType.subtitle.toStyle(color: isVisible ? tokens.textPrimary : tokens.textMuted),
                  ),
                  value: isVisible,
                  activeColor: palette.primaryColor,
                  checkColor: tokens.textPrimary,
                  onChanged: (val) {
                    IptvSettings.toggleCategoryVisibility(cat);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPortalsModalCustomizerCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Portal Card Display Style',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<PortalCardStyle>(
            valueListenable: IptvSettings.portalCardStyle,
            builder: (context, style, _) {
              return SegmentedTabs<PortalCardStyle>(
                selected: style,
                onSelected: (s) {
                  IptvSettings.setPortalCardStyle(s);
                  setState(() {});
                },
                options: [
                  for (final s in PortalCardStyle.values)
                    SegmentedTabOption(value: s, label: s.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showPortalExpiry,
            builder: (context, showExpiry, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Portal Expiry Date',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display subscription expiration tag on portal cards',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showExpiry,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowPortalExpiry(val),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showPortalConnections,
            builder: (context, showConn, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Max Active Connections Tag',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display current and max concurrent streaming connections',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showConn,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowPortalConnections(val),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          Text(
            'Default Starting Tab',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: IptvSettings.defaultPortalTab,
            builder: (context, tabIdx, _) {
              return SegmentedTabs<int>(
                selected: tabIdx,
                onSelected: IptvSettings.setDefaultPortalTab,
                options: const [
                  SegmentedTabOption(value: 0, label: 'Xtream Panels'),
                  SegmentedTabOption(value: 1, label: 'M3U Playlists'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPortalBrowserCustomizerCard(AppThemePalette palette) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channel Stream Layout Mode',
            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<PortalBrowserLayout>(
            valueListenable: IptvSettings.browserLayout,
            builder: (context, layout, _) {
              return SegmentedTabs<PortalBrowserLayout>(
                selected: layout,
                onSelected: (l) {
                  IptvSettings.setBrowserLayout(l);
                  setState(() {});
                },
                options: [
                  for (final l in PortalBrowserLayout.values)
                    SegmentedTabOption(value: l, label: l.label),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<PortalBrowserLayout>(
            valueListenable: IptvSettings.browserLayout,
            builder: (context, layout, _) {
              if (layout != PortalBrowserLayout.grid) return const SizedBox.shrink();
              return ValueListenableBuilder<int>(
                valueListenable: IptvSettings.browserGridColumns,
                builder: (context, cols, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Grid Stream Columns',
                            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                          ),
                          Text(
                            '$cols Columns',
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
                          value: cols.toDouble(),
                          min: 2,
                          max: 6,
                          divisions: 4,
                          onChanged: (val) => IptvSettings.setBrowserGridColumns(val.round()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(color: tokens.borderSubtle),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              );
            },
          ),

          ValueListenableBuilder<double>(
            valueListenable: IptvSettings.sidebarWidth,
            builder: (context, width, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Category Sidebar Width',
                        style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                      ),
                      Text(
                        '${width.round()} px',
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
                      value: width,
                      min: 200.0,
                      max: 340.0,
                      divisions: 14,
                      onChanged: (val) => IptvSettings.setSidebarWidth(val),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showStreamLogos,
            builder: (context, showLogos, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Channel Stream Logos',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display channel poster and logos in stream rows',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showLogos,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowStreamLogos(val),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showEpgSnippet,
            builder: (context, showEpg, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show EPG "Now Playing" Snippet',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display current television guide title below channel',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showEpg,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowEpgSnippet(val),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: tokens.borderSubtle),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
            valueListenable: IptvSettings.showCategoryCount,
            builder: (context, showCount, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Category Stream Counts',
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Show number of available streams next to category names',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: showCount,
                    activeColor: palette.primaryColor,
                    onChanged: (val) => IptvSettings.setShowCategoryCount(val),
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
