import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/continue_watching/continue_watching_item.dart';
import '../../models/movie/movie.dart';
import '../../models/anime/anime_media.dart';
import '../../pages/details/details_page.dart';
import '../../pages/anime/anime_details_page.dart';
import '../../pages/anime_arabic/anime_arabic_details_page.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/content/content_settings.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../common/focusable_card.dart';
import '../common/section_header.dart';
import '../common/slider_arrow.dart';
import '../../services/storage/app_image_cache.dart';


/// Whether this platform has a pointer that can raise a hover, and so can be
/// trusted to reveal an affordance on demand.
///
/// [CardInteraction.highlighted] is `hovered || focused`, and neither ever goes
/// true on a touchscreen. Anything gated on it alone is invisible on a phone
/// and unreachable on D-pad, so those platforms show it at rest instead.
bool continueWatchingHasPointer() {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

class ContinueWatchingSlider extends StatefulWidget {
  final String? typeFilter; // 'main', 'anime', or null for all
  final String title;

  const ContinueWatchingSlider({
    super.key,
    this.typeFilter,
    this.title = 'Continue Watching',
  });

  @override
  State<ContinueWatchingSlider> createState() => _ContinueWatchingSliderState();
}

class _ContinueWatchingSliderState extends State<ContinueWatchingSlider> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHoveringSlider = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollButtons);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;
    final canLeft = _scrollController.position.pixels > 10;
    final canRight =
        _scrollController.position.pixels < _scrollController.position.maxScrollExtent - 10;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;
    final viewportWidth = _scrollController.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.8 * directionMultiplier;
    final target = (_scrollController.position.pixels + scrollAmount)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop() => continueWatchingHasPointer();

  /// Sessions saved before [ContinueWatchingItem.isAdult] existed are
  /// re-classified from their stored source fingerprint, so nothing adult
  /// survives a switch that is off.
  bool _isAdult(ContinueWatchingItem item) =>
      item.isAdult ||
      ContinueWatchingService.isAdultSession(
        id: item.id,
        type: item.type,
        addonName: item.addonName,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ContentSettings.adultEnabled,
      builder: (context, adultEnabled, _) => _buildSlider(context, adultEnabled),
    );
  }

  Widget _buildSlider(BuildContext context, bool adultEnabled) {
    final isDesktop = _isDesktop();

    return ValueListenableBuilder<List<ContinueWatchingItem>>(
      valueListenable: ContinueWatchingService.activeItems,
      builder: (context, allItems, _) {
        final items = allItems.where((i) {
          if (!adultEnabled && _isAdult(i)) return false;
          if (widget.typeFilter == 'main') {
            return i.type != 'anime' && !i.id.startsWith('anilist:') && !i.id.startsWith('arabic_anime:');
          } else if (widget.typeFilter == 'anime') {
            return i.type == 'anime' || i.id.startsWith('anilist:') || i.id.startsWith('arabic_anime:') || i.addonName == 'ArabicAnime';
          } else if (widget.typeFilter == 'arabic_anime') {
            return i.id.startsWith('arabic_anime:') || i.addonName == 'ArabicAnime';
          } else if (widget.typeFilter == 'general_anime') {
            return (i.type == 'anime' || i.id.startsWith('anilist:')) &&
                !i.id.startsWith('arabic_anime:') &&
                i.addonName != 'ArabicAnime';
          }
          return true;
        }).toList();

        if (items.isEmpty) return const SizedBox.shrink();

        final screenWidth = MediaQuery.sizeOf(context).width;
        final cardWidth = screenWidth > 900
            ? 280.0
            : screenWidth > 600
                ? 240.0
                : 200.0;
        final cardHeight = cardWidth * 0.62 + 60.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              SectionHeader(title: widget.title, count: items.length),

              const SizedBox(height: ZplaySpacing.s12),

              // Horizontal Card Slider with Desktop Floating Arrows
              MouseRegion(
                onEnter: (_) => setState(() => _isHoveringSlider = true),
                onExit: (_) => setState(() => _isHoveringSlider = false),
                child: SizedBox(
                  height: cardHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ListView.separated(
                        clipBehavior: Clip.none,
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s16,
                        ),
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: ZplaySpacing.s16),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ContinueWatchingCard(
                            item: item,
                            width: cardWidth,
                            onTap: () => ContinueWatchingService.resumePlayback(context, item),
                            onRemove: () => ContinueWatchingService.removeItem(item),
                          );
                        },
                      ),

                      if (isDesktop) ...[
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          left: _canScrollLeft && _isHoveringSlider ? 10 : -60,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: SliderArrow(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => _scroll(-1),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          right: _canScrollRight && _isHoveringSlider ? 10 : -60,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: SliderArrow(
                              icon: Icons.arrow_forward_ios_rounded,
                              onTap: () => _scroll(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContinueWatchingCard extends StatefulWidget {
  final ContinueWatchingItem item;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ContinueWatchingCard({
    required this.item,
    required this.width,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard> {
  void _openDetails(BuildContext context) {
    final item = widget.item;
    if (item.id.startsWith('arabic_anime:') || item.addonName == 'ArabicAnime') {
      final slug = item.id.replaceAll('arabic_anime:', '');
      final card = ArabicAnimeCard(
        slug: slug,
        title: item.title,
        cover: item.posterUrl ?? item.backdropUrl,
      );

      Navigator.push(
        context,
        CinematicSlideRoute(
          page: AnimeArabicDetailsPage(
            anime: card,
            initialEpisodeNumber: item.episode,
          ),
        ),
      );
      return;
    }

    if (item.type == 'anime' || item.id.startsWith('anilist:')) {
      final anilistId = int.tryParse(item.id.replaceAll('anilist:', '')) ?? 0;
      final anime = AnimeMedia(
        id: anilistId,
        titleEnglish: item.title,
        titleRomaji: item.title,
        titleNative: '',
        titleUserPreferred: item.title,
        coverImageLarge: item.posterUrl ?? '',
        coverImageExtraLarge: item.posterUrl ?? '',
        bannerImage: item.backdropUrl ?? '',
        description: '',
        seasonYear: int.tryParse(item.year ?? '') ?? 0,
        averageScore: 0,
        genres: const [],
        format: 'TV',
        status: 'RELEASING',
        totalEpisodes: 0,
      );

      Navigator.push(
        context,
        CinematicSlideRoute(page: AnimeDetailsPage(anime: anime)),
      );
    } else {
      final movie = Movie(
        id: item.id,
        name: item.title,
        poster: item.posterUrl ?? item.backdropUrl,
        year: item.year,
        type: item.type,
        addonBaseUrl: '',
      );

      final box = context.findRenderObject() as RenderBox?;
      final offset = box?.localToGlobal(box.size.center(Offset.zero));

      Navigator.push(
        context,
        LiquidRevealRoute(
          page: DetailsPage(movie: movie),
          tapPosition: offset,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final item = widget.item;
    final imgHeight = widget.width * 0.58;
    final progress = item.progressPercent;
    final imageUrl = item.backdropUrl ?? item.posterUrl;

    return FocusableCard(
      onTap: widget.onTap,
      builder: (_, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.mdAll,
        child: AnimatedContainer(
          duration: ZplayMotion.base,
          curve: ZplayMotion.standard,
          width: widget.width,
          // Focus stays put: the 3px ring marks the card, and paint never
          // moves the layout box, so siblings never re-flow.
          transform: state.hovered
              ? Matrix4.diagonal3Values(1.02, 1.02, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.75),
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: state.highlighted
                  ? tokens.borderStrong
                  : tokens.borderDefault,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: state.highlighted ? 0.45 : 0.30,
                ),
                blurRadius: state.highlighted ? 24 : 16,
                offset: Offset(0, state.highlighted ? 12 : 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: ZplayRadius.mdAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Backdrop / Thumbnail with Play Overlay & Badge
                Stack(
                  children: [
                    Container(
                      width: widget.width,
                      height: imgHeight,
                      color: tokens.surface,
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              cacheManager: AppImageCache.manager,
                              // Thumb is widget.width (200-280px) 16:9; bound to ~3x.
                              memCacheWidth: (widget.width * 3).round().clamp(96, 1280).toInt(),
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _buildPlaceholder(context))
                          : _buildPlaceholder(context),
                    ),

                    // Gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              tokens.bg.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Play button: permanently visible where there is no
                    // pointer to reveal it, hover-revealed where there is.
                    // Scale tracks the same rule so it never rests half-sized.
                    Positioned.fill(
                      child: Center(
                        child: Builder(
                          builder: (context) {
                            final revealed = state.highlighted ||
                                !continueWatchingHasPointer();
                            return AnimatedScale(
                              scale: revealed ? 1.0 : 0.8,
                              duration: const Duration(milliseconds: 180),
                              child: AnimatedOpacity(
                                opacity: revealed ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 180),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.accent,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            tokens.accent.withValues(alpha: 0.5),
                                        blurRadius: 14,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: tokens.textPrimary,
                                    size: 28,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Action Buttons (Top-Right: always on mobile, on highlight on desktop)
                    if (state.highlighted || !continueWatchingHasPointer())
                      Positioned(
                        top: ZplaySpacing.s8,
                        right: ZplaySpacing.s8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Details Button
                            Tooltip(
                              message: 'View Details',
                              child: FocusableCard(
                                onTap: () => _openDetails(context),
                                builder: (_, state) => Container(
                                  padding: const EdgeInsets.all(
                                    ZplaySpacing.s4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.bg.withValues(alpha: 0.75),
                                    border: Border.all(
                                      color: tokens.borderStrong,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            // Dismiss / Remove Button
                            Tooltip(
                              message: 'Remove from Continue Watching',
                              child: FocusableCard(
                                onTap: widget.onRemove,
                                builder: (_, state) => Container(
                                  padding: const EdgeInsets.all(
                                    ZplaySpacing.s4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.bg.withValues(alpha: 0.75),
                                    border: Border.all(
                                      color: tokens.borderStrong,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Source Tag (Top-Left)
                    Positioned(
                      top: ZplaySpacing.s8,
                      left: ZplaySpacing.s8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s8,
                          vertical: ZplaySpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.bg.withValues(alpha: 0.65),
                          borderRadius: ZplayRadius.xsAll,
                          border: Border.all(
                            color: tokens.borderStrong,
                            width: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.isTorrent ? Icons.cloud_download_rounded : Icons.link_rounded,
                              size: 10,
                              color: item.isTorrent
                                  ? tokens.info
                                  : tokens.success,
                            ),
                            const SizedBox(width: ZplaySpacing.s4),
                            Text(
                              item.addonName ?? (item.isTorrent ? 'Torrent' : 'Stream'),
                              style: ZplayType.overline.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Remaining time / Percentage (Bottom-Right)
                    Positioned(
                      bottom: ZplaySpacing.s8,
                      right: ZplaySpacing.s8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s8,
                          vertical: ZplaySpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.bg.withValues(alpha: 0.75),
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          item.remainingMinutes > 0
                              ? '${item.remainingMinutes}m left'
                              : '${(progress * 100).toInt()}%',
                          style: ZplayType.caption.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Bottom Progress Bar
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3.5,
                        color: tokens.textPrimary.withValues(
                          alpha: ZplayOpacity.overlayHover,
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: tokens.accent,
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.accent.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Title and Episode Metadata
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s8,
                    vertical: ZplaySpacing.s8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.subtitle.toStyle(
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: ZplaySpacing.s4),
                      Text(
                        item.type == 'series' && item.season != null && item.episode != null
                            ? 'S${item.season!.toString().padLeft(2, '0')}:E${item.episode!.toString().padLeft(2, '0')}${item.episodeTitle != null ? ' • ${item.episodeTitle}' : ''}'
                            : (item.year != null ? '${item.year} • Movie' : 'Movie'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildPlaceholder(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      color: tokens.surface,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          color: tokens.textDisabled,
          size: 36,
        ),
      ),
    );
  }
}
