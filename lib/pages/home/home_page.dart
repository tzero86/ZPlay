import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/hero/hero_media_resolver.dart';
import '../../services/trakt/trakt_list_source.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';
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

/// The page's own control row, below `MediaQuery` top padding: the filter pills
/// with 4 dp of breathing room above and below them.
///
/// It is one row on every form factor and carries only what is the page's - the
/// All/Movies/Series/Anime pills and Home's two page-level actions. The brand and
/// the destinations are the shell's top bar now, so the 34 dp wordmark band that
/// used to sit above the pills is gone and the pills are the tallest thing in the
/// row. That is what sets the height, exactly as the television bar already did
/// before the shell took the brand over.
const double _televisionAppBarHeight = 36;

/// The pointer's version of the same row, one pill size up: 4 + 44 + 4.
///
/// The old 58 dp was 8 + a 34 dp wordmark + 16, and the wordmark is not this
/// bar's to carry any more. What is left is the pill row, so the row's height is
/// the pill's - and the icon buttons beside it are held to the same height
/// rather than setting it themselves.
const double _pointerAppBarHeight = 52;

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

/// The pointer's filter row: the same control, one size up, at the touch-sized
/// target the segmented control has always used off a television.
const double _pointerTabHeight = 44;

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

  /// How far one UP or DOWN moves the page, in logical pixels. Roughly two rail
  /// pitches, so a press carries the focus past the row it is leaving rather
  /// than nudging the page a few pixels at a time.
  static const double _keyScrollStep = 120;

  bool _loading = true;
  final List<MovieSection> _sections = [];
  String? _error;

  List<Movie> _featuredMovies = [];
  _HomeFilter _selectedFilter = _HomeFilter.all;

  /// Anime discovery rows for the Anime tab, loaded on first use.
  final List<_AnimeRow> _animeRows = [];
  bool _animeLoading = false;
  bool _animeLoaded = false;

  /// Trakt's three public lists, fetched once per home load.
  ///
  /// They need no OAuth token, so they are the only Trakt content a signed-out
  /// user can have. Held separately from [_sections] so [_injectSimilarSections]
  /// can remove and re-place the personalised rails without touching them, and
  /// so a null result simply leaves the list empty.
  final List<MovieSection> _traktPublicSections = [];
  bool _traktPublicLoaded = false;
  bool _traktPublicInFlight = false;

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

  /// The scroll viewport Home's own arrow keys fall back on.
  ///
  /// The edge test below has to know where the page's visible box is, and a
  /// `ScrollController` holds no geometry: it knows the offset and the extent,
  /// not the pixels. The key is on the `ListView` itself so the rect comes from
  /// the render object rather than from a second copy of the layout's numbers.
  final GlobalKey _pageKey = GlobalKey();

  /// Focus that landed off-screen, and the focus manager telling us so.
  ///
  /// `FocusManager` is a [ChangeNotifier] that fires exactly when the primary
  /// focus node changes (see `FocusManager._notify`), so this is the cue that
  /// focus has moved rather than the key handler guessing whether it will.
  FocusNode? _lastFocused;

  /// How far past a viewport edge a focused widget has to sit before the arrow
  /// key is treated as having nowhere left to go.
  ///
  /// Half a rail pitch. A TV card is ~118 dp wide and the 540 dp canvas is
  /// measured against the whole window, so a threshold narrower than that
  /// would fire while the focused card is still comfortably on screen and
  /// swallow the key that was supposed to move focus; a larger one would let
  /// focus leave the page entirely before the fallback took over.
  static const double _edgeTolerance = 60;

  void _onPrimaryFocusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node == _lastFocused) return;
    _lastFocused = node;
    _revealFocused(node);
  }

  /// Brings a newly focused widget into the page's viewport.
  ///
  /// This is the half of "focus moved off-screen" that the key handler cannot
  /// do: traversal lands on a node wherever the tree happens to put it, and if
  /// that node is above the fold the page has to move or the user is focused on
  /// something they cannot see. Skipped when the widget is already fully inside
  /// the viewport, so a normal move between two cards does not nudge the page.
  void _revealFocused(FocusNode? node) {
    if (!mounted || node?.context == null) return;
    if (!_scrollController.hasClients) return;
    final viewportBox = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) return;

    final targetBox = node!.context!.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached || !targetBox.hasSize) return;

    final targetGlobal = targetBox.localToGlobal(Offset.zero);
    final viewportGlobal = viewportBox.localToGlobal(Offset.zero);
    final targetTop = targetGlobal.dy - viewportGlobal.dy;
    final targetBottom = targetTop + targetBox.size.height;
    final viewportHeight = viewportBox.size.height;

    // Do not scroll for whole-page or very large containers.
    if (targetBox.size.height >= viewportHeight * 0.85) return;

    final topInset = _topInsetFor(context);
    // If the focused target is inside or above the top bar / filter row, do not scroll.
    if (targetBottom <= topInset) return;

    final visibleTop = topInset + ZplaySpacing.s8;
    final visibleBottom = viewportHeight - ZplaySpacing.s16;

    final isFullyVisible = targetTop >= visibleTop && targetBottom <= visibleBottom;
    if (isFullyVisible) return;

    final position = _scrollController.position;
    double? targetOffset;

    if (targetBottom > visibleBottom) {
      final delta = targetBottom - visibleBottom;
      targetOffset = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    } else if (targetTop < visibleTop) {
      final delta = visibleTop - targetTop;
      targetOffset = (position.pixels - delta).clamp(0.0, position.maxScrollExtent);
    }

    if (targetOffset != null && (targetOffset - position.pixels).abs() > 1.0) {
      _scrollController.animateTo(
        targetOffset,
        duration: ZplayMotion.base,
        curve: Curves.easeOutCubic,
      );
    }
  }


  /// Whether the page is the thing that should answer an arrow key.
  ///
  /// **Traversal owns the arrow key; scrolling is the fallback when traversal
  /// has nowhere to go.** The previous handler took UP and DOWN on every press
  /// the page could scroll, which meant a remote standing on the hero CTA could
  /// never reach the first rail: the key was gone before `DirectionalFocusIntent`
  /// ever saw it. The only correct time to scroll is when the focused widget is
  /// already at the edge of the visible area, because that is the one case
  /// where there is nothing left to traverse to.
  bool _scrollPageForKey(LogicalKeyboardKey key) {
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return false;
    }
    final position = _scrollController.hasClients
        ? _scrollController.position
        : null;
    final viewportBox = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    final node = FocusManager.instance.primaryFocus;
    if (position == null || viewportBox == null || !viewportBox.attached || !viewportBox.hasSize || node?.context == null) {
      return false;
    }

    final targetBox = node!.context!.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached || !targetBox.hasSize) return false;

    final targetGlobal = targetBox.localToGlobal(Offset.zero);
    final viewportGlobal = viewportBox.localToGlobal(Offset.zero);
    final targetTop = targetGlobal.dy - viewportGlobal.dy;
    final targetBottom = targetTop + targetBox.size.height;
    final topInset = _topInsetFor(context);

    // If the focused widget is in the top bar or filter bar, never scroll here -
    // let directional traversal move focus down into the page content.
    if (targetBottom <= topInset) return false;

    final visibleTop = topInset + ZplaySpacing.s8;
    final visibleBottom = viewportBox.size.height - ZplaySpacing.s16;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (position.pixels <= 0) return false;
      if (targetTop > visibleTop + _edgeTolerance) return false;
      _scrollController.animateTo(
        math.max(0, position.pixels - _keyScrollStep),
        duration: ZplayMotion.base,
        curve: Curves.easeOutCubic,
      );
      return true;
    }

    if (position.pixels >= position.maxScrollExtent) return false;
    if (targetBottom < visibleBottom - _edgeTolerance) return false;
    _scrollController.animateTo(
      math.min(position.maxScrollExtent, position.pixels + _keyScrollStep),
      duration: ZplayMotion.base,
      curve: Curves.easeOutCubic,
    );
    return true;
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
    FocusManager.instance.addListener(_onPrimaryFocusChanged);

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

  /// The filter row for a window too narrow to carry it in the app bar.
  ///
  /// Only reachable below `_appBarFilterBreakpoint`, where the wordmark band and
  /// a second control row will not both fit. On a television and on a wide
  /// window this is not built at all - see `_filtersInAppBar`.
  Widget _buildFilterSlot(BuildContext context) {
    return Padding(
      // No top inset here: the scroll view's own top padding already clears the
      // control row exactly. Adding any more put this row below the row it
      // belongs under - a double count of the same inset, which is the bug the
      // padding rewrite exists to remove.
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        0,
        ZplaySpacing.s20,
        ZplaySpacing.s4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildFilterTabs(context),
      ),
    );
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
    // The page's own chrome, from the one place that defines it.
    final chromeAbove = _topInsetFor(context);

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
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
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

  /// Fetches Trakt's public rails and puts them on the page.
  ///
  /// **[HomePageSettings.fetchTraktPublicSection] returns null** for a list that
  /// is not public, for a failed fetch, and for an empty one. All three mean the
  /// same thing to a rail: there is nothing to draw, so nothing is added. That
  /// is the whole reason this is safe on a device with no Trakt account, no
  /// network, or no key - a null simply leaves [_traktPublicSections] empty and
  /// no heading appears over nothing.
  ///
  /// Runs beside the addon stream rather than inside it, so three Trakt reads
  /// never sit between the user and the first rail.
  Future<void> _loadTraktPublicSections() async {
    if (_traktPublicLoaded || _traktPublicInFlight) return;
    _traktPublicInFlight = true;
    try {
      final fetched = await Future.wait([
        for (final list in const [
          TraktSeeAllList.trending,
          TraktSeeAllList.popular,
          TraktSeeAllList.anticipated,
        ])
          HomePageSettings.fetchTraktPublicSection(list),
      ]);

      if (!mounted) return;
      setState(() {
        _traktPublicSections
          ..clear()
          ..addAll(fetched.whereType<MovieSection>());
        _traktPublicLoaded = true;
      });
    } finally {
      _traktPublicInFlight = false;
    }
  }

  /// Inserts the fetched Trakt rails at the position the user chose for
  /// recommendations, so there is one rule for where "extra" content goes
  /// rather than two that can disagree.
  void _injectTraktPublicSections() {
    if (!mounted || _traktPublicSections.isEmpty) return;
    setState(() {
      _sections.removeWhere(
        (s) =>
            s.catalog.id.startsWith('trakt_trending') ||
            s.catalog.id.startsWith('trakt_popular') ||
            s.catalog.id.startsWith('trakt_anticipated'),
      );
      switch (HomePageSettings.similarPosition.value) {
        case SimilarSectionPosition.top:
          _sections.insertAll(0, _traktPublicSections);
          break;
        case SimilarSectionPosition.underCinemeta:
          final insertIdx = _sections.length > 1 ? 1 : _sections.length;
          _sections.insertAll(insertIdx, _traktPublicSections);
          break;
        case SimilarSectionPosition.middle:
          _sections.insertAll(_sections.length ~/ 2, _traktPublicSections);
          break;
        case SimilarSectionPosition.bottom:
          _sections.addAll(_traktPublicSections);
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

      // Trakt's public lists are independent of the addon stream, so they are
      // started here and awaited at the end: a slow or dead Trakt cannot hold
      // the first rail back.
      final traktPublic = _loadTraktPublicSections();

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

      // Trakt's rails land whenever they land.
      //
      // **Deliberately not awaited.** Awaiting here put the three Trakt reads
      // between "the addon rails are on screen" and "the skeleton clears", so a
      // Trakt that was slow or unreachable held Home on its loading state for as
      // long as it took - which is the one thing the rails are not worth. The
      // future injects itself when it answers, and a null injects nothing.
      unawaited(
        traktPublic.then((_) {
          if (mounted) _injectTraktPublicSections();
        }),
      );

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

  /// True only on a television. Read in one place so the height, the tab row and
  /// the bar's own furniture cannot disagree about which layout they are in.
  static bool _isTelevision(BuildContext context) =>
      FormFactorService.of(context) == FormFactor.television;

  /// The height of the row's own content: the filter pills, and the ceiling the
  /// icon buttons beside them are held to so neither can set the chrome's height
  /// by itself.
  static double _tabHeightFor(BuildContext context) =>
      _isTelevision(context) ? _televisionTabHeight : _pointerTabHeight;

  /// The page's own control row, below `MediaQuery` top padding.
  static double _appBarHeightFor(BuildContext context) =>
      _isTelevision(context) ? _televisionAppBarHeight : _pointerAppBarHeight;

  /// Everything the page draws above its first pixel of content: the safe-area
  /// inset the shell did not consume, the page's own control row, and the gap
  /// under it.
  ///
  /// The shell's top bar is a real layout child that reserves its own space, so
  /// this pays for the page's chrome only. Nothing here is a second charge for
  /// the shell, and `padding.top` is zero wherever the shell draws that bar.
  static double _topInsetFor(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      _appBarHeightFor(context) +
      ZplaySpacing.s8;

  /// Width at which the filter tabs move into the control row; below it they sit
  /// inline above the hero at full width, where the row has no room to spare.
  ///
  /// Derived from the row's own furniture rather than guessed. The segmented
  /// control budgets 78 dp for its narrowest segment (`_minSegmentWidth`) and
  /// about 97 for the widest label here ("Movies"), so four segments are ~390 at
  /// their widest; the divider and its margins add 33, the two page actions 88,
  /// and the row's own padding 28 - about 540. This used to be 1000 because the
  /// row also carried a ~90 px wordmark and, before that, six icon buttons; both
  /// are gone, and the 180 dp of slack 720 leaves over that ~540 is what keeps a
  /// wider glyph or a longer label from overflowing a row that cannot wrap.
  static const double _appBarFilterBreakpoint = 720;

  /// Whether the tabs live in the bar rather than in a row of their own.
  ///
  /// **A television always carries them in the bar**, whatever the width: its
  /// canvas is fixed at the ten-foot size, and the bar has no second row to fall
  /// back to. Off a television the tabs join the bar as soon as the row can hold
  /// them beside the page's two actions; below that they are the head of the
  /// scroll content instead, where they have the full width.
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
    final rowHeight = _tabHeightFor(context);
    return Semantics(
      container: true,
      label: 'Home content filter',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _homeFilterLabels) ...[
            _HomeFilterPill(
              label: entry.$2,
              selected: _selectedFilter == entry.$1,
              height: rowHeight,
              onTap: () => _setFilter(entry.$1),
            ),
            if (entry.$1 != _homeFilterLabels.last.$1)
              const SizedBox(width: ZplaySpacing.s8),
          ],
        ],
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

    // The page's control row is a `Positioned` overlay, so the space it occupies
    // has to be the scroll view's *top padding* - not a spacer widget at the head
    // of the list. A spacer is content: it scrolls away, and once it has, the
    // list has nothing left to travel up past, so the hero can never be scrolled
    // back into view. That is the whole of "I can scroll down but never back up"
    // - UP took the list to offset 0, which slid the hero's *bottom* under the
    // row instead of lifting it above it.
    //
    // Padding is part of the scroll extent, so content can always travel back
    // above the row and the hero is always reachable.
    //
    // `_topInsetFor` is the page's chrome and nothing else. The shell's top bar
    // is a layout child that reserves its own space and hands this page a
    // `MediaQuery` with the top safe area already consumed, so the 48 dp of
    // shell above this box is not charged again here.
    final appBarInset = _topInsetFor(context);

    final slots = <Widget>[
      // When the tabs are *not* in the control row - a narrow pointer window -
      // they are the head of the scroll content, directly under it. This is
      // content, not chrome, so it scrolls away, which is correct: it is a
      // control, and a control that floats over the content would cover the
      // first rail. The row's own inset above it is the scroll view's padding,
      // so nothing is ever hidden behind the row.
      if (!_filtersInAppBar(context)) _buildFilterSlot(context),
      if (!HomePageSettings.enableSpotlight.value)
        // Nothing to reserve here: the control row's inset is the padding below.
        // This used to add `topPadding + 76` as a second leading spacer, which
        // double-counted the bar and pushed the first rail a whole bar down.
        const SizedBox.shrink()
      else if (isAnimeTab && featured.isEmpty)
        // Nothing to feature yet on the Anime tab: let the rows below start
        // right under the control row instead of reserving an empty hero band.
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
              // A Trakt public rail's catalog is synthetic - `trakt_trending` is
              // not an addon endpoint, so See All would open a CatalogPage that
              // asks Cinemeta for a catalog that does not exist. Curated rails
              // are synthetic for the same reason.
              showSeeAll: !visibleSections[i].catalog.id.startsWith(
                'curated_',
              ) &&
                  !visibleSections[i].catalog.id.startsWith('trakt_'),
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
            // The same inset the loaded page uses, so the skeleton's hero
            // placeholder sits exactly where the hero lands and nothing jumps
            // when the first section arrives.
            _HomeSkeleton(topInset: appBarInset)
          else if (_error != null && _sections.isEmpty)
            ErrorView(error: _error, onRetry: _loadHome)
          else
            RefreshIndicator(
              color: tokens.accent,
              backgroundColor: tokens.surface,
              onRefresh: _loadHome,
              child: ListView.builder(
                key: _pageKey,
                controller: _scrollController,
                clipBehavior: Clip.none,
                // Top padding rather than a leading spacer - see `appBarInset`.
                padding: EdgeInsets.only(top: appBarInset),
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
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: true,
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

            // UP and DOWN fall through to directional traversal whenever there
            // is anywhere for focus to go, and only scroll the page when the
            // focused widget is already sitting at the edge of the viewport.
            // Taking them unconditionally is what stopped a remote reaching the
            // first rail from the hero: the key never got as far as
            // `DirectionalFocusIntent`.
            if (_scrollPageForKey(event.logicalKey)) {
              return KeyEventResult.handled;
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
    if (!_showIntro) return const SizedBox.shrink();
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
ZplayLogo(size: iconSize * 1.5),
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
class _HomeFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final double height;

  final VoidCallback onTap;


  const _HomeFilterPill({
    required this.label,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    const radius = ZplayRadius.fullAll;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: radius,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: selected
                  ? Colors.white.withValues(alpha: 0.18)
                  : (state.highlighted
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.06)),
              border: Border.all(color: Colors.transparent),
            ),
            child: Text(
              label,
              style: ZplayType.label.copyWith(
                weight: selected ? FontWeight.w600 : FontWeight.w500,
              ).toStyle(
                color: selected || state.highlighted
                    ? tokens.textPrimary
                    : tokens.textSecondary,
              ),
            ),
          ),
        ),
    );
  }
}

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
          // The inset is already the row plus its gap; adding the gap again
          // here put the skeleton's hero 8 dp below the real one, so the whole
          // page shifted up the moment the first section landed.
          SizedBox(height: topInset),
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
    // The page's own control row, and nothing else.
    //
    // It used to be two storeys: a 34 dp brand wordmark with the pills under it
    // on a pointer, and a single 28 dp row on a television, where a 540 dp canvas
    // could not pay for the wordmark. The brand and the destinations are the
    // shell's top bar now, so the page keeps only what is the page's - the
    // All/Movies/Series/Anime pills and Home's two page-level actions - in one
    // row on every form factor.
    final television = FormFactorService.of(context) == FormFactor.television;
    // The buttons are held to the row's own content height. A 48 dp Material
    // default would be the tallest thing in the row and would set the chrome's
    // height by itself, which is the height this row exists to stop paying.
    //
    // `constraints` alone does not do it: Material 3 turns it into the style's
    // min/max size, and `MaterialTapTargetSize.padded` then grows the box back
    // to 48 dp around it. Measured on the device canvas - the buttons rendered
    // 48x48 and set the row's height themselves - so the style states the size
    // and the tap target policy both.
    final rowHeight = _HomePageState._tabHeightFor(context);
    final ButtonStyle rowButton = IconButton.styleFrom(
      // 44 dp square on a pointer - Material 3's own visual default is 40, and
      // 44 is the touch minimum - and the 32 dp the ten-foot row has always used
      // there, where a 48 dp box would set the chrome's height by itself.
      minimumSize: Size(television ? 32 : 44, rowHeight),
      maximumSize: Size(television ? 32 : 44, rowHeight),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.only(
          // 4 + the row's own content + 4 keeps `_appBarHeightFor` exact.
          top: topPadding + ZplaySpacing.s4,
          bottom: ZplaySpacing.s4,
          left: ZplaySpacing.s20,
          right: ZplaySpacing.s8,
        ),
        decoration: BoxDecoration(color: tokens.bg),
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: tokens.hairline),
        ),
        // **This bar cannot be transparent, however much chrome it costs.**
        //
        // It was set to `Colors.transparent` on a television so the hero would
        // run under it instead of sitting below a second filled bar, and that
        // looked right until the first rail scrolled up: measured on the
        // television, "Popular 50 / Cinemeta" drew straight through
        // "All Movies Series Anime" and both became unreadable at once.
        //
        // The bar is a `Positioned` overlay over a scrolling list, so anything
        // that lets the content show through is only correct while the content
        // is behind it - which is the top of the page and nowhere else. Opaque
        // on every form factor; the hero keeps its height budget instead.
        // The row is pinned to its own height rather than left to wrap, so the
        // chrome is `_appBarHeightFor` whatever the actions are gated to: with
        // the quiz and the calendar both switched off there would otherwise be
        // no child left to give the row a height, and the scroll inset would
        // reserve space for a row that is not there.
        height: _HomePageState._appBarHeightFor(context) + topPadding,
        child: Row(
          children: [
            // All / Movies / Series pills: they lead the row, and the free
            // space falls between them and the page's actions.
            if (filterTabs != null) ...[
              // Intrinsic width, deliberately — NOT Flexible. A Flexible here
              // also takes flex 1, exactly like a Spacer beside it, so the two
              // split the free space; the tabs then use only their natural width
              // and strand the remainder *after* themselves, pushing the row's
              // right end 384px short of the right edge at 2042px wide.
              // Measured, not guessed. The tabs only enter the row above
              // `_appBarFilterBreakpoint`, where the row has room for them.
              filterTabs!,
              const Spacer(),
              Container(
                width: 1,
                height: ZplaySpacing.s16,
                margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                color: tokens.borderStrong,
              ),
            ] else
              // No pills in this window: they are the head of the scroll content
              // instead, and the page's actions still sit at the row's end
              // rather than against its left edge.
              const Spacer(),
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
                  style: rowButton,
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
                  style: rowButton,
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

  /// The slides, with hero media resolved.
  ///
  /// A catalog response carries a backdrop and a trailer key on some titles and
  /// not on others, so the hero asks [HeroMediaResolver] to fill what is
  /// missing. Six slides, not a whole page of rails: the tail past the first
  /// dozen is work no one ever sees, and on a 2 GB television every extra
  /// lookup is a socket and a decode competing with the rows underneath.
  List<Movie> _slides = const [];

  /// The exact list [_slides] was resolved from, so an unchanged rebuild does
  /// not re-run the resolver and hand the carousel a new list identity.
  List<Movie>? _enrichedFrom;

  Timer? _timer;
  int _index = 0;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    _slides = List<Movie>.of(widget.movies);
    if (widget.movies.isNotEmpty) {
      _fetchDetail(widget.movies.first);
      if (widget.movies.length > 1) _fetchDetail(widget.movies[1]);
    }
    _enrich();
    _startTimer();
  }

  /// Fills in the backdrop and trailer key the slides are missing.
  ///
  /// Best-effort by contract: with no TMDb key, or when every lookup fails, the
  /// resolver hands the same list straight back and nothing here changes.
  Future<void> _enrich() async {
    if (identical(_enrichedFrom, widget.movies)) return;
    _enrichedFrom = widget.movies;
    final resolved = await HeroMediaResolver.enrich(widget.movies);
    if (!mounted || identical(resolved, _slides)) return;
    setState(() => _slides = resolved);
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
      // The new list has to land here as well as in `initState`. Assigning only
      // in `initState` meant the carousel kept showing the *first* set of
      // movies forever: `_slides` was never refreshed, so switching the filter
      // tab, reloading Home, or any rail arriving late left the hero painting
      // whatever it was first handed - or nothing at all, since
      // `_totalSlideCount` counts `_slides` and a stale empty list renders an
      // empty band.
      _slides = List<Movie>.of(widget.movies);
      if (widget.movies.isNotEmpty) _fetchDetail(widget.movies.first);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _enrich();
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

  int get _totalSlideCount => _slides.length;

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
    if (index < _slides.length) {
      _fetchDetail(_slides[index]);
    }
    final nextSlide = (index + 1) % _totalSlideCount;
    if (nextSlide < _slides.length) {
      _fetchDetail(_slides[nextSlide]);
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
  static const double _heroCompactHeight = 236;

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
    // The carousel floats inside the page, so it asks the page's own chrome
    // rule rather than repeating it: the control row, its gap under it, and the
    // safe-area inset the shell did not consume. Nothing here pays for the
    // shell's top bar - it is a layout child that has already taken its space
    // out of this box.
    final chromeAbove = _HomePageState._topInsetFor(context);
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
                final movie = _slides[i];
                final detail = _detailsCache[movie.id];
                return _HeroSlide(
                  movie: movie,
                  detail: detail,
                  screenWidth: screenWidth,
                  bandHeight: heroHeight,
                );
              },
            ),

            // Dot indicators.
            //
            // Drawn on a television but **not** in the traversal order. Each dot
            // is a `FocusableCard` 7 dp tall, sitting 16 dp above the bottom of
            // the band - and directional traversal from the hero CTA finds it
            // before it finds the first rail, because it is the nearest
            // focusable node below the button. One DOWN jumped the carousel
            // instead of moving into content, which is precisely the "focus is
            // erratic, the highlight gets lost" report, and it is invisible
            // besides: a 7 dp ring is not something a user from a sofa is meant
            // to find. The arrows below already carry the `_isHovering` guard
            // for the same reason; the dots needed the same treatment and did
            // not have it.
            //
            // Rotation still runs on its timer, and the poster in the hero
            // carries the artwork, so a slide is still reachable - by waiting
            // rather than by hunting for a dot.
            if (totalSlides > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Focus(
                  // On a television the dots are decoration, not controls.
                  //
                  // Both flags, and neither alone was enough - measured on the
                  // device. `skipTraversal` removes the row from the traversal
                  // order, so nothing moves focus *to* it, but the node stays
                  // focusable and traversal from the hero CTA landed on it
                  // anyway. Focus then sat on an invisible row of 7 dp marks with
                  // no ring drawn anywhere, and every arrow key after that went
                  // nowhere a user could see. `canRequestFocus: false` is what
                  // actually closes it.
                  //
                  // Pointer devices keep both: the dots stay visible and
                  // clickable, which is what a mouse or a finger is for.
                  canRequestFocus:
                      FormFactorService.of(context) != FormFactor.television,
                  skipTraversal:
                      FormFactorService.of(context) == FormFactor.television,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(totalSlides, (i) {
                      final active = i == _index;
                      final dotColor =
                          active ? tokens.accent : tokens.textDisabled;
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

  /// The first of [candidates] that is a usable wide image, or null.
  ///
  /// A blank or whitespace URL is not usable: catalogs carry both, and an
  /// empty string would otherwise reach `CachedNetworkImage` as a request for
  /// the current page.
  static String? _wideArtwork(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return null;
  }

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

    // Wide artwork, in the order the hero prefers it.
    //
    // `MovieDetail.background` first: the hero already fetches the detail for
    // this slide, so the art costs nothing extra. `Movie.backdrop` second - the
    // catalog sometimes carries it and [HeroMediaResolver] fills it from TMDb
    // when it does not.
    //
    // **A poster is never the background.** A poster is 2:3 and a hero band is
    // roughly 16:9, so filling the band with one crops two thirds of the frame
    // away or stretches it; and the old code did both at once, painting a
    // blurred, 50%-dimmed copy of the poster over the whole band behind the
    // text. That is the flat, washed-out look this replaces. With no wide art
    // at all the band is a scrim over `tokens.bg` and the logo/title treatment
    // below carries the slide on its own.
    final backdropUrl = _wideArtwork(
      detail?.background,
      movie.backdrop,
    );
    final year = detail?.year ?? movie.year;
    final rating = detail?.imdbRating;
    final description = detail?.description;
    final genres = detail?.genres ?? const <String>[];
    final logo = detail?.logo;
    // The band draws 960 dp of a 16:9 still on the television and up to ~2x that
    // on a desktop window, and the decode is the largest one this screen ever
    // makes. 1280 physical pixels covers the TV at DPR 2 and a 1280 dp window
    // at DPR 1 without re-downloading a second copy for a bigger screen.
    const heroCacheWidth = 1280;
    Widget heroArtwork({
      required String url,
      required BoxFit fit,
      required Alignment alignment,
      FilterQuality filterQuality = FilterQuality.medium,
    }) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheManager: AppImageCache.manager,
        memCacheWidth: heroCacheWidth,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        fadeInDuration: const Duration(milliseconds: 300),
        // Nothing behind the scrim but the page background, so a failed decode
        // leaves a clean band rather than a grey rectangle.
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background ──
        ColoredBox(color: tokens.bg),
        if (backdropUrl != null)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A band wider than 16:9 gets the art pinned to the right, so
                // the crop happens on the side the text does not occupy rather
                // than through the middle of the frame.
                final containerAspect =
                    constraints.maxWidth / constraints.maxHeight;
                if (containerAspect <= 16 / 9) {
                  return heroArtwork(
                    url: backdropUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  );
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: constraints.maxHeight * (16 / 9),
                    height: constraints.maxHeight,
                    child: heroArtwork(
                      url: backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                );
              },
            ),
          ),

        // The scrim, and the only one.
        //
        // Text sits on top of the artwork, so legibility must not depend on
        // what the picture happens to be doing underneath it. That is what this
        // band buys: opaque `tokens.bg` where the text column stands, easing to
        // nothing over the far two thirds where there is no text to read.
        //
        // It is directional rather than uniform on purpose. The previous stack -
        // a 95% left wash, an 85% top gradient and a bottom gradient that went
        // fully opaque at 28% - layered into an effective ~99% over the whole
        // left half and most of the top. An earlier version took the full-image
        // overlay approach and was rejected for washing the content out; this
        // is the opposite failure, where the artwork is the only thing carrying
        // the hero and it was being erased. One scrim, one axis, art intact on
        // the right where the eye lands on the picture.
        //
        // The stops are the prototype's own: near-opaque across the first
        // third so a bright frame cannot read through the title, then a
        // fall-off pushed out to 0.82 so the fade happens across the picture
        // rather than eating into it, and the far 18% left clean.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.38, 0.65, 0.82],
                colors: [
                  tokens.bg.withValues(alpha: 0.98),
                  tokens.bg.withValues(alpha: 0.90),
                  tokens.bg.withValues(alpha: 0.50),
                  tokens.bg.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // The foot, and it is a foot: opaque where the band meets the page's
        // own `tokens.bg` below it, so there is no seam, and cleared to nothing
        // by 30% up the band.
        //
        // It used to hold 60% all the way to the top. A `LinearGradient` with
        // two stops and nothing after them is a plateau, not a ramp, so the
        // artwork was dimmed over 78% of its height - which washed out again
        // the "clears to the right" the horizontal scrim had just bought.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.30, 1.0],
                colors: [
                  tokens.bg,
                  tokens.bg.withValues(alpha: 0.30),
                  tokens.bg.withValues(alpha: 0.0),
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
                            // A second autofocus on a television, deliberately.
                            //
                            // Removing this in favour of "the rail owns starting
                            // focus" was tried and measured worse: with focus
                            // starting on the rail the first directional press had
                            // no dependable destination and landed on a node with
                            // no ring drawn anywhere, so the arrow keys looked
                            // simply dead. The rail's autofocus and this one do
                            // contend, and which wins depends on mount order, but
                            // having the hero's call to action focused is worth
                            // that: it is the one control on the screen that says
                            // what the page is for, and DOWN from it reaches the
                            // first rail.
                            //
                            // The contention is not left as a surprise -
                            // `_settleAtHeroCta` in the traversal test requests this
                            // node explicitly rather than trusting which
                            // autofocus won, so the test exercises the path a
                            // user is actually on.
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
                              side: WidgetStateBorderSide.resolveWith((states) {
                                if (states.contains(WidgetState.focused)) {
                                  return const BorderSide(color: Colors.white, width: 2);
                                }
                                return const BorderSide(color: Colors.transparent, width: 2);
                              }),
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
                                side: WidgetStateBorderSide.resolveWith((states) {
                                  if (states.contains(WidgetState.focused)) {
                                    return BorderSide(color: tokens.accent, width: 2);
                                  }
                                  return BorderSide(color: tokens.hairlineStrong.color, width: 1);
                                }),
                              ),
                            );
                          },
                        ),
                      ],
                      // The trailer control, only where there is a trailer.
                      //
                      // TMDb hands back a YouTube *key*, not a playable file, and
                      // nothing in this app can play a youtube.com watch URL - so
                      // this opens YouTube and hands the video to whatever the
                      // device already has. It is an affordance, not a second
                      // hero: same button height as the others, same outline
                      // weight, and it only appears when a key exists.
                      if (movie.trailerKey != null &&
                          movie.trailerKey!.isNotEmpty)
                        Builder(
                          builder: (context) => _TrailerButton(
                            trailerKey: movie.trailerKey!,
                            compact: isCompact,
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

/// Opens a hero title's trailer in YouTube.
///
/// TMDb resolves a trailer to a YouTube video *key*, and neither Media3 nor
/// mpv can play a `youtube.com/watch` URL - there is no extractor in this app and
/// no dependency that would provide one. So the hero does not pretend to be a
/// video surface: it hands the key to YouTube, which the device already knows
/// how to play, over an intent the Android manifest already declares.
///
/// Built on [OutlinedButton] rather than [FocusableCard] so it matches the
/// Details button beside it exactly - a Material button is already a `Focus`
/// node, so the remote reaches it through the same traversal as every other
/// button on the page. `ActivateIntent` is what the remote's centre key sends.
class _TrailerButton extends StatelessWidget {
  final String trailerKey;
  final bool compact;

  const _TrailerButton({required this.trailerKey, required this.compact});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.https('www.youtube.com', '/watch', {'v': trailerKey});
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // A device with no browser and no YouTube, or a key the platform
      // rejects. The button has already done its job by being there; there is
      // nothing to recover and nothing worth interrupting the user with.
      debugPrint('[HomePage] trailer launch failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: Icon(
        Icons.play_circle_outline_rounded,
        size: compact ? 18 : 20,
        color: tokens.textEmphasis,
      ),
      label: Text(
        'Trailer',
        style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
      ),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? ZplaySpacing.s16 : ZplaySpacing.s20,
          vertical: compact ? ZplaySpacing.s12 : ZplaySpacing.s16,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: ZplayRadius.mdAll,
        ),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: tokens.accent, width: 2);
          }
          return BorderSide(color: tokens.hairlineStrong.color, width: 1);
        }),
      ),
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
