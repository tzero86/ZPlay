import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/content/content_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/theme/glass_settings.dart';
import '../../shell/app_shell_scope.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/anime/anime_slider_section.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/hero_meta_line.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/home/continue_watching_slider.dart';
import 'anime_details_page.dart';
import 'anime_stream_sheet.dart';
import 'anime_search_page.dart';
import '../anime_arabic/anime_arabic_details_page.dart';
import '../anime_arabic/anime_arabic_stream_sheet.dart';
import '../../services/storage/app_image_cache.dart';

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  final AnilistService _anilistService = AnilistService.instance;
  final AnimeLibraryService _libraryService = AnimeLibraryService.instance;
  final AnimeArabicService _arabicService = AnimeArabicService.instance;
  final ScrollController _scrollController = ScrollController();

  bool _isArabicMode = false;
  bool _loading = true;
  String? _error;

  // General Anime data
  List<AnimeMedia> _trending = [];
  List<AnimeMedia> _popularSeason = [];
  List<AnimeMedia> _topRated = [];
  List<AnimeMedia> _upcoming = [];
  List<AnimeMedia> _actionAnime = [];
  List<AnimeMedia> _romanceAnime = [];
  List<AnimeMedia> _fantasyAnime = [];
  List<AnimeMedia> _sciFiAnime = [];

  // Arabic Anime data
  HomeFeed? _arabicFeed;
  final Map<int, ArabicAnimeCard> _arabicCards = {};

  @override
  void initState() {
    super.initState();
    _libraryService.addListener(_onLibraryChanged);
    _libraryService.init();
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);
    _loadAnimeData();
  }

  @override
  void dispose() {
    ContentSettings.adultEnabled.removeListener(_onAdultContentChanged);
    _libraryService.removeListener(_onLibraryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  /// AniList queries embed the 18+ switch, so refetch the rows through the
  /// existing load path when it flips.
  void _onAdultContentChanged() {
    if (!mounted) return;
    _loadAnimeData();
  }

  Future<void> _loadAnimeData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isArabicMode) {
      try {
        final feed = await _arabicService.getHome();
        _arabicCards.clear();
        void registerCards(List<ArabicAnimeCard> list) {
          for (final c in list) {
            _arabicCards[c.slug.hashCode.abs()] = c;
          }
        }
        registerCards(feed.spotlight);
        registerCards(feed.recentEpisodes);
        registerCards(feed.trending);
        registerCards(feed.popularMovies);
        registerCards(feed.topSeasonal);
        registerCards(feed.seasonal);
        registerCards(feed.legendary);
        registerCards(feed.upcoming);

        if (mounted) {
          setState(() {
            _arabicFeed = feed;
            _loading = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading Arabic Anime data: $e');
        if (mounted) {
          setState(() {
            _error = 'Failed to load Arabic Anime catalog. Check your internet connection.';
            _loading = false;
          });
        }
      }
      return;
    }

    try {
      final trendingFut = _anilistService.fetchTrendingAnime(perPage: 18);
      final seasonFut = _anilistService.fetchPopularThisSeason(perPage: 18);
      final topRatedFut = _anilistService.fetchTopRated(perPage: 18);
      final upcomingFut = _anilistService.fetchUpcomingNextSeason(perPage: 18);
      final actionFut = _anilistService.fetchByGenre('Action', perPage: 18);
      final romanceFut = _anilistService.fetchByGenre('Romance', perPage: 18);
      final fantasyFut = _anilistService.fetchByGenre('Fantasy', perPage: 18);
      final sciFiFut = _anilistService.fetchByGenre('Sci-Fi', perPage: 18);

      final results = await Future.wait([
        trendingFut,
        seasonFut,
        topRatedFut,
        upcomingFut,
        actionFut,
        romanceFut,
        fantasyFut,
        sciFiFut,
      ]);

      if (mounted) {
        final hasAnyData = results.any((list) => list.isNotEmpty);
        setState(() {
          _trending = results[0];
          _popularSeason = results[1];
          _topRated = results[2];
          _upcoming = results[3];
          _actionAnime = results[4];
          _romanceAnime = results[5];
          _fantasyAnime = results[6];
          _sciFiAnime = results[7];
          _loading = false;
          if (!hasAnyData) {
            _error = 'Failed to load Anime catalog. Please check your internet connection or retry.';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading Anime data: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load Anime catalog. Check your internet connection.';
          _loading = false;
        });
      }
    }
  }

  void _onModeChanged(bool arabic) {
    if (_isArabicMode == arabic) return;
    setState(() {
      _isArabicMode = arabic;
    });
    _loadAnimeData();
  }

  void _playEpisode(AnimeMedia anime, int episodeNumber) {
    if (_isArabicMode || anime.isArabic || _arabicCards.containsKey(anime.id)) {
      final card = _arabicCards[anime.id] ??
          ArabicAnimeCard(
            slug: (anime.slug != null && anime.slug!.isNotEmpty)
                ? anime.slug!
                : anime.titleEnglish.toLowerCase().replaceAll(' ', '-'),
            title: anime.displayTitle,
            cover: anime.coverUrl,
          );
      _arabicService.getDetails(card.slug).then((details) {
        if (!mounted) return;
        final ep = details.episodes.firstWhere(
          (e) => e.number == episodeNumber,
          orElse: () => details.episodes.isNotEmpty
              ? details.episodes.first
              : ArabicEpisode(
                  number: episodeNumber,
                  title: 'الحلقة $episodeNumber',
                  encodedHref: '',
                  watchPath: '/e/${card.slug}-$episodeNumber#tok',
                ),
        );
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => AnimeArabicStreamSheet(
            details: details,
            episode: ep,
            autoPlay: false,
          ),
        );
      });
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimeStreamSheet(
        anime: anime,
        episodeNumber: episodeNumber,
        autoPlay: false,
      ),
    );
  }

  void _openDetails(AnimeMedia anime, [int? preferredEpisode]) {
    if (_isArabicMode || anime.isArabic || _arabicCards.containsKey(anime.id)) {
      final card = _arabicCards[anime.id] ??
          ArabicAnimeCard(
            slug: (anime.slug != null && anime.slug!.isNotEmpty)
                ? anime.slug!
                : anime.titleEnglish.toLowerCase().replaceAll(' ', '-'),
            title: anime.displayTitle,
            cover: anime.coverUrl,
          );
      final epNum = preferredEpisode ?? (anime.totalEpisodes > 0 ? anime.totalEpisodes : null);
      Navigator.push(
        context,
        CinematicSlideRoute(
          page: AnimeArabicDetailsPage(
            anime: card,
            initialEpisodeNumber: epNum,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      CinematicSlideRoute(
        page: AnimeDetailsPage(anime: anime),
      ),
    );
  }

  /// Settings is a shell slot now, so this switches the shell instead of pushing
  /// a route that would stack a second navigation model above it. The lookup is
  /// nullable because widget tests and entity routes mount this page outside the
  /// shell, where the no-op is the correct outcome.
  void _navigateToSettings() {
    AppShellScope.of(context)?.go(ShellSlot.settings);
  }

  void _navigateToSearch(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: AnimeSearchPage(initialArabicMode: _isArabicMode),
        tapPosition: tapPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        final tokens = context.tokens;
        final backgroundContent = AnimatedAmbientBackground(
          child: Stack(
            children: [
              // Main scrollable content
              if (_loading && (_isArabicMode ? _arabicFeed == null : _trending.isEmpty))
                Center(
                  child: CircularProgressIndicator(color: palette.primaryColor),
                )
              else if (_error != null && (_isArabicMode ? _arabicFeed == null : _trending.isEmpty))
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: tokens.danger,
                        size: 48,
                      ),
                      const SizedBox(height: ZplaySpacing.s16),
                      Text(
                        _error!,
                        style: ZplayType.title.toStyle(
                          color: tokens.textEmphasis,
                        ),
                      ),
                      const SizedBox(height: ZplaySpacing.s16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.primaryColor,
                        ),
                        onPressed: _loadAnimeData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                RefreshIndicator(
                  color: palette.primaryColor,
                  backgroundColor: palette.cardBackgroundColor,
                  onRefresh: _loadAnimeData,
                  child: ListView(
                    controller: _scrollController,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    children: [
                      if (_isArabicMode) ...[
                        // 1. Arabic Hero Carousel (Matching Home Page)
                        if (_arabicFeed != null &&
                            (_arabicFeed!.spotlight.isNotEmpty || _arabicFeed!.trending.isNotEmpty))
                          _AnimeHeroCarousel(
                            animeList: (_arabicFeed!.spotlight.isNotEmpty
                                    ? _arabicFeed!.spotlight
                                    : _arabicFeed!.trending)
                                .take(6)
                                .map((c) => c.toAnimeMedia())
                                .toList(),
                            onWatchNow: (anime) => _playEpisode(anime, 1),
                            onDetailsTap: _openDetails,
                          ),

                        const SizedBox(height: ZplaySpacing.s16),

                        // 2. Anime Continue Watching Slider
                        const ContinueWatchingSlider(
                          typeFilter: 'arabic_anime',
                          title: 'متابعة المشاهدة',
                        ),

                        const SizedBox(height: ZplaySpacing.s8),

                        // 3. Arabic Sliders with Desktop Scroll Arrows
                        if (_arabicFeed != null) ...[
                          if (_arabicFeed!.recentEpisodes.isNotEmpty)
                            AnimeSliderSection(
                              title: '⚡ آخر الحلقات المعروضة',
                              subtitle: 'أحدث الحلقات المضافة المترجمة للعربية',
                              animeList: _arabicFeed!.recentEpisodes.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: (anime) => _openDetails(anime, anime.totalEpisodes > 0 ? anime.totalEpisodes : null),
                            ),
                          if (_arabicFeed!.trending.isNotEmpty)
                            AnimeSliderSection(
                              title: '🔥 الأكثر شهرة وتداولاً',
                              subtitle: 'الأنميات الأكثر مشاهدة حالياً',
                              animeList: _arabicFeed!.trending.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                          if (_arabicFeed!.popularMovies.isNotEmpty)
                            AnimeSliderSection(
                              title: '🎬 الأفلام الأكثر شعبية',
                              subtitle: 'أفلام الأنمي المميزة',
                              animeList: _arabicFeed!.popularMovies.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                          if (_arabicFeed!.topSeasonal.isNotEmpty)
                            AnimeSliderSection(
                              title: '👑 أفضل الأنميات',
                              subtitle: 'أنميات ذات تقييمات استثنائية',
                              animeList: _arabicFeed!.topSeasonal.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                          if (_arabicFeed!.seasonal.isNotEmpty)
                            AnimeSliderSection(
                              title: '🌟 أنميات موسمية',
                              subtitle: 'عروض الموسم الحالي',
                              animeList: _arabicFeed!.seasonal.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                          if (_arabicFeed!.legendary.isNotEmpty)
                            AnimeSliderSection(
                              title: '⚔️ أنميات أسطورية',
                              subtitle: 'أعمال خالدة يجب ألا تفوتك',
                              animeList: _arabicFeed!.legendary.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                          if (_arabicFeed!.upcoming.isNotEmpty)
                            AnimeSliderSection(
                              title: '🚀 المنتظرة قريباً',
                              subtitle: 'أنميات قادمة قريباً',
                              animeList: _arabicFeed!.upcoming.map((c) => c.toAnimeMedia()).toList(),
                              onAnimeTap: _openDetails,
                            ),
                        ],
                      ] else ...[
                        // 1. Full Bleed Hero Carousel (Matching Home Page)
                        if (_trending.isNotEmpty)
                          _AnimeHeroCarousel(
                            animeList: _trending.take(6).toList(),
                            onWatchNow: (anime) => _playEpisode(anime, 1),
                            onDetailsTap: _openDetails,
                          ),

                        const SizedBox(height: ZplaySpacing.s16),

                        // 2. Anime Continue Watching Slider
                        const ContinueWatchingSlider(
                          typeFilter: 'general_anime',
                          title: 'Continue Watching',
                        ),

                        const SizedBox(height: ZplaySpacing.s8),

                        // 3. Sliders with Desktop Scroll Arrows
                        AnimeSliderSection(
                          title: 'Trending on AniList',
                          subtitle: 'Top popular and trending series',
                          animeList: _trending,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Popular This Season (AniList Sync)',
                          subtitle: 'Currently airing hits · ${AnilistService.currentSeason()}',
                          animeList: _popularSeason,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'All-Time Masterpieces',
                          subtitle: 'Critically acclaimed top rated anime',
                          animeList: _topRated,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Anticipated Next Season',
                          subtitle: 'Upcoming anime you cannot miss',
                          animeList: _upcoming,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Action & Adventure',
                          subtitle: 'High octane battles and epic journeys',
                          animeList: _actionAnime,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Romance & Drama',
                          subtitle: 'Heartfelt emotional stories',
                          animeList: _romanceAnime,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Fantasy & Isekai',
                          subtitle: 'Magical realms and alternate worlds',
                          animeList: _fantasyAnime,
                          onAnimeTap: _openDetails,
                        ),
                        AnimeSliderSection(
                          title: 'Sci-Fi & Cyberpunk',
                          subtitle: 'Futuristic technologies and dystopian worlds',
                          animeList: _sciFiAnime,
                          onAnimeTap: _openDetails,
                        ),
                      ],

                      // Trailing gap only: the dock used to reserve 110 px of clearance here.
                      SizedBox(height: ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom),
                    ],
                  ),
                ),
            ],
          ),
        );

        final overlayChildren = <Widget>[
          // Floating Glass App Bar (Home Page Style)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _AnimeGlassAppBar(
              topPadding: topPadding,
              isArabicMode: _isArabicMode,
              onModeChanged: _onModeChanged,
              onSearchTap: _navigateToSearch,
              onSettingsTap: _navigateToSettings,
            ),
          ),

          // Custom Scroll Track (Matching Home Page)
          if (MediaQuery.sizeOf(context).width > 800)
            Positioned(
              right: 24,
              bottom: 40,
              child: CustomScrollTrack(controller: _scrollController),
            ),

        ];

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ValueListenableBuilder<bool>(
            valueListenable: GlassSettings.enabled,
            builder: (context, enabled, _) {
              final overlays = Stack(children: overlayChildren);
              if (enabled) {
                return LiquidGlassView(
                  realTimeCapture: true,
                  useSync: true,
                  pixelRatio: 0.85,
                  refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
                  regionCapture: true,
                  backgroundWidget: backgroundContent,
                  child: overlays,
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: backgroundContent),
                  ...overlayChildren,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted Glass App Bar for Anime (Matching Home Page GlassAppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeGlassAppBar extends StatelessWidget {
  final double topPadding;
  final bool isArabicMode;
  final ValueChanged<bool> onModeChanged;
  final void Function(Offset?) onSearchTap;
  final VoidCallback onSettingsTap;

  const _AnimeGlassAppBar({
    required this.topPadding,
    required this.isArabicMode,
    required this.onModeChanged,
    required this.onSearchTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;
    final isMobile = MediaQuery.sizeOf(context).width < 430;
    // Every control in this bar is a focus target: the mode pills measured
    // 25 dp tall, which is not something a five-way pad can land on.
    final minTapTarget = FormFactorService.of(context) == FormFactor.compact
        ? 40.0
        : kMinInteractiveDimension;

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.only(
          // Zero on every form factor whose shell draws the top bar, which is
          // what hands this page its MediaQuery; the phone's bar is at the foot,
          // so there the page still pays the status-bar strip itself.
          top: topPadding + ZplaySpacing.s8,
          bottom: ZplaySpacing.s16,
          left: isMobile ? ZplaySpacing.s8 : ZplaySpacing.s20,
          right: ZplaySpacing.s8,
        ),
        decoration: BoxDecoration(
          // Opaque, where this was a 90-96% `#080A0F` gradient. Nothing blurs
          // behind this bar: it has no lens wrapper, and the glass gate
          // (`GlassSettings.enabled`) defaults false, so a translucent fill only
          // let the bright anime artwork smear through underneath and left the
          // bar's own text on a moving background. Kept byte-identical to Home's
          // `_GlassAppBar`, which had the same treatment for the same reason.
          //
          // `tokens.bg` over the literal also fixes a palette mismatch: `#080A0F`
          // is only the ocean palette's background, so the bar stayed ocean-black
          // under all eleven other palettes.
          color: tokens.bg,
          border: Border(bottom: tokens.hairline),
        ),
        child: Row(
          children: [
            // Mode Switcher (General Anime vs Arabic Anime).
            //
            // The brand pill and the `ZPlay Anime` wordmark that used to sit to
            // the left of this are gone: the shell's top bar already carries the
            // brand, and the browse switcher above this page already says which
            // vertical is showing. Both were a second copy of chrome the user
            // can see 48 dp higher up.
            Container(
              padding: const EdgeInsets.all(ZplaySpacing.s4),
              decoration: BoxDecoration(
                // The track is the audit's 6%-white inset wash, so the border
                // scale's subtlest step is the exact match for the fill.
                color: tokens.borderSubtle,
                borderRadius: ZplayRadius.lgAll,
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeButton(
                    tokens: tokens,
                    label: isDesktop ? '🇯🇵 General' : '🇯🇵',
                    isActive: !isArabicMode,
                    onTap: () => onModeChanged(false),
                    minHeight: minTapTarget,
                  ),
                  _buildModeButton(
                    tokens: tokens,
                    label: isDesktop ? '🇸🇦 Arabic Anime' : '🇸🇦',
                    isActive: isArabicMode,
                    onTap: () => onModeChanged(true),
                    minHeight: minTapTarget,
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZplaySpacing.s8),

            // Search Button
            Builder(
              builder: (context) {
                return IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    color: tokens.textEmphasis,
                    size: 25,
                  ),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final offset = box?.localToGlobal(box.size.center(Offset.zero));
                    onSearchTap(offset);
                  },
                );
              },
            ),

            // Settings takes no reveal origin, unlike Search: it is a shell slot.
            IconButton(
              icon: Icon(
                Icons.settings_rounded,
                color: tokens.textEmphasis,
                size: 24,
              ),
              onPressed: onSettingsTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required ZplayTokens tokens,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required double minHeight,
  }) {
    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => AnimatedContainer(
        duration: ZplayMotion.base,
        curve: ZplayMotion.standard,
        // 48 dp on anything that is not a held phone. These pills measured 25 dp
        // tall, which is a target a five-way pad cannot reliably land on; the
        // label stays the same size, the pill just has room around it.
        height: minHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
        decoration: BoxDecoration(
          // The drop shadow under the active pill is gone: it is a second,
          // blurred edge under the pill, and the fill already says which mode is
          // on.
          color: isActive
              ? AppThemeService.currentPalette.value.primaryColor
              : Colors.transparent,
          borderRadius: ZplayRadius.mdAll,
        ),
        child: Text(
          label,
          style: ZplayType.bodySmall
              .copyWith(weight: isActive ? FontWeight.w700 : FontWeight.w600)
              .toStyle(
                color: isActive ? tokens.textPrimary : tokens.textEmphasis,
              ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-Bleed Anime Hero Carousel (Matching Home Page _HeroCarousel)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeHeroCarousel extends StatefulWidget {
  final List<AnimeMedia> animeList;
  final Function(AnimeMedia) onWatchNow;
  final Function(AnimeMedia) onDetailsTap;

  const _AnimeHeroCarousel({
    required this.animeList,
    required this.onWatchNow,
    required this.onDetailsTap,
  });

  @override
  State<_AnimeHeroCarousel> createState() => _AnimeHeroCarouselState();
}

class _AnimeHeroCarouselState extends State<_AnimeHeroCarousel> {
  static const _rotateEvery = Duration(seconds: 8);
  final PageController _pageController = PageController();

  Timer? _timer;
  int _index = 0;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.animeList.length < 2) return;
    _timer = Timer.periodic(_rotateEvery, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % widget.animeList.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: ZplayMotion.emphasized,
      );
    });
  }

  void _pauseTimer() => _timer?.cancel();

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 600),
      curve: ZplayMotion.emphasized,
    );
  }

  /// The prototype's anime spotlight is a band, not the screen: 220 of 540 dp
  /// on a television, so the seasonal rails under it are on screen at the same
  /// time. The curve this replaces asked for 0.52-0.82 of the viewport with a
  /// 380-620 dp floor, which on a 540 dp canvas produced a 620 dp hero - taller
  /// than the display it was drawn on, so the first rail was always below the
  /// fold and the page opened as a hero with nothing else.
  double _heroHeight(double screenWidth, double screenHeight) {
    final target = screenHeight * (screenWidth < 600 ? 0.62 : 0.55);
    return target.clamp(screenWidth < 600 ? 320.0 : 260.0, 560.0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = _heroHeight(screenWidth, screenHeight);

    if (widget.animeList.isEmpty) return SizedBox(height: heroHeight);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        _pauseTimer();
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _startTimer();
      },
      child: SizedBox(
        height: heroHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.animeList.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final anime = widget.animeList[i];
                return _AnimeHeroSlide(
                  anime: anime,
                  screenWidth: screenWidth,
                  compactHeight: heroHeight < 400,
                  onWatchNow: () => widget.onWatchNow(anime),
                  onDetailsTap: () => widget.onDetailsTap(anime),
                );
              },
            ),

            // Dot indicators.
            //
            // Same treatment as Home's: on a television these are decoration,
            // not controls. A 7 dp dot is not a target anyone from a sofa is
            // meant to find, and directional traversal from the hero's buttons
            // found them first - one DOWN jumped the carousel instead of moving
            // into the rails, with the focus ring drawn around a 7 dp mark.
            // Rotation still runs on its timer and the slides still exist, so a
            // slide is reachable by waiting; a pointer keeps both.
            if (widget.animeList.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Focus(
                  canRequestFocus:
                      FormFactorService.of(context) != FormFactor.television,
                  skipTraversal:
                      FormFactorService.of(context) == FormFactor.television,
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.animeList.length, (i) {
                    final active = i == _index;
                    return FocusableCard(
                      onTap: () => _goTo(i),
                      builder: (_, state) => AnimatedContainer(
                        duration: ZplayMotion.base,
                        curve: ZplayMotion.standard,
                        margin: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s4,
                        ),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.xsAll,
                          color: active
                              ? AppThemeService.currentPalette.value.primaryColor
                              : tokens.textDisabled,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: AppThemeService.currentPalette.value.primaryColor
                                        .withValues(alpha: 0.55),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                    }),
                  ),
                ),
              ),

            // Desktop Hover Arrows
            if (widget.animeList.length > 1 &&
                _isHovering &&
                screenWidth > 600) ...[
              if (_index > 0)
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CarouselArrow(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => _goTo(_index - 1),
                    ),
                  ),
                ),
              if (_index < widget.animeList.length - 1)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CarouselArrow(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: () => _goTo(_index + 1),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimeHeroSlide extends StatelessWidget {
  final AnimeMedia anime;
  final double screenWidth;

  /// True when the hero band is too short for the full spotlight - a television
  /// at 960x540 gets ~300 dp, where the prototype's own spotlight is 220. The
  /// synopsis is dropped there rather than letting the column overflow the band.
  final bool compactHeight;

  final VoidCallback onWatchNow;
  final VoidCallback onDetailsTap;

  const _AnimeHeroSlide({
    required this.anime,
    required this.screenWidth,
    required this.compactHeight,
    required this.onWatchNow,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isCompact = screenWidth < 600;
    final hasBanner = anime.bannerImage.trim().isNotEmpty;
    final bannerUrl = hasBanner ? anime.bannerImage : null;
    final posterUrl = anime.coverUrl.trim().isNotEmpty ? anime.coverUrl : null;
    final effectiveUrl = bannerUrl ?? posterUrl;
    // Layer 1 blur + foreground Layer 2 decode each URL once: same URL +
    // same memCacheWidth hits the shared ResizeImage cache entry.
    final heroCacheWidth = hasBanner ? 1280 : 512;
    Widget heroArtwork({
      required String url,
      required BoxFit fit,
      required Alignment alignment,
      FilterQuality filterQuality = FilterQuality.medium,
      Widget Function(BuildContext, String)? placeholder,
      Widget Function(BuildContext, String, Object)? errorWidget,
    }) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheManager: AppImageCache.manager,
        memCacheWidth: heroCacheWidth,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget: errorWidget ?? (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background Layers ──
        if (effectiveUrl != null && effectiveUrl.trim().isNotEmpty)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final containerWidth = constraints.maxWidth;
                final containerHeight = constraints.maxHeight;
                final containerAspect = containerWidth / containerHeight;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Layer 1: Ambient blurred background fill (eliminates all black bars)
                    ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 32,
                              sigmaY: 32,
                            ),
                            child: Transform.scale(
                              scale: 1.15,
                              child: heroArtwork(
                                url: effectiveUrl,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.low,
                                placeholder: (_, __) =>
                                    ColoredBox(color: tokens.surface),
                                errorWidget: (_, __, ___) =>
                                    ColoredBox(color: tokens.surface),
                              ),
                            ),
                          ),
                          ColoredBox(
                            color: tokens.bg.withValues(alpha: 0.50),
                          ),
                        ],
                      ),
                    ),

                    // Layer 2: Crisp foreground artwork
                    if (hasBanner) ...[
                      // Landscape 16:9 banner available
                      if (containerAspect <= 1.78)
                        Positioned.fill(
                          child: heroArtwork(
                            url: bannerUrl!,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.15),
                          ),
                        )
                      else
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: (containerHeight * (16 / 9))
                              .clamp(0.0, containerWidth),
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              return const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: [0.0, 0.22],
                                colors: [Colors.transparent, Colors.white],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.dstIn,
                            child: heroArtwork(
                              url: bannerUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                    ] else ...[
                      // Portrait poster fallback (when no 16:9 banner is available)
                      if (containerAspect <= 1.2)
                        Positioned.fill(
                          child: heroArtwork(
                            url: effectiveUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        )
                      else
                        Positioned(
                          top: 40,
                          bottom: isCompact ? 70 : 60,
                          right: isCompact ? 24 : 72,
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: ZplayRadius.lgAll,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    blurRadius: 36,
                                    spreadRadius: 4,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: ZplayRadius.lgAll,
                                child: heroArtwork(
                                  url: effectiveUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          )
        else
          ColoredBox(color: tokens.surface),

        // Left horizontal wash for cinematic readability. The wash keeps its
        // gradient structure — it is a legibility scrim over artwork, not chrome —
        // and only takes its colour from the palette, like Home's hero.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.38, 0.85],
                colors: [
                  tokens.bg.withValues(alpha: 0.95),
                  tokens.bg.withValues(alpha: 0.70),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Top Gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  tokens.bg.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Bottom Gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.30, 0.75],
                colors: [
                  tokens.bg,
                  tokens.bg.withValues(alpha: 0.80),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Content Overlay
        Positioned(
          left: isCompact ? ZplaySpacing.s20 : ZplaySpacing.s48,
          right: isCompact ? ZplaySpacing.s20 : ZplaySpacing.s48,
          bottom: compactHeight ? 24 : (isCompact ? 36 : 56),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isCompact ? double.infinity : 680.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One metadata line, in the reference's order: the genres,
                  // the year, the episode count and the studio, with the score
                  // in a badge in front of it.
                  //
                  // This was a hand-built `Row` carrying its own badge and its
                  // own separator. It held the same facts as Home's meta line in
                  // a second visual register, which is the one thing the shared
                  // line exists to end, so it is now that line.
                  //
                  // The "AniList Sync" prefix is gone because AniList is where
                  // every title on this page comes from: naming the source on
                  // every slide says nothing that tells one slide from the next.
                  //
                  // **No band grew.** The line replaced a row of the same height
                  // in the same place, and the terms it drops are the ones the
                  // model cannot fill - a title with no season year, no episode
                  // count and no studio prints fewer terms rather than padding
                  // the line out.
                  HeroMetaLine(
                    terms: [
                      ...anime.genres.take(3),
                      if (anime.seasonYear > 0) '${anime.seasonYear}',
                      if (anime.totalEpisodes > 0)
                        '${anime.totalEpisodes} Episodes',
                      if (anime.studioName.isNotEmpty) anime.studioName,
                    ],
                    leadingRating: anime.averageScore > 0
                        ? anime.formattedScore
                        : null,
                  ),

                  SizedBox(
                    height: compactHeight ? ZplaySpacing.s8 : ZplaySpacing.s16,
                  ),

                  // Title
                  Text(
                    anime.displayTitle,
                    style: ZplayType.display
                        .copyWith(
                          size: compactHeight
                              ? 32
                              : (isCompact ? 30 : 44),
                        )
                        .toStyle(color: tokens.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Synopsis: the prototype's spotlight has none, so a hero
                  // band that is only ~300 dp tall on a television keeps the
                  // title, the meta line and the two actions instead of
                  // overflowing to fit a paragraph.
                  if (anime.description.isNotEmpty && !compactHeight) ...[
                    SizedBox(
                      height: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s16,
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompact ? double.infinity : 580,
                      ),
                      child: Text(
                        anime.description,
                        maxLines: isCompact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.body
                            .copyWith(size: isCompact ? 14.5 : 15.5)
                            .toStyle(color: tokens.textEmphasis),
                      ),
                    ),
                  ],

                  // Genre chips used to sit here as a second row of pills. The
                  // prototype carries the genres in the meta line above, which
                  // is both what the design asks for and 44 dp less chrome
                  // before the first rail on a 540 dp television.

                  // Action buttons (Matching Home Page)
                  SizedBox(
                    height: compactHeight
                        ? ZplaySpacing.s12
                        : (isCompact ? ZplaySpacing.s20 : ZplaySpacing.s24),
                  ),
                  Row(
                    children: [
                      // The shared pill, so this band's calls to action are the
                      // same shape as Home's hero and the details page's Play.
                      // It replaced an accent-gradient `ElevatedButton` whose
                      // focus treatment changed the border width - a reflow of
                      // the label on every focus move, which is what the ring
                      // drawn *over* the pill exists to avoid.
                      Builder(
                        builder: (context) => PillButton(
                          label: 'Watch S1:E1',
                          icon: Icons.play_arrow_rounded,
                          onPressed: onWatchNow,
                        ),
                      ),
                      SizedBox(
                        width: isCompact ? ZplaySpacing.s8 : ZplaySpacing.s12,
                      ),
                      // The qualifier beside the affirmative, so the row is two
                      // pills of one height and one shape rather than a pill
                      // and an outlined rectangle.
                      Builder(
                        builder: (context) => PillButton(
                          label: 'AniList Details',
                          icon: Icons.info_outline_rounded,
                          variant: PillVariant.secondary,
                          onPressed: onDetailsTap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CarouselArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => AnimatedContainer(
        duration: ZplayMotion.base,
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state.highlighted ? tokens.surfaceRaised : tokens.surface,
          border: Border.all(
            color: state.highlighted ? tokens.accent : tokens.borderStrong,
          ),
        ),
        child: Icon(
          icon,
          color: state.highlighted ? tokens.textPrimary : tokens.textEmphasis,
          size: 24,
        ),
      ),
    );
  }
}
