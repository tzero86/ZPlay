import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// Top header bar for the video player.
class PlayerTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? quality;
  final VoidCallback onBack;

  final VoidCallback? onToggleEpisodes;
  final bool isEpisodesActive;
  /// Opens the in-player sources panel; null hides the Sources badge.
  final VoidCallback? onShowSources;
  final bool isSourcesActive;
  final VoidCallback? onScreenshot;
  final VoidCallback? onToggleAspect;
  final VoidCallback? onCast;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final VoidCallback? onCopyStreamUrl;
  final VoidCallback? onLock;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.quality,
    required this.onBack,
    this.onToggleEpisodes,
    this.isEpisodesActive = false,
    this.onShowSources,
    this.isSourcesActive = false,
    this.onScreenshot,
    this.onToggleAspect,
    this.onCast,
    this.onDownload,
    this.isDownloading = false,
    this.onCopyStreamUrl,
    this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + ZplaySpacing.s12,
        left: ZplaySpacing.s24,
        right: ZplaySpacing.s24,
        bottom: ZplaySpacing.s24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.bg.withValues(alpha: 0.75),
            tokens.bg.withValues(alpha: 0.35),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frosted Glass Circular Back Button
          PlayerIconButton(
            size: 44,
            iconSize: 26,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Back',
            backgroundColor: tokens.bg.withValues(alpha: 0.20),
            borderRadius: ZplayRadius.full,
            onPressed: onBack,
          ),

          const SizedBox(width: ZplaySpacing.s16),

          // Title & Details Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: ZplayType.title
                            .toStyle(color: tokens.textPrimary)
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(
                                  color: Color(0x99000000),
                                  offset: Offset(0, 2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (quality != null && quality!.isNotEmpty) ...[
                      const SizedBox(width: ZplaySpacing.s8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: ZplaySpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.textPrimary
                              .withValues(alpha: ZplayOpacity.overlayHover),
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          quality!.toUpperCase(),
                          style: ZplayType.overline
                              .toStyle(color: tokens.textPrimary)
                              .copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: ZplaySpacing.s2),
                  Text(
                    subtitle!,
                    style: ZplayType.label
                        .toStyle(color: tokens.textEmphasis)
                        .copyWith(
                          fontWeight: FontWeight.w400,
                          shadows: const [
                            Shadow(
                              color: Color(0x99000000),
                              offset: Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Top-Right Action Badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onToggleEpisodes != null) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggleEpisodes,
                    borderRadius: ZplayRadius.smAll,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s12,
                        vertical: ZplaySpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: isEpisodesActive
                            ? PlayerTheme.accent.withValues(alpha: 0.30)
                            : tokens.bg.withValues(alpha: 0.20),
                        borderRadius: ZplayRadius.smAll,
                        border: Border.all(
                          color: isEpisodesActive
                              ? PlayerTheme.accent.withValues(alpha: 0.85)
                              : tokens.borderStrong,
                          width: 1.2,
                        ),
                        boxShadow: isEpisodesActive
                            ? [
                                BoxShadow(
                                  color: PlayerTheme.accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.video_library_rounded,
                            size: 18,
                            color: isEpisodesActive ? tokens.accent : tokens.textPrimary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'Episodes',
                            style: ZplayType.label
                                .toStyle(color: tokens.textPrimary)
                                .copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (onShowSources != null) ...[
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onShowSources,
                    borderRadius: ZplayRadius.smAll,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s12,
                        vertical: ZplaySpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: isSourcesActive
                            ? PlayerTheme.accent.withValues(alpha: 0.30)
                            : tokens.bg.withValues(alpha: 0.20),
                        borderRadius: ZplayRadius.smAll,
                        border: Border.all(
                          color: isSourcesActive
                              ? PlayerTheme.accent.withValues(alpha: 0.85)
                              : tokens.borderStrong,
                          width: 1.2,
                        ),
                        boxShadow: isSourcesActive
                            ? [
                                BoxShadow(
                                  color: PlayerTheme.accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.playlist_play_rounded,
                            size: 18,
                            color: isSourcesActive ? tokens.accent : tokens.textPrimary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'Sources',
                            style: ZplayType.label
                                .toStyle(color: tokens.textPrimary)
                                .copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (onCopyStreamUrl != null) ...[
                PlayerIconButton(
                  size: 40,
                  iconSize: 20,
                  icon: const Icon(Icons.link_rounded),
                  tooltip: 'Copy Stream URL',
                  backgroundColor: tokens.bg.withValues(alpha: 0.13),
                  onPressed: onCopyStreamUrl,
                ),
                const SizedBox(width: 8),
              ],
              if (onScreenshot != null) ...[
                PlayerIconButton(
                  size: 40,
                  iconSize: 20,
                  icon: const Icon(Icons.camera_alt_outlined),
                  tooltip: 'Screenshot',
                  backgroundColor: tokens.bg.withValues(alpha: 0.13),
                  onPressed: onScreenshot,
                ),
                const SizedBox(width: 8),
              ],
              if (onDownload != null) ...[
                PlayerIconButton(
                  size: 40,
                  iconSize: 20,
                  icon: isDownloading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.success,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined),
                  tooltip: isDownloading ? 'Downloading...' : 'Download Media',
                  backgroundColor: isDownloading
                      ? tokens.success.withValues(alpha: 0.2)
                      : tokens.bg.withValues(alpha: 0.13),
                  onPressed: onDownload,
                ),
                const SizedBox(width: 8),
              ],
              if (onLock != null) ...[
                PlayerIconButton(
                  size: 40,
                  iconSize: 20,
                  icon: const Icon(Icons.lock_outline_rounded),
                  tooltip: 'Lock Screen',
                  backgroundColor: tokens.bg.withValues(alpha: 0.13),
                  onPressed: onLock,
                ),
                const SizedBox(width: 8),
              ],
              if (onCast != null)
                PlayerIconButton(
                  size: 40,
                  iconSize: 20,
                  icon: const Icon(Icons.cast_rounded),
                  tooltip: 'Cast',
                  backgroundColor: tokens.bg.withValues(alpha: 0.13),
                  onPressed: onCast,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
