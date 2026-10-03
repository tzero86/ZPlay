import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/manga/manga.dart';
import '../../models/manga/manga_chapter.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/manga/manga_service.dart';
import '../../services/manga/manga_settings.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/slider_arrow.dart';
import '../../widgets/manga/manga_card.dart';
import '../../widgets/manga/manga_category_dropdown.dart';
import '../settings/appearance/manga_settings_page.dart';
import 'manga_reader_page.dart';
import 'widgets/manga_reader_controls.dart';
import '../../services/storage/app_image_cache.dart';

class MangaPage extends StatefulWidget {
  const MangaPage({super.key});

  @override
  State<MangaPage> createState() => _MangaPageState();
}

class _MangaPageState extends State<MangaPage> {
  // Static cache to preserve state across navigations
  static List<Manga>? _cachedMangaList;
  static List<Map<String, dynamic>>? _cachedReadingHistory;
  static int _cachedCurrentPage = 1;
  static String _cachedSearchQuery = '';
  static String _cachedSelectedGenre = 'All';
  static double _cachedScrollOffset = 0.0;

  final MangaService _mangaService = MangaService();
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Manga> _mangaList = [];
  List<Map<String, dynamic>> _readingHistory = [];
  
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  String _searchQuery = '';
  String _selectedGenre = 'All';
  
  // Track grid layout dimensions
  late double _screenWidth;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _cachedScrollOffset);
    _searchController.text = _cachedSearchQuery;
    _selectedGenre = _cachedSelectedGenre;
    
    MangaSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    if (_cachedMangaList != null && _cachedReadingHistory != null) {
      _mangaList = _cachedMangaList!;
      _readingHistory = _cachedReadingHistory!;
      _currentPage = _cachedCurrentPage;
      _searchQuery = _cachedSearchQuery;
      _selectedGenre = _cachedSelectedGenre;
      // Refresh reading history in background silently
      _mangaService.getReadingHistory().then((history) {
        if (mounted) {
          setState(() {
            _readingHistory = history;
            _cachedReadingHistory = history;
          });
        }
      });
    } else {
      _isLoading = true;
      _loadInitialData();
    }
    
    MangaService.readingHistoryRevision.addListener(_loadHistory);
    _scrollController.addListener(_onScroll);
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    MangaSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    MangaService.readingHistoryRevision.removeListener(_loadHistory);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      _cachedScrollOffset = _scrollController.offset;
    }
    if (_isLoading || _isLoadingMore) return;
    
    // If we're within 800 pixels of the bottom, load more
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadHistory() async {
    final history = await _mangaService.getReadingHistory();
    if (mounted) {
      setState(() {
        _readingHistory = history;
      });
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _mangaList.clear();
    });
    
    final results = await Future.wait([
      _searchQuery.isEmpty 
          ? _mangaService.getManga(page: _currentPage, tag: _selectedGenre == 'All' ? null : _selectedGenre)
          : _mangaService.searchManga(_searchQuery, page: _currentPage),
      _mangaService.getReadingHistory(),
    ]);

    if (mounted) {
      setState(() {
        _mangaList = results[0] as List<Manga>;
        _readingHistory = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
        
        _cachedMangaList = _mangaList;
        _cachedReadingHistory = _readingHistory;
        _cachedCurrentPage = _currentPage;
        _cachedSearchQuery = _searchQuery;
        _cachedSelectedGenre = _selectedGenre;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    
    _currentPage++;
    final newManga = _searchQuery.isEmpty 
        ? await _mangaService.getManga(page: _currentPage, tag: _selectedGenre == 'All' ? null : _selectedGenre)
        : await _mangaService.searchManga(_searchQuery, page: _currentPage);
        
    if (mounted) {
      setState(() {
        _mangaList.addAll(newManga);
        _isLoadingMore = false;
        
        _cachedMangaList = _mangaList;
        _cachedCurrentPage = _currentPage;
      });
    }
  }
  
  void _onSearchChanged(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _loadInitialData();
  }

  void _onGenreSelected(String genre) {
    if (_selectedGenre == genre && _searchQuery.isEmpty) return;
    setState(() {
      _selectedGenre = genre;
      _cachedSelectedGenre = genre;
      _searchQuery = '';
      _searchController.clear();
      _cachedSearchQuery = '';
    });
    _loadInitialData();
  }

  void _resumeReading(Map<String, dynamic> historyEntry) {
    final mangaJson = historyEntry['manga'];
    final manga = Manga.fromJson(mangaJson);
    final chapterIndex = historyEntry['chapterIndex'] as int;
    final pageIndex = historyEntry['pageIndex'] as int;
    final chaptersList = (historyEntry['chapters'] as List).map((c) => MangaChapter.fromJson(c)).toList();

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MangaReaderPage(
          manga: manga,
          chapters: chaptersList,
          currentChapterIndex: chapterIndex,
          resumePageIndex: pageIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _onRemoveHistory(String mangaId) {
    _mangaService.removeHistory(mangaId).then((_) {
      _loadHistory();
    });
  }

  void _showMangaCustomizer(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: palette.primaryColor, size: 20),
                      const SizedBox(width: ZplaySpacing.s12),
                      Text(
                        'Customize Manga Section',
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  Divider(color: tokens.borderDefault),
                  const SizedBox(height: ZplaySpacing.s12),

                  Text(
                    'Poster Card Density',
                    style: ZplayType.label.toStyle(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: ZplaySpacing.s8),
                  ValueListenableBuilder<MangaCardDensity>(
                    valueListenable: MangaSettings.cardDensity,
                    builder: (context, density, _) {
                      return SegmentedTabs<MangaCardDensity>(
                        semanticsLabel: 'Manga poster card density',
                        selected: density,
                        onSelected: MangaSettings.setCardDensity,
                        options: [
                          for (final option in MangaCardDensity.values)
                            SegmentedTabOption(
                              value: option,
                              label: option.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: ZplaySpacing.s16),

                  ValueListenableBuilder<bool>(
                    valueListenable: MangaSettings.enableAmbientLights,
                    builder: (context, enabled, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Moving Ambient Background Glow', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        value: enabled,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => MangaSettings.setEnableAmbientLights(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: MangaSettings.showContinueReading,
                    builder: (context, show, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show "Continue Reading" Slider', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        value: show,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => MangaSettings.setShowContinueReading(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: MangaSettings.showContentTypeBadge,
                    builder: (context, show, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show Content Type Badge on Posters', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        value: show,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => MangaSettings.setShowContentTypeBadge(val),
                      );
                    },
                  ),

                  const SizedBox(height: ZplaySpacing.s12),
                  Divider(color: tokens.borderDefault),
                  const SizedBox(height: ZplaySpacing.s12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.primaryColor.withValues(alpha: 0.15),
                        foregroundColor: palette.primaryColor,
                        side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
                        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s12),
                      ),
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: Text('More Appearance & Reader Settings', style: ZplayType.label.toStyle()),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MangaSettingsPage()),
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.sizeOf(context).width;
    final palette = AppThemeService.currentPalette.value;
    final ambientEnabled = MangaSettings.enableAmbientLights.value;
    final showScrollTrack = MangaSettings.showScrollTrack.value;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Moving Ambient Background ──
          if (ambientEnabled)
            const Positioned.fill(child: AnimatedAmbientBackground())
          else
            Positioned.fill(
              child: Container(color: palette.scaffoldBackgroundColor),
            ),

          LiquidGlassView(
            pixelRatio: 0.25,
            refreshRate: LiquidGlassRefreshRate.low,
            backgroundWidget: _buildScrollableContent(),
            child: Stack(
              children: [
                // Top App Bar / Search / Customize
                _buildAppBar(),
                
                // Custom Scroll Track (Desktop only)
                if (_screenWidth > 800 && showScrollTrack)
                  Positioned(
                    right: 24,
                    bottom: 40,
                    child: CustomScrollTrack(controller: _scrollController),
                  ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent() {
    final palette = AppThemeService.currentPalette.value;
    final density = MangaSettings.cardDensity.value;
    final sizing = MangaCardSizing.fromWidth(_screenWidth, density: density);
    final showContinue = MangaSettings.showContinueReading.value;
    final isMobile = _screenWidth < 600;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tokens = context.tokens;

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: 76.0 + topInset), // Spacer for top app bar
        ),

        // ── Reader Atmosphere & Page Mode ──
        // The prototype puts the reader's two controls on the shelf, not three
        // taps into a settings sheet. Both write settings the reader honours.
        const SliverToBoxAdapter(child: MangaReaderControlBar()),

        // ── Continue Reading ──
        if (showContinue && _readingHistory.isNotEmpty && _searchQuery.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24),
              child: SectionHeader(
                title: 'Continue Reading',
                count: _readingHistory.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: ZplaySpacing.s8),
              child: _ContinueReadingSlider(
                readingHistory: _readingHistory,
                onResume: _resumeReading,
                onRemove: _onRemoveHistory,
                screenWidth: _screenWidth,
                isMobile: isMobile,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24),
          ),
        ],

        // ── Discovery / Search Results & Category Dropdown ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? ZplaySpacing.s16 : ZplaySpacing.s32,
              vertical: isMobile ? ZplaySpacing.s12 : ZplaySpacing.s16,
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Search Results'
                            : (_selectedGenre == 'All' ? 'Discover Manga' : '$_selectedGenre Manga'),
                        style: ZplayType.titleLarge.toStyle(
                          color: tokens.textPrimary,
                        ),
                      ),
                      if (_searchQuery.isEmpty) ...[
                        const SizedBox(height: ZplaySpacing.s12),
                        Row(
                          children: [
                            MangaCategoryDropdown(
                              selectedGenre: _selectedGenre,
                              genres: MangaService.popularGenres,
                              onGenreSelected: _onGenreSelected,
                            ),
                            if (_selectedGenre != 'All') ...[
                              const SizedBox(width: ZplaySpacing.s8),
                              _ClearGenreChip(
                                label: 'Clear',
                                tooltip: 'Reset to All Categories',
                                onTap: () => _onGenreSelected('All'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Search Results'
                                : (_selectedGenre == 'All' ? 'Discover Manga' : '$_selectedGenre Manga'),
                            style: ZplayType.display.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          if (_searchQuery.isEmpty && _selectedGenre != 'All')
                            Padding(
                              padding: const EdgeInsets.only(top: ZplaySpacing.s4),
                              child: Text(
                                'Filtered by category • $_selectedGenre',
                                style: ZplayType.bodySmall.toStyle(
                                  color: palette.primaryColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_searchQuery.isEmpty)
                        Row(
                          children: [
                            MangaCategoryDropdown(
                              selectedGenre: _selectedGenre,
                              genres: MangaService.popularGenres,
                              onGenreSelected: _onGenreSelected,
                            ),
                            if (_selectedGenre != 'All') ...[
                              const SizedBox(width: ZplaySpacing.s8),
                              _ClearGenreChip(
                                tooltip: 'Reset to All Categories',
                                onTap: () => _onGenreSelected('All'),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
          ),
        ),
        
        if (_isLoading && _mangaList.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: tokens.textPrimary),
            ),
          )
        else if (_mangaList.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No manga found',
                style: ZplayType.title.toStyle(color: tokens.textEmphasis),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding, vertical: ZplaySpacing.s8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: sizing.cardWidth + sizing.spacing * 2,
                mainAxisSpacing: ZplaySpacing.s32,
                crossAxisSpacing: sizing.spacing,
                mainAxisExtent: sizing.totalHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return MangaCard(manga: _mangaList[index]);
                },
                childCount: _mangaList.length,
              ),
            ),
          ),
          
        if (_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s32),
              child: Center(child: CircularProgressIndicator(color: tokens.textPrimary)),
            ),
          ),
        
        SliverToBoxAdapter(
          child: SizedBox(height: ZplaySpacing.s24 + bottomInset), // Trailing gap only; the dock needed 110 px here
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    final topInset = MediaQuery.paddingOf(context).top;
    final isMobile = _screenWidth < 600;
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    return Positioned(
      top: ZplaySpacing.s12 + topInset,
      left: isMobile ? ZplaySpacing.s12 : ZplaySpacing.s24,
      right: isMobile ? ZplaySpacing.s12 : ZplaySpacing.s24,
      child: Row(
        children: [
          
          // Search Bar
          Expanded(
            child: ClipRRect(
              borderRadius: ZplayRadius.lgAll,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  // Opaque, where this was a 5%-white wash behind a sigma-16
                  // blur. Nothing needs the blur: the field floats over the
                  // poster grid, so the fill only let artwork smear through the
                  // text it is supposed to frame.
                  color: tokens.surface,
                  border: Border.all(
                    color: _searchQuery.isNotEmpty ? palette.primaryColor : tokens.borderDefault,
                    width: 1.5,
                  ),
                  borderRadius: ZplayRadius.lgAll,
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _onSearchChanged,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search Manga, Manhwa, Manhua...',
                    hintStyle: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                    prefixIcon: Icon(Icons.search_rounded, color: palette.primaryColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s20,
                      vertical: ZplaySpacing.s12,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: ZplaySpacing.s12),

          // Quick Customize Button
          ClipRRect(
            borderRadius: ZplayRadius.lgAll,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border.all(
                  color: tokens.borderDefault,
                  width: 1.5,
                ),
                borderRadius: ZplayRadius.lgAll,
              ),
              child: IconButton(
                icon: Icon(Icons.tune_rounded, color: tokens.textEmphasis),
                tooltip: 'Customize Manga Section',
                onPressed: () => _showMangaCustomizer(context),
                splashRadius: ZplayRadius.lg,
              ),
            ),
          ),
          
          // Spacer so search bar doesn't touch the right edge on wide desktop screens
          if (_screenWidth > 800) const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _ContinueReadingSlider extends StatefulWidget {
  final List<Map<String, dynamic>> readingHistory;
  final void Function(Map<String, dynamic>) onResume;
  final void Function(String mangaId) onRemove;
  final double screenWidth;
  final bool isMobile;

  const _ContinueReadingSlider({
    required this.readingHistory,
    required this.onResume,
    required this.onRemove,
    required this.screenWidth,
    required this.isMobile,
  });

  @override
  State<_ContinueReadingSlider> createState() => _ContinueReadingSliderState();
}

class _ContinueReadingSliderState extends State<_ContinueReadingSlider> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHovering = false;

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
    final canRight = _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 10;
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
    final scrollAmount = (viewportWidth * 0.75) * directionMultiplier;
    final target = (_scrollController.position.pixels + scrollAmount).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !widget.isMobile;
    final sizing = MangaCardSizing.fromWidth(
      widget.screenWidth,
      density: MangaSettings.cardDensity.value,
    );

    // Cover, then the caption block beneath it. The rail is exactly as tall as
    // its tallest card, so a title can never be clipped and the row cannot jump
    // as the reading history changes. The block is measured through the ambient
    // text scaler for the same reason: a fixed height from the raw type size
    // would overflow the rail for a user running a larger text scale.
    final scaler = MediaQuery.textScalerOf(context);
    final cardHeight =
        sizing.posterHeight +
        ZplaySpacing.s8 +
        scaler.scale(ZplayType.subtitle.size) * ZplayType.subtitle.height +
        ZplaySpacing.s4 +
        scaler.scale(ZplayType.bodySmall.size) * ZplayType.bodySmall.height;

    return MouseRegion(
      onEnter: (_) {
        if (isDesktop) setState(() => _isHovering = true);
      },
      onExit: (_) {
        if (isDesktop) setState(() => _isHovering = false);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            // The padding is headroom for the focus ring and the lift, both of
            // which are painted outside the card's own box.
            height: cardHeight + ZplaySpacing.s16,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isMobile
                    ? ZplaySpacing.s12
                    : ZplaySpacing.s24,
                vertical: ZplaySpacing.s8,
              ),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.readingHistory.length,
              itemBuilder: (context, index) {
                return _buildHistoryCard(
                  widget.readingHistory[index],
                  sizing,
                );
              },
            ),
          ),
          // Only while the pointer is over the rail. Built unconditionally,
          // these two arrows sat at `left: -60` / `right: -60` on a television -
          // off screen and still focusable, so a D-pad could land on a control
          // nobody can see. The rail is still traversable and scrolls itself to
          // whichever card holds focus.
          if (isDesktop && _isHovering) ...[
            // Left Arrow
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: _canScrollLeft && _isHovering ? ZplaySpacing.s12 : -60,
              top: 0,
              bottom: 0,
              child: Center(
                child: SliderArrow(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => _scroll(-1),
                ),
              ),
            ),
            // Right Arrow
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              right: _canScrollRight && _isHovering ? ZplaySpacing.s12 : -60,
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
    );
  }

  /// One shelf card, in the prototype's `manga-card` anatomy: the cover with
  /// the chapter tag on it, then the title and a muted progress line.
  ///
  /// The wide 16:9 card this replaces put the chapter name in a frosted panel
  /// over the art; the prototype tags the chapter on the cover and keeps the
  /// caption underneath, which is also the shape every other rail card in the
  /// app uses.
  Widget _buildHistoryCard(Map<String, dynamic> entry, MangaCardSizing sizing) {
    final tokens = context.tokens;
    final mangaJson = entry['manga'] as Map<String, dynamic>;
    final mangaId = (mangaJson['id'] ?? '').toString();
    final title = (mangaJson['title'] ?? 'Unknown').toString();
    final author = (mangaJson['author'] ?? '').toString();
    final coverUrl =
        (mangaJson['cover_normal'] ?? mangaJson['cover_small'] ?? '').toString();
    final chapterIndex = entry['chapterIndex'] as int;
    final chaptersList = entry['chapters'] as List;

    final chapterLabel = _chapterLabel(chaptersList, chapterIndex);
    final progress = chaptersList.isEmpty
        ? 0
        : (((chapterIndex + 1) / chaptersList.length) * 100)
              .round()
              .clamp(0, 100);
    final removeSize = FocusMetrics.controlHeight(context);

    return FocusableCard(
      onTap: () => widget.onResume(entry),
      builder: (context, state) => AnimatedScale(
        duration: ZplayMotion.base,
        curve: ZplayMotion.standard,
        scale: state.pressed ? 0.97 : (state.highlighted ? 1.03 : 1.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
          // `Align` hands the card loose vertical constraints. The rail's
          // `ListView` gives its children a *tight* cross-axis height, and a
          // `Column` under a tight height overflows by whatever the type scale
          // adds; here the card measures itself and the extra rail height simply
          // sits below it.
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: sizing.cardWidth,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CardFocusRing(
                  focused: state.focused,
                  radius: ZplayRadius.smAll,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: ZplayRadius.smAll,
                        child: SizedBox(
                          width: sizing.cardWidth,
                          height: sizing.posterHeight,
                          child: coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  cacheManager: AppImageCache.manager,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  errorWidget: (_, _, _) => const MissingPoster(),
                                )
                              : const MissingPoster(),
                        ),
                      ),
                      if (chapterLabel.isNotEmpty)
                        Positioned(
                          left: ZplaySpacing.s8,
                          bottom: ZplaySpacing.s8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.bg.withValues(alpha: 0.85),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ZplaySpacing.s4,
                                vertical: ZplaySpacing.s2,
                              ),
                              child: Text(
                                chapterLabel,
                                style: ZplayType.caption
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                            ),
                          ),
                        ),
                      // Removing an entry stays available on the shelf, where
                      // the entry is. It is a focus target of its own, so the
                      // remote can reach it without a long press.
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Tooltip(
                          message: 'Remove from Continue Reading',
                          child: FocusableCard(
                            onTap: () => widget.onRemove(mangaId),
                            builder: (context, closeState) => CardFocusRing(
                              focused: closeState.focused,
                              radius: ZplayRadius.fullAll,
                              child: SizedBox(
                                width: removeSize,
                                height: removeSize,
                                child: Center(
                                  child: Container(
                                    width: ZplaySpacing.s24,
                                    height: ZplaySpacing.s24,
                                    decoration: BoxDecoration(
                                      color: tokens.bg.withValues(alpha: 0.75),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: tokens.textPrimary,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s8),
                // Both lines are `Flexible`: the rail height is computed from the
                // type scale, and a font whose line box is a fraction taller than
                // `size * height` would otherwise overflow this column by that
                // fraction. Flexible lets the box absorb it.
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s4),
                Flexible(
                  child: Text(
                    author.isEmpty
                        ? '$progress% read'
                        : '$author · $progress% read',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  /// `Ch. 164` for the chapter the entry resumes at, or empty when the history
  /// entry predates the chapter list.
  static String _chapterLabel(List chaptersList, int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= chaptersList.length) return '';
    final number = chaptersList[chapterIndex]['number'];
    if (number is! num || number <= 0) return '';
    final value = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    return 'Ch. $value';
  }
}

/// The way back from a filtered shelf to the whole catalogue.
///
/// This was an [InkWell], which is pointer-only: `InkWell` is not a `Focus`
/// widget, so on a television nothing could land on it and a shelf filtered to
/// one category had no way back to `All`. It is a [FocusableCard] now, with the
/// app's single focus ring and the form factor's minimum target height, and it
/// carries no resting border - a chip's fill says whether it is selected, and
/// the accent outline is reserved for where the focus is.
class _ClearGenreChip extends StatelessWidget {
  /// Null draws the icon-only form.
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  const _ClearGenreChip({
    this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final height = FocusMetrics.controlHeight(context);

    return Tooltip(
      message: tooltip,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: height),
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? ZplaySpacing.s8 : ZplaySpacing.s12,
            ),
            decoration: BoxDecoration(
              color: state.highlighted
                  ? tokens.borderStrong
                  : tokens.borderSubtle,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    label == null
                        ? Icons.refresh_rounded
                        : Icons.close_rounded,
                    size: label == null ? 18 : 16,
                    color: tokens.textEmphasis,
                  ),
                  if (label != null) ...[
                    const SizedBox(width: ZplaySpacing.s4),
                    Text(
                      label!,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textEmphasis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
