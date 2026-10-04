import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'About ZPlay'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s24,
            ),
            children: [
              // App Brand Header
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: ZplayRadius.lgAll,
                        boxShadow: [
                          BoxShadow(
                            color: tokens.accent.withValues(
                              alpha: ZplayOpacity.textDisabled,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: tokens.onAccent,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ZPlay',
                      style: ZplayType.display.toStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.hasData ? snapshot.data!.version : '1.1.6';
                        return Text(
                          'Version $version • Next-Gen Streaming Hub',
                          style: ZplayType.label.toStyle(
                            color: tokens.textSecondary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Description Card
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s20),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.lgAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Universal Entertainment Ecosystem',
                      style: ZplayType.subtitle.toStyle(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ZPlay is an all-in-one entertainment client bringing together movies, TV series, anime, live IPTV, music, manga, and audiobooks into a unified, high-performance interface with custom Liquid Glass visuals.',
                      style: ZplayType.body
                          .toStyle(color: tokens.textSecondary)
                          .copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Architecture & Core Technologies
              Text(
                'CORE TECHNOLOGIES',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              _buildTechTile(
                context: context,
                title: 'High-Performance Video Engine',
                subtitle: 'Powered by embedded media_kit / libmpv with hardware-accelerated decoding.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                context: context,
                title: 'Debrid & Multi-Source Scrapers',
                subtitle: 'Direct high-speed cloud playback via Real-Debrid, TorBox, and Stremio addons.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                context: context,
                title: 'Liquid Glass GLSL Shaders',
                subtitle: 'Custom real-time optical refraction, lenses, and fluid physics.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                context: context,
                title: 'Trakt & Cloud Synchronization',
                subtitle: 'Cross-platform watchlist, episode tracking, and playback scrobbling.',
              ),

              const SizedBox(height: 24),

              // Credits & Licence
              Text(
                'CREDITS & LICENCE',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              _buildLinkTile(
                context: context,
                icon: Icons.code_rounded,
                title: 'ZPlay',
                subtitle: 'Independent fork maintained by tzero86',
                url: 'https://github.com/tzero86/ZPlay',
              ),
              const SizedBox(height: 10),
              _buildLinkTile(
                context: context,
                icon: Icons.history_edu_rounded,
                title: 'Based on PlayTorrio V3',
                subtitle: 'Original project by Ayman (@ayman708-UX)',
                url: 'https://github.com/ayman708-UX/PlayTorrioV3',
              ),
              const SizedBox(height: 10),
              _buildTmdbAttributionTile(context),
              const SizedBox(height: 10),
              _buildLicenseTile(context),

              const SizedBox(height: 16),
              Text(
                'Poppins and Playfair Display are bundled under the SIL Open Font License 1.1.',
                style: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTechTile({
    required BuildContext context,
    required String title,
    required String subtitle,
  }) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: ZplayRadius.xsAll,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZplayType.subtitle.toStyle(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: ZplayType.bodySmall.toStyle(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A tappable credit row that opens [url] in the system browser.
  Widget _buildLinkTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    final tokens = context.tokens;
    return _CreditTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Icon(
        Icons.open_in_new_rounded,
        size: 16,
        color: tokens.textMuted,
      ),
      onTap: () => _openUrl(url),
    );
  }

  /// TMDb attribution, required by the TMDb terms: their logo, the notice
  /// verbatim, and a link back to themoviedb.org.
  Widget _buildTmdbAttributionTile(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/branding/tmdb-logo.png',
            height: 20,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) => Text(
              'TMDB',
              style: ZplayType.label.toStyle(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This product uses the TMDB API but is not endorsed or certified by TMDB.',
            style: ZplayType.bodySmall
                .toStyle(color: tokens.textSecondary)
                .copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _openUrl('https://www.themoviedb.org'),
            borderRadius: ZplayRadius.xsAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'themoviedb.org',
                style: ZplayType.label.toStyle(
                  color: tokens.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: tokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the licence notice: ZPlay's own GPL attribution header plus every
  /// third-party package licence Flutter collected at build time.
  Widget _buildLicenseTile(BuildContext context) {
    final tokens = context.tokens;
    return _CreditTile(
      icon: Icons.gavel_rounded,
      title: 'GNU GPL v3.0',
      subtitle:
          'ZPlay is a modified version of PlayTorrio V3, distributed under the '
          'GNU General Public License v3.0. Tap to read the licence.',
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: tokens.textMuted,
      ),
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'ZPlay',
        applicationLegalese: 'Copyright (C) 2026 tzero86\n'
            'Based on PlayTorrio V3, Copyright (C) 2026 Ayman\n'
            'https://github.com/tzero86/ZPlay\n'
            'https://github.com/ayman708-UX/PlayTorrioV3\n\n'
            'This program is free software: you can redistribute it and/or modify '
            'it under the terms of the GNU General Public License as published by '
            'the Free Software Foundation, either version 3 of the License, or '
            '(at your option) any later version.\n\n'
            'This program is distributed in the hope that it will be useful, but '
            'WITHOUT ANY WARRANTY; without even the implied warranty of '
            'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU '
            'General Public License for more details.',
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Shared visual for the credits rows on the About page.
class _CreditTile extends StatelessWidget {
  const _CreditTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      borderRadius: ZplayRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: ZplayRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: ZplayRadius.mdAll,
            border: Border.fromBorderSide(tokens.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: tokens.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ZplayType.subtitle.toStyle(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: ZplayType.bodySmall
                          .toStyle(color: tokens.textSecondary)
                          .copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
