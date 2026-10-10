import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/horizontal_edge_fade.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/slider_arrow.dart';
import '../../widgets/movie/movie_card.dart';
import 'anime_arabic_stream_sheet.dart';
import '../../services/storage/app_image_cache.dart';

class AnimeArabicDetailsPage extends StatefulWidget {
  final ArabicAnimeCard anime;
  final int? initialEpisodeNumber;

  const AnimeArabicDetailsPage({
    super.key,
    required this.anime,
    this.initialEpisodeNumber,
  });

  @override
  State<AnimeArabicDetailsPage> createState() => _AnimeArabicDetailsPageState();
}

class _AnimeArabicDetailsPageState extends State<AnimeArabicDetailsPage>
  with SingleTickerProviderStateMixin {
  final AnimeArabicService _service = AnimeArabicService.instance;

  ArabicAnimeDetails? _details;
  bool _loading = true;
  String? _error;
  bool _isSynopsisExpanded = false;

  int _selectedEpisodeBatch = 0; // 50 episodes per chunk
  int? _highlightedEpisode;
  static const int _chunkSize = 50;

  final TextEditingController _jumpEpController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _recsScrollController = ScrollController();
  bool _canScrollRecsLeft = false;
  bool _canScrollRecsRight = true;
  bool _isHoveringRecs = false;

  @override
  void initState() {
    super.initState();
    _highlightedEpisode = widget.initialEpisodeNumber;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
    _recsScrollController.addListener(_updateRecsScrollButtons);
    _loadDetails();
  }

  @override
  void dispose() {
    _animController.dispose();
    _jumpEpController.dispose();
    _recsScrollController.removeListener(_updateRecsScrollButtons);
    _recsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _service.getDetails(widget.anime.slug);
      if (mounted) {
        final targetEp = widget.initialEpisodeNumber ?? _highlightedEpisode;
        int batch = 0;
        if (targetEp != null && res.episodes.isNotEmpty) {
          final idx = res.episodes.indexWhere((e) => e.number == targetEp);
          if (idx >= 0) {
            batch = (idx / _chunkSize).floor();
          }
        }
        setState(() {
          _details = res;
          _selectedEpisodeBatch = batch;
          _highlightedEpisode = targetEp;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load anime details: $e';
        });
      }
    }
  }

  void _updateRecsScrollButtons() {
    if (!_recsScrollController.hasClients) return;
    final max = _recsScrollController.position.maxScrollExtent;
    final current = _recsScrollController.offset;
    final canLeft = current > 10;
    final canRight = current < max - 10;

    if (canLeft != _canScrollRecsLeft || canRight != _canScrollRecsRight) {
      setState(() {
        _canScrollRecsLeft = canLeft;
        _canScrollRecsRight = canRight;
      });
    }
  }

  void _scrollRecs(bool right) {
    if (!_recsScrollController.hasClients) return;
    final current = _recsScrollController.offset;
    final target = right ? current + 450 : current - 450;
    _recsScrollController.animateTo(
      target.clamp(0.0, _recsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _playEpisode(ArabicEpisode episode) {
    if (_details == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimeArabicStreamSheet(
        details: _details!,
        episode: episode,
        autoPlay: false,
      ),
    );
  }

  void _jumpToEpisode(String value) {
    final ep = int.tryParse(value.trim());
    if (ep == null || ep <= 0 || _details == null) return;

    final totalEps = _details!.episodes.length;
    final targetEp = ep.clamp(1, totalEps > 0 ? totalEps : 1);
    final targetBatch = ((targetEp - 1) / _chunkSize).floor();

    setState(() {
      _selectedEpisodeBatch = targetBatch;
      _highlightedEpisode = targetEp;
    });

    _jumpEpController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth > 900;
    final isMobile = screenWidth < 600;
    final tokens = ZplayTokens.of(context);

    final backdropUrl = _details?.displayBanner ?? widget.anime.cover ?? '';
    final coverUrl = _details?.displayCover ?? widget.anime.cover ?? '';
    final title = _details?.title ?? widget.anime.title;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedAmbientBackground(
        child: Stack(
          children: [
          // 1. Dynamic Ambient Backdrop
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isMobile ? 400 : 550,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: backdropUrl,
                    cacheManager: AppImageCache.manager,
                    memCacheWidth: 1280,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                // Cinematic blur & dark gradients
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.bg.withValues(alpha: 0.3),
                        tokens.bg.withValues(alpha: 0.75),
                        tokens.bg,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Main Scrollable Content
          SafeArea(
            bottom: false,
            child: _loading && _details == null
                ? Center(child: CircularProgressIndicator(color: tokens.accent))
                : _error != null && _details == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded, color: tokens.danger, size: 48),
                            const SizedBox(height: ZplaySpacing.s16),
                            Text(_error!, style: ZplayType.title.toStyle(color: tokens.textEmphasis)),
                            const SizedBox(height: ZplaySpacing.s16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: tokens.accent),
                              onPressed: _loadDetails,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              // App Bar Space
                              const SliverToBoxAdapter(child: SizedBox(height: 60)),

                              // Main Hero Info Section
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isDesktop ? 60 : (isMobile ? ZplaySpacing.s16 : ZplaySpacing.s32),
                                    vertical: ZplaySpacing.s16,
                                  ),
                                  child: isMobile
                                      ? _buildMobileHero(coverUrl, title)
                                      : _buildDesktopHero(coverUrl, title),
                                ),
                              ),

                              const SliverToBoxAdapter(child: SizedBox(height: ZplaySpacing.s32)),

                              // Episodes Section
                              if (_details != null && _details!.episodes.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isDesktop ? 60 : (isMobile ? ZplaySpacing.s16 : ZplaySpacing.s32),
                                    ),
                                    child: _buildEpisodesSection(),
                                  ),
                                ),

                              const SliverToBoxAdapter(child: SizedBox(height: ZplaySpacing.s32)),

                              // Related Anime Rail
                              if (_details != null && _details!.related.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: isDesktop ? 60 : (isMobile ? ZplaySpacing.s16 : ZplaySpacing.s32),
                                      bottom: 60,
                                    ),
                                    child: _buildRelatedSection(),
                                  ),
                                ),

                              SliverToBoxAdapter(
                                child: SizedBox(height: 60.0 + MediaQuery.paddingOf(context).bottom),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),

          // 3. Floating Quiet Back Button
          //
          // This page is a pushed route, so the shell nav is not painted over
          // it: this button is the whole of the top chrome, and it floats on
          // the canvas - no opaque band, no hairline - the way the film details
          // page's back affordance does.
          Positioned(
            top: isDesktop
                ? ZplaySpacing.s24
                : (MediaQuery.paddingOf(context).top + 10),
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
      ),
      ),
    );
  }

  Widget _buildDesktopHero(String coverUrl, String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPoster(coverUrl, 230, 335),
        const SizedBox(width: 36),
        Expanded(child: _buildMetaDetails(title)),
      ],
    );
  }

  Widget _buildMobileHero(String coverUrl, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(child: _buildPoster(coverUrl, 165, 245)),
        const SizedBox(height: ZplaySpacing.s20),
        _buildMetaDetails(title),
      ],
    );
  }

  Widget _buildPoster(String coverUrl, double width, double height) {
    final tokens = ZplayTokens.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.mdAll,
        boxShadow: [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: ZplayRadius.mdAll,
        child: coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                cacheManager: AppImageCache.manager,
                memCacheWidth: 512,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: tokens.surface,
                  child: Icon(Icons.broken_image_rounded, color: tokens.textDisabled, size: 40),
                ),
              )
            : Container(color: tokens.surface),
      ),
    );
  }

  Widget _buildMetaDetails(String title) {
    final tokens = ZplayTokens.of(context);
    final status = _details?.status ?? widget.anime.tag ?? 'يعرض الآن';
    final rating = _details?.rating ?? widget.anime.rating;
    final year = _details?.year;
    final studio = _details?.studio;
    final genres = _details?.genres ?? const [];
    final description = _details?.description ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ZplayType.display.copyWith(weight: FontWeight.w900).toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: ZplaySpacing.s12),

        // Badges Row
        Wrap(
          spacing: 10,
          runSpacing: ZplaySpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rating != null && rating.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZplaySpacing.s4),
                decoration: BoxDecoration(
                  color: tokens.warning.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                  border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: tokens.warning, size: 16),
                    const SizedBox(width: ZplaySpacing.s4),
                    Text(
                      rating,
                      style: ZplayType.label.toStyle(color: tokens.warning),
                    ),
                  ],
                ),
              ),
            if (year != null && year.isNotEmpty)
              _buildPill(year, tokens.borderStrong, tokens.textEmphasis),
            _buildPill(status, tokens.accent.withValues(alpha: 0.2), tokens.accent),
            if (studio != null && studio.isNotEmpty)
              _buildPill(studio, tokens.borderDefault, tokens.textEmphasis),
          ],
        ),

        const SizedBox(height: 14),

        // Genres
        if (genres.isNotEmpty)
          Wrap(
            spacing: ZplaySpacing.s8,
            runSpacing: ZplaySpacing.s8,
            children: genres.map((g) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: 5),
                decoration: BoxDecoration(
                  color: tokens.borderSubtle,
                  borderRadius: ZplayRadius.lgAll,
                  border: Border.fromBorderSide(tokens.hairlineStrong),
                ),
                child: Text(
                  g,
                  style: ZplayType.bodySmall.copyWith(weight: FontWeight.w600).toStyle(color: tokens.textEmphasis),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 18),

        // Action Button (Watch highlighted/latest/first ep)
        if (_details != null && _details!.episodes.isNotEmpty)
          Builder(
            builder: (_) {
              final targetEpNum = _highlightedEpisode ?? _details!.episodes.first.number;
              final targetEp = _details!.episodes.firstWhere(
                (e) => e.number == targetEpNum,
                orElse: () => _details!.episodes.first,
              );
              return PillButton(
                label: 'مشاهدة الحلقة $targetEpNum',
                icon: Icons.play_arrow_rounded,
                onPressed: () => _playEpisode(targetEp),
              );
            },
          ),

        const SizedBox(height: 18),

        // Synopsis
        if (description.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                maxLines: _isSynopsisExpanded ? null : 3,
                overflow: _isSynopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: ZplayType.body.copyWith(height: 1.5).toStyle(color: tokens.textEmphasis),
              ),
              if (description.length > 140)
                GestureDetector(
                  onTap: () => setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _isSynopsisExpanded ? 'عرض أقل' : 'عرض المزيد',
                      style: ZplayType.label.toStyle(color: tokens.accent),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildPill(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZplaySpacing.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: ZplayRadius.smAll,
      ),
      child: Text(
        text,
        style: ZplayType.bodySmall.copyWith(weight: FontWeight.w600).toStyle(color: textColor),
      ),
    );
  }

  Widget _buildEpisodesSection() {
    final tokens = ZplayTokens.of(context);
    final episodes = _details!.episodes;
    final totalEpisodes = episodes.length;
    final totalBatches = (totalEpisodes / _chunkSize).ceil();

    final startIndex = _selectedEpisodeBatch * _chunkSize;
    final endIndex = (startIndex + _chunkSize).clamp(0, totalEpisodes);
    final currentBatchEpisodes = episodes.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        _onRailGrid(
          SectionHeader(
            title: 'الحلقات',
            count: totalEpisodes,
            trailing: totalEpisodes > 1
                ? SizedBox(
                    width: 110,
                    height: 36,
                    child: TextField(
                      controller: _jumpEpController,
                      keyboardType: TextInputType.number,
                      onSubmitted: _jumpToEpisode,
                      style: ZplayType.label.toStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'اذهب لرقم...',
                        hintStyle:
                            ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        filled: true,
                        fillColor: tokens.borderSubtle,
                        border: OutlineInputBorder(
                          borderRadius: ZplayRadius.smAll,
                          borderSide: tokens.hairlineStrong,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: ZplayRadius.smAll,
                          borderSide: BorderSide(color: tokens.accent),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),

        const SizedBox(height: ZplaySpacing.s16),

        // Batches tabs if > 50 episodes
        if (totalBatches > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: totalBatches,
              separatorBuilder: (_, __) => const SizedBox(width: ZplaySpacing.s8),
              itemBuilder: (context, index) {
                final batchStart = index * _chunkSize + 1;
                final batchEnd = ((index + 1) * _chunkSize).clamp(1, totalEpisodes);
                final isSelected = index == _selectedEpisodeBatch;

                return FocusableCard(
                  onTap: () => setState(() {
                    _selectedEpisodeBatch = index;
                    _highlightedEpisode = null;
                  }),
                  builder: (_, state) => CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.smAll,
                    child: AnimatedScale(
                      duration: ZplayMotion.fast,
                      curve: ZplayMotion.standard,
                      scale: state.hovered ? 1.03 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: ZplaySpacing.s8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? tokens.accent.withValues(alpha: 0.25)
                              : tokens.borderSubtle,
                          borderRadius: ZplayRadius.smAll,
                          border: Border.all(
                            color: isSelected
                                ? tokens.accent
                                : tokens.borderDefault,
                          ),
                        ),
                        child: Text(
                          '$batchStart - $batchEnd',
                          style: ZplayType.label.copyWith(weight: isSelected ? FontWeight.w700 : FontWeight.w500).toStyle(color: isSelected ? tokens.textPrimary : tokens.textEmphasis),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: ZplaySpacing.s16),

        // Episode Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            int crossAxisCount = 2;
            if (w > 1200) {
              crossAxisCount = 6;
            } else if (w > 900) {
              crossAxisCount = 5;
            } else if (w > 650) {
              crossAxisCount = 4;
            } else if (w > 450) {
              crossAxisCount = 3;
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: ZplaySpacing.s12,
                crossAxisSpacing: ZplaySpacing.s12,
                childAspectRatio: 1.6,
              ),
              itemCount: currentBatchEpisodes.length,
              itemBuilder: (context, index) {
                final ep = currentBatchEpisodes[index];
                final isHighlighted = ep.number == _highlightedEpisode;
                return _buildEpisodeCard(ep, isHighlighted);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEpisodeCard(ArabicEpisode episode, bool isHighlighted) {
    final tokens = ZplayTokens.of(context);
    final thumb = episode.thumb ?? _details?.displayBanner ?? widget.anime.cover ?? '';

    return FocusableCard(
      onTap: () => _playEpisode(episode),
      builder: (_, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          // The lift answers the pointer, not focus: on a television a D-pad
          // press must not nudge the tile the user is aiming at.
          scale: state.hovered ? 1.04 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: isHighlighted
                    ? tokens.accent
                    : tokens.borderDefault,
                width: isHighlighted ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumb,
                  cacheManager: AppImageCache.manager,
                  memCacheWidth: 330,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: tokens.surface),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: ZplaySpacing.s2),
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Text(
                        'EP ${episode.number}',
                        style: ZplayType.caption.copyWith(weight: FontWeight.w900).toStyle(color: tokens.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        episode.title.isNotEmpty ? episode.title : 'الحلقة ${episode.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.bodySmall.copyWith(weight: FontWeight.w600).toStyle(color: tokens.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.play_arrow_rounded, color: tokens.textPrimary, size: 20),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedSection() {
    final related = _details!.related;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _onRailGrid(const SectionHeader(title: 'أنميات ذات صلة')),
          const SizedBox(height: 14),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringRecs = true),
            onExit: (_) => setState(() => _isHoveringRecs = false),
            child: SizedBox(
              height: sizing.totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  HorizontalEdgeFade(
                    scrollController: _recsScrollController,
                    extent: isDesktop ? 60 : 40,
                    child: ListView.separated(
                      clipBehavior: Clip.none,
                      controller: _recsScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: related.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(width: sizing.spacing),
                      itemBuilder: (context, index) {
                        final item = related[index];
                        return SizedBox(
                          width: sizing.cardWidth,
                          child: MovieCard(
                            movie: _relatedAsMovie(item),
                            onTap: () {
                              Navigator.push(
                                context,
                                CinematicSlideRoute(
                                  page: AnimeArabicDetailsPage(anime: item),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),

                  // Desktop Floating Scroll Arrows (Matching Home Page & Anime Slider)
                  if (isDesktop) ...[
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      left: _canScrollRecsLeft && _isHoveringRecs ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scrollRecs(false),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      right: _canScrollRecsRight && _isHoveringRecs ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_forward_ios_rounded,
                          onTap: () => _scrollRecs(true),
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
  }

  /// A display-only [Movie] for the related rail, so a related title can sit
  /// there as the same [MovieCard] the rest of the app's rails use. It is only
  /// ever drawn: the tap still pushes [_AnimeArabicDetailsPageState]'s own
  /// route.
  Movie _relatedAsMovie(ArabicAnimeCard item) => Movie(
        id: 'arabic_anime:${item.slug}',
        name: item.title,
        poster: (item.cover == null || item.cover!.isEmpty) ? null : item.cover,
        type: 'anime',
        addonBaseUrl: '',
      );

  /// The shared [SectionHeader], placed on this page's own grid.
  ///
  /// See [_onRailGrid] for why the header's own inset is cancelled.
  Widget _onRailGrid(Widget child) {
    return Transform.translate(
      offset: const Offset(-ZplaySpacing.s16, 0),
      child: child,
    );
  }
}
