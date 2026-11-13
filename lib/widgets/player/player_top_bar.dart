import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// Top header bar for the video player.
class PlayerTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// The source currently playing, shown as a tag beside the title so the
  /// viewer can see which provider they are on. Null hides the tag.
  ///
  /// This used to be called `quality` and fed the source's raw `name`, which for
  /// a built-in ZPlayHTTP source is the scraped group tag — the sweep read
  /// `111477` next to the title on the 1.5.5 build. The value is the label the
  /// source list shows for the same source, from one rule
  /// (`StreamSource.providerLabel`), so a chip over the video and the row the
  /// user picked can no longer disagree.
  final String? sourceLabel;

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
    this.sourceLabel,
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
                    if (sourceLabel != null && sourceLabel!.isNotEmpty) ...[
                      const SizedBox(width: ZplaySpacing.s8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: ZplaySpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.textPrimary.withValues(
                            alpha: ZplayOpacity.overlayHover,
                          ),
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          sourceLabel!.toUpperCase(),
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
              if (onToggleEpisodes != null)
                _TopBarBadge(
                  icon: Icons.video_library_rounded,
                  label: 'Episodes',
                  active: isEpisodesActive,
                  onTap: onToggleEpisodes!,
                ),
              if (onShowSources != null) ...[
                const SizedBox(width: 10),
                _TopBarBadge(
                  icon: Icons.playlist_play_rounded,
                  label: 'Sources',
                  active: isSourcesActive,
                  onTap: onShowSources!,
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

/// The Episodes / Sources pill in the top-right cluster: glass fill, accent
/// border and glow while its panel is the one open.
class _TopBarBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TopBarBadge({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableInkWell(
      onTap: onTap,
      borderRadius: ZplayRadius.smAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s12,
          vertical: ZplaySpacing.s8,
        ),
        decoration: BoxDecoration(
          color: active
              ? PlayerTheme.accent.withValues(alpha: 0.30)
              : tokens.bg.withValues(alpha: 0.20),
          borderRadius: ZplayRadius.smAll,
          border: Border.all(
            color: active
                ? PlayerTheme.accent.withValues(alpha: 0.85)
                : tokens.borderStrong,
            width: 1.2,
          ),
          boxShadow: active
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
              icon,
              size: 18,
              color: active ? tokens.accent : tokens.textPrimary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: ZplayType.label
                  .toStyle(color: tokens.textPrimary)
                  .copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
            ),
          ],
        ),
      ),
    );
  }
}
