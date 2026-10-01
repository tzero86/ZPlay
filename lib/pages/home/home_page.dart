import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/movie/movie.dart';
import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/layout/form_factor.dart';
import '../../services/content/content_settings.dart';
import '../../widgets/anime/anime_slider_section.dart';
import '../anime/anime_details_page.dart';

import '../../models/movie/movie_detail.dart';
import '../../models/movie/movie_section.dart';
import '../details/details_page.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/collections/collections_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/rail_skeleton.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/home/continue_watching_slider.dart';
import '../../widgets/movie/movie_card.dart';
import '../../widgets/movie/movie_slider_section.dart';
import '../ai/wewatch_quiz_page.dart';
import '../calendar/tv_calendar_page.dart';
import '../../shell/app_shell_scope.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/updater/app_updater_service.dart';
import '../../widgets/updater/update_dialog.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../widgets/p2p/p2p_warning_dialog.dart';
import 'package:flutter/services.dart';
import '../../services/window/window_service.dart';
import '../../services/storage/app_image_cache.dart';

enum _HomeFilter { all, movies, series, anime }

/// The ten-foot top chrome, below `MediaQuery` top padding: one 28 dp control
/// row with 4 dp of breathing room above and below it.
///
/// The pointer bar carries a brand wordmark, and a 540 dp canvas cannot pay for
/// one. Stremio, measured on this same Chromecast with Google TV at the same
/// 1920x1080 / 320 density, starts its content at the top edge and gives its
/// filter row ~23 dp. Ours spent 58 dp on the wordmark band plus a second 44 dp
/// pill row under it, so the first pixel of content sat 118 dp down - 22% of the
/// visible height given to chrome. The wordmark is the whole of the 58 dp, so on
/// a television it goes and the tabs move up into its place.
const double _televisionAppBarHeight = 36;

/// The ten-foot filter row: compact inline tabs rather than a 44 dp control with
/// its own track, against the reference app's ~23 dp row.
///
/// **28 dp and not 24, and the number comes from a measurement.** The track
/// insets its segment by 3 dp top and bottom, and a 13 dp label's line box is
/// 19 dp tall, so a 24 dp track leaves 18 dp for 19 dp of text: the first build
/// of this reported `A RenderFlex overflowed by 1.00 pixels on the bottom` from
/// `segmented_tabs.dart` on the device canvas. 28 is 19 + 6 + 3 dp of slack, and
/// it is the compact end of the 24-28 dp the change was asked for.
const double _televisionTabHeight = 28;

/// A lazily fetched anime discovery row for the Anime home tab.
class _AnimeRow {
  final String title;
  final String subtitle;
  final List<AnimeMedia> items;

  const _AnimeRow({
    required this.title,
    required this.subtitle,
    required this.items,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _manager = AddonManager.instance;
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  final List<MovieSection> _sections = [];
  String? _error;

  List<Movie> _featuredMovies = [];
  _HomeFilter _selectedFilter = _HomeFilter.all;

  /// Anime discovery rows for the Anime tab, loaded on first use.
  final List<_AnimeRow> _animeRows = [];
  bool _animeLoading = false;
  bool _animeLoaded = false;

  /// Debounces [_refreshSimilarSections]: my-list / continue-watching /
  /// palette ticks fire on every change, and each refresh is 4 network
  /// fetches. Rapid ticks coalesce into one trailing refresh.
  Timer? _similarDebounce;
  bool _similarRefreshInFlight = false;

  /// Coalesces rapid 18+ switch flips into one trailing [_loadHome], mirroring
  /// [_similarDebounce] so a toggle never fans out into overlapping home loads.
  Timer? _adultReloadDebounce;
  Timer? _animeRefreshDebounce;

  /// The shell controller this page is subscribed to, if it is mounted inside
  /// the shell at all, plus the slot the last notification reported. Both are
  /// needed to spot a *return* to Home rather than any other switch.
  AppShellController? _shellController;
  ShellSlot? _lastSlot;

  List<MovieSection> get _visibleSections => _sections
      .map(_filterSection)
      .where((section) => section.movies.isNotEmpty)
      .toList();

  MovieSection _filterSection(MovieSection section, {_HomeFilter? filter}) {
    final activeFilter = filter ?? _selectedFilter;
    final movies = section.movies
        .where((movie) => _matchesFilter(movie, activeFilter))
        .toList();
    return MovieSection(
      title: section.title,
      subtitle: section.subtitle,
      contentType: section.contentType,
      addonBaseUrl: section.addonBaseUrl,
      catalog: section.catalog,
      movies: movies,
    );
  }

  /// [movies], [series] and [anime] partition [all]: every non-movie type —
  /// tv, anime, and whatever type a future addon invents — stays visible under
  /// Series, so no catalog entry can fall through both tabs. Anime is split out
  /// of Series so the dedicated tab can surface it the way the Anime page does.
  bool _matchesFilter(Movie movie, _HomeFilter filter) =>
      filter == _HomeFilter.all || _partitionOf(movie) == filter;

  /// Which partition a title belongs to: the one place the Movies / Series /
  /// Anime split is defined, so the filter and the tab counts cannot drift
  /// apart.
  _HomeFilter _partitionOf(Movie movie) {
    if (_isAnime(movie)) return _HomeFilter.anime;
    return movie.type.trim().toLowerCase() == 'movie'
        ? _HomeFilter.movies
        : _HomeFilter.series;
  }

  /// Mirrors the `anime` filter in [ContinueWatchingSlider] so both agree on
  /// what counts as anime.
  static bool _isAnime(Movie movie) {
    final id = movie.id;
    return movie.type.trim().toLowerCase() == 'anime' ||
        id.startsWith('anilist:') ||
        id.startsWith('arabic_anime:');
  }

  List<Movie> get _visibleFeaturedMovies => _pickFeatured(_visibleSections);

  void _setFilter(_HomeFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    if (filter == _HomeFilter.anime || filter == _HomeFilter.all) {
      _ensureAnimeRows();
    }
  }

  /// Pulls the same AniList rows the dedicated Anime page shows. Runs once per
  /// session, only when the Anime tab is opened, so regular home loads are
  /// untouched. A failed load leaves the tab empty and retries on next open.
  Future<void> _ensureAnimeRows() async {
    if (_animeLoaded || _animeLoading) return;
    setState(() => _animeLoading = true);

    final anilist = AnilistService.instance;
    try {
      final results = await Future.wait([
        anilist.fetchTrendingAnime(perPage: 18),
        anilist.fetchPopularThisSeason(perPage: 18),
        anilist.fetchTopRated(perPage: 18),
        anilist.fetchUpcomingNextSeason(perPage: 18),
        anilist.fetchByGenre('Action', perPage: 18),
        anilist.fetchByGenre('Romance', perPage: 18),
        anilist.fetchByGenre('Fantasy', perPage: 18),
        anilist.fetchByGenre('Sci-Fi', perPage: 18),
      ]);

      if (!mounted) return;
      final rows = <_AnimeRow>[
        _AnimeRow(
          title: '🔥 Trending Anime',
          subtitle: 'Top popular and trending series',
          items: results[0],
        ),
        _AnimeRow(
          title: '🌟 Popular This Season (${AnilistService.currentSeason()})',
          subtitle: 'Currently airing hits',
          items: results[1],
        ),
        _AnimeRow(
          title: '⭐ All-Time Masterpieces',
          subtitle: 'Critically acclaimed top rated anime',
          items: results[2],
        ),
        _AnimeRow(
          title: '🚀 Anticipated Next Season',
          subtitle: 'Upcoming anime you cannot miss',
          items: results[3],
        ),
        _AnimeRow(
          title: '⚔️ Action & Adventure',
          subtitle: 'High octane battles and epic journeys',
          items: results[4],
        ),
        _AnimeRow(
          title: '💖 Romance & Drama',
          subtitle: 'Heartfelt emotional stories',
          items: results[5],
        ),
        _AnimeRow(
          title: '🔮 Fantasy & Isekai',
          subtitle: 'Magical realms and alternate worlds',
          items: results[6],
        ),
        _AnimeRow(
          title: '🤖 Sci-Fi & Cyberpunk',
          subtitle: 'Futuristic technologies and dystopian worlds',
          items: results[7],
        ),
      ].where((row) => row.items.isNotEmpty).toList();

      setState(() {
        _animeRows
          ..clear()
          ..addAll(rows);
        _animeLoading = false;
        _animeLoaded = true;
      });
    } catch (e) {
      debugPrint('[HomePage] Anime rows failed: $e');
      if (!mounted) return;
      setState(() => _animeLoading = false);
    }
  }

  void _openAnimeDetails(AnimeMedia anime) {
    Navigator.push(
      context,
      CinematicSlideRoute(page: AnimeDetailsPage(anime: anime)),
    );
  }

  /// The anime rows and the catalog/recommendation caches were built under the
  /// old switch value, so invalidate the recommendation cache immediately.
  /// Rows themselves are kept visible (stale-while-refresh); only the affected
  /// rows are refreshed independently so the UI never goes blank.
  void _onAdultContentChanged() {
    if (!mounted) return;
    MetadataService.clearCatalogCache();
    HomePageSettings.clearRecommendationCache();
    _adultReloadDebounce?.cancel();
    _animeRefreshDebounce?.cancel();
    // Do NOT clear _animeRows here; keep stale rows visible. Instead, schedule a
    // per-row refresh so each anime row updates independently on the trailing debounce.
    _animeRefreshDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _ensureAnimeRows();
    });
  }

  /// Curated rails are local, so a toggle takes effect without a reload: the
  /// switch only adds or drops them from the rail list.
  void _onCollectionsChanged() {
    if (!mounted) return;
    _injectCuratedSections();
  }

  static bool _hasShownIntro = false;
  late bool _showIntro;


  /// Height the hero band actually took, reported by the carousel.
  ///
  /// Null until the first frame. The rails use it to size their cards against
  /// the space that is genuinely left rather than against a second, independent
  /// guess at where the hero ends - which is what had them 114 dp too tall on a
  /// television, with the overflow showing up as a chopped movie title.
  double? _heroBandHeight;

  @override
  void initState() {
    super.initState();
    _showIntro = !_hasShownIntro;
    _hasShownIntro = true;

    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    MyListService.items.addListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.addListener(_onSettingsChanged);
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);
    CollectionsService.showOnHome.addListener(_onCollectionsChanged);
    CollectionsService.collections.addListener(_onCollectionsChanged);

    if (_showIntro) {
      _playIntro();
    }

    _loadHome();
    if (!_showIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
    }
  }

  static bool _hasRunStartupDialogs = false;
  static bool _hasAutoCheckedUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState, where an inherited lookup is not yet
    // legal. The shell keeps one controller for its whole life, but a rebuild
    // that replaces the scope can hand over a new instance, so the listener is
    // swapped only when the instance actually differs.
    final controller = AppShellScope.of(context);
    if (identical(controller, _shellController)) return;
    _shellController?.current.removeListener(_onSlotChanged);
    _shellController = controller;
    _lastSlot = controller?.current.value;
    controller?.current.addListener(_onSlotChanged);
  }

  /// Addons are added and removed from Settings, so their catalogs are stale by
  /// the time the user comes back. The shell keeps every slot alive in an
  /// IndexedStack, so returning to Home rebuilds nothing on its own and this
  /// notification is the only cue that a reload is due.
  void _onSlotChanged() {
    final slot = _shellController?.current.value;
    final returnedHome = slot == ShellSlot.home && _lastSlot != ShellSlot.home;
    _lastSlot = slot;
    if (returnedHome && mounted) _loadHome();
  }

  /// Vertical space one content rail may use on Home, chrome above it excluded.
  ///
  /// The canvas, minus the app bar and filter row, minus the hero band the
  /// carousel reported it actually took, minus this row's own header and the gap
  /// above it.
  ///
  /// **A television rail is never squeezed. A pointer rail is never squeezed
  /// either - it is only ever too small because the window is small.**
  ///
  /// This used to be "whatever is left after the hero", and that is what produced
  /// both symptoms the user reported. First the title was chopped: a 326.5 dp
  /// rail had 212 dp and overflowed. Then, once the card honoured its budget, the
  /// poster shrank to 165 dp - a 37% cut - because the hero had taken 234 dp and
  /// the rail absorbed the difference. Correct arithmetic, wrong owner: a
  /// *filter* budget should not be able to resize a *card* that has no business
  /// being resized.
  ///
  /// The rule that works is the reference app's: one focal point per screen, and
  /// cards sized by the screen rather than squeezed by whatever is above them.
  ///
  /// So on a television the budget is "a full rail", and the hero is not
  /// subtracted at all. It is a *compact* band instead - 296 dp sized to what a
  /// slide actually contains, rather than 421 dp taken as a fraction of the
  /// canvas - and the page simply scrolls, because a 540 dp television showing a
  /// hero and a full row of posters is two screens' worth of content, not one
  /// screen's worth of compromise.
  ///
  /// A poster at its drawn size is the thing that makes a rail look like a rail,
  /// so it is the thing that gets protected. Only a rail that genuinely cannot
  /// fit beside the chrome is reduced, and never below a poster that still reads
  /// as one.
  double _railHeightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final chromeAbove = _isTelevision(context)
        ? _televisionAppBarHeight + ZplaySpacing.s8
        : _appBarHeight;

    // A full card, at the width this screen gives it.
    final natural = MovieCardSizing.fromWidth(size.width).totalHeight;
    if (_isTelevision(context)) {
      // Only a rail that genuinely cannot fit is reduced, and never below a
      // poster that still reads as one. Everything above this floor is the
      // screen's business, not the rail's.
      final ceiling = size.height - chromeAbove - 38 - ZplaySpacing.s12;
      return natural <= ceiling ? natural : ceiling;
    }

    // A pointer still budgets against what is left, because there the hero and
    // the rails genuinely stack and the window is usually tall enough for both.
    final hero = _heroBandHeight;
    final heroHeight = hero ?? size.height * 0.42;
    final remaining = size.height - chromeAbove - heroHeight - 38 - ZplaySpacing.s12;
    return remaining.clamp(120.0, double.infinity);
  }

  Future<void> _runStartupDialogs() async {
    if (_hasRunStartupDialogs || !mounted) return;
    _hasRunStartupDialogs = true;

    // 1. Check & show Update dialog first
    await _checkAutoUpdate();
    if (!mounted) return;

    // 2. Check & show P2P warning dialog after update dialog
    await _checkP2pWarning();
  }

  Future<void> _checkAutoUpdate() async {
    if (_hasAutoCheckedUpdate) return;
    _hasAutoCheckedUpdate = true;
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo != null && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      debugPrint('[HomePage] Auto update check failed: $e');
    }
  }

  Future<void> _checkP2pWarning() async {
    try {
      final shouldShow = await P2pSettingsService.shouldShowWarning();
      if (shouldShow && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => const P2pWarningDialog(),
        );
      }
    } catch (e) {
      debugPrint('[HomePage] P2P warning check failed: $e');
    }
  }

  @override
  void dispose() {
    _similarDebounce?.cancel();
    _adultReloadDebounce?.cancel();
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    MyListService.items.removeListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.removeListener(_onSettingsChanged);
    ContentSettings.adultEnabled.removeListener(_onAdultContentChanged);
    CollectionsService.showOnHome.removeListener(_onCollectionsChanged);
    CollectionsService.collections.removeListener(_onCollectionsChanged);
    _shellController?.current.removeListener(_onSlotChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // Coalesce rapid my-list / continue-watching / palette ticks into one
    // trailing refresh; the immediate setState below keeps visuals instant.
    _similarDebounce?.cancel();
    _similarDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _similarRefreshInFlight) return;
      _refreshSimilarSections();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _injectSimilarSections({
    MovieSection? listSection,
    MovieSection? watchingSection,
    MovieSection? traktSection,
    MovieSection? simklSection,
  }) {
    if (!mounted) return;
    setState(() {
      _sections.removeWhere(
        (s) =>
            s.title.toLowerCase().startsWith('because you') ||
            s.catalog.id == 'bestsimilar' ||
            s.catalog.id == 'bestsimilar_list' ||
            s.catalog.id == 'bestsimilar_watching' ||
            s.catalog.id == 'trakt_recommendations' ||
            s.catalog.id == 'simkl_recommendations',
      );

      final toInsert = <MovieSection>[];
      if (watchingSection != null) toInsert.add(watchingSection);
      if (listSection != null) toInsert.add(listSection);
      if (traktSection != null) toInsert.add(traktSection);
      if (simklSection != null) toInsert.add(simklSection);

      if (toInsert.isEmpty) return;

      switch (HomePageSettings.similarPosition.value) {
        case SimilarSectionPosition.top:
          _sections.insertAll(0, toInsert);
          break;
        case SimilarSectionPosition.underCinemeta:
          final insertIdx = _sections.length > 1 ? 1 : _sections.length;
          _sections.insertAll(insertIdx, toInsert);
          break;
        case SimilarSectionPosition.middle:
          final insertIdx = _sections.length ~/ 2;
          _sections.insertAll(insertIdx, toInsert);
          break;
        case SimilarSectionPosition.bottom:
          _sections.addAll(toInsert);
          break;
      }
    });
  }

  /// Appends the curated rails after every addon rail.
  ///
  /// Pinned to the tail on purpose: [_pickFeatured] builds the hero from the
  /// leading sections, so a curated rail at the head would change which titles
  /// the page spotlights. The removeWhere guard keeps a reload, a toggle, or a
  /// ranked-lists swap from stacking duplicate copies. With a TMDb key
  /// configured these rails carry ranked lists instead of the bundled picks.
  void _injectCuratedSections() {
    if (!mounted) return;
    setState(() {
      _sections.removeWhere((s) => s.catalog.id.startsWith('curated_'));
      if (!CollectionsService.showOnHome.value) return;
      _sections.addAll(CollectionsService.homeSections());
    });
  }

  Future<void> _refreshSimilarSections() async {
    if (_similarRefreshInFlight) return;
    _similarRefreshInFlight = true;
    try {
      final listFuture = HomePageSettings.fetchBestSimilarSection(
        forceRefresh: true,
      );
      final watchingFuture =
          HomePageSettings.fetchContinueWatchingSimilarSection(
            forceRefresh: true,
          );
      final traktFuture = HomePageSettings.fetchTraktRecommendationsSection(
        forceRefresh: true,
      );
      final simklFuture = HomePageSettings.fetchSimklRecommendationsSection(
        forceRefresh: true,
      );

      final results = await Future.wait([
        listFuture,
        watchingFuture,
        traktFuture,
        simklFuture,
      ]);
      _injectSimilarSections(
        listSection: results[0],
        watchingSection: results[1],
        traktSection: results[2],
        simklSection: results[3],
      );
    } finally {
      _similarRefreshInFlight = false;
    }
  }

  Future<void> _playIntro() async {
    // Show intro for 1.8 seconds so it feels fast and allows full shader pre-warming
    await Future.delayed(const Duration(milliseconds: 1800));

    // If still loading critical data, wait a bit longer (up to a timeout or until ready)
    while (_loading && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (mounted) {
      setState(() => _showIntro = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
    }
  }

  Future<void> _loadHome() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _sections.clear();
      _featuredMovies.clear();
    });

    try {
      final listFuture = HomePageSettings.fetchBestSimilarSection();
      final watchingFuture =
          HomePageSettings.fetchContinueWatchingSimilarSection();
      final traktFuture = HomePageSettings.fetchTraktRecommendationsSection();
      final simklFuture = HomePageSettings.fetchSimklRecommendationsSection();

      await for (final section in _manager.streamHomeSections()) {
        if (!mounted) return;

        setState(() {
          _sections.add(section);

          // Re-pick featured movies with the new section.
          _featuredMovies = _pickFeatured(_sections);

          // Stop full-page loading as soon as we have enough to show the hero.
          if (_loading && _featuredMovies.isNotEmpty) {
            _loading = false;
          }
        });
      }

      // Inject recommendation sections (List, Continue Watching, Trakt, Simkl)
      final results = await Future.wait([
        listFuture,
        watchingFuture,
        traktFuture,
        simklFuture,
      ]);
      if (mounted) {
        _injectSimilarSections(
          listSection: results[0],
          watchingSection: results[1],
          traktSection: results[2],
          simklSection: results[3],
        );
      }

      // Curated collections trail the addon rails; appended, never prepended.
      _injectCuratedSections();

      // If we got through the whole stream and still loading (e.g., no addons worked)
      if (mounted && _loading) {
        setState(() => _loading = false);
      }

      // Anime discovery rows are part of All, but they are fetched in the
      // background so they never delay the usual home content.
      if (mounted && _selectedFilter == _HomeFilter.all) {
        unawaited(_ensureAnimeRows());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Picks a handful of varied movies to rotate through in the hero —
  /// one from each of the first few sections so it isn't just a wall of
  /// the same catalog, deduped by id+type.
  List<Movie> _pickFeatured(List<MovieSection> sections) {
    final featured = <Movie>[];
    final seen = <String>{};

    for (final section in sections) {
      for (final movie in section.movies.take(3)) {
        final key = '${movie.type}:${movie.id}';
        if (seen.add(key)) {
          featured.add(movie);
          break;
        }
      }
      if (featured.length >= 6) break;
    }

    // Fallback: if sections were too sparse to get variety, top up from
    // the first section's list.
    if (featured.length < 2 && sections.isNotEmpty) {
      for (final movie in sections.first.movies) {
        final key = '${movie.type}:${movie.id}';
        if (seen.add(key)) featured.add(movie);
        if (featured.length >= 6) break;
      }
    }

    return featured;
  }

  /// Height of the app bar below `MediaQuery` top padding
  /// (8 top pad + 34 logo + 16 bottom pad).
  static const double _appBarHeight = 58;

  /// True only on a television. Read in one place so the height, the tab row and
  /// the bar's own furniture cannot disagree about which layout they are in.
  static bool _isTelevision(BuildContext context) =>
      FormFactorService.of(context) == FormFactor.television;

  /// The app bar's own height above the inset, per form factor.
  static double _appBarHeightFor(BuildContext context) =>
      _isTelevision(context) ? _televisionAppBarHeight : _appBarHeight;

  /// Width at which the filter tabs move into the app bar; below it they sit
  /// inline above the hero at full width, where the bar has no room to spare.
  ///
  /// Measured against the bar's own furniture rather than guessed: the logo is
  /// ~90px, the divider 17, and six icon buttons ~288, so the control needs
  /// ~400px plus its own ~330 natural width. At 700 the bar handed it about
  /// 250, so the labels truncated to "Mo…", "Seri…", "Ani…".
  static const double _appBarFilterBreakpoint = 1000;

  /// Whether the tabs live in the bar rather than in a row of their own.
  ///
  /// **A television always carries them in the bar.** The 400px of furniture the
  /// breakpoint is dodging is the wordmark, and the wordmark is exactly what the
  /// ten-foot bar no longer has - so the row that could not fit the tabs is the
  /// row that does not exist there, and the tabs stop paying for a second 44 dp
  /// row underneath it.
  static bool _filtersInAppBar(BuildContext context) =>
      _isTelevision(context) ||
      MediaQuery.sizeOf(context).width >= _appBarFilterBreakpoint;

  /// Labels only, no counts.
  ///
  /// The tabs used to carry a count of the catalogue titles each filter
  /// matches, and those numbers described the *catalogue* while the tabs
  /// describe what is actually on screen. The Anime tab additionally surfaces
  /// AniList discovery rows fetched separately on first open, so its count sat
  /// at 0 next to a screenful of tiles. A number that contradicts the content
  /// beside it is worse than no number, and naming the filter is the tab's job.
  Widget _buildFilterTabs(BuildContext context) {
    return SegmentedTabs<_HomeFilter>(
      // The one number that changes with the form factor: the track's own
      // paddings are proportional, so 24 dp renders the same control, compact.
      height: _isTelevision(context) ? _televisionTabHeight : 44,
      semanticsLabel: 'Home content filter',
      selected: _selectedFilter,
      onSelected: _setFilter,
      options: [
        for (final (filter, label) in _homeFilterLabels)
          SegmentedTabOption(value: filter, label: label),
      ],
    );
  }

  /// ListView slot 0: spacing when the tabs moved into the app bar, the tabs
  /// themselves otherwise.
  Widget _buildFilterSlot(BuildContext context, double topPadding) {
    if (_filtersInAppBar(context)) {
      return SizedBox(
        height: topPadding + _appBarHeightFor(context) + ZplaySpacing.s8,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        topPadding + _appBarHeight + ZplaySpacing.s12,
        ZplaySpacing.s20,
        ZplaySpacing.s4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildFilterTabs(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final tokens = context.tokens;
    final visibleSections = _visibleSections;

    final isAnimeTab = _selectedFilter == _HomeFilter.anime;
    final isAllTab = _selectedFilter == _HomeFilter.all;
    // The Anime tab leads with anime rows; All appends them so its usual
    // order stays put. Movies/Series never show them.
    final animeRows = (isAnimeTab || isAllTab)
        ? _animeRows
        : const <_AnimeRow>[];
    final featured = _visibleFeaturedMovies;
    final hasContent =
        visibleSections.isNotEmpty || animeRows.isNotEmpty || _animeLoading;

    final animeRowWidgets = <Widget>[
      for (final row in animeRows)
        AnimeSliderSection(
          title: row.title,
          subtitle: row.subtitle,
          animeList: row.items,
          onAnimeTap: _openAnimeDetails,
        ),
    ];

    // Whether this page is being drawn for a television. The hero is a band on a
    // pointer and an overlay here, and the rail budget in `_railHeightFor`
    // branches on the same answer - the two have to agree or the layout and its
    // arithmetic drift apart, which is how the posters came to be 37% smaller
    // than the design intended.
    final television = _isTelevision(context);

    final slots = <Widget>[
      _buildFilterSlot(context, topPadding),
      if (!HomePageSettings.enableSpotlight.value)
        SizedBox(height: topPadding + 76)
      else if (isAnimeTab && featured.isEmpty)
        // Nothing to feature yet on the Anime tab: let the rows below start
        // right under the app bar instead of reserving an empty hero band.
        const SizedBox.shrink()
      else if (television)
        // **On a television the spotlight is a compact hero, not a 234 dp band.**
        //
        // It used to take 234 dp of a 540 dp screen - 43% - and everything below
        // it was squeezed into the remainder, which is why the rails came out at
        // 165 dp posters after the card fix: a 37% cut that read as "forcibly
        // shrunk" rather than as a design decision.
        //
        // The band is now sized by what a hero actually needs to show a title and
        // its actions - not by a fraction of the canvas - and the rails beneath
        // are given their full natural height regardless. A film is a film
        // because of its poster; a featured title is still recognisable at a
        // third of that height.
        //
        // The carousel is still here and still focusable, so the remote reaches
        // the same Watch button it always did.
        _HeroCarousel(
          movies: featured,
          compact: true,
          onHeightChanged: (height) {
            if (mounted && height != _heroBandHeight) {
              setState(() => _heroBandHeight = height);
            }
          },
        )
      else
        _HeroCarousel(
          movies: featured,
          onHeightChanged: (height) {
            if (mounted && height != _heroBandHeight) {
              setState(() => _heroBandHeight = height);
            }
          },
        ),
      // All keeps unfiltered recents so the row really is everything watched;
      // Movies/Series drop anime recents, the Anime tab keeps only those.
      ContinueWatchingSlider(
        typeFilter: switch (_selectedFilter) {
          _HomeFilter.anime => 'anime',
          _HomeFilter.all => null,
          _ => 'main',
        },
        title: 'Continue Watching',
      ),
      if (isAnimeTab && _animeLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: ZplaySpacing.s32),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (isAnimeTab) ...animeRowWidgets,
      if (!hasContent)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZplaySpacing.s24,
            ZplaySpacing.s32,
            ZplaySpacing.s24,
            ZplaySpacing.s48,
          ),
          child: Center(
            child: Text(
              isAnimeTab
                  ? 'No anime available right now.'
                  : _loading
                  // Saying "no titles match this filter" while the addons
                  // are still answering is a lie the user can see through:
                  // the same tab fills in seconds later. Naming the wait
                  // tells them to leave it alone.
                  ? 'Loading your library...'
                  : 'No titles match this filter. Try another tab, or pull down to refresh.',
              style: ZplayType.body.toStyle(color: context.tokens.textEmphasis),
            ),
          ),
        ),
      for (var i = 0; i < visibleSections.length; i++)
        ValueListenableBuilder<bool>(
          valueListenable: HomePageSettings.enableCalendar,
          builder: (context, calEnabled, _) {
            return MovieSliderSection(
              section: visibleSections[i],
              showCalendarButton:
                  calEnabled && i >= (visibleSections.length - 2),
              showSeeAll: !visibleSections[i].catalog.id.startsWith('curated_'),
              // What is left below the hero, minus this row's own header. The
              // hero already reserves a peek at a rail; this is the rest of the
              // truth, and without it the card is sized to its natural 326.5 dp
              // and runs 114 dp off the bottom of a 540 dp screen - which is
              // where the chopped-off movie title came from.
              maxHeight: _railHeightFor(context),
            );
          },
        ),
      // All is a superset: anime discovery content trails the usual rows.
      if (!isAnimeTab) ...animeRowWidgets,
      // The shell reserves its own chrome's space, so the old 110px dock
      // clearance collapses to one gap; a phone still has a gesture bar, so the
      // safe-area term stays.
      SizedBox(height: ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom),
    ];

    final backgroundContent = AnimatedAmbientBackground(
      child: Stack(
        children: [
          // ── Main scrollable content ──
          // The skeleton tracks the *unfiltered* load, not the visible
          // sections.
          //
          // It used to be `_sections.isEmpty`, which is false the moment any
          // section arrives - even if the Movies filter has just removed every
          // one of them. Switching to Movies during the first load therefore
          // showed neither skeleton nor content: a blank page, which on a
          // television reads as a dead app. Filtering an empty list is still an
          // empty list, so the skeleton is the honest thing to show.
          if (_loading && !_showIntro && _sections.isEmpty)
            _HomeSkeleton(
              topInset:
                  topPadding + _appBarHeightFor(context) + ZplaySpacing.s8,
            )
          else if (_error != null && _sections.isEmpty)
            ErrorView(error: _error, onRetry: _loadHome)
          else
            RefreshIndicator(
              color: tokens.accent,
              backgroundColor: tokens.surface,
              onRefresh: _loadHome,
              child: ListView.builder(
                controller: _scrollController,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: slots.length,
                itemBuilder: (context, index) => slots[index],
              ),
            ),

          // ── Television hero ──
          //
          // **Deliberately absent.**
          //
          // The obvious way to stop the hero stealing the rail's height is to
          // draw it *over* the first rail. That was tried and it is wrong: a
          // 260 dp artwork band over a 260 dp poster row is two focal points at
          // the same size, and the artwork washes out the posters underneath it.
          // That is the opposite of the one-focal-point rule the whole change is
          // built on - it just moves the fight from the layout to the paint.
          //
          // So on a television the featured title is a *row*, not a band. The
          // spotlight carousel still exists and is still reachable - it is the
          // first thing in the scroll, in its own compact form - and the rails
          // below it get their full 260 dp poster because nothing is displacing
          // them.
        ],
      ),
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Focus(
        // Deliberately NOT autofocused. This node wraps the whole page body, so
        // its rect covers every focusable child, and directional (D-pad)
        // traversal looks for candidates outside the focused node's rectangle -
        // from here it finds none in any direction, so no card could ever be
        // reached. Focus starts on the hero CTA instead, which sits inside the
        // content. Key handling is unaffected: events from a focused descendant
        // still bubble up to this handler.
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus != null && primaryFocus.context != null) {
              final focusedWidget = primaryFocus.context!.widget;
              if (focusedWidget is EditableText) {
                return KeyEventResult.ignored;
              }
            }
            // Toggling lives in the shell now (F11 and the rail row), so it
            // works from every slot rather than only from this page. Escape
            // stays here: leaving fullscreen is a per-screen reflex.
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (WindowService.instance.isDesktop &&
                  WindowService.instance.isFullscreen) {
                WindowService.instance.exitFullscreen();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: _buildBody(backgroundContent, topPadding, context),
      ),
    );
  }

  /// Uses the same shader-free composition on every platform. This avoids
  /// capturing the scrolling page and keeps Skia and Impeller visually equal.
  Widget _buildBody(
    Widget backgroundContent,
    double topPadding,
    BuildContext context,
  ) {
    final overlayChildren = <Widget>[
      // ── Floating glass app bar ──
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _GlassAppBar(
          topPadding: topPadding,
          filterTabs: _filtersInAppBar(context)
              ? _buildFilterTabs(context)
              : null,
        ),
      ),

      // ── Custom Scroll Track ──
      if (MediaQuery.sizeOf(context).width > 800) // Desktop only
        Positioned(
          right: 24,
          bottom: 40,
          child: CustomScrollTrack(controller: _scrollController),
        ),

      // ── Intro Splash Screen ──
      Positioned.fill(child: _buildIntroOverlay(context)),
    ];

    return ValueListenableBuilder<bool>(
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

        return Container(
          color: context.tokens.bg,
          child: Stack(
            children: [
              RepaintBoundary(child: backgroundContent),
              ...overlayChildren,
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntroOverlay(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final titleSize = (screenWidth * 0.08).clamp(40.0, 56.0);
    final subtitleSize = (screenWidth * 0.03).clamp(16.0, 20.0);
    final iconSize = (screenWidth * 0.12).clamp(48.0, 72.0);

    return IgnorePointer(
      ignoring: !_showIntro,
      child: AnimatedOpacity(
        opacity: _showIntro ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        child: Container(
          color: context.tokens.bg,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon_small.png',
                  width: iconSize * 1.5,
                  height: iconSize * 1.5,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: ZplaySpacing.s32),
                Text(
                  'ZPlay',
                  textAlign: TextAlign.center,
                  style: ZplayType.display
                      .copyWith(size: titleSize)
                      .toStyle(color: context.tokens.textPrimary),
                ),
                const SizedBox(height: ZplaySpacing.s8),
                Text(
                  'Your Cinema Universe',
                  textAlign: TextAlign.center,
                  style: ZplayType.overline
                      .copyWith(size: subtitleSize, letterSpacing: 2)
                      .toStyle(color: context.tokens.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content filter — All / Movies / Series / Anime.
//
// One segmented control (the shared [SegmentedTabs]) rather than four
// independent text tabs. Those were ~26px tall with an 18px accent underline of
// their own that grew out of nothing, so nothing connected one tab to the next
// and a remote had little to aim at. The control now carries one sliding
// selection indicator, a focus ring that is distinct from the accent fill, and
// 44px targets.
// ─────────────────────────────────────────────────────────────────────────────

const _homeFilterLabels = <(_HomeFilter, String)>[
  (_HomeFilter.all, 'All'),
  (_HomeFilter.movies, 'Movies'),
  (_HomeFilter.series, 'Series'),
  (_HomeFilter.anime, 'Anime'),
];

/// What Home looks like while its first load is in flight.
///
/// This used to be a single spinner centred on an otherwise empty screen —
/// which, on a TV, is the entire interface for the first few seconds. The shapes
/// below are the page's real ones: the hero band, then rails at the geometry the
/// cards will actually arrive at, so nothing moves when they land.
class _HomeSkeleton extends StatelessWidget {
  final double topInset;

  const _HomeSkeleton({required this.topInset});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topInset + ZplaySpacing.s8),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZplaySpacing.s20,
              0,
              ZplaySpacing.s20,
              ZplaySpacing.s24,
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                ),
              ),
            ),
          ),
          RailSkeleton(sizing: sizing, showHeader: true),
          const SizedBox(height: ZplaySpacing.s24),
          RailSkeleton(sizing: sizing, showHeader: true, count: 5),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted Glass App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _GlassAppBar extends StatelessWidget {
  final double topPadding;
  final Widget? filterTabs;

  const _GlassAppBar({required this.topPadding, this.filterTabs});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The ten-foot bar is a different bar, not a shorter one: no wordmark, a
    // single control row, and a size for the icon buttons that does not set the
    // chrome's height by itself. Everything it shares with the pointer bar -
    // fill, hairline, the tabs, the button behaviour - is unchanged.
    final television = FormFactorService.of(context) == FormFactor.television;
    // The compact button box: a 48 dp Material default would be the tallest
    // thing in a 28 dp row and would undo the height this change exists to
    // remove. 18 px of glyph inside 28 dp keeps the row's own rhythm.
    //
    // `constraints` alone does not do it: Material 3 turns it into the style's
    // min/max size, and `MaterialTapTargetSize.padded` then grows the box back
    // to 48 dp around it. Measured on the device canvas - the buttons rendered
    // 48x48 and set the row's height themselves - so the style states the size
    // and the tap target policy both.
    final ButtonStyle? televisionButton = television
        ? IconButton.styleFrom(
            minimumSize: const Size(32, _televisionTabHeight),
            maximumSize: const Size(32, _televisionTabHeight),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        : null;
    return RepaintBoundary(
      child: Container(
        padding: television
            ? EdgeInsets.only(
                // 4 + the 28 dp control row + 4 keeps
                // `_televisionAppBarHeight` (36) exact.
                top: topPadding + ZplaySpacing.s4,
                bottom: ZplaySpacing.s4,
                left: ZplaySpacing.s20,
                right: ZplaySpacing.s8,
              )
            : EdgeInsets.only(
                // 8 + the 34px logo + 16 keeps `_appBarHeight` (58) exact.
                top: topPadding + ZplaySpacing.s8,
                bottom: ZplaySpacing.s16,
                left: ZplaySpacing.s20,
                right: ZplaySpacing.s8,
              ),
        decoration: BoxDecoration(
          // Opaque, where this was a 90-96% `#080A0F` gradient. Nothing blurs
          // behind this bar: it has no lens wrapper, and the glass gate
          // (`GlassSettings.enabled`) defaults false, so a translucent fill only
          // let the hero smear through underneath and left the bar's own text on
          // a moving background. Content now passes behind a solid bar.
          //
          // `tokens.bg` over the literal also fixes a palette mismatch: `#080A0F`
          // is only the ocean palette's background, so the bar stayed ocean-black
          // under all eleven other palettes.
          color: tokens.bg,
          border: Border(bottom: tokens.hairline),
        ),
        child: Row(
          children: [
            // Logo and wordmark: pointer devices only. They are the entire
            // reason the pointer bar is 58 dp, and a 540 dp canvas that shows
            // 22% of itself as chrome cannot buy a name the rail's selected row
            // and the page's own title already give.
            if (!television) ...[
              Image.asset(
                'assets/icon_small.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Text(
                'ZPlay',
                style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
              ),
              const Spacer(),
            ],
            // All / Movies / Series tabs (wide layouts only, and always on a
            // television, where the wordmark that used to crowd them is gone).
            if (filterTabs != null) ...[
              // Intrinsic width, deliberately — NOT Flexible. A Flexible here
              // also takes flex 1, exactly like the Spacer above it, so the two
              // split the free space; the tabs then use only their natural width
              // and strand the remainder *after* themselves, pushing the tabs,
              // divider and icon buttons 384px short of the right edge at 2042px
              // wide. Measured, not guessed. Right-alignment is safe because the
              // tabs only enter the bar above _appBarFilterBreakpoint, where the
              // bar has room for them and the control's own width clamp applies.
              filterTabs!,
              // On a television the tabs lead the row, because the wordmark that
              // used to hold the left end is gone: the free space moves between
              // the tabs and the buttons rather than in front of both.
              if (television) const Spacer(),
              // A television's divider is glyph-height, not the 18 of a bar with
              // a 34 px logo beside it.
              Container(
                width: 1,
                height: television ? ZplaySpacing.s16 : 18,
                margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                color: tokens.borderStrong,
              ),
            ],
            // AI Taste Profile Quiz
            ValueListenableBuilder<bool>(
              valueListenable: HomePageSettings.enableAiQuiz,
              builder: (context, aiQuizEnabled, _) {
                if (!aiQuizEnabled) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    color: tokens.accent,
                    size: television ? 18 : 22,
                  ),
                  tooltip: 'AI Taste Quiz',
                  style: televisionButton,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeWatchQuizPage(),
                      ),
                    );
                  },
                );
              },
            ),
            // TV Shows Airing Calendar
            ValueListenableBuilder<bool>(
              valueListenable: HomePageSettings.enableCalendar,
              builder: (context, calEnabled, _) {
                if (!calEnabled) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(
                    Icons.calendar_month_rounded,
                    color: tokens.textEmphasis,
                    size: television ? 18 : 22,
                  ),
                  tooltip: 'TV Airing Calendar',
                  style: televisionButton,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TvCalendarPage()),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Carousel — rotates through a handful of featured titles.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  final List<Movie> movies;

  /// Reports the band height the carousel actually took.
  ///
  /// The page needs this because the hero and the first rail below it are one
  /// vertical budget, and the two used to compute it separately: the hero
  /// reserved "a peek at a rail" while the rail sized itself from width alone,
  /// so the card ended up taller than the space the hero had agreed to leave.
  /// One number, produced once by whoever owns the layout, ends the argument.
  final ValueChanged<double>? onHeightChanged;

  /// Draw the band at the height its content needs rather than a fraction of the
  /// canvas. Set on a television, where a 540 dp screen cannot afford a hero that
  /// is 43% of it and a usable row of posters at the same time.
  final bool compact;

  const _HeroCarousel({
    required this.movies,
    this.onHeightChanged,
    this.compact = false,
  });

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final PageController _pageController = PageController();
  final Map<String, MovieDetail?> _detailsCache = {};

  Timer? _timer;
  int _index = 0;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    if (widget.movies.isNotEmpty) {
      _fetchDetail(widget.movies.first);
      if (widget.movies.length > 1) _fetchDetail(widget.movies[1]);
    }
    _startTimer();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movies != widget.movies) {
      _index = 0;
      _detailsCache.clear();
      if (widget.movies.isNotEmpty) _fetchDetail(widget.movies.first);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _startTimer();
    }
  }

  @override
  void dispose() {
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  int get _totalSlideCount => widget.movies.length;

  void _startTimer() {
    _timer?.cancel();
    if (!HomePageSettings.heroAutoRotate.value) return;
    if (_totalSlideCount < 2) return;
    final interval = Duration(
      seconds: HomePageSettings.heroRotateSeconds.value,
    );
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % _totalSlideCount;
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

  Future<void> _fetchDetail(Movie movie) async {
    if (_detailsCache.containsKey(movie.id)) return;
    _detailsCache[movie.id] = null; // marks as "loading" so we don't refetch
    try {
      final detail = await MetadataService.fetchMeta(
        baseUrl: movie.addonBaseUrl,
        type: movie.type,
        imdbId: movie.id,
      );
      if (mounted) {
        setState(() => _detailsCache[movie.id] = detail);
      }
    } catch (_) {
      // Not critical — falls back to basic Movie data / title text.
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (index < widget.movies.length) {
      _fetchDetail(widget.movies[index]);
    }
    final nextSlide = (index + 1) % _totalSlideCount;
    if (nextSlide < widget.movies.length) {
      _fetchDetail(widget.movies[nextSlide]);
    }
  }

  /// Vertical space below the hero that the first content rail needs in order to
  /// read as a rail rather than as a suggestion to scroll.
  ///
  /// This is a *peek*, not the whole rail. Reserving the full `MovieCardSizing`
  /// row would be defensible arithmetic and terrible design: on a 540 dp
  /// television the rail is 326.5 dp, so reserving all of it alongside 44 dp of
  /// chrome leaves 119 dp for the hero, and the page that is supposed to fix
  /// "the hero is everything" becomes a 93 dp letterbox with a full row of
  /// titles under it. What the user needs to see is that there is a rail - its
  /// header and the top of the first row of posters - so that is what is
  /// reserved.
  ///
  /// A peek is also what the layouts it replaces already did by eye: Home's
  /// section headers and the settings pages all let a rail run off the bottom
  /// edge, which is what makes a long page look long rather than truncated.
  /// Mirrors `MovieSliderSection`: a `SectionHeader` (titleLarge's line box plus
  /// the header's own top padding), 12 dp of gap, and enough of the poster row
  /// to show that it is a row of posters.
  double _firstRailReserve(double screenWidth) =>
      38 + ZplaySpacing.s12 + MovieCardSizing.fromWidth(screenWidth).posterHeight * 0.45;

  /// The shortest band that still holds the part of a hero slide that is never
  /// dropped: the metadata row, a two-line 46 px title, the 16 dp above it, the
  /// 16 dp before the buttons, the 56 dp buttons, and the 48 dp bottom inset.
  ///
  /// Measured from `_HeroSlide` rather than guessed. The first version of the
  /// chrome-aware hero used 228 dp for the whole column, but that column is
  /// bottom-aligned: a band shorter than its content pushes the title off the
  /// top rather than clipping the bottom, so 228 dp shipped a hero with the
  /// poster's name cut in half. The slide now drops the synopsis and the genre
  /// chips to fit a smaller band (see `_synopsisBudget`), so this is the floor
  /// for the content that stays.
  static const double _heroContentMinimum = 234;

  /// Height of a compact band, for a screen too short to spend 43% of itself on
  /// a hero.
  ///
  /// Measured from `_HeroSlide` rather than chosen: the metadata row, a
  /// two-line 46 px title, a one-line synopsis, the genre chips, the 56 dp
  /// buttons and the 48 dp bottom inset. The full-size band asked for 421 dp on
  /// the same 540 dp screen, which is what left the rails below with 165 dp
  /// posters instead of 260.
  static const double _heroCompactHeight = 296;

  /// Height of the hero band.
  ///
  /// Every branch is a fraction of the space the band actually has, not of the
  /// window. That distinction is the whole fix: the fractions used to be taken
  /// of the full canvas while the app bar and filter tabs were stacked on top of
  /// the result, and the floors were never checked against the space they were
  /// dividing. A hero may be small, but it may not be the only thing on screen.
  double _heroHeight(double screenWidth, double screenHeight) {
    final style = HomePageSettings.heroStyle.value;
    // The band sits below the app bar and the filter tabs, so "the whole
    // screen" is not available to it - which is what this comment claimed while
    // the code measured against the whole screen anyway.
    //
    // Budgeting against the full canvas is what pushed the first rail off a
    // television. On the 960x540 set the ceiling bound at 421.2 dp (0.78 of
    // 540), and with 44 dp of app bar and filter row above it that put the top
    // of the first rail at 503 dp - leaving 74.8 dp of a 326.5 dp rail visible.
    // The comment said this left "a slice for the first rail"; it left a fifth
    // of one, so Home opened on a hero with a row of titles sliced off beneath
    // it. The hero is the best thing on the page, but a page is not a poster.
    //
    // The ceiling is therefore taken against the space the band actually has,
    // after the chrome above it and a rail's worth of the space below, and the
    // fraction then picks inside that. The floor is min'd against the ceiling
    // *before* the clamp, because `double.clamp` throws when its lower bound
    // exceeds its upper one - and on a 540 dp television the 520 dp floor still
    // sits above the ceiling. Order matters.
    // The carousel floats inside the page, so it asks the page's own chrome rule
    // rather than repeating it: a television's bar is 36 dp and carries the
    // filter pills, a pointer's is 58 dp and the pills sit in a row of their own
    // below it.
    final chromeAbove = _HomePageState._isTelevision(context)
        ? _televisionAppBarHeight + ZplaySpacing.s8
        : _HomePageState._appBarHeight;
    final available = screenHeight - chromeAbove - _firstRailReserve(screenWidth);
    if (available <= 0) return screenHeight * 0.5;
    // The slide's own content sets a minimum, and it is a *lower* bound rather
    // than a preference: the text column is bottom-aligned inside a 48 dp inset,
    // so a band shorter than the title, synopsis, chips and two buttons stacks
    // them upward past the top of the band and the poster's name is cut in half.
    // The first pass of this fix had no such bound and shipped exactly that,
    // trading a rail below the fold for a broken title inside the hero.
    //
    // So the fraction is applied to the available space and then raised to the
    // content minimum if it lands below it. Raising past the fraction is safe
    // here: the ceiling still applies afterwards, and a window too short to
    // hold both the content and the rail is a window that has to scroll.
    const contentMinimum = _heroContentMinimum;
    final ceiling = (available * 0.78).clamp(220.0, screenHeight);

    double pick(double fraction, double floor) {
      // The style floor is the lower bound, and the ceiling is the ceiling. The
      // content minimum is a *hard* one that can override the fraction without
      // ever exceeding the ceiling - which is what keeps a short window from
      // asking for a band bigger than itself, since `double.clamp` throws when
      // its lower bound is above its upper one.
      final lowBound = floor > ceiling ? ceiling : floor;
      final styled = (available * fraction).clamp(lowBound, ceiling);
      final floorWithinWindow = contentMinimum > screenHeight ? screenHeight : contentMinimum;
      return styled < floorWithinWindow ? floorWithinWindow : styled;
    }

    if (style == HeroStyle.compact) {
      if (screenWidth < 600) return pick(0.50, 260.0);
      if (screenWidth < 1100) return pick(0.44, 300.0);
      return pick(0.42, 340.0);
    }
    if (style == HeroStyle.minimalist) {
      if (screenWidth < 600) return pick(0.30, 180.0);
      if (screenWidth < 1100) return pick(0.28, 200.0);
      return pick(0.26, 220.0);
    }
    // Immersive, the default.
    if (screenWidth < 600) return pick(0.68, 460.0);
    if (screenWidth < 1100) return pick(0.62, 520.0);
    return pick(0.70, 620.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // A compact band is sized by what it has to show, not by a fraction of the
    // canvas. 296 dp holds the metadata row, a two-line title, a one-line
    // synopsis, the chips and the two buttons inside the 48 dp bottom inset -
    // measured from the widgets - and it is a third less than the 421 dp this
    // used to ask for on the same screen.
    final heroHeight = widget.compact
        ? _heroCompactHeight
        : _heroHeight(screenWidth, screenHeight);
    final tokens = context.tokens;
    final totalSlides = _totalSlideCount;
    // Reported from the same number the layout uses, in both the empty and the
    // populated case. A post-frame callback rather than a call in build, because
    // the listener is the parent's `setState` and calling it during a build
    // would rebuild this widget while it is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeightChanged?.call(heroHeight);
    });

    if (totalSlides == 0) {
      return SizedBox(height: heroHeight);
    }

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
              itemCount: totalSlides,
              onPageChanged: _onPageChanged,
              // A `PageView` claims the vertical drag by default, and a vertical
              // drag inside it never reaches the `ListView` that owns the page.
              // On a television that is fatal rather than awkward: there is no
              // pointer, so the only ways to scroll Home are a drag and a wheel,
              // and both are read here as page changes. The user scrolls down,
              // the page moves, and the hero can never be scrolled back to.
              //
              // The dots that already exist are the way between slides, and
              // rotation still runs on its timer, so nothing is lost - on a
              // pointer device the drag is a convenience rather than a route,
              // and on a television it was a trap.
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, i) {
                final movie = widget.movies[i];
                final detail = _detailsCache[movie.id];
                return _HeroSlide(
                  movie: movie,
                  detail: detail,
                  screenWidth: screenWidth,
                  bandHeight: heroHeight,
                );
              },
            ),

            // Dot indicators
            if (totalSlides > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(totalSlides, (i) {
                    final active = i == _index;
                    final dotColor = active
                        ? tokens.accent
                        : tokens.textDisabled;
                    return FocusableCard(
                      onTap: () => _goTo(i),
                      builder: (_, state) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: ZplayMotion.standard,
                        margin: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s4,
                        ),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.fullAll,
                          color: dotColor,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: tokens.accent.withValues(
                                      alpha: 0.55,
                                    ),
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

            // Arrows
            if (totalSlides > 1 && _isHovering && screenWidth > 600) ...[
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
              if (_index < totalSlides - 1)
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
          // Chrome over artwork, so it flattens to the raised token surfaces
          // instead of the fork's translucent black discs.
          color: state.highlighted
              ? tokens.surfaceRaised
              : tokens.surfaceOverlay,
          border: Border.all(
            color: state.highlighted ? tokens.accent : tokens.borderStrong,
            width: 1.5,
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

// ─────────────────────────────────────────────────────────────────────────────
// Hero Slide — a single featured title within the carousel.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSlide extends StatelessWidget {
  final Movie movie;
  final MovieDetail? detail;
  final double screenWidth;

  /// Height the band actually has, so the slide can drop the parts of itself that
  /// do not fit instead of overflowing the band. See [build].
  final double bandHeight;

  const _HeroSlide({
    required this.movie,
    required this.detail,
    required this.screenWidth,
    required this.bandHeight,
  });

  /// Band height at which the synopsis is worth showing: the title, its gaps,
  /// the two buttons and the bottom inset, plus three lines of `ZplayType.body`
  /// and the 16 dp above them. Measured from this widget, not estimated - the
  /// first version of the chrome-aware hero used a single 228 dp floor for the
  /// whole column and clipped the title.
  static const double _synopsisBudget = 300;

  /// Band height at which the genre chips fit on top of all of that.
  static const double _chipsBudget = 350;

  void _openDetails(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final isCompact = screenWidth < 600;
    final tokens = context.tokens;
    final heroStyle = HomePageSettings.heroStyle.value;

    // What fits in the band, in the order the slide gives things up.
    //
    // The band is now sized against the space the page actually has left after
    // its chrome and the rail below, which on a 540 dp television is about 228 dp
    // - far less than this column's natural height, so a band bounded only from
    // above overflows. The column is bottom-aligned, so the title is what
    // disappears: the first version of that change shipped a hero with the
    // poster's name cut off by the top of the band.
    //
    // Rather than guess a number large enough to hold everything (which gives
    // back the space the rail needed) the slide drops the least load-bearing
    // parts first: the synopsis, then the genre chips. The title and the two
    // buttons are what the slide exists for and are never dropped.
    final roomForSynopsis = bandHeight >= _synopsisBudget;
    final roomForChips = bandHeight >= _chipsBudget;

    final hasBackdrop =
        detail?.background != null && detail!.background!.trim().isNotEmpty;
    final backdropUrl = hasBackdrop ? detail!.background! : null;
    final posterUrl = movie.poster;
    final imageUrl = backdropUrl ?? posterUrl;
    final year = detail?.year ?? movie.year;
    final rating = detail?.imdbRating;
    final description = detail?.description;
    final genres = detail?.genres ?? const <String>[];
    final logo = detail?.logo;
    // Layer 1 blur + foreground Layer 2 + portrait card decode each URL once:
    // same URL + same memCacheWidth hits the shared ResizeImage cache entry.
    final heroCacheWidth = hasBackdrop ? 1280 : 512;
    Widget heroArtwork({
      required String url,
      required BoxFit fit,
      required Alignment alignment,
      FilterQuality filterQuality = FilterQuality.medium,
      Duration fadeIn = const Duration(milliseconds: 300),
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
        fadeInDuration: fadeIn,
        placeholder: placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget: errorWidget ?? (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background Layers ──
        if (imageUrl != null && imageUrl.trim().isNotEmpty)
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
                                url: imageUrl,
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
                          ColoredBox(color: tokens.bg.withValues(alpha: 0.50)),
                        ],
                      ),
                    ),

                    // Layer 2: Crisp foreground artwork
                    if (hasBackdrop) ...[
                      // Landscape 16:9 backdrop available
                      if (containerAspect <= 1.78)
                        Positioned.fill(
                          child: heroArtwork(
                            url: backdropUrl!,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.15),
                          ),
                        )
                      else
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: (containerHeight * (16 / 9)).clamp(
                            0.0,
                            containerWidth,
                          ),
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
                              url: backdropUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                    ] else ...[
                      // Portrait poster fallback (when no 16:9 backdrop is available)
                      if (containerAspect <= 1.2)
                        Positioned.fill(
                          child: heroArtwork(
                            url: imageUrl,
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
                                  url: imageUrl,
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

        // Left horizontal wash for cinematic readability
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

        // Top gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [tokens.bg.withValues(alpha: 0.85), Colors.transparent],
              ),
            ),
          ),
        ),

        // Bottom gradient (fades seamlessly into the body background)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.28, 0.70],
                colors: [
                  tokens.bg,
                  tokens.bg.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Content overlay ──
        Positioned(
          left: isCompact ? ZplaySpacing.s20 : ZplaySpacing.s48,
          right: isCompact ? ZplaySpacing.s20 : ZplaySpacing.s48,
          bottom: isCompact
              ? (heroStyle == HeroStyle.minimalist
                    ? ZplaySpacing.s16
                    : ZplaySpacing.s32)
              : (heroStyle == HeroStyle.minimalist
                    ? ZplaySpacing.s24
                    : ZplaySpacing.s48),
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
                  // Rating + year + runtime
                  Row(
                    children: [
                      if (rating != null && rating.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                            vertical: ZplaySpacing.s4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.warning.withValues(
                              alpha: ZplayOpacity.overlayHover,
                            ),
                            borderRadius: ZplayRadius.smAll,
                            border: Border.all(
                              color: tokens.warning.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: tokens.warning,
                              ),
                              const SizedBox(width: ZplaySpacing.s4),
                              Text(
                                rating,
                                style: ZplayType.bodyNumeric
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: tokens.warning),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: ZplaySpacing.s8),
                      ],
                      if (year != null && year.isNotEmpty)
                        Text(
                          year,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textSecondary,
                          ),
                        ),
                      if (detail?.runtime != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                          ),
                          child: Icon(
                            Icons.circle,
                            size: 4,
                            color: tokens.textDisabled,
                          ),
                        ),
                        Text(
                          detail!.runtime!,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),

                  SizedBox(
                    height: heroStyle == HeroStyle.minimalist
                        ? ZplaySpacing.s8
                        : ZplaySpacing.s16,
                  ),

                  // Title / clearlogo
                  _HeroTitle(
                    title: movie.name,
                    logoUrl: logo,
                    isCompact: isCompact || heroStyle == HeroStyle.minimalist,
                    // A short band gets the smaller title, so the name is never
                    // the thing that gets cut. The 46 px title is two lines of
                    // 54 dp; at 32 px it is one line of 38, which is the
                    // difference between the slide fitting and the name
                    // disappearing off the top of the band.
                    shrink: !roomForSynopsis,
                  ),

                  // Description (Hidden in Minimalist, 1-line in Compact, 3-line in Immersive)
                  if (heroStyle != HeroStyle.minimalist &&
                      description != null &&
                      description.isNotEmpty &&
                      roomForSynopsis) ...[
                    SizedBox(
                      height: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s16,
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompact ? double.infinity : 560,
                      ),
                      child: Text(
                        description,
                        maxLines: heroStyle == HeroStyle.compact
                            ? 1
                            : (isCompact ? 2 : 3),
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.body.toStyle(
                          color: tokens.textEmphasis,
                        ),
                      ),
                    ),
                  ],

                  // Genre chips (Immersive only)
                  if (heroStyle == HeroStyle.immersive &&
                      genres.isNotEmpty &&
                      roomForChips) ...[
                    const SizedBox(height: ZplaySpacing.s16),
                    Wrap(
                      spacing: ZplaySpacing.s8,
                      runSpacing: ZplaySpacing.s8,
                      children: genres.take(4).map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s12,
                            vertical: ZplaySpacing.s4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: ZplayRadius.lgAll,
                            border: Border.all(color: tokens.borderStrong),
                          ),
                          child: Text(
                            genre,
                            style: ZplayType.bodySmall
                                .copyWith(weight: FontWeight.w600)
                                .toStyle(color: tokens.textEmphasis),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Action buttons
                  SizedBox(
                    height: heroStyle == HeroStyle.minimalist
                        ? ZplaySpacing.s12
                        : (isCompact ? ZplaySpacing.s16 : ZplaySpacing.s24),
                  ),
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          return ElevatedButton.icon(
                            // The starting point for keyboard and D-pad
                            // traversal on Home. Without one, no node holds
                            // focus and the first arrow press does nothing.
                            autofocus: true,
                            onPressed: () => _openDetails(context),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                            ),
                            label: Text(
                              'Watch Now',
                              style: ZplayType.subtitle.toStyle(),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: tokens.onAccent,
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact
                                    ? ZplaySpacing.s16
                                    : ZplaySpacing.s24,
                                vertical: isCompact
                                    ? ZplaySpacing.s12
                                    : ZplaySpacing.s16,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: ZplayRadius.mdAll,
                              ),
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.35),
                            ),
                          );
                        },
                      ),
                      if (heroStyle != HeroStyle.minimalist) ...[
                        SizedBox(
                          width: isCompact ? ZplaySpacing.s8 : ZplaySpacing.s12,
                        ),
                        Builder(
                          builder: (context) {
                            return OutlinedButton.icon(
                              onPressed: () => _openDetails(context),
                              icon: Icon(
                                Icons.info_outline_rounded,
                                size: isCompact ? 18 : 20,
                                color: tokens.textEmphasis,
                              ),
                              label: Text(
                                'Details',
                                style: ZplayType.subtitle.toStyle(
                                  color: tokens.textEmphasis,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact
                                      ? ZplaySpacing.s16
                                      : ZplaySpacing.s20,
                                  vertical: isCompact
                                      ? ZplaySpacing.s12
                                      : ZplaySpacing.s16,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: ZplayRadius.mdAll,
                                ),
                                side: tokens.hairlineStrong,
                              ),
                            );
                          },
                        ),
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Hero Title — clearlogo when available, crossfaded text fallback otherwise.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroTitle extends StatelessWidget {
  final String title;
  final String? logoUrl;
  final bool isCompact;

  /// One step down from the full display size, for a band too short to hold the
  /// rest of the slide. The name is the one thing a hero cannot lose, so it is
  /// what gives way in size rather than in existence.
  final bool shrink;

  const _HeroTitle({
    required this.title,
    required this.logoUrl,
    required this.isCompact,
    this.shrink = false,
  });

  @override
  Widget build(BuildContext context) {
    // A shrunk title is one line at 32 px rather than two at 46, which is what
    // lets the name survive in a band that cannot hold the full column.
    final small = isCompact || shrink;
    final maxHeight = small ? 76.0 : 118.0;
    final textStyle = ZplayType.display
        .copyWith(size: small ? 32 : 46)
        .toStyle(color: context.tokens.textPrimary);

    final titleText = Text(
      title,
      maxLines: small ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );

    if (logoUrl == null || logoUrl!.isEmpty) {
      return titleText;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: CachedNetworkImage(
          imageUrl: logoUrl!,
          cacheManager: AppImageCache.manager,
          memCacheWidth: 512,
          fit: BoxFit.contain,
          alignment: Alignment.bottomLeft,
          filterQuality: FilterQuality.medium,
          fadeInDuration: const Duration(milliseconds: 250),
          placeholder: (_, __) => titleText,
          errorWidget: (_, __, ___) => titleText,
        ),
      ),
    );
  }
}
