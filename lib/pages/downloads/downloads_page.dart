import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:zplay/models/movie/movie_detail.dart';
import 'package:zplay/models/movie/video.dart';

import '../../models/download/download_task_model.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/download/download_service.dart';
import '../../utils/platform/open_file_location_helper.dart';
import '../../utils/platform/storage_space_helper.dart';
import '../../utils/download/download_path_helper.dart';
import '../player/player_screen.dart';
import '../../services/storage/app_image_cache.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/segmented_tabs.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

/// Which transfer list the page shows. Only the selected one is built.
enum DownloadTab { active, downloaded }

class _DownloadsPageState extends State<DownloadsPage> {
  /// The list the switcher is on. Changing it only swaps the content slivers.
  DownloadTab _tab = DownloadTab.active;

  /// Device capacity for the partition downloads land on, or null while it is
  /// being measured and whenever it cannot be determined. The meter is only
  /// drawn for a real measurement - see [_StorageBreakdownBar].
  StorageSpaceInfo? _storageInfo;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    try {
      final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
      final info = await StorageSpaceHelper.getAvailableSpace(dir);
      if (mounted) setState(() => _storageInfo = info);
    } catch (e) {
      // A host without the platform plugins - a widget test, a stripped build -
      // has no partition to measure. That is the same state as an unreadable
      // one: no meter, and the transfer lists carry on untouched.
      debugPrint('[DownloadsPage] storage probe failed: $e');
    }
  }

  void _playDownloadedMedia(DownloadTask task) {
    final file = File(task.targetFilePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on disk. It may have been moved or deleted.')),
      );
      return;
    }

    final detail = MovieDetail(
      id: task.mediaId,
      name: task.title,
      type: task.type,
      poster: task.posterUrl,
      background: task.backdropUrl,
      year: task.year,
    );

    Video? episodeVideo;
    if (task.season != null && task.episode != null) {
      episodeVideo = Video(
        id: '${task.mediaId}:${task.season}:${task.episode}',
        title: task.episodeTitle ?? 'Episode ${task.episode}',
        season: task.season ?? 1,
        episode: task.episode ?? 1,
        thumbnail: task.backdropUrl,
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: task.toLocalStreamSource(),
          title: task.title,
          detail: detail,
          episode: episodeVideo,
        ),
      ),
    );
  }

  void _confirmDelete(DownloadTask task) {
    final tokens = context.tokens;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
        title: Text(
          'Delete Download',
          style: ZplayType.title.toStyle(color: tokens.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${task.title}" and remove the file from storage?',
          style: ZplayType.body.toStyle(color: tokens.textEmphasis),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: ZplayType.label.toStyle(color: tokens.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.textPrimary,
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              DownloadService.instance.deleteDownload(task.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        final tokens = context.tokens;
        return Scaffold(
          backgroundColor: tokens.bg,
          body: AnimatedAmbientBackground(
            child: ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: DownloadService.instance.tasksNotifier,
              builder: (context, tasks, _) {
                final activeCount = tasks.where((t) => !t.isCompleted && !t.isFailed).length;
                final completedCount = tasks.where((t) => t.isCompleted).length;
                final activeTasks = tasks.where((t) => !t.isCompleted).toList();
                final completedTasks = tasks.where((t) => t.isCompleted).toList();

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(tokens, activeCount, completedCount),
                    ),
                    if (_storageInfo != null)
                      SliverToBoxAdapter(child: _StorageBreakdownBar(info: _storageInfo!)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          ZplaySpacing.s20,
                          ZplaySpacing.s16,
                          ZplaySpacing.s20,
                          ZplaySpacing.s4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedTabs<DownloadTab>(
                            semanticsLabel: 'Download list',
                            selected: _tab,
                            onSelected: (tab) => setState(() => _tab = tab),
                            options: [
                              SegmentedTabOption(
                                value: DownloadTab.active,
                                label: 'Active',
                                count: activeCount,
                              ),
                              SegmentedTabOption(
                                value: DownloadTab.downloaded,
                                label: 'Downloaded',
                                count: completedCount,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_tab == DownloadTab.active)
                      _buildActiveList(activeTasks, palette)
                    else
                      _buildCompletedList(completedTasks, palette),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The page's own title block. It is the first sliver, so nothing scrolls
  /// under it and it carries no tint; it pays the status-bar inset itself
  /// because the shell removes the top padding from this page's subtree.
  Widget _buildHeader(ZplayTokens tokens, int activeCount, int completedCount) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        MediaQuery.paddingOf(context).top + ZplaySpacing.s12,
        ZplaySpacing.s8,
        ZplaySpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Downloads',
                  style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                ),
                const SizedBox(height: ZplaySpacing.s2),
                Text(
                  '$activeCount active • $completedCount downloaded',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.folder_open_rounded,
              color: tokens.textSecondary,
              size: 22,
            ),
            tooltip: 'Open Downloads Folder',
            onPressed: () async {
              final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
              final opened = await OpenFileLocationHelper.openLocation(dir);
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder path: $dir')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveList(List<DownloadTask> tasks, AppThemePalette palette) {
    final tokens = context.tokens;
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_done_rounded,
                size: 64,
                color: tokens.textDisabled,
              ),
              const SizedBox(height: ZplaySpacing.s16),
              Text(
                'No active downloads',
                style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'Media you download from the video player will show up here.',
                style: ZplayType.body.toStyle(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s16,
      ),
      sliver: SliverList.separated(
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s12),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _buildActiveCard(task, palette);
        },
      ),
    );
  }

  Widget _buildActiveCard(DownloadTask task, AppThemePalette palette) {
    final tokens = context.tokens;
    final progress = task.progressPercent;
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isFailed = task.status == DownloadStatus.failed;

    // The row's own activation is its primary action - pause while it is
    // running, resume or retry when it is not - so the row is a real remote
    // target that draws the ring. A task with no primary action (queued,
    // cancelled) is not turned into a focus stop it cannot act on.
    final VoidCallback? primaryAction = isDownloading
        ? () => DownloadService.instance.pauseDownload(task.id)
        : (isPaused || isFailed
            ? () => DownloadService.instance.resumeDownload(task.id)
            : null);

    // No fill and no border: the row is spacing over the page surface, and the
    // only edge it ever draws is the focus ring.
    return FocusableCard(
      onTap: primaryAction,
      enabled: primaryAction != null,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.mdAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          padding: const EdgeInsets.all(ZplaySpacing.s12),
          decoration: BoxDecoration(
            color: state.highlighted
                ? tokens.surfaceRaised.withValues(alpha: ZplayOpacity.overlayHover)
                : Colors.transparent,
            borderRadius: ZplayRadius.mdAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: ZplayRadius.smAll,
                    child: Container(
                      width: 50,
                      height: 70,
                      color: tokens.surface,
                      child: task.posterUrl != null && task.posterUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: task.posterUrl!,
                              cacheManager: AppImageCache.manager,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.movie_rounded,
                                color: tokens.textDisabled,
                              ))
                          : Icon(
                              Icons.movie_rounded,
                              color: tokens.textDisabled,
                            ),
                    ),
                  ),

                  const SizedBox(width: ZplaySpacing.s12),

                  // Title & Engine Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: ZplaySpacing.s4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ZplaySpacing.s4,
                                vertical: ZplaySpacing.s2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primaryColor.withValues(alpha: 0.15),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                task.sourceType == DownloadSourceType.p2p
                                    ? 'P2P Torrent'
                                    : (task.sourceType == DownloadSourceType.debrid ? 'Cloud Debrid' : 'Direct HTTP'),
                                style: ZplayType.caption.toStyle(
                                  color: palette.primaryColor,
                                ),
                              ),
                            ),
                            if (task.peers > 0) ...[
                              const SizedBox(width: ZplaySpacing.s8),
                              Text(
                                '${task.peers} peers',
                                style: ZplayType.caption.toStyle(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: ZplaySpacing.s4),
                        Text(
                          isFailed
                              ? 'Failed: ${task.error ?? "Unknown error"}'
                              : isPaused
                                  ? 'Paused (${(progress * 100).toStringAsFixed(1)}%)'
                                  : '${(progress * 100).toStringAsFixed(1)}% • ${task.speedLabel} • ETA: ${task.etaLabel}',
                          style: ZplayType.bodySmall.toStyle(
                            color: isFailed
                                ? tokens.danger
                                : (isPaused ? tokens.warning : tokens.textEmphasis),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDownloading)
                        IconButton(
                          icon: Icon(
                            Icons.pause_circle_rounded,
                            color: tokens.warning,
                            size: 26,
                          ),
                          tooltip: 'Pause',
                          onPressed: () => DownloadService.instance.pauseDownload(task.id),
                        )
                      else if (isPaused)
                        IconButton(
                          icon: Icon(Icons.play_circle_fill_rounded, color: palette.primaryColor, size: 26),
                          tooltip: 'Resume',
                          onPressed: () => DownloadService.instance.resumeDownload(task.id),
                        )
                      else if (isFailed)
                        IconButton(
                          icon: Icon(
                            Icons.replay_rounded,
                            color: tokens.warning,
                            size: 26,
                          ),
                          tooltip: 'Retry / Reconnect',
                          onPressed: () => DownloadService.instance.resumeDownload(task.id),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.folder_open_rounded,
                          color: tokens.textSecondary,
                          size: 22,
                        ),
                        tooltip: 'Open Folder Location',
                        onPressed: () async {
                          final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Folder: ${File(task.targetFilePath).parent.path}')),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: tokens.textMuted,
                          size: 22,
                        ),
                        tooltip: 'Cancel',
                        onPressed: () => _confirmDelete(task),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: ZplaySpacing.s12),

              // Progress Bar
              ClipRRect(
                borderRadius: ZplayRadius.xsAll,
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 5,
                  backgroundColor: tokens.borderDefault,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFailed
                        ? tokens.danger
                        : (isPaused ? tokens.warning : palette.primaryColor),
                  ),
                ),
              ),
              const SizedBox(height: ZplaySpacing.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    task.sizeLabel,
                    style: ZplayType.caption.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: ZplayType.caption.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedList(List<DownloadTask> tasks, AppThemePalette palette) {
    final tokens = context.tokens;
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 64,
                color: tokens.textDisabled,
              ),
              const SizedBox(height: ZplaySpacing.s16),
              Text(
                'No downloaded media',
                style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'Completed downloads will appear here for offline playback.',
                style: ZplayType.body.toStyle(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(ZplaySpacing.s16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: ZplaySpacing.s12,
          crossAxisSpacing: ZplaySpacing.s12,
          childAspectRatio: 0.58,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildCompletedCard(tasks[index], palette),
          childCount: tasks.length,
        ),
      ),
    );
  }

  Widget _buildCompletedCard(DownloadTask task, AppThemePalette palette) {
    final tokens = context.tokens;
    // No fill and no border: the artwork is the card and the spacing around it
    // is the only chrome; the wash belongs to the pointer, the ring to the
    // remote.
    return FocusableCard(
      // The whole tile plays: the poster is the control and the centred play
      // glyph inside it is that control's visual, not a second focus stop.
      onTap: () => _playDownloadedMedia(task),
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.mdAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          decoration: BoxDecoration(
            color: state.highlighted
                ? tokens.surfaceRaised.withValues(alpha: ZplayOpacity.overlayHover)
                : Colors.transparent,
            borderRadius: ZplayRadius.mdAll,
          ),
          child: ClipRRect(
            borderRadius: ZplayRadius.mdAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster / Backdrop Thumbnail with Play Trigger
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: tokens.surface,
                        child: task.posterUrl != null && task.posterUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: task.posterUrl!,
                                cacheManager: AppImageCache.manager,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Center(
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: tokens.textDisabled,
                                    size: 36,
                                  ),
                                ))
                            : Center(
                                child: Icon(
                                  Icons.movie_rounded,
                                  color: tokens.textDisabled,
                                  size: 36,
                                ),
                              ),
                      ),

                      // Gradient
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Center Play Button - the tile's own activation is the
                      // play action, so this is its visual, not a second stop.
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.primaryColor,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: tokens.onAccent,
                            size: 28,
                          ),
                        ),
                      ),

                      // Open Folder Location (Top-Left)
                      Positioned(
                        top: ZplaySpacing.s4,
                        left: ZplaySpacing.s4,
                        child: FocusableCard(
                          onTap: () async {
                            final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Path: ${task.targetFilePath}')),
                              );
                            }
                          },
                          builder: (context, state) => Container(
                            padding: const EdgeInsets.all(ZplaySpacing.s4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.7),
                              border: Border.all(
                                color: tokens.borderStrong,
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              Icons.folder_open_rounded,
                              size: 14,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ),

                      // Delete Action (Top-Right)
                      Positioned(
                        top: ZplaySpacing.s4,
                        right: ZplaySpacing.s4,
                        child: FocusableCard(
                          onTap: () => _confirmDelete(task),
                          builder: (context, state) => Container(
                            padding: const EdgeInsets.all(ZplaySpacing.s4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.7),
                              border: Border.all(
                                color: tokens.borderStrong,
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 14,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ),

                      // File size tag (Bottom-Right)
                      Positioned(
                        bottom: ZplaySpacing.s4,
                        right: ZplaySpacing.s4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s4,
                            vertical: ZplaySpacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            DownloadTask.formatBytes(task.totalBytes),
                            style: ZplayType.caption.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Metadata Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZplaySpacing.s8,
                    ZplaySpacing.s8,
                    ZplaySpacing.s8,
                    ZplaySpacing.s8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.label.toStyle(
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: ZplaySpacing.s2),
                      Text(
                        task.season != null && task.episode != null
                            ? 'S${task.season}:E${task.episode} • Offline'
                            : (task.year != null ? '${task.year} • Offline' : 'Offline Media'),
                        style: ZplayType.caption.toStyle(
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
      ),
    );
  }
}

/// The device-storage breakdown above the transfer lists.
///
/// Only ever built from a real measurement: `StorageSpaceHelper` returns null
/// when it cannot read the partition, and the caller draws nothing then. A meter
/// is a claim about the device, so a made-up capacity would be worse than no
/// meter - the point of the row is to tell someone whether the next download
/// fits.
class _StorageBreakdownBar extends StatelessWidget {
  const _StorageBreakdownBar({required this.info});

  final StorageSpaceInfo info;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final usedBytes = (info.totalBytes - info.freeBytes).clamp(
      0,
      info.totalBytes,
    );
    final usedFraction = info.totalBytes <= 0
        ? 0.0
        : usedBytes / info.totalBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s16,
        ZplaySpacing.s12,
        ZplaySpacing.s16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s16,
          vertical: ZplaySpacing.s12,
        ),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: ZplayRadius.smAll,
          border: Border.all(color: tokens.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Device Storage: ${DownloadTask.formatBytes(usedBytes)} Used of ${info.totalFormatted}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.label.toStyle(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s12),
                Text(
                  '${info.freeFormatted} Free',
                  style: ZplayType.caption.toStyle(color: tokens.textMuted),
                ),
              ],
            ),
            const SizedBox(height: ZplaySpacing.s8),
            ClipRRect(
              borderRadius: ZplayRadius.xsAll,
              child: LinearProgressIndicator(
                value: usedFraction,
                minHeight: 8,
                backgroundColor: tokens.surfaceRaised,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
