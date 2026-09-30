import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/video.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/my_list/my_list_item.dart';
import '../../services/metadata/bestsimilar_scraper.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/cloudstream/cloudstream_manager.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/focusable_card.dart';
import '../discover/discover_page.dart';
import '../player/watch_screen.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';

// ---------------------------------------------------------------------------
// Cast avatars
// ---------------------------------------------------------------------------

/// Gradient pair for a cast avatar.
///
/// The old six hardcoded pairs carried no identity — the avatar is decoration,
/// not a face. One deterministic cycle over four semantic hues keeps a given
/// name's avatar stable and adjacent cast members distinct, while the hue now
/// comes from the active palette instead of a literal.
List<Color> _avatarGradient(ZplayTokens tokens, int index) {
  final hue = switch (index % 4) {
    0 => tokens.accent,
    1 => tokens.info,
    2 => tokens.success,
    _ => tokens.warning,
  };
  return [Color.lerp(tokens.bg, hue, 0.45)!, hue];
}

class DetailsPage extends StatefulWidget {
  final Movie movie;

  /// Optional "More Like This" row. Not every addon/catalog gives you
  /// recommendations for free — pass in whatever list of Movie you already
  /// have (e.g. same-genre catalog results, or a recommendations field if
  /// your addon's meta response includes one). Section just doesn't render
  /// if this is null/empty, so it's safe to leave unset for now.
  final List<Movie>? relatedItems;

  const DetailsPage({super.key, required this.movie, this.relatedItems});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage>
    with SingleTickerProviderStateMixin {
  MovieDetail? _detail;
  bool _isLoading = true;

  int? _selectedSeason;
  int? _previousSeason;
  List<Video> _currentSeasonEpisodes = [];

  bool _isSynopsisExpanded = false;

  // Similar content from BestSimilar
  List<BSItem> _similarItems = [];
  bool _isFetchingSimilar = false;

  String? _resolvedType;
  String? _resolvedBaseUrl;

  bool get _isCollection {
    final t = _resolvedType ?? _detail?.type ?? widget.movie.type;
    return t == 'collections' ||
        t == 'collection' ||
        widget.movie.isCollection ||
        (_detail != null && _detail!.isCollection);
  }

  bool get _isSeries {
    final t = _resolvedType ?? _detail?.type ?? widget.movie.type;
    return (t == 'series' ||
            t == 'tv' ||
            t == 'anime' ||
            (_detail != null && _detail!.videos.isNotEmpty)) &&
        !_isCollection;
  }

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final Map<int, ScrollController> _episodeControllers = {};

  ScrollController get _episodeScrollController {
    final key = _selectedSeason ?? -1;
    if (!_episodeControllers.containsKey(key)) {
      final c = ScrollController();
      c.addListener(_updateEpisodeScrollButtons);
      _episodeControllers[key] = c;
    }
    return _episodeControllers[key]!;
  }

  final ScrollController _castScrollController = ScrollController();
  final ScrollController _seasonScrollController = ScrollController();
  final ScrollController _relatedScrollController = ScrollController();
  final ScrollController _similarScrollController = ScrollController();

  bool _canScrollEpisodesLeft = false;
  bool _canScrollEpisodesRight = true;
  bool _isHoveringEpisodes = false;

  bool _canScrollCastLeft = false;
  bool _canScrollCastRight = true;
  bool _isHoveringCast = false;

  bool _canScrollRelatedLeft = false;
  bool _canScrollRelatedRight = true;
  bool _isHoveringRelated = false;

  bool _canScrollSeasonsLeft = false;
  bool _canScrollSeasonsRight = true;
  bool _isHoveringSeasons = false;

  bool _canScrollSimilarLeft = false;
  bool _canScrollSimilarRight = true;
  bool _isHoveringSimilar = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _castScrollController.addListener(_updateCastScrollButtons);
    _relatedScrollController.addListener(_updateRelatedScrollButtons);
    _seasonScrollController.addListener(_updateSeasonScrollButtons);
    _similarScrollController.addListener(_updateSimilarScrollButtons);

    _fetchDetails();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final c in _episodeControllers.values) {
      c.dispose();
    }
    _castScrollController.dispose();
    _seasonScrollController.dispose();
    _relatedScrollController.dispose();
    _similarScrollController.dispose();
    super.dispose();
  }

  Future<void> _handlePlayAction(Video? ep) async {
    if (_detail == null) return;

    Navigator.push(
      context,
      CinematicSlideRoute(
        page: WatchScreen(
          detail: _detail!,
          type: _resolvedType ?? _detail!.type,
          selectedEpisode: ep,
          isCollection: _isCollection,
        ),
      ),
    );
  }

  void _updateEpisodeScrollButtons() {
    if (!_episodeScrollController.hasClients) return;
    final canLeft = _episodeScrollController.position.pixels > 0;
    final canRight =
        _episodeScrollController.position.pixels <
        _episodeScrollController.position.maxScrollExtent;
    if (_canScrollEpisodesLeft != canLeft ||
        _canScrollEpisodesRight != canRight) {
      setState(() {
        _canScrollEpisodesLeft = canLeft;
        _canScrollEpisodesRight = canRight;
      });
    }
  }

  void _updateCastScrollButtons() {
    if (!_castScrollController.hasClients) return;
    final canLeft = _castScrollController.position.pixels > 0;
    final canRight =
        _castScrollController.position.pixels <
        _castScrollController.position.maxScrollExtent;
    if (_canScrollCastLeft != canLeft || _canScrollCastRight != canRight) {
      setState(() {
        _canScrollCastLeft = canLeft;
        _canScrollCastRight = canRight;
      });
    }
  }

  void _updateRelatedScrollButtons() {
    if (!_relatedScrollController.hasClients) return;
    final canLeft = _relatedScrollController.position.pixels > 0;
    final canRight =
        _relatedScrollController.position.pixels <
        _relatedScrollController.position.maxScrollExtent;
    if (_canScrollRelatedLeft != canLeft ||
        _canScrollRelatedRight != canRight) {
      setState(() {
        _canScrollRelatedLeft = canLeft;
        _canScrollRelatedRight = canRight;
      });
    }
  }

  void _updateSeasonScrollButtons() {
    if (!_seasonScrollController.hasClients) return;
    final canLeft = _seasonScrollController.position.pixels > 0;
    final canRight =
        _seasonScrollController.position.pixels <
        _seasonScrollController.position.maxScrollExtent;
    if (_canScrollSeasonsLeft != canLeft ||
        _canScrollSeasonsRight != canRight) {
      setState(() {
        _canScrollSeasonsLeft = canLeft;
        _canScrollSeasonsRight = canRight;
      });
    }
  }

  void _updateSimilarScrollButtons() {
    if (!_similarScrollController.hasClients) return;
    final canLeft = _similarScrollController.position.pixels > 0;
    final canRight =
        _similarScrollController.position.pixels <
        _similarScrollController.position.maxScrollExtent;
    if (_canScrollSimilarLeft != canLeft ||
        _canScrollSimilarRight != canRight) {
      setState(() {
        _canScrollSimilarLeft = canLeft;
        _canScrollSimilarRight = canRight;
      });
    }
  }

  void _scrollList(ScrollController controller, double directionMultiplier) {
    if (!controller.hasClients) return;
    final viewportWidth = controller.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.7 * directionMultiplier;
    final target = (controller.position.pixels + scrollAmount).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _fetchDetails() async {
    String effectiveBaseUrl = widget.movie.addonBaseUrl;
    String effectiveType = widget.movie.type;
    String effectiveId = widget.movie.id;

    // Handle direct CloudStream detail resolution
    if (effectiveId.startsWith('cloudstream:') ||
        effectiveBaseUrl == 'cloudstream') {
      final parts = effectiveId.split(':');
      if (parts.length >= 3) {
        final sourceId = parts[1];
        final mediaUrl = Uri.decodeComponent(parts.sublist(2).join(':'));
        final csDetail = await CloudStreamManager.instance
            .fetchCloudStreamDetail(
              sourceId: sourceId,
              mediaUrl: mediaUrl,
              fallbackTitle: widget.movie.name,
              fallbackPoster: widget.movie.poster,
            );
        if (csDetail != null) {
          if (mounted) {
            setState(() {
              _detail = csDetail;
              _resolvedType = csDetail.type;
              _isLoading = false;

              if (csDetail.videos.isNotEmpty) {
                final seasons = csDetail.videos
                    .map((v) => v.season)
                    .where((s) => s != null)
                    .toSet()
                    .toList();
                seasons.sort();
                if (seasons.isNotEmpty) {
                  _selectedSeason = seasons.first;
                  _updateEpisodesForSeason();
                } else {
                  _currentSeasonEpisodes = List.from(csDetail.videos);
                }
              }
            });
            _animController.forward();

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _updateSeasonScrollButtons();
                _updateCastScrollButtons();
                _updateRelatedScrollButtons();
              }
            });

            _fetchSimilarContent();
          }
          return;
        }
      }
    }

    if (effectiveId.startsWith('bestsimilar_') ||
        effectiveBaseUrl.contains('bestsimilar')) {
      final yearNum = widget.movie.year != null
          ? int.tryParse(widget.movie.year!.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;
      final resolved = await MetadataService.findMovieByTitle(
        title: widget.movie.name,
        type: widget.movie.type,
        year: yearNum,
      );
      if (resolved != null) {
        effectiveBaseUrl = resolved.addonBaseUrl;
        effectiveType = resolved.type;
        effectiveId = resolved.id;
        _resolvedBaseUrl = effectiveBaseUrl;
        _resolvedType = effectiveType;
      }
    }

    var meta = await MetadataService.fetchMeta(
      baseUrl: effectiveBaseUrl,
      type: effectiveType,
      imdbId: effectiveId,
    );

    // If fetchMeta failed, try fallback search to resolve
    if (meta == null && !effectiveId.startsWith('tt')) {
      final yearNum = widget.movie.year != null
          ? int.tryParse(widget.movie.year!.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;
      final resolved = await MetadataService.findMovieByTitle(
        title: widget.movie.name,
        type: widget.movie.type,
        year: yearNum,
      );
      if (resolved != null) {
        effectiveBaseUrl = resolved.addonBaseUrl;
        effectiveType = resolved.type;
        effectiveId = resolved.id;
        _resolvedBaseUrl = effectiveBaseUrl;
        _resolvedType = effectiveType;
        meta = await MetadataService.fetchMeta(
          baseUrl: resolved.addonBaseUrl,
          type: resolved.type,
          imdbId: resolved.id,
        );
      }
    }

    if (meta != null && meta.type.isNotEmpty) {
      _resolvedType = meta.type;
    }

    if (mounted) {
      setState(() {
        _detail = meta;
        _isLoading = false;

        if (meta != null &&
            (_isSeries || meta.videos.isNotEmpty) &&
            meta.videos.isNotEmpty) {
          final seasons = meta.videos
              .map((v) => v.season)
              .where((s) => s != null)
              .toSet()
              .toList();
          seasons.sort();
          if (seasons.isNotEmpty) {
            _selectedSeason = seasons.first;
            _updateEpisodesForSeason();
          } else {
            _currentSeasonEpisodes = List.from(meta.videos);
          }
        }
      });
      _animController.forward();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateSeasonScrollButtons();
          _updateCastScrollButtons();
          _updateRelatedScrollButtons();
        }
      });

      // Fire off similar content fetch in background
      _fetchSimilarContent();
    }
  }

  Future<void> _fetchSimilarContent() async {
    if (_isFetchingSimilar) return;
    setState(() => _isFetchingSimilar = true);

    try {
      final title = _detail?.name ?? widget.movie.name;
      final yearStr = _detail?.year ?? widget.movie.year;
      final year = yearStr != null
          ? int.tryParse(yearStr.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;
      final isTv = _isSeries;

      final hit = await BestSimilarScraper.findBest(
        title: title,
        year: year,
        isTv: isTv,
      );

      if (hit == null || !mounted) {
        if (mounted) setState(() => _isFetchingSimilar = false);
        return;
      }

      final details = await BestSimilarScraper.fetchDetails(
        id: hit.id,
        slug: hit.slug,
      );

      if (mounted) {
        setState(() {
          _similarItems = details?.similar ?? [];
          _isFetchingSimilar = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateSimilarScrollButtons();
        });
      }
    } catch (e) {
      debugPrint('[Similar] fetch failed: $e');
      if (mounted) setState(() => _isFetchingSimilar = false);
    }
  }

  Future<void> _openSimilarItem(BSItem item) async {
    final resolved = await MetadataService.findMovieByTitle(
      title: item.title,
      type: item.isTv ? 'series' : (_resolvedType ?? widget.movie.type),
      year: item.year,
      preferredBaseUrl: _resolvedBaseUrl ?? widget.movie.addonBaseUrl,
    );

    if (resolved != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DetailsPage(movie: resolved)),
      );
    }
  }

  void _updateEpisodesForSeason() {
    if (_detail == null || _selectedSeason == null) return;
    setState(() {
      _currentSeasonEpisodes = _detail!.videos
          .where((v) => v.season == _selectedSeason)
          .toList();
      _currentSeasonEpisodes.sort(
        (a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_episodeScrollController.hasClients) {
        _episodeScrollController.jumpTo(0);
      }
      _updateEpisodeScrollButtons();
    });
  }

  bool _isDesktop([BuildContext? ctx]) {
    return MediaQuery.sizeOf(ctx ?? context).width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: tokens.accent))
          : _detail == null
          ? _buildError()
          : _buildContent(context),
    );
  }

  Widget _buildError() {
    final tokens = context.tokens;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_rounded,
            size: 64,
            color: tokens.textDisabled,
          ),
          const SizedBox(height: ZplaySpacing.s16),
          Text(
            'Details unavailable.',
            style: ZplayType.title.toStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: ZplaySpacing.s24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.surface,
              foregroundColor: tokens.textPrimary,
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = context.tokens;
    final meta = _detail!;
    final bgUrl = meta.background ?? meta.poster ?? widget.movie.poster;
    final posterUrl = meta.poster ?? widget.movie.poster;
    final isDesktop = _isDesktop(context);
    final screenSize = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Sized from the viewport that is actually left, not from a fraction of a
    // monitor's height.
    //
    // A television is 960x540 dp - 960 wide, which clears the desktop
    // breakpoint, but only 540 tall. Laying it out like a desktop meant a
    // 280dp-wide 2:3 poster was 420dp tall on its own, so the poster ran off
    // the bottom and pushed Play Movie and the rest of the buttons out of the
    // viewport entirely. The hero is a backdrop offset rather than a real
    // content height, so it gives way first; the poster is then bounded by
    // whatever is left, minus the two buttons that must remain visible.
    final isShortViewport = screenSize.height < 700;
    final heroFraction = isDesktop ? (isShortViewport ? 0.30 : 0.46) : 0.4;
    final heroHeight = (screenSize.height * heroFraction).clamp(
      isShortViewport ? 150.0 : 320.0,
      520.0,
    );
    final contentMaxWidth = isDesktop ? 1440.0 : double.infinity;
    final overlap = isDesktop ? (isShortViewport ? 60.0 : 120.0) : 70.0;
    // What the content column has left to work with, once the backdrop offset,
    // the horizontal padding and the bottom inset are gone. The poster is
    // bounded by this so it can never be what pushes the buttons off-screen.
    final availableHeight =
        screenSize.height -
        (heroHeight - overlap) -
        ZplaySpacing.s48 -
        bottomInset;

    return Stack(
      children: [
        if (bgUrl != null) _buildBackdrop(bgUrl, screenSize),
        Positioned.fill(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? ZplaySpacing.s48 : ZplaySpacing.s24,
                        0,
                        isDesktop ? ZplaySpacing.s48 : ZplaySpacing.s24,
                        ZplaySpacing.s48 + bottomInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: heroHeight - overlap),
                          isDesktop
                              ? _buildDesktopLayout(
                                  meta,
                                  posterUrl,
                                  availableHeight: availableHeight,
                                )
                              : _buildMobileLayout(meta, posterUrl),
                          const SizedBox(height: ZplaySpacing.s32),
                          if (meta.cast.isNotEmpty) ...[
                            _buildCastRow(meta.cast),
                            const SizedBox(height: ZplaySpacing.s32),
                          ],
                          if (meta.videos.isNotEmpty) ...[
                            if (meta.videos
                                    .map((v) => v.season)
                                    .where((s) => s != null)
                                    .toSet()
                                    .length >
                                1) ...[
                              _buildSeasonSelector(meta),
                              const SizedBox(height: ZplaySpacing.s24),
                            ] else ...[
                              _buildSectionHeader(
                                _isCollection
                                    ? 'Movies in Collection'
                                    : 'Episodes',
                              ),
                            ],
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 550),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.topCenter,
                                  children: <Widget>[
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                    final isIncoming =
                                        child.key == ValueKey(_selectedSeason);
                                    final int incomingSeason =
                                        _selectedSeason ?? 1;
                                    final int previousSeason =
                                        _previousSeason ?? 1;

                                    final bool slidingRight =
                                        incomingSeason > previousSeason;

                                    // Incoming starts offset, Outgoing ends offset
                                    final Offset beginOffset = isIncoming
                                        ? (slidingRight
                                              ? const Offset(0.12, 0.0)
                                              : const Offset(-0.12, 0.0))
                                        : (slidingRight
                                              ? const Offset(-0.12, 0.0)
                                              : const Offset(0.12, 0.0));

                                    final slideAnimation =
                                        Tween<Offset>(
                                          begin: beginOffset,
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        );

                                    final scaleAnimation =
                                        Tween<double>(
                                          begin: 0.94,
                                          end: 1.0,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        );

                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: slideAnimation,
                                        child: ScaleTransition(
                                          scale: scaleAnimation,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                              child: _buildEpisodeSlider(
                                key: ValueKey(_selectedSeason),
                              ),
                            ),
                            const SizedBox(height: ZplaySpacing.s32),
                          ],
                          if (widget.relatedItems != null &&
                              widget.relatedItems!.isNotEmpty) ...[
                            _buildRelatedRow(widget.relatedItems!),
                            const SizedBox(height: ZplaySpacing.s32),
                          ],
                          if (_similarItems.isNotEmpty) ...[
                            _buildSimilarRow(),
                            const SizedBox(height: ZplaySpacing.s32),
                          ] else if (_isFetchingSimilar) ...[
                            _buildSectionHeader('Similar Content'),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: ZplaySpacing.s40,
                                ),
                                child: SizedBox(
                                  width: ZplaySpacing.s24,
                                  height: ZplaySpacing.s24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: tokens.accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: ZplaySpacing.s32),
                          ],
                          const SizedBox(height: ZplaySpacing.s48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: isDesktop ? ZplaySpacing.s24 : (topInset + 10),
          left: isDesktop ? ZplaySpacing.s48 : ZplaySpacing.s16,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: tokens.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: tokens.textPrimary.withValues(
                    alpha: ZplayOpacity.borderMedium,
                  ),
                  padding: const EdgeInsets.all(ZplaySpacing.s12),
                  side: BorderSide(color: tokens.borderStrong),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Persistent, full-viewport cinematic backdrop.
  //
  // Unlike a hero strip that gets cropped to a fixed height and then hands
  // off to flat background color, this sits behind the *entire* screen and
  // stays there while the foreground scrolls over it — so the image never
  // abruptly disappears, it just gradually recedes under layered scrims.
  // Three separate gradients do different jobs so no single one has to be
  // aggressive enough to look like a hard cutoff:
  //   1. a soft cap at the very top (keeps the back button legible)
  //   2. a slow bottom fade that only reaches solid bg near ~90% down
  //   3. a gentle horizontal wash so text on the left never fights the image
  // -------------------------------------------------------------------------
  Widget _buildBackdrop(String bgUrl, Size screenSize) {
    final tokens = context.tokens;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenSize.height,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: bgUrl,
              cacheManager: AppImageCache.manager,
              memCacheWidth: 1280,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            // horizontal wash — darkens where the title/synopsis sit, leaves
            // the rest of the image breathing room instead of blacking it all out
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    tokens.bg,
                    tokens.surfaceRaised.withValues(alpha: 0.60),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.42, 0.82],
                ),
              ),
            ),
            // slow bottom fade — the whole point of the fix: this used to
            // resolve to solid bg by ~70% of a 300-460px strip, now it takes
            // nearly the full viewport height to settle
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    tokens.surfaceRaised.withValues(alpha: 0.40),
                    tokens.bg,
                  ],
                  stops: const [0.0, 0.62, 0.94],
                ),
              ),
            ),
            // top cap so the back button always has contrast
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tokens.bg.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.22],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Desktop: real two-column layout. Poster + actions pinned left;
  // logo/title, metadata, synopsis fill the right. With the backdrop now
  // persistent behind everything, this row no longer needs a "quick facts"
  // filler box just to feel less empty underneath the poster — genres are
  // already in the metadata line, so it's dropped to avoid repeating itself.
  // -------------------------------------------------------------------------
  Widget _buildDesktopLayout(
    MovieDetail meta,
    String? posterUrl, {
    required double availableHeight,
  }) {
    final tokens = context.tokens;

    // The column is poster + gap + Play + gap + Library, and the two buttons
    // are the part that must never fall below the fold: on a television
    // "Play Movie" is the only way into the app's main function. So the poster
    // takes whatever height is left over rather than a fixed width that
    // decides its own height from a 2:3 ratio.
    const double buttonHeight = 56;
    const double columnGap = ZplaySpacing.s12;
    const double posterGap = ZplaySpacing.s16;
    final double maxPosterHeight =
        availableHeight - buttonHeight * 2 - columnGap - posterGap;

    // Width is whatever a 2:3 poster of that height needs, capped at the
    // desktop size so a tall monitor still gets the 280dp column it had.
    final double posterWidth = (maxPosterHeight * 2 / 3).clamp(120.0, 280.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: posterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (posterUrl != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: ZplayRadius.mdAll,
                    boxShadow: [
                      // subtle accent-tinted glow behind the poster, on top
                      // of the usual drop shadow, so it reads as "lit" rather
                      // than just floating on black
                      BoxShadow(
                        color: tokens.accent.withValues(alpha: 0.18),
                        blurRadius: 46,
                        spreadRadius: -6,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: ZplayRadius.mdAll,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: CachedNetworkImage(
                        imageUrl: posterUrl,
                        cacheManager: AppImageCache.manager,
                        memCacheWidth: 512,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: tokens.surface),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: posterGap),
              _buildPlayButton(fullWidth: true),
              const SizedBox(height: columnGap),
              _buildLibraryButton(fullWidth: true),
            ],
          ),
        ),
        const SizedBox(width: ZplaySpacing.s32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogoOrTitle(meta, isDesktop: true),
              const SizedBox(height: ZplaySpacing.s16),
              _buildMetadataRow(meta),
              if (meta.description != null && meta.description!.isNotEmpty) ...[
                const SizedBox(height: ZplaySpacing.s24),
                _buildSynopsis(meta.description!),
              ],
              if (meta.genres.isNotEmpty) ...[
                const SizedBox(height: ZplaySpacing.s24),
                _buildGenreChips(meta.genres),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(MovieDetail meta, String? posterUrl) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (posterUrl != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.smAll,
                  boxShadow: [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.16),
                      blurRadius: 28,
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: ZplayRadius.smAll,
                  child: CachedNetworkImage(
                    imageUrl: posterUrl,
                    cacheManager: AppImageCache.manager,
                    memCacheWidth: 330,
                    width: 110,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(width: ZplaySpacing.s16),
            Expanded(child: _buildLogoOrTitle(meta, isDesktop: false)),
          ],
        ),
        const SizedBox(height: ZplaySpacing.s24),
        _buildMetadataRow(meta),
        const SizedBox(height: ZplaySpacing.s24),
        Row(
          children: [
            Expanded(child: _buildPlayButton(fullWidth: true)),
            const SizedBox(width: ZplaySpacing.s12),
            _buildLibraryButton(fullWidth: false),
          ],
        ),
        if (meta.description != null && meta.description!.isNotEmpty) ...[
          const SizedBox(height: ZplaySpacing.s24),
          _buildSynopsis(meta.description!),
        ],
        if (meta.genres.isNotEmpty) ...[
          const SizedBox(height: ZplaySpacing.s16),
          _buildGenreChips(meta.genres),
        ],
      ],
    );
  }

  // Logo is now capped in both width AND height, so it can never dwarf the
  // poster next to it the way it did before (that's what made the poster
  // look like an afterthought in the screenshot).
  Widget _buildLogoOrTitle(MovieDetail meta, {required bool isDesktop}) {
    if (meta.logo != null && meta.logo!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 380 : 220,
          maxHeight: isDesktop ? 130 : 80,
        ),
        child: CachedNetworkImage(
          imageUrl: meta.logo!,
          cacheManager: AppImageCache.manager,
          memCacheWidth: 512,
          alignment: Alignment.bottomLeft,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _buildTextTitle(meta.name, isDesktop),
        ),
      );
    }
    return _buildTextTitle(meta.name, isDesktop);
  }

  Widget _buildTextTitle(String text, bool isDesktop) {
    final tokens = context.tokens;

    return Text(
      text,
      style: ZplayType.display
          .copyWith(size: isDesktop ? 40 : 28)
          .toStyle(color: tokens.textPrimary)
          .copyWith(
            shadows: [
              Shadow(
                color: tokens.bg.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
    );
  }

  // Small pill chips for genres, sitting under the synopsis. This replaces
  // the old boxed "Quick Facts" panel — same information, but styled as a
  // lightweight row instead of a card that left dead space under the poster.
  Widget _buildGenreChips(List<String> genres) {
    final tokens = context.tokens;

    return Wrap(
      spacing: ZplaySpacing.s8,
      runSpacing: ZplaySpacing.s8,
      children: genres.map((g) {
        Offset? lastTap;
        // The Listener records the pointer origin for the reveal without
        // joining the gesture arena, so the card's tap still fires.
        return Listener(
          onPointerDown: (d) => lastTap = d.position,
          child: FocusableCard(
            onTap: () {
              Navigator.push(
                context,
                LiquidRevealRoute(
                  page: DiscoverPage(query: g, isGenre: true),
                  tapPosition: lastTap,
                ),
              );
            },
            builder: (_, state) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(
                  alpha: ZplayOpacity.borderSubtle,
                ),
                borderRadius: ZplayRadius.lgAll,
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Text(
                g,
                style: ZplayType.label
                    .copyWith(weight: FontWeight.w600)
                    .toStyle(color: tokens.textEmphasis),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMetadataRow(MovieDetail meta) {
    final tokens = context.tokens;
    final List<Widget> items = [];

    if (meta.year != null && meta.year!.isNotEmpty) {
      items.add(
        Text(
          meta.year!,
          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
        ),
      );
    }

    if (_isSeries) {
      final seasonCount = meta.videos
          .map((v) => v.season)
          .where((s) => s != null)
          .toSet()
          .length;
      if (seasonCount > 0) {
        items.add(
          Text(
            '$seasonCount Season${seasonCount > 1 ? "s" : ""}',
            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
          ),
        );
      }
    } else if (meta.runtime != null && meta.runtime!.isNotEmpty) {
      items.add(
        Text(
          meta.runtime!,
          style: ZplayType.body.toStyle(color: tokens.textEmphasis),
        ),
      );
    }

    if (meta.imdbRating != null && meta.imdbRating!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(
              alpha: ZplayOpacity.borderStrong,
            ),
            borderRadius: ZplayRadius.xsAll,
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, color: tokens.warning, size: 14),
              const SizedBox(width: ZplaySpacing.s4),
              Text(
                meta.imdbRating!,
                style: ZplayType.bodySmall
                    .copyWith(weight: FontWeight.w700)
                    .toStyle(color: tokens.textPrimary),
              ),
            ],
          ),
        ),
      );
    }

    if (meta.genres.isNotEmpty) {
      items.add(
        Text(
          meta.genres.take(3).join(' · '),
          style: ZplayType.body.toStyle(color: tokens.textEmphasis),
        ),
      );
    }

    final List<Widget> spaced = [];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
            child: Text(
              '•',
              style: ZplayType.body
                  .copyWith(size: 16)
                  .toStyle(color: tokens.textDisabled),
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: spaced,
    );
  }

  Widget _buildPlayButton({required bool fullWidth}) {
    final tokens = context.tokens;

    return _HoverButton(
      onTap: () => _handlePlayAction(
        _currentSeasonEpisodes.isNotEmpty
            ? _currentSeasonEpisodes.first
            : (_detail?.videos.isNotEmpty == true
                  ? _detail!.videos.first
                  : null),
      ),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s24,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tokens.accent, tokens.accentPressed],
          ),
          borderRadius: ZplayRadius.smAll,
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: tokens.onAccent, size: 24),
            const SizedBox(width: 6),
            Text(
              _isCollection
                  ? 'Play First Movie'
                  : (_isSeries ? 'Play Episodes' : 'Play Movie'),
              style: ZplayType.subtitle
                  .copyWith(weight: FontWeight.w700)
                  .toStyle(color: tokens.onAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryButton({required bool fullWidth}) {
    return ValueListenableBuilder<List<MyListItem>>(
      valueListenable: MyListService.items,
      builder: (context, items, _) {
        final tokens = context.tokens;
        final inList =
            _detail != null &&
            MyListService.isInList(
              MyListItem.fromMovieDetail(
                id: _detail!.id,
                name: _detail!.name,
                poster: _detail!.poster,
                year: _detail!.year,
                type: _detail!.type,
                imdbId: _detail!.id.startsWith('tt') ? _detail!.id : null,
                tmdbId: _detail!.tmdbId != null
                    ? int.tryParse(_detail!.tmdbId!)
                    : null,
              ),
            );

        return _HoverButton(
          onTap: () => _toggleMyList(),
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s20,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: inList
                  ? tokens.accent.withValues(alpha: 0.18)
                  : tokens.textPrimary.withValues(
                      alpha: ZplayOpacity.borderDefault,
                    ),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: inList
                    ? tokens.accent.withValues(alpha: 0.35)
                    : tokens.textPrimary.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  inList
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: inList ? tokens.accent : tokens.textPrimary,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  inList ? 'In Library' : 'Library',
                  style: ZplayType.body
                      .copyWith(weight: FontWeight.w600)
                      .toStyle(
                        color: inList ? tokens.accent : tokens.textPrimary,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleMyList() {
    if (_detail == null) return;

    final item = MyListItem.fromMovieDetail(
      id: _detail!.id,
      name: _detail!.name,
      poster: _detail!.poster,
      year: _detail!.year,
      type: _detail!.type,
      imdbId: _detail!.id.startsWith('tt') ? _detail!.id : null,
      tmdbId: _detail!.tmdbId != null ? int.tryParse(_detail!.tmdbId!) : null,
    );

    MyListService.toggle(item);
  }

  Widget _buildSynopsis(String text) {
    final tokens = context.tokens;
    final style = ZplayType.body
        .copyWith(size: 15, height: 1.55, letterSpacing: 0.2)
        .toStyle(color: tokens.textEmphasis);
    const maxLines = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.clamp(0.0, 720.0);
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);

        final isOverflowing = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Text(
                  text,
                  maxLines: _isSynopsisExpanded ? null : maxLines,
                  overflow: _isSynopsisExpanded
                      ? TextOverflow.visible
                      : TextOverflow.fade,
                  style: style,
                ),
              ),
            ),
            if (isOverflowing) ...[
              const SizedBox(height: ZplaySpacing.s8),
              FocusableCard(
                onTap: () =>
                    setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                builder: (_, state) => Text(
                  _isSynopsisExpanded ? 'Show less' : 'Read more',
                  style: ZplayType.body
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: tokens.textPrimary),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s16),
      child: Text(
        title,
        style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
      ),
    );
  }

  Widget _buildCastRow(List<String> cast) {
    final tokens = context.tokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringCast = true),
      onExit: (_) => setState(() => _isHoveringCast = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Cast'),
          SizedBox(
            height: 132,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  clipBehavior: Clip.none,
                  controller: _castScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: cast.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: ZplaySpacing.s24),
                  itemBuilder: (context, index) {
                    final name = cast[index];
                    final initials = name.isNotEmpty
                        ? name
                              .trim()
                              .split(' ')
                              .map((e) => e.isNotEmpty ? e[0] : '')
                              .take(2)
                              .join('')
                              .toUpperCase()
                        : '?';
                    final pair = _avatarGradient(
                      tokens,
                      name.hashCode.abs() % 4,
                    );

                    return SizedBox(
                      width: 84,
                      child: Column(
                        children: [
                          Builder(
                            builder: (context) {
                              Offset? lastTap;
                              return GestureDetector(
                                onTapDown: (d) => lastTap = d.globalPosition,
                                child: _HoverButton(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      LiquidRevealRoute(
                                        page: DiscoverPage(
                                          query: name,
                                          isGenre: false,
                                        ),
                                        tapPosition: lastTap,
                                      ),
                                    );
                                  },
                                  scaleAmount: 1.05,
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: pair,
                                      ),
                                      border: Border.all(
                                        color: tokens.textPrimary.withValues(
                                          alpha: ZplayOpacity.borderMedium,
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      initials,
                                      style: ZplayType.titleLarge
                                          .copyWith(size: 24)
                                          .toStyle(color: tokens.textPrimary),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: ZplaySpacing.s8),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.bodySmall
                                .copyWith(height: 1.2)
                                .toStyle(color: tokens.textEmphasis),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (_isDesktop()) ...[
                  if (_canScrollCastLeft)
                    Positioned(
                      left: 0,
                      top: 10,
                      bottom: 40,
                      child: _buildScrollArrow(
                        Icons.arrow_back_ios_new_rounded,
                        () => _scrollList(_castScrollController, -1),
                        _isHoveringCast,
                      ),
                    ),
                  if (_canScrollCastRight)
                    Positioned(
                      right: 0,
                      top: 10,
                      bottom: 40,
                      child: _buildScrollArrow(
                        Icons.arrow_forward_ios_rounded,
                        () => _scrollList(_castScrollController, 1),
                        _isHoveringCast,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector(MovieDetail meta) {
    final tokens = context.tokens;
    final seasons = meta.videos
        .map((v) => v.season)
        .where((s) => s != null)
        .toSet()
        .toList();
    seasons.sort();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringSeasons = true),
      onExit: (_) => setState(() => _isHoveringSeasons = false),
      child: SizedBox(
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ListView.separated(
              clipBehavior: Clip.none,
              controller: _seasonScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: seasons.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: ZplaySpacing.s12),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final isSelected = _selectedSeason == season;
                return _HoverButton(
                  onTap: () {
                    if (_selectedSeason != season) {
                      setState(() {
                        _previousSeason = _selectedSeason;
                        _selectedSeason = season;
                      });
                      _updateEpisodesForSeason();
                    }
                  },
                  scaleAmount: 1.02,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tokens.textPrimary
                          : tokens.textPrimary.withValues(
                              alpha: ZplayOpacity.borderSubtle,
                            ),
                      borderRadius: ZplayRadius.lgAll,
                      border: Border.all(
                        color: isSelected
                            ? tokens.textPrimary
                            : tokens.textPrimary.withValues(
                                alpha: ZplayOpacity.borderMedium,
                              ),
                      ),
                    ),
                    child: Text(
                      'Season $season',
                      style: ZplayType.subtitle
                          .copyWith(
                            weight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          )
                          .toStyle(
                            color: isSelected ? tokens.bg : tokens.textPrimary,
                          ),
                    ),
                  ),
                );
              },
            ),
            if (_isDesktop()) ...[
              if (_canScrollSeasonsLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    Icons.arrow_back_ios_new_rounded,
                    () => _scrollList(_seasonScrollController, -1),
                    _isHoveringSeasons,
                  ),
                ),
              if (_canScrollSeasonsRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    Icons.arrow_forward_ios_rounded,
                    () => _scrollList(_seasonScrollController, 1),
                    _isHoveringSeasons,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeSlider({Key? key}) {
    final tokens = context.tokens;
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 300.0 : 230.0;
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      key: key,
      onEnter: (_) => setState(() => _isHoveringEpisodes = true),
      onExit: (_) => setState(() => _isHoveringEpisodes = false),
      child: SizedBox(
        height: isDesktop ? 275 : 245,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                final leftFadeStop = bounds.width > 0
                    ? (fadeWidth / bounds.width).clamp(0.01, 0.2)
                    : 0.05;
                final rightFadeStop = bounds.width > 0
                    ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99)
                    : 0.95;

                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _canScrollEpisodesLeft ? Colors.transparent : tokens.bg,
                    tokens.bg,
                    tokens.bg,
                    _canScrollEpisodesRight ? Colors.transparent : tokens.bg,
                  ],
                  stops: [0.0, leftFadeStop, rightFadeStop, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: ListView.separated(
                clipBehavior: Clip.hardEdge,
                controller: _episodeScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _currentSeasonEpisodes.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: ZplaySpacing.s16),
                itemBuilder: (context, index) {
                  final ep = _currentSeasonEpisodes[index];
                  return SizedBox(
                    width: cardWidth,
                    child: _EpisodeCard(
                      episode: ep,
                      fallbackImageUrl:
                          _detail?.background ??
                          _detail?.poster ??
                          widget.movie.poster,
                      onTap: () => _handlePlayAction(ep),
                      isCollection: _isCollection,
                    ),
                  );
                },
              ),
            ),
            if (isDesktop) ...[
              if (_canScrollEpisodesLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: fadeWidth + 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [tokens.bg, tokens.bg.withValues(alpha: 0.0)],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildScrollArrow(
                        Icons.arrow_back_ios_new_rounded,
                        () => _scrollList(_episodeScrollController, -1),
                        _isHoveringEpisodes,
                      ),
                    ),
                  ),
                ),
              if (_canScrollEpisodesRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: fadeWidth + 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [tokens.bg, tokens.bg.withValues(alpha: 0.0)],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildScrollArrow(
                        Icons.arrow_forward_ios_rounded,
                        () => _scrollList(_episodeScrollController, 1),
                        _isHoveringEpisodes,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // "More Like This" — fills the dead space at the bottom of the page and
  // gives people somewhere to go next instead of hitting a wall of black.
  Widget _buildRelatedRow(List<Movie> related) {
    final tokens = context.tokens;
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 150.0 : 120.0;
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringRelated = true),
      onExit: (_) => setState(() => _isHoveringRelated = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('More Like This'),
          SizedBox(
            height: cardWidth * 1.5 + 8,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    final leftFadeStop = bounds.width > 0
                        ? (fadeWidth / bounds.width).clamp(0.01, 0.2)
                        : 0.05;
                    final rightFadeStop = bounds.width > 0
                        ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99)
                        : 0.95;

                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _canScrollRelatedLeft ? Colors.transparent : tokens.bg,
                        tokens.bg,
                        tokens.bg,
                        _canScrollRelatedRight ? Colors.transparent : tokens.bg,
                      ],
                      stops: [0.0, leftFadeStop, rightFadeStop, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    clipBehavior: Clip.hardEdge,
                    controller: _relatedScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: related.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: ZplaySpacing.s16),
                    itemBuilder: (context, index) {
                      final item = related[index];
                      return SizedBox(
                        width: cardWidth,
                        child: _HoverButton(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailsPage(movie: item),
                              ),
                            );
                          },
                          scaleAmount: 1.05,
                          child: ClipRRect(
                            borderRadius: ZplayRadius.smAll,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: item.poster != null
                                  ? CachedNetworkImage(
                                      imageUrl: item.poster!,
                                      cacheManager: AppImageCache.manager,
                                      memCacheWidth: 330,
                                      fit: BoxFit.cover,
                                    )
                                  : ColoredBox(color: tokens.surface),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (isDesktop) ...[
                  if (_canScrollRelatedLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              tokens.bg,
                              tokens.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildScrollArrow(
                            Icons.arrow_back_ios_new_rounded,
                            () => _scrollList(_relatedScrollController, -1),
                            _isHoveringRelated,
                          ),
                        ),
                      ),
                    ),
                  if (_canScrollRelatedRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              tokens.bg,
                              tokens.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _buildScrollArrow(
                            Icons.arrow_forward_ios_rounded,
                            () => _scrollList(_relatedScrollController, 1),
                            _isHoveringRelated,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarRow() {
    final tokens = context.tokens;
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 160.0 : 130.0;
    final cardHeight = cardWidth * 1.5 + 64; // poster + text area
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringSimilar = true),
      onExit: (_) => setState(() => _isHoveringSimilar = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Similar Content'),
          SizedBox(
            height: cardHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    final leftFadeStop = bounds.width > 0
                        ? (fadeWidth / bounds.width).clamp(0.01, 0.2)
                        : 0.05;
                    final rightFadeStop = bounds.width > 0
                        ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99)
                        : 0.95;

                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _canScrollSimilarLeft ? Colors.transparent : tokens.bg,
                        tokens.bg,
                        tokens.bg,
                        _canScrollSimilarRight ? Colors.transparent : tokens.bg,
                      ],
                      stops: [0.0, leftFadeStop, rightFadeStop, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    clipBehavior: Clip.hardEdge,
                    controller: _similarScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _similarItems.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: ZplaySpacing.s16),
                    itemBuilder: (context, index) {
                      final item = _similarItems[index];
                      return SizedBox(
                        width: cardWidth,
                        child: _HoverButton(
                          onTap: () => _openSimilarItem(item),
                          scaleAmount: 1.05,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Poster
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: ZplayRadius.smAll,
                                    child: AspectRatio(
                                      aspectRatio: 2 / 3,
                                      child: item.thumbUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: item.thumbUrl,
                                              cacheManager:
                                                  AppImageCache.manager,
                                              memCacheWidth: 330,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                    color: tokens.surface,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.movie_rounded,
                                                        color:
                                                            tokens.textDisabled,
                                                        size: 36,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: tokens.surface,
                                              child: Center(
                                                child: Icon(
                                                  Icons.movie_rounded,
                                                  color: tokens.textDisabled,
                                                  size: 36,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  // Similarity badge
                                  if (item.similarityPercent != null)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.bg.withValues(
                                            alpha: 0.75,
                                          ),
                                          borderRadius: ZplayRadius.xsAll,
                                          border: Border.all(
                                            color: tokens.accent.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          '${item.similarityPercent}%',
                                          style: ZplayType.caption
                                              .copyWith(weight: FontWeight.w700)
                                              .toStyle(
                                                color: tokens.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  // Rating badge
                                  if (item.rating != null)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.bg.withValues(
                                            alpha: 0.75,
                                          ),
                                          borderRadius: ZplayRadius.xsAll,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.star_rounded,
                                              color: tokens.warning,
                                              size: 13,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              item.rating!.toStringAsFixed(1),
                                              style: ZplayType.caption
                                                  .copyWith(
                                                    weight: FontWeight.w700,
                                                  )
                                                  .toStyle(
                                                    color: tokens.textPrimary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: ZplaySpacing.s8),
                              // Title
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.label
                                    .copyWith(weight: FontWeight.w600)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: ZplaySpacing.s2),
                              // Year + genre
                              Text(
                                [
                                  if (item.year != null) '${item.year}',
                                  if (item.genre != null)
                                    item.genre!.split(',').first.trim(),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (isDesktop) ...[
                  if (_canScrollSimilarLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 60,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              tokens.bg,
                              tokens.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildScrollArrow(
                            Icons.arrow_back_ios_new_rounded,
                            () => _scrollList(_similarScrollController, -1),
                            _isHoveringSimilar,
                          ),
                        ),
                      ),
                    ),
                  if (_canScrollSimilarRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 60,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              tokens.bg,
                              tokens.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _buildScrollArrow(
                            Icons.arrow_forward_ios_rounded,
                            () => _scrollList(_similarScrollController, 1),
                            _isHoveringSimilar,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap, bool isVisible) {
    final tokens = context.tokens;

    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !isVisible,
          // An invisible arrow must not be a focus stop: IgnorePointer blocks
          // taps but not focus, so a remote would land on a control that is not
          // on screen. ExcludeFocus rather than the focus primitive's enabled
          // flag, because the focusable lives inside the shared _HoverButton.
          child: ExcludeFocus(
            excluding: !isVisible,
            child: _HoverButton(
              onTap: onTap,
              scaleAmount: 1.1,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tokens.bg.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tokens.textPrimary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(icon, color: tokens.textPrimary, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final Video episode;
  final String? fallbackImageUrl;
  final VoidCallback? onTap;
  final bool isCollection;

  const _EpisodeCard({
    required this.episode,
    this.fallbackImageUrl,
    this.onTap,
    this.isCollection = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ep = episode;
    final imgUrl = ep.thumbnail ?? fallbackImageUrl;

    return FocusableCard(
      onTap: onTap,
      enabled: onTap != null,
      builder: (_, state) {
        return AnimatedScale(
          scale: state.highlighted ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: state.highlighted
                    ? tokens.textPrimary.withValues(alpha: 0.22)
                    : tokens.borderSubtle,
              ),
              boxShadow: state.highlighted
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: ZplayRadius.smAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imgUrl != null)
                          CachedNetworkImage(
                            imageUrl: imgUrl,
                            cacheManager: AppImageCache.manager,
                            memCacheWidth: 330,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                ColoredBox(color: tokens.surfaceRaised),
                          )
                        else
                          ColoredBox(color: tokens.surfaceRaised),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                tokens.bg.withValues(alpha: 0.75),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        Center(
                          child: AnimatedOpacity(
                            opacity: state.highlighted ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tokens.textPrimary.withValues(
                                  alpha: 0.95,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: tokens.bg,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(ZplaySpacing.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              isCollection
                                  ? 'PART ${ep.episode ?? "?"}'
                                  : 'EP ${ep.episode ?? "?"}',
                              style: ZplayType.bodySmall
                                  .copyWith(weight: FontWeight.w700)
                                  .toStyle(color: tokens.accent),
                            ),
                            const Spacer(),
                            if (ep.released != null && ep.released!.length >= 4)
                              Text(
                                isCollection
                                    ? ep.released!.substring(0, 4)
                                    : (ep.released!.length >= 10
                                          ? ep.released!.substring(0, 10)
                                          : ep.released!),
                                style: ZplayType.caption.toStyle(
                                  color: tokens.textMuted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: ZplaySpacing.s4),
                        Text(
                          ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.label
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textPrimary),
                        ),
                        if (ep.overview != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            ep.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.bodySmall
                                .copyWith(height: 1.3)
                                .toStyle(color: tokens.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoverButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleAmount;

  const _HoverButton({
    required this.child,
    required this.onTap,
    this.scaleAmount = 1.04,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => AnimatedScale(
        scale: state.pressed ? 0.96 : (state.highlighted ? scaleAmount : 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
