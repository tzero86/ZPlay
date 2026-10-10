import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/anime/anime_media.dart';
import '../../models/movie/movie.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../../services/anime/extractors/anidb_extractor.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/horizontal_edge_fade.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/movie/movie_card.dart';
import '../../services/storage/app_image_cache.dart';

class AnimeDetailsModal extends StatefulWidget {
  final AnimeMedia initialAnime;
  final Function(AnimeMedia anime, int episodeNumber, bool isDub) onPlayEpisode;
  final Function(AnimeMedia) onNavigateToAnime;
  final VoidCallback onClose;

  const AnimeDetailsModal({
    super.key,
    required this.initialAnime,
    required this.onPlayEpisode,
    required this.onNavigateToAnime,
    required this.onClose,
  });

  @override
  State<AnimeDetailsModal> createState() => _AnimeDetailsModalState();
}

class _AnimeDetailsModalState extends State<AnimeDetailsModal> {
  late AnimeMedia _anime;
  bool _isLoadingDetails = true;
  bool _isDub = false;
  int _selectedEpisodeBatch = 0; // 50 episodes per batch
  int? _highlightedEpisode;
  List<AniDbEpisode>? _aniDbEpisodes;

  final TextEditingController _jumpEpController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();

  final ScrollController _relationsScrollController = ScrollController();
  final ScrollController _recsScrollController = ScrollController();
  final ScrollController _castScrollController = ScrollController();

  static const int _chunkSize = 50;

  @override
  void initState() {
    super.initState();
    _anime = widget.initialAnime;
    _fetchFullDetails();
    _resolveAniDbEpisodes();
  }

  @override
  void didUpdateWidget(AnimeDetailsModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAnime.id != widget.initialAnime.id) {
      setState(() {
        _anime = widget.initialAnime;
        _isLoadingDetails = true;
        _selectedEpisodeBatch = 0;
        _highlightedEpisode = null;
        _aniDbEpisodes = null;
      });
      _jumpEpController.clear();
      _fetchFullDetails();
      _resolveAniDbEpisodes();
    }
  }

  @override
  void dispose() {
    _jumpEpController.dispose();
    _keyboardFocusNode.dispose();
    _relationsScrollController.dispose();
    _recsScrollController.dispose();
    _castScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchFullDetails() async {
    final full = await AnilistService.instance.fetchAnimeDetails(_anime.id);
    if (full != null && mounted) {
      setState(() {
        _anime = full;
        _isLoadingDetails = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingDetails = false);
    }
  }

  void _resolveAniDbEpisodes() async {
    try {
      final slug = await AniDbExtractor.instance.mapAnime(
        titleCandidates: [
          _anime.titleEnglish,
          _anime.titleRomaji,
          _anime.titleNative,
          _anime.titleUserPreferred,
        ].where((t) => t.isNotEmpty).toList(),
      );
      if (slug != null) {
        final episodes = await AniDbExtractor.instance.getEpisodes(slug);
        if (episodes != null && mounted) {
          setState(() {
            _aniDbEpisodes = episodes;
          });
        }
      }
    } catch (_) {}
  }

  int get _computedTotalEpisodes {
    if (_aniDbEpisodes != null && _aniDbEpisodes!.isNotEmpty) {
      return _aniDbEpisodes!.length;
    }
    if (_anime.totalEpisodes > 0) return _anime.totalEpisodes;
    if (_anime.nextAiring != null && _anime.nextAiring!.episode > 1) {
      return _anime.nextAiring!.episode - 1;
    }
    if (_anime.format.toUpperCase() == 'MOVIE') return 1;
    return 24;
  }

  void _jumpToEpisode(String value) {
    final ep = int.tryParse(value.trim());
    if (ep == null || ep <= 0) return;

    final totalEps = _computedTotalEpisodes;
    final targetEp = ep.clamp(1, totalEps);
    final targetBatch = ((targetEp - 1) / _chunkSize).floor();

    setState(() {
      _selectedEpisodeBatch = targetBatch;
      _highlightedEpisode = targetEp;
    });
    FocusScope.of(context).unfocus();
  }

  /// Opens the watch-status menu under the pill that was activated.
  ///
  /// The items, the surface and the `library.setWatchlistStatus` callback are
  /// exactly what the old `PopupMenuButton` posted; only the positioning is
  /// copied from the discover page's chip menu, and only the second focus node
  /// the button's child painted is dropped.
  Future<void> _openStatusMenu(BuildContext anchor) async {
    final tokens = ZplayTokens.of(context);
    final button = anchor.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;

    final status = await showMenu<AnimeWatchStatus>(
      context: anchor,
      color: tokens.surfaceOverlay,
      constraints: const BoxConstraints(maxHeight: 360),
      shape: RoundedRectangleBorder(
        borderRadius: ZplayRadius.smAll,
        side: BorderSide(color: tokens.borderStrong),
      ),
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: AnimeWatchStatus.watching,
          child: Text('Watching',
              style: ZplayType.body.toStyle(color: tokens.textPrimary)),
        ),
        PopupMenuItem(
          value: AnimeWatchStatus.planToWatch,
          child: Text('Plan to Watch',
              style: ZplayType.body.toStyle(color: tokens.textPrimary)),
        ),
        PopupMenuItem(
          value: AnimeWatchStatus.completed,
          child: Text('Completed',
              style: ZplayType.body.toStyle(color: tokens.textPrimary)),
        ),
        PopupMenuItem(
          value: AnimeWatchStatus.dropped,
          child: Text('Dropped',
              style: ZplayType.body.toStyle(color: tokens.textSecondary)),
        ),
      ],
    );

    if (status != null) {
      AnimeLibraryService.instance.setWatchlistStatus(_anime, status);
      if (mounted) setState(() {});
    }
  }

  /// A display-only [Movie] for the relations rail, so a franchise entry can
  /// sit in the rail as the same [MovieCard] the rest of the app's rails use.
  /// It is only ever drawn: the tap still goes through the AniList lookup.
  Movie _relationAsMovie(AnimeRelation rel) => Movie(
        id: 'anilist_${rel.id}',
        name: rel.title,
        poster: rel.coverUrl.isEmpty ? null : rel.coverUrl,
        type: 'anime',
        addonBaseUrl: '',
      );

  /// A display-only [Movie] for the recommendations rail. See
  /// [_relationAsMovie] for why the tap is not the card's own.
  Movie _recommendationAsMovie(AnimeMedia rec) => Movie(
        id: 'anilist_${rec.id}',
        name: rec.displayTitle,
        poster: rec.coverUrl.isEmpty ? null : rec.coverUrl,
        year: rec.seasonYear > 0 ? '${rec.seasonYear}' : null,
        type: 'anime',
        addonBaseUrl: '',
      );

  @override
  Widget build(BuildContext context) {
    final library = AnimeLibraryService.instance;
    final watchItem = library.getWatchlistItem(_anime.id);
    final size = MediaQuery.sizeOf(context);
    final tokens = ZplayTokens.of(context);
    final isMobile = size.width < 750;
    final sizing = MovieCardSizing.fromWidth(size.width);

    final modalWidth = isMobile ? size.width - 16 : math.min(size.width * 0.94, 980.0);
    final modalHeight = isMobile ? size.height * 0.94 : math.min(size.height * 0.94, 820.0);

    final totalEps = _computedTotalEpisodes;
    final totalBatches = (totalEps / _chunkSize).ceil().clamp(1, 9999);
    final currentBatchSafe = _selectedEpisodeBatch.clamp(0, totalBatches - 1);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent closing when tapping inside modal content
              child: PerformanceLiquidLens(
                style: PerformanceGlassStyles.sheet,
                child: Container(
                  width: modalWidth,
                  height: modalHeight,
                  decoration: BoxDecoration(
                    color: tokens.surfaceOverlay,
                    borderRadius: ZplayRadius.sheetTop,
                    border: Border.all(color: tokens.borderStrong),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.75),
                        blurRadius: 40,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: ZplayRadius.sheetTop,
                    child: Column(
                      children: [
                        // Top Backdrop Header
                        Stack(
                          children: [
                            SizedBox(
                              height: isMobile ? 190 : 250,
                              width: double.infinity,
                              child: CachedNetworkImage(
                                imageUrl: _anime.backdropUrl,
                                cacheManager: AppImageCache.manager,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                errorWidget: (_, __, ___) => Container(
                                  color: tokens.surface,
                                )),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.25),
                                      tokens.surfaceOverlay.withValues(
                                        alpha: 0.75,
                                      ),
                                      tokens.surfaceOverlay,
                                    ],
                                    stops: const [0.0, 0.65, 1.0],
                                  ),
                                ),
                              ),
                            ),

                            if (_isLoadingDetails)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  color: tokens.accent,
                                  backgroundColor: Colors.transparent,
                                  minHeight: 2.5,
                                ),
                              ),

                            // Top Back and Close Buttons (Always visible on any window size)
                            Positioned(
                              top: 14,
                              left: 14,
                              child: _buildHeaderIconButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                onTap: widget.onClose,
                              ),
                            ),
                            Positioned(
                              top: 14,
                              right: 14,
                              child: _buildHeaderIconButton(
                                icon: Icons.close_rounded,
                                onTap: widget.onClose,
                              ),
                            ),

                            // Title & Badges in Header
                            Positioned(
                              left: isMobile ? 16 : 24,
                              right: isMobile ? 60 : 80,
                              bottom: 12,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (_anime.averageScore > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                tokens.warning,
                                                Color.lerp(
                                                      tokens.warning,
                                                      Colors.black,
                                                      0.15,
                                                    ) ??
                                                    tokens.warning,
                                              ],
                                            ),
                                            borderRadius: ZplayRadius.smAll,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, color: Colors.black, size: 13),
                                              const SizedBox(width: 3),
                                              Text(
                                                _anime.formattedScore,
                                                style: ZplayType.caption
                                                    .copyWith(
                                                      weight: FontWeight.w900,
                                                    )
                                                    .toStyle(
                                                      color: Colors.black,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: tokens.accent,
                                          borderRadius: ZplayRadius.smAll,
                                        ),
                                        child: Text(
                                          _anime.formattedFormat.toUpperCase(),
                                          style: ZplayType.overline.copyWith(weight: FontWeight.w900).toStyle(color: tokens.onAccent),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: tokens.borderStrong,
                                          borderRadius: ZplayRadius.smAll,
                                        ),
                                        child: Text(
                                          _anime.formattedStatus,
                                          style: ZplayType.overline.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                                        ),
                                      ),
                                      if (_anime.seasonYear > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: tokens.borderDefault,
                                            borderRadius: ZplayRadius.smAll,
                                          ),
                                          child: Text(
                                            '${_anime.seasonYear}',
                                            style: ZplayType.overline.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textEmphasis),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: ZplaySpacing.s8),
                                  Text(
                                    _anime.displayTitle,
                                    style: ZplayType.display
                                        .copyWith(
                                          size: isMobile ? 20 : 26,
                                          weight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                        )
                                        .toStyle(color: tokens.textPrimary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_anime.titleNative.isNotEmpty)
                                    Text(
                                      _anime.titleNative,
                                      style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Scrollable Content Body
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile
                                  ? ZplaySpacing.s16
                                  : ZplaySpacing.s24,
                              vertical: ZplaySpacing.s12,
                            ),
                            physics: const BouncingScrollPhysics(),
                            children: [
                              // Action Row: Play + Add to List + SUB/DUB toggle
                              Row(
                                children: [
                                  PillButton(
                                    label: watchItem != null &&
                                            watchItem.lastWatchedEpisode > 0
                                        ? 'Resume Ep ${watchItem.lastWatchedEpisode}'
                                        : 'Play Ep 1',
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: () {
                                      final epToPlay = watchItem?.lastWatchedEpisode ?? 1;
                                      widget.onPlayEpisode(_anime, epToPlay, _isDub);
                                    },
                                  ),
                                  const SizedBox(width: ZplaySpacing.s12),

                                  // Watchlist Status Popup
                                  Builder(
                                    builder: (buttonContext) => PillButton(
                                      label: watchItem != null
                                          ? watchItem.status.name.toUpperCase()
                                          : 'ADD TO LIST',
                                      variant: PillVariant.secondary,
                                      icon: watchItem != null
                                          ? Icons.check_circle_rounded
                                          : Icons.bookmark_outline_rounded,
                                      onPressed: () =>
                                          _openStatusMenu(buttonContext),
                                    ),
                                  ),

                                  const Spacer(),

                                  // SUB / DUB Toggle
                                  SegmentedTabs<bool>(
                                    options: const [
                                      SegmentedTabOption<bool>(
                                          value: false, label: 'SUB'),
                                      SegmentedTabOption<bool>(
                                          value: true, label: 'DUB'),
                                    ],
                                    selected: _isDub,
                                    onSelected: (value) =>
                                        setState(() => _isDub = value),
                                    height: 40,
                                  ),
                                ],
                              ),

                              // Synopsis
                              if (_anime.description.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Text(
                                  _anime.description,
                                  style: ZplayType.body.copyWith(height: 1.5).toStyle(color: tokens.textEmphasis),
                                ),
                              ],

                              // Genres Chips
                              if (_anime.genres.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _anime.genres
                                      .map(
                                        (g) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZplaySpacing.s4),
                                          decoration: BoxDecoration(
                                            color: tokens.borderSubtle,
                                            borderRadius: ZplayRadius.mdAll,
                                            border: Border.all(color: tokens.borderStrong),
                                          ),
                                          child: Text(
                                            g,
                                            style: ZplayType.caption.toStyle(color: tokens.textEmphasis),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],

                              const SizedBox(height: ZplaySpacing.s24),
                              Divider(color: tokens.borderDefault),
                              const SizedBox(height: 14),

                              // ─── EPISODES HEADER & 50-CHUNK PAGINATION + JUMP FIELD ───
                              _onRailGrid(
                                SectionHeader(
                                  title: 'Episodes',
                                  trailing: Text(
                                    '($totalEps total)',
                                    style: ZplayType.labelNumeric
                                        .toStyle(color: tokens.textMuted),
                                  ),
                                ),
                              ),

                              const SizedBox(height: ZplaySpacing.s12),

                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // Jump to episode + Page selector
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Jump input field
                                      Container(
                                        width: 130,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: tokens.surface,
                                          borderRadius: ZplayRadius.smAll,
                                          border: Border.all(color: tokens.borderStrong),
                                        ),
                                        child: TextField(
                                          controller: _jumpEpController,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.go,
                                          onSubmitted: _jumpToEpisode,
                                          style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                                          decoration: InputDecoration(
                                            hintText: 'Jump to ep #',
                                            hintStyle: ZplayType.caption.toStyle(color: tokens.textMuted),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8, vertical: 10),
                                            suffixIcon: IconButton(
                                              padding: EdgeInsets.zero,
                                              icon: Icon(Icons.arrow_forward_rounded, color: tokens.accent, size: 16),
                                              onPressed: () => _jumpToEpisode(_jumpEpController.text),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 10),

                                      // Prev Batch Arrow
                                      IconButton(
                                        icon: Icon(Icons.chevron_left_rounded, color: tokens.textEmphasis, size: 20),
                                        onPressed: currentBatchSafe > 0
                                            ? () => setState(() => _selectedEpisodeBatch = currentBatchSafe - 1)
                                            : null,
                                      ),

                                      // 50-Episode Chunk Dropdown
                                      if (totalBatches > 1)
                                        Container(
                                          height: 34,
                                          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                                          decoration: BoxDecoration(
                                            color: tokens.surface,
                                            borderRadius: ZplayRadius.smAll,
                                            border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
                                          ),
                                          child: DropdownButton<int>(
                                            value: currentBatchSafe,
                                            underline: const SizedBox.shrink(),
                                            dropdownColor: tokens.surfaceOverlay,
                                            style: ZplayType.bodySmall.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                                            icon: Icon(Icons.expand_more_rounded, color: tokens.accent, size: 16),
                                            items: List.generate(
                                              totalBatches,
                                              (idx) {
                                                final start = idx * _chunkSize + 1;
                                                final end = math.min((idx + 1) * _chunkSize, totalEps);
                                                return DropdownMenuItem(
                                                  value: idx,
                                                  child: Text('$start – $end'),
                                                );
                                              },
                                            ),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() => _selectedEpisodeBatch = val);
                                              }
                                            },
                                          ),
                                        ),

                                      // Next Batch Arrow
                                      IconButton(
                                        icon: Icon(Icons.chevron_right_rounded, color: tokens.textEmphasis, size: 20),
                                        onPressed: currentBatchSafe < totalBatches - 1
                                            ? () => setState(() => _selectedEpisodeBatch = currentBatchSafe + 1)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 14),

                              // Episode Grid with Hover Effects
                              _buildEpisodeGrid(
                                totalEps,
                                currentBatchSafe * _chunkSize,
                                math.min((currentBatchSafe + 1) * _chunkSize, totalEps),
                                watchItem?.lastWatchedEpisode,
                              ),

                              // Characters & Voice Cast
                              if (_anime.characters.isNotEmpty) ...[
                                const SizedBox(height: ZplaySpacing.s32),
                                _onRailGrid(
                                  const SectionHeader(
                                      title: 'Characters & Voice Cast'),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 145,
                                  child: HorizontalEdgeFade(
                                    scrollController: _castScrollController,
                                    extent: isMobile ? 40 : 60,
                                    child: ListView.separated(
                                      clipBehavior: Clip.none,
                                      controller: _castScrollController,
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: _anime.characters.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                                      itemBuilder: (context, index) {
                                        final char = _anime.characters[index];
                                        return SizedBox(
                                          width: 90,
                                          child: Column(
                                            children: [
                                              ClipRRect(
                                                borderRadius: ZplayRadius.smAll,
                                                child: CachedNetworkImage(
                                                  imageUrl: char.imageLarge,
                                                  cacheManager: AppImageCache.manager,
                                                  memCacheWidth: 255,
                                                  width: 85,
                                                  height: 85,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => Container(
                                                    color: tokens.surfaceRaised,
                                                    child: Icon(Icons.person_rounded, color: tokens.textDisabled),
                                                  )),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                char.nameFull,
                                                style: ZplayType.caption.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                              Text(
                                                char.role,
                                                style: ZplayType.overline.toStyle(color: tokens.textMuted),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                      );
                                    },
                                  ),
                                  ),
                                ),
                              ],

                              // Franchise & Relations
                              if (_anime.relations.isNotEmpty) ...[
                                const SizedBox(height: ZplaySpacing.s32),
                                _onRailGrid(
                                  const SectionHeader(
                                      title: 'Franchise & Relations'),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: sizing.totalHeight,
                                  child: HorizontalEdgeFade(
                                    scrollController: _relationsScrollController,
                                    extent: isMobile ? 40 : 60,
                                    child: ListView.separated(
                                      clipBehavior: Clip.none,
                                      controller: _relationsScrollController,
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: _anime.relations.length,
                                      separatorBuilder: (_, __) =>
                                          SizedBox(width: sizing.spacing),
                                      itemBuilder: (context, index) {
                                        final rel = _anime.relations[index];
                                        return SizedBox(
                                          width: sizing.cardWidth,
                                          child: MovieCard(
                                            movie: _relationAsMovie(rel),
                                            onTap: () async {
                                              final media = await AnilistService
                                                  .instance
                                                  .fetchAnimeDetails(rel.id);
                                              if (media != null) {
                                                widget.onNavigateToAnime(media);
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],

                              // Recommendations / You May Also Like
                              if (_anime.recommendations.isNotEmpty) ...[
                                const SizedBox(height: ZplaySpacing.s32),
                                _onRailGrid(
                                  const SectionHeader(
                                      title: 'You May Also Like'),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: sizing.totalHeight,
                                  child: HorizontalEdgeFade(
                                    scrollController: _recsScrollController,
                                    extent: isMobile ? 40 : 60,
                                    child: ListView.separated(
                                      clipBehavior: Clip.none,
                                      controller: _recsScrollController,
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: _anime.recommendations.length,
                                      separatorBuilder: (_, __) =>
                                          SizedBox(width: sizing.spacing),
                                      itemBuilder: (context, index) {
                                        final rec = _anime.recommendations[index];
                                        return SizedBox(
                                          width: sizing.cardWidth,
                                          child: MovieCard(
                                            movie: _recommendationAsMovie(rec),
                                            onTap: () =>
                                                widget.onNavigateToAnime(rec),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: ZplaySpacing.s24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderIconButton({required IconData icon, required VoidCallback onTap}) {
    final tokens = ZplayTokens.of(context);
    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.fullAll,
        child: ClipRRect(
          borderRadius: ZplayRadius.fullAll,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(ZplaySpacing.s8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: tokens.textDisabled),
              ),
              child: Icon(icon, color: tokens.textPrimary, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeGrid(
    int total,
    int startIndex,
    int endIndex,
    int? lastWatchedEp,
  ) {
    final count = endIndex - startIndex;

    final tokens = ZplayTokens.of(context);
    if (count <= 0) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 75,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final epNum = startIndex + index + 1;
        final isWatched = lastWatchedEp != null && epNum <= lastWatchedEp;
        final isCurrent = lastWatchedEp == epNum;
        final isHighlighted = _highlightedEpisode == epNum;

        return FocusableCard(
          onTap: () => widget.onPlayEpisode(_anime, epNum, _isDub),
          builder: (_, state) => CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: AnimatedScale(
              duration: ZplayMotion.fast,
              curve: ZplayMotion.standard,
              // The lift answers the pointer, not focus: on a television a
              // D-pad press must not nudge the tile the user is aiming at.
              scale: state.hovered ? 1.04 : 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? tokens.danger.withValues(alpha: 0.30)
                      : isCurrent
                          ? tokens.accent.withValues(alpha: 0.35)
                          : (isWatched
                              ? tokens.borderDefault
                              : tokens.surface),
                  borderRadius: ZplayRadius.smAll,
                  border: Border.all(
                    color: isHighlighted
                        ? tokens.danger
                        : isCurrent
                            ? tokens.accent
                            : (isWatched
                                ? tokens.textDisabled
                                : tokens.borderDefault),
                    width: (isCurrent || isHighlighted) ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$epNum',
                    style: ZplayType.label
                        .copyWith(
                          weight: (isCurrent || isHighlighted)
                              ? FontWeight.w900
                              : FontWeight.w700,
                        )
                        .toStyle(
                          color: isHighlighted
                              ? tokens.danger
                              : isCurrent
                                  ? tokens.accent
                                  : (isWatched
                                        ? tokens.textEmphasis
                                        : tokens.textPrimary),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The shared [SectionHeader], placed on this modal's own grid.
  ///
  /// See [_onRailGrid] for why the header's own inset is cancelled.
  Widget _onRailGrid(Widget child) {
    return Transform.translate(
      offset: const Offset(-ZplaySpacing.s16, 0),
      child: child,
    );
  }
}
