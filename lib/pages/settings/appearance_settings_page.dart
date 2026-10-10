import 'dart:io';

import 'package:flutter/material.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/audiobook/audiobook_settings.dart';
import '../../services/theme/custom_background_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/manga/manga_settings.dart';
import '../../services/music/music_settings.dart';
import '../../services/diagnostics/renderer_backend.dart';
import 'appearance/audiobook_settings_page.dart';
import 'appearance/custom_background_settings_page.dart';
import 'appearance/home_ui_settings_page.dart';
import 'appearance/liquid_glass_settings_page.dart';
import 'appearance/live_tv_settings_page.dart';
import 'appearance/manga_settings_page.dart';
import 'appearance/music_settings_page.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/settings/settings_app_bar.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedAmbientBackground(child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SettingsAppBar(title: 'Appearance & Interface'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            children: [
              // Header description
              Padding(
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
                child: Text(
                  'Fine-tune the visual atmosphere, custom wallpaper background, color palettes, and interface layouts.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              // ── Interface & atmosphere ────────────────────────────────────
              _buildGroup(
                label: 'INTERFACE & ATMOSPHERE',
                rows: [
                  // Custom Wallpaper & Atmosphere Background
                  ValueListenableBuilder<CustomBackgroundData>(
                    valueListenable: CustomBackgroundService.notifier,
                    builder: (context, customBg, _) {
                      return ValueListenableBuilder<AppThemePalette>(
                        valueListenable: AppThemeService.currentPalette,
                        builder: (context, currentPalette, _) {
                          return _buildRow(
                            icon: Icons.wallpaper_rounded,
                            iconColor: tokens.accent,
                            title: 'Custom Background & Wallpaper',
                            subtitle:
                                'Upload custom photos, choose curated dark wallpapers, and blend theme ambient lighting',
                            value: customBg.hasCustomBackground
                                ? 'Custom Active'
                                : 'Default Theme',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CustomBackgroundSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),

                  // Liquid Glass Setup
                  ValueListenableBuilder<bool>(
                    valueListenable: GlassSettings.enabled,
                    builder: (context, glassEnabled, _) {
                      return ValueListenableBuilder<GlassPreset>(
                        valueListenable: GlassSettings.preset,
                        builder: (context, preset, _) {
                          return _buildRow(
                            icon: Icons.blur_on_rounded,
                            iconColor: glassEnabled
                                ? tokens.accent
                                : tokens.textDisabled,
                            title: 'Liquid Glass Setup',
                            subtitle:
                                'Adjust hover impact, wobble spring physics, lens refraction, and chromatic aberration',
                            value: glassEnabled ? preset.label : 'Disabled',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const LiquidGlassSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),

                  // Home Page UI & Themes
                  ValueListenableBuilder<AppThemePalette>(
                    valueListenable: AppThemeService.currentPalette,
                    builder: (context, currentPalette, _) {
                      return _buildRow(
                        icon: Icons.palette_rounded,
                        iconColor: tokens.accent,
                        title: 'Home Page UI & Themes',
                        subtitle:
                            'Color schemes, "Because you have on your list" smart slider, hero spotlight, and card density',
                        value: currentPalette.name,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HomeUiSettingsPage(),
                            ),
                          );
                          setState(() {});
                        },
                      );
                    },
                  ),

                  // Live TV & Sports UI
                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.enableSpotlight,
                    builder: (context, spotlightEnabled, _) {
                      return ValueListenableBuilder<AppThemePalette>(
                        valueListenable: AppThemeService.currentPalette,
                        builder: (context, currentPalette, _) {
                          return _buildRow(
                            icon: Icons.live_tv_rounded,
                            iconColor: tokens.accent,
                            title: 'Live TV & Sports UI',
                            subtitle:
                                'Broadcast hero spotlight, channel card density, category ordering, and live badge styling',
                            value: spotlightEnabled ? 'Spotlight ON' : 'Compact',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const LiveTvSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: ZplaySpacing.s24),

              // ── Content ───────────────────────────────────────────────────
              _buildGroup(
                label: 'CONTENT',
                rows: [
                  // Manga UI & Reader Atmosphere
                  ValueListenableBuilder<MangaReadingMode>(
                    valueListenable: MangaSettings.defaultReadingMode,
                    builder: (context, readingMode, _) {
                      return ValueListenableBuilder<AppThemePalette>(
                        valueListenable: AppThemeService.currentPalette,
                        builder: (context, currentPalette, _) {
                          return _buildRow(
                            icon: Icons.menu_book_rounded,
                            iconColor: tokens.accent,
                            title: 'Manga UI & Reader Atmosphere',
                            subtitle:
                                'Ambient moving lighting, card density, reading layout widths, webtoon/horizontal modes, and page deck preview',
                            value: readingMode == MangaReadingMode.webtoon
                                ? 'Webtoon'
                                : 'Horizontal',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MangaSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: ZplaySpacing.s24),

              // ── Playback ──────────────────────────────────────────────────
              _buildGroup(
                label: 'PLAYBACK',
                rows: [
                  // Audiobook UI & Player Studio
                  ValueListenableBuilder<AudiobookPlayerPreset>(
                    valueListenable: AudiobookSettings.selectedPlayerPreset,
                    builder: (context, playerPreset, _) {
                      return ValueListenableBuilder<AppThemePalette>(
                        valueListenable: AppThemeService.currentPalette,
                        builder: (context, currentPalette, _) {
                          return _buildRow(
                            icon: Icons.headphones_rounded,
                            iconColor: tokens.accent,
                            title: 'Audiobook UI & Player Studio',
                            subtitle:
                                'Hero spotlight, 5 distinct player designs, drag & drop modular studio, waveform canvas scrubber, and custom controls',
                            value: playerPreset.label.split(' ').first,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AudiobookSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),

                  // Music UI & Player Studio
                  ValueListenableBuilder<MusicFullscreenPreset>(
                    valueListenable: MusicSettings.selectedFullscreenPreset,
                    builder: (context, fullPreset, _) {
                      return ValueListenableBuilder<AppThemePalette>(
                        valueListenable: AppThemeService.currentPalette,
                        builder: (context, currentPalette, _) {
                          return _buildRow(
                            icon: Icons.music_note_rounded,
                            iconColor: tokens.accent,
                            title: 'Music UI & Player Studio',
                            subtitle:
                                'Hero spotlight, lossless badges, and fullscreen player studio for layout, seekbar, physics & turntable styling',
                            value: fullPreset.label.split(' ').first,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MusicSettingsPage(),
                                ),
                              );
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),

              // ── Diagnostics (Windows graphics backend) ────────────────────
              if (Platform.isWindows) ...[
                const SizedBox(height: ZplaySpacing.s24),
                _buildGroup(
                  label: 'DIAGNOSTICS',
                  rows: [_buildRendererBackendContent()],
                ),
              ],
            ],
          ),
        ),
      ),
    ));
  }

  /// One labelled group: an overline header over the rows it gathers.
  ///
  /// The rows rest on the page canvas and are separated by hairline dividers,
  /// so a group reads as one section without a panel drawn around it.
  Widget _buildGroup({required String label, required List<Widget> rows}) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: ZplaySpacing.s4,
            bottom: ZplaySpacing.s8,
          ),
          child: Text(
            label,
            style: ZplayType.overline.toStyle(color: tokens.textMuted),
          ),
        ),
        Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: tokens.borderSubtle, height: 1),
              rows[i],
            ],
          ],
        ),
      ],
    );
  }

  /// A navigation row inside a group: leading icon, title + subtitle, the live
  /// value on the right, and a chevron. No icon chip and no badge pill.
  Widget _buildRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s16,
            vertical: ZplaySpacing.s12,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: ZplaySpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ZplayType.subtitle.toStyle(
                        color: tokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: ZplaySpacing.s2),
                    Text(
                      subtitle,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Text(
                value,
                textAlign: TextAlign.right,
                style: ZplayType.caption.toStyle(color: tokens.textMuted),
                maxLines: 1,
              ),
              const SizedBox(width: ZplaySpacing.s8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: tokens.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Windows graphics-backend panel. It lives inside its own group, so it
  /// carries no surface of its own — only the header row and the two choices.
  Widget _buildRendererBackendContent() {
    return ValueListenableBuilder<RendererBackend>(
      valueListenable: RendererBackendSettings.current,
      builder: (context, backend, _) {
        final tokens = context.tokens;
        return Padding(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: ZplaySpacing.s2),
                    child: Icon(
                      Icons.speed_rounded,
                      size: 20,
                      // The row reports a driver-compatibility state, so it
                      // borrows the semantic warning rather than the accent.
                      color: backend == RendererBackend.impeller
                          ? tokens.warning
                          : tokens.accent,
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Graphics Backend',
                                style: ZplayType.subtitle.toStyle(
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            Text(
                              backend.label,
                              style: ZplayType.caption.toStyle(
                                color: tokens.textMuted,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                        const SizedBox(height: ZplaySpacing.s2),
                        Text(
                          'Skia is recommended on Windows here — '
                          'Impeller coincided with an NVIDIA driver crash.',
                          style: ZplayType.bodySmall.toStyle(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s12),
              _buildBackendOption(
                backend: RendererBackend.skia,
                selected: backend == RendererBackend.skia,
              ),
              const SizedBox(height: ZplaySpacing.s8),
              _buildBackendOption(
                backend: RendererBackend.impeller,
                selected: backend == RendererBackend.impeller,
              ),
              const SizedBox(height: ZplaySpacing.s12),
              Row(
                children: [
                  Icon(
                    Icons.restart_alt_rounded,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  Expanded(
                    child: Text(
                      'Restart the app to apply — the backend is fixed when the engine starts.',
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackendOption({
    required RendererBackend backend,
    required bool selected,
  }) {
    final tokens = context.tokens;
    // Both rows carry the palette accent; the selected one is distinguished by
    // its fill and border rather than by a second hue.
    final color = tokens.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => RendererBackendSettings.setBackend(backend),
        borderRadius: ZplayRadius.smAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            // Only the selected choice wears a surface; the unselected one
            // rests on the canvas.
            color: selected ? tokens.accentSubtle : null,
            borderRadius: ZplayRadius.smAll,
            border: selected
                ? Border.all(
                    color: color.withValues(alpha: ZplayOpacity.borderStrong),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? color : tokens.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backend == RendererBackend.skia
                          ? 'Skia (Recommended)'
                          : 'Impeller',
                      style: ZplayType.label.toStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      backend.description,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
