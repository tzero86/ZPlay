import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/hero/hero_media_resolver.dart';
import '../../services/trakt/trakt_list_source.dart';
import 'dart:math' as math;
import 'dart:ui';

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
import '../../services/metadata/metahub_art.dart';
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
import '../../widgets/common/tab_strip.dart';
import '../../widgets/common/pill_button.dart';
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

  /// The hero band, so `_revealFocused` can tell whether the focused node is
  /// inside it. See that method for why the band is one unit.
  final GlobalKey _heroKey = GlobalKey();

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

  /// Where the hero band starts inside the page's scroll viewport, or null when
  /// no hero is on screen.
  ///
  /// Asked of the carousel's render box rather than computed, because the page
  /// scrolls: an arithmetic answer from the hero's own height would be wrong as
  /// soon as anything above it moved.
  double? _heroBandTop() {
    if (!_scrollController.hasClients) return null;
    final viewportBox = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
      return null;
    }
    final heroBox = _heroKey.currentContext?.findRenderObject() as RenderBox?;
    if (heroBox == null || !heroBox.attached || !heroBox.hasSize) return null;
    return heroBox.localToGlobal(Offset.zero).dy -
        viewportBox.localToGlobal(Offset.zero).dy;
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

    // **A target inside the hero is revealed as the whole band, not as itself.**
    //
    // Revealing a CTA by its own rect scrolls until *it* clears the bar, which
    // drags everything above it - the title, the metadata, the rating badge -
    // under the bar to do it. Measured on the television: focusing "Watch Now"
    // put the band's top row at y=-12, so "2025 · 47 min" was sliced through the
    // middle of the text. The band is one unit and scrolling must move the
    // whole of it.
    final heroTop = _heroBandTop();
    final inHero = heroTop != null && targetTop >= heroTop;
    if (inHero) {
      final position = _scrollController.position;
      // Scroll *up* by exactly how far the band is intruding. `heroTop` is
      // measured in the viewport's coordinates, so a negative value means the
      // band is already above the bar's underside and the correction is
      // `topInset - heroTop`; a positive one means the band is clear and the
      // correction is zero. Signed, then clamped at 0, because scrolling up
      // past the top of the list is not a position this list can hold.
      final intrusion = topInset - heroTop;
      final next = (position.pixels - math.max(0.0, intrusion))
          .clamp(0.0, position.maxScrollExtent);
      if ((next - position.pixels).abs() > 1.0) {
        _scrollController.animateTo(
          next,
          duration: ZplayMotion.base,
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final visibleTop = topInset + ZplaySpacing.s8;
    final visibleBottom = viewportHeight - ZplaySpacing.s16;

    final isFullyVisible =
        targetTop >= visibleTop && targetBottom <= visibleBottom;
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

  List<Movie> get _visibleFeaturedMovies => pickFeatured(_visibleSections);

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

  /// Wide artwork of the slide the hero is currently showing, reported by the
  /// carousel and painted behind the rails by [_HeroBackdropBand].
  ///
  /// The hero used to scroll away and leave a flat `tokens.bg` behind the
  /// rails. This is the artwork it was showing, kept there blurred so the
  /// featured title reads as "still here" rather than gone. Null until the
  /// carousel reports, and null on a slide with no wide art - which is the same
  /// "a poster is never the background" rule the hero band itself follows.
  String? _heroBackdropUrl;

  /// The carousel reports the current slide's artwork; this is where it lands.
  ///
  /// Guarded on an actual change so a rotation between two slides sharing the
  /// same backdrop does not rebuild the page - and, more to the point, so the
  /// carousel's periodic tick never reaches this page at all when nothing about
  /// the art moved. See `_HeroCarouselState._reportBackdrop`.
  void _onHeroBackdropChanged(String? url) {
    if (!mounted || url == _heroBackdropUrl) return;
    setState(() => _heroBackdropUrl = url);
  }

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
  /// Pinned to the tail on purpose: [pickFeatured] builds the hero from the
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
          _featuredMovies = pickFeatured(_sections);

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
    // The shared strip, not a private pill row. It carries the same overlay
    // treatment as the shell's top bar - no resting fill, an accent bar under
    // the active label - and Home's own `_HomeFilterPill` had drifted back to a
    // filled block, which is the one thing that treatment exists to remove.
    // One component means the next change reaches Home for free.
    return TabStrip<_HomeFilter>(
      options: [
        for (final entry in _homeFilterLabels)
          TabStripOption<_HomeFilter>(value: entry.$1, label: entry.$2),
      ],
      selected: _selectedFilter,
      onSelected: _setFilter,
      semanticsLabel: 'Home content filter',
      height: _tabHeightFor(context),
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
          key: _heroKey,
          movies: featured,
          compact: true,
          onHeightChanged: (height) {
            if (mounted && height != _heroBandHeight) {
              setState(() => _heroBandHeight = height);
            }
          },
          onBackdropChanged: _onHeroBackdropChanged,
        )
      else
        _HeroCarousel(
          key: _heroKey,
          movies: featured,
          onHeightChanged: (height) {
            if (mounted && height != _heroBandHeight) {
              setState(() => _heroBandHeight = height);
            }
          },
          onBackdropChanged: _onHeroBackdropChanged,
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
              // Netflix's rails are landscape thumbnails under a heading, not
              // posters with a name under each one. A seven-wide row of 2:3
              // posters at ten feet is mostly artwork with unreadable captions;
              // the landscape shape puts more titles on screen at once and the
              // row's own heading is what names them.
              artwork: CardArtwork.landscape,
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
          // ── Hero backdrop band ──
          //
          // First child of the *content* stack, which is what puts it behind
          // the rails and behind the opaque control row: the bar is a sibling
          // overlay painted above this whole stack (see `_buildBody`), so a band
          // drawn in here cannot bleed through it. See `_HeroBackdropBand` for
          // why that ordering is load-bearing rather than incidental.
          _HeroBackdropBand(url: _heroBackdropUrl, chromeTop: appBarInset),
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
// Hero Backdrop Band — the hero's artwork, blurred, behind the rails.
// ─────────────────────────────────────────────────────────────────────────────

/// The featured title's backdrop, heavily blurred and dimmed, sitting behind the
/// scroll content so the hero reads as "still there" once it has scrolled away.
///
/// In the reference app the artwork does not leave with the band: the rails
/// scroll over a defocused, darkened copy of it. Home used to leave a flat
/// `tokens.bg` under the rails, which is the "the hero evaporated" look. This
/// is that band, in one place.
///
/// **Why this is painted as its own blurred image and not a [BackdropFilter].**
/// A `BackdropFilter` blurs whatever is already painted beneath it *on the frame
/// being drawn* - which here is the scrolling list, so it would re-run a
/// full-screen blur every scroll frame. That is the obvious implementation and
/// it is exactly the wrong one for a 2 GB television. Instead the band draws
/// its own small, static copy of the artwork with [ImageFiltered] and lets
/// [RepaintBoundary] keep it cached, so scrolling the rails over it costs
/// nothing: the blur is only recomputed when the *slide changes*, not when the
/// page moves.
///
/// **Why it cannot bleed through the opaque chrome.** The control row is a
/// `Positioned` overlay painted above this whole stack by `_buildBody`, so a
/// band drawn as a child here is already underneath it. The clip below is not
/// what makes that true - it is what keeps it true if the stacking is ever
/// rearranged, and it makes the guarantee readable at the call site. A band
/// that let even a sliver reach behind the bar would be the reverted bug: a
/// washed-out filter row with the rails showing through it.
///
/// The decode is deliberately tiny ([_bandCacheWidth]). The output is blurred
/// past recognition, so decoding a full-width still would spend RAM and decode
/// time on detail that is thrown away by the blur. This is the single largest
/// cost this widget would otherwise add to a memory-constrained television.
class _HeroBackdropBand extends StatelessWidget {
  /// Wide artwork of the current slide, or null when there is none.
  final String? url;

  /// Height of the opaque chrome above the scroll content (the control row and
  /// its gap). The band is clipped to start below it.
  final double chromeTop;

  const _HeroBackdropBand({required this.url, required this.chromeTop});

  /// Decode width for the blurred copy, in physical pixels.
  ///
  /// A defocused, dimmed backdrop carries no legible detail, so a small decode
  /// is indistinguishable on screen while being far cheaper to fetch, decode and
  /// hold in memory. The blur and the upscale do the rest.
  static const int _bandCacheWidth = 96;

  /// Blur sigma for the band.
  ///
  /// Heavy on purpose - this is the defocus that makes the backdrop read as
  /// "atmosphere" rather than as a competing poster. Big enough that no face or
  /// title in the still survives to compete with the rails' own text.
  static const double _blurSigma = 28;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // No wide art on this slide, or the spotlight is off: there is nothing to
    // stand in for, so the page keeps its plain background rather than guessing.
    if (url == null) return const SizedBox.shrink();

    return Positioned.fill(
      // The boundary is what keeps the blur off the scroll hot path. Without
      // one, the band and the `ListView` beside it share a composited layer, so
      // every scroll frame would re-rasterize the blurred artwork along with the
      // rails. With it, the blur is rastered once per slide and scrolling only
      // re-rasters the list.
      child: RepaintBoundary(
        child: ClipRect(
          // Painted from below the chrome down, so the artwork can never reach
          // the opaque control row. See the class doc for why this matters.
          clipper: _BelowChromeClipper(chromeTop),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The blurred artwork. `ImageFiltered` (not `BackdropFilter`) so
              // the cost is a one-off raster of a static subtree, not a
              // per-frame blur of the scrolling list. See the class doc.
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: _blurSigma,
                  sigmaY: _blurSigma,
                  // Clamp, so the blurred edge does not fade to transparent at
                  // the band's boundary and show the page background through.
                  tileMode: TileMode.clamp,
                ),
                child: CachedNetworkImage(
                  imageUrl: url!,
                  cacheManager: AppImageCache.manager,
                  memCacheWidth: _bandCacheWidth,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

              // Dim, so the rails' titles and metadata stay legible over it.
              // This is the whole point of the band - it must never compete
              // with the content scrolling over it, only sit behind it.
              //
              // Deepening toward the bottom, where the rails sit: the eye
              // expects the poster text to be against the darkest part, and the
              // top is the part nearest the control row.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.bg.withValues(alpha: 0.78),
                        tokens.bg.withValues(alpha: 0.84),
                        tokens.bg.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips a child to the area *below* [chromeTop], so a full-bleed background
/// cannot paint into the page's opaque chrome at the top.
///
/// The band is already painted under the chrome by the stack order, so this is
/// a structural guarantee rather than a visual fix: it means the band stays
/// correct even if the overlay order changes, and it documents the requirement
/// where the band is built.
class _BelowChromeClipper extends CustomClipper<Rect> {
  final double chromeTop;

  const _BelowChromeClipper(this.chromeTop);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, chromeTop, size.width, size.height - chromeTop);

  @override
  bool shouldReclip(_BelowChromeClipper oldClipper) =>
      oldClipper.chromeTop != chromeTop;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Carousel — rotates through a handful of featured titles.
// ─────────────────────────────────────────────────────────────────────────────

/// Picks the titles the hero rotates through: at most one movie per section so
/// the hero is not a wall of the same catalog, deduped by id+type, and drawn
/// from the newest end of each section.
///
/// `variation` is the hero's freshness knob. The default is a bucket of the
/// current time (see [_defaultHeroVariation]), so a rebuild re-derives the same
/// set within a session - no flicker - while the hero as a whole is not pinned
/// to one set of six titles forever. The old picker took `section.movies[0]` on
/// every call with no date ordering at all, which is how a 2012 title sat in
/// the hero on every visit.
///
/// Recency is the preference, variation is what breaks the tie it leaves: only
/// a section's three most recent titles are eligible (see [_variationWindow]),
/// and `variation` rotates the pick among them.
///
/// Top-level so the selection rules can be regression-tested; the page calls it
/// through `_visibleFeaturedMovies` and on reload.
List<Movie> pickFeatured(List<MovieSection> sections, {int? variation}) {
  final rotation = variation ?? _defaultHeroVariation(DateTime.now());
  final featured = <Movie>[];
  final seen = <String>{};

  for (final section in sections) {
    final recent = [...section.movies]..sort(_newestFirst);
    final window = recent.take(_variationWindow).toList();
    for (var step = 0; step < window.length; step++) {
      final movie = window[(rotation + step) % window.length];
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

/// How many of a section's most recent titles are hero-eligible. Small on
/// purpose: the hero must read as "what's new", and the rotation's job is to
/// vary the pick, not to excavate the back catalogue.
const int _variationWindow = 3;

/// The hero's default variation bucket: whole hours since the epoch.
///
/// Changes often enough that the hero is not pinned to one set of titles, and
/// rarely enough that consecutive rebuilds - which re-run [pickFeatured] - keep
/// showing the same titles instead of flickering between two sets.
int _defaultHeroVariation(DateTime now) =>
    now.millisecondsSinceEpoch ~/ Duration.millisecondsPerHour;

/// Newest release year first, and a year that is not a plain 4-digit prefix
/// sorts last. Never throws: catalogs carry `releaseInfo` strings like
/// `2019–2021` and `Season 3`, so the parse is a defensive prefix, not an
/// `int.parse` of the whole field.
int _newestFirst(Movie a, Movie b) {
  final yearA = _releaseYear(a);
  final yearB = _releaseYear(b);
  if (yearA == null && yearB == null) return 0;
  if (yearA == null) return 1;
  if (yearB == null) return -1;
  return yearB.compareTo(yearA);
}

int? _releaseYear(Movie movie) {
  final raw = movie.year?.trim() ?? '';
  if (raw.length < 4) return null;
  return int.tryParse(raw.substring(0, 4));
}

/// The hero's wide artwork as the ordered candidate list the slide works
/// through, or an empty list when there is no usable image at all.
///
/// The order is the hero's preference:
/// `MovieDetail.background` (the hero already fetches the detail, so the art
/// costs nothing extra), then `Movie.backdrop` (the catalog sometimes carries
/// it and [HeroMediaResolver] fills it from TMDb when it does not), then
/// [MetahubArt.backdropUrl] - the keyless metahub still, which is why a title
/// with no background anywhere else no longer leaves a black band. The metahub
/// source is gated on [MetahubArt.isUsableId]: anything that is not `tt` plus
/// digits 404s there, so the request is skipped rather than spent. `poster` -
/// the movie's own poster - is appended last (see below).
///
/// A blank or whitespace URL is not usable: catalogs carry both, and an empty
/// string would otherwise reach the image as a request for the current page.
/// Duplicates are dropped, so a `background` that is also the `backdrop` cannot
/// spend a request on the same URL twice. `poster` is gated the same way.
///
/// **The poster is the last resort against a black band.** A poster is 2:3 and
/// a hero band is roughly 16:9, so filling the band with one crops two thirds
/// of the frame away or stretches it - which is exactly why it sits after
/// every wide candidate and only ever gets a turn when they all fail. But a
/// black band is strictly worse than imperfect art: a very new title can have
/// no wide art anywhere at all (metahub 404s the ids it has not indexed yet),
/// and the band must still paint *something*. The movie's poster - whether
/// its data carries the metahub poster or the catalog's own - is therefore the
/// final candidate. Fitting it is [HeroArtwork]'s problem, not this list's.
///
/// Top-level, and the only place the order is spelled, because two places need
/// it and they must not be able to disagree: the slide paints these candidates
/// in order (see [HeroArtwork]), and the carousel reports the same list upward
/// so the page can blur the art behind the rails. A second copy would let the
/// band show art the hero is not showing.
List<String> heroWideArtworkCandidates(String? a, String? b, String imdbId,
    [String? poster]) {
  final candidates = <String>[];
  for (final url in [a, b]) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) continue;
    if (!candidates.contains(trimmed)) candidates.add(trimmed);
  }
  if (MetahubArt.isUsableId(imdbId)) {
    final fallback = MetahubArt.backdropUrl(imdbId);
    if (!candidates.contains(fallback)) candidates.add(fallback);
  }
  // The poster goes dead last: the last resort against a black band, reached
  // only when every wide candidate above has failed to load. Gated exactly
  // like the URLs above - trimmed, blanks dropped, duplicates dropped.
  final trimmedPoster = poster?.trim();
  if (trimmedPoster != null && trimmedPoster.isNotEmpty) {
    if (!candidates.contains(trimmedPoster)) candidates.add(trimmedPoster);
  }
  return candidates;
}

/// The hero band's wide artwork: the first of [candidates] that actually
/// loads, and nothing at all once they are exhausted.
///
/// A non-empty URL is not proof of an image: catalogs carry dead `background`
/// URLs, and the slide used to take the first non-empty candidate and render
/// `SizedBox.shrink()` when it failed to *load* - a dead `Movie.backdrop`
/// blanked the band and the metahub fallback never got a turn. The chain
/// therefore advances on load error, not on absence.
///
/// [onActiveUrlChanged] reports whichever candidate is actually painted (null
/// at the terminal state), so the carousel's backdrop report cannot disagree
/// with the slide - the two share [heroWideArtworkCandidates] as their single
/// source of truth and this callback as their single source of "which one
/// loaded".
///
/// Public so the fallback chain can be regression-tested; the hero slide is the
/// only production caller. [cacheManager] defaults to the shared
/// [AppImageCache.manager] and exists so tests can script load failures -
/// production always leaves it alone.
class HeroArtwork extends StatefulWidget {
  final List<String> candidates;
  final ValueChanged<String?>? onActiveUrlChanged;
  final BaseCacheManager cacheManager;

  HeroArtwork({
    super.key,
    required this.candidates,
    this.onActiveUrlChanged,
    BaseCacheManager? cacheManager,
  }) : cacheManager = cacheManager ?? AppImageCache.manager;

  @override
  State<HeroArtwork> createState() => _HeroArtworkState();
}

class _HeroArtworkState extends State<HeroArtwork> {
  /// Candidates that have already failed to load in this slide's lifetime.
  /// Kept so a rebuild does not re-request a URL the chain has given up on:
  /// the band rebuilds several times a minute while the hero rotates.
  final Set<String> _failed = {};

  /// The last value reported through [HeroArtwork.onActiveUrlChanged], so the
  /// callback is a change report rather than one call per rebuild.
  String? _lastReported;

  /// The candidate on screen: the first that has not failed, or null when
  /// every one has - the terminal state, which renders nothing and leaves the
  /// slide's scrim band to carry it.
  String? get _active {
    for (final url in widget.candidates) {
      if (!_failed.contains(url)) return url;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(covariant HeroArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new candidate list is a new question - a detail landing can add
    // `MovieDetail.background` - so the chain is retried from the top. Lists
    // compare by content: the fresh list identity every build hands in must
    // not re-request URLs that already failed.
    if (!listEquals(oldWidget.candidates, widget.candidates)) {
      _failed.clear();
      _report();
    }
  }

  /// A candidate failed to load: drop it and give the next one its turn.
  ///
  /// Deferred one frame because the error surfaces while the image is
  /// building, and `setState` is not legal there - the same reason
  /// [_HeroLogoSlotState] defers its flip to the text fallback.
  void _onLoadFailed(String url) {
    if (!mounted || !_failed.add(url)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _report();
    });
  }

  /// Publishes [_active] upward when it changed. Deferred because it is also
  /// called from `initState`/`didUpdateWidget`, where the listener may be the
  /// page's own `setState`.
  void _report() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final active = _active;
      if (active == _lastReported) return;
      _lastReported = active;
      widget.onActiveUrlChanged?.call(active);
    });
  }

  // The band draws 960 dp of a 16:9 still on the television and up to ~2x that
  // on a desktop window, and the decode is the largest one this screen ever
  // makes. 1280 physical pixels covers the TV at DPR 2 and a 1280 dp window
  // at DPR 1 without re-downloading a second copy for a bigger screen.
  static const heroCacheWidth = 1280;

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active == null) {
      // Every candidate failed: nothing behind the scrim but the page
      // background, so the band stays clean rather than a grey rectangle.
      return const SizedBox.shrink();
    }
    return CachedNetworkImage(
      imageUrl: active,
      cacheManager: widget.cacheManager,
      memCacheWidth: heroCacheWidth,
      // Full-bleed: cover fills the band edge to edge. The old code pinned a
      // 16:9 crop to the right of anything wider and left the text side flat
      // `tokens.bg` - on the television band (960x236) that was art over 44%
      // of the width and a black slab behind the title.
      //
      // The same fit serves the poster at the tail of the candidate list: a
      // 2:3 poster is centre-cropped by this cover, which is acceptable and
      // preferable to `contain`, whose letterbox bars would show the band as
      // broken in a full-bleed hero. One fit, one centred alignment, whichever
      // candidate is active - and the list order (wide art first, poster last)
      // is what keeps the crop from being the common case.
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      fadeInDuration: const Duration(milliseconds: 300),
      // Nothing behind the scrim but the page background, so a failed decode
      // leaves a clean band rather than a grey rectangle.
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) {
        _onLoadFailed(active);
        return const SizedBox.shrink();
      },
    );
  }
}

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

  /// Reports the wide artwork URL of the slide currently on screen.
  ///
  /// The page paints it behind the rails once the hero has scrolled away (see
  /// `_HeroBackdropBand`), and it has to be the *current* slide's art or the
  /// band quietly disagrees with the title that was just on screen. The
  /// carousel is the only thing that knows which slide that is and when it
  /// changes - the page cannot ask the `PageView`, and re-deriving it from
  /// `widget.movies` would miss both the enrichment and the detail fetch.
  final ValueChanged<String?>? onBackdropChanged;

  /// Draw the band at the height its content needs rather than a fraction of the
  /// canvas. Set on a television, where a 540 dp screen cannot afford a hero that
  /// is 43% of it and a usable row of posters at the same time.
  final bool compact;

  const _HeroCarousel({
    super.key,
    required this.movies,
    this.onHeightChanged,
    this.onBackdropChanged,
    this.compact = false,
  });

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final PageController _pageController = PageController();
  final Map<String, MovieDetail?> _detailsCache = {};

  /// The artwork URL each slide is actually painting (null = every candidate
  /// failed), keyed by movie id. Written by the slides themselves through
  /// `_onArtworkChanged`; read by [_currentBackdrop].
  final Map<String, String?> _artworkByMovie = {};

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
    // The resolver is what fills in a catalog's missing backdrop, so the
    // current slide's art may only exist from here.
    _reportBackdrop();
  }

  /// The wide artwork of the slide on screen, or null when there is none.
  ///
  /// Resolved over the same [heroWideArtworkCandidates] the slide paints with,
  /// so the band the page draws behind the rails is provably the art the hero
  /// is showing rather than a second opinion about it. Once the slide has
  /// reported (see [_onArtworkChanged]), its answer wins outright: a dead
  /// `MovieDetail.background` has the hero on the next candidate and the band
  /// has to follow it there. Before that first report, the primary candidate.
  String? get _currentBackdrop {
    if (_index >= _slides.length) return null;
    final movie = _slides[_index];
    if (_artworkByMovie.containsKey(movie.id)) return _artworkByMovie[movie.id];
    final candidates = heroWideArtworkCandidates(
      _detailsCache[movie.id]?.background,
      movie.backdrop,
      movie.id,
      movie.poster,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  /// A slide's painted artwork moved - a candidate failed to load and the
  /// chain advanced, or the slide settled on its answer. Remember it, and
  /// repaint the band if it was the slide on screen. A prefetch of a neighbour
  /// must never repaint it; [_reportBackdrop] de-dupes the URL either way.
  void _onArtworkChanged(String movieId, String? url) {
    if (!mounted) return;
    _artworkByMovie[movieId] = url;
    if (_index < _slides.length && _slides[_index].id == movieId) {
      _reportBackdrop();
    }
  }

  /// Reports the current slide's artwork upward, if it changed.
  ///
  /// Last-reported value is kept so this is not a `setState` per slide. The
  /// caller repaints a blurred band over the whole content area when it fires,
  /// and the hero rotates on a timer whether or not anything about the artwork
  /// moved - a bare rotation must not cost a full-area repaint.
  ///
  /// Called from every point that can change *what the current slide's art is*,
  /// not just from page changes: a detail landing upgrades `movie.backdrop` to
  /// `detail.background`, and enrichment fills either of them in after the fact.
  /// Firing only on page change would leave the band showing the catalog's art -
  /// or nothing - for the whole time a slide was on screen.
  void _reportBackdrop() {
    final next = _currentBackdrop;
    if (next == _lastReportedBackdrop) return;
    _lastReportedBackdrop = next;
    widget.onBackdropChanged?.call(next);
  }

  /// Guards [_reportBackdrop] against reporting the same URL twice.
  String? _lastReportedBackdrop;


  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _startTimer();
  }

  /// Whether two slide lists hold the same titles in the same order.
  ///
  /// Identity is the wrong test here and was the reason the hero could never
  /// leave its first slide: the page hands the carousel a freshly built list on
  /// every rebuild (`_visibleFeaturedMovies` is a getter that re-picks), so
  /// `oldWidget.movies != widget.movies` was true on every build and the update
  /// path below reset the carousel to slide 0 and cleared its caches. A slide
  /// change reports its backdrop, which setStates the page, which rebuilt it -
  /// so advancing one slide immediately snapped the hero back to the first.
  /// The titles are what the carousel is showing; two lists of the same titles
  /// are the same show.
  bool _sameSlides(List<Movie> a, List<Movie> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].type != b[i].type) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSlides(oldWidget.movies, widget.movies)) {
      _index = 0;
      _detailsCache.clear();
      _artworkByMovie.clear();
      // The new list has to land here as well as in `initState`. Assigning only
      // in `initState` meant the carousel kept showing the *first* set of
      // movies forever: `_slides` was never refreshed, so switching the filter
      // tab, reloading Home, or any rail arriving late left the hero painting
      // whatever it was first handed - or nothing at all, since
      // `_totalSlideCount` counts `_slides` and a stale empty list renders an
      // empty band.
      _slides = List<Movie>.of(widget.movies);
      if (widget.movies.isNotEmpty) _fetchDetail(widget.movies.first);
      _enrich();
      _startTimer();
      // A new list resets the carousel to slide 0, and the page's band has to
      // follow it there rather than keep showing whatever the old list led with.
      //
      // Deferred, not called here: `didUpdateWidget` runs while the parent is
      // building, and the report is the parent's `setState` - calling it
      // directly is the "setState() or markNeedsBuild() called during build"
      // assertion. Same reason the height report in `build` is a post-frame
      // callback.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The page jump is deferred alongside the report rather than run
        // inline, for the reason spelled out above: `jumpToPage` dispatches
        // `onPageChanged` synchronously, that path reports the backdrop upward,
        // and the report is the parent's `setState`. `didUpdateWidget` runs
        // while the parent is building, so jumping inline raised
        // "setState() or markNeedsBuild() called during build" whenever the
        // list genuinely changed while the hero was off its first slide -
        // switching the Home filter tab on slide 2 is the everyday route there.
        if (_pageController.hasClients) _pageController.jumpToPage(0);
        _reportBackdrop();
      });
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
        // A detail landing upgrades `movie.backdrop` to `detail.background`, so
        // the band can change without the carousel changing slide. Only the
        // slide on screen can change what the page shows, though - a prefetch
        // of a neighbour must not repaint it.
        if (_index < _slides.length && _slides[_index].id == movie.id) {
          _reportBackdrop();
        }
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
    // After the `setState` above, so it reports the slide that is now showing.
    _reportBackdrop();
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
  /// poster's name cut in half. The slide shrinks the title to fit a smaller
  /// band (see `_HeroSlideState._titleShrinkBudget`) and drops nothing else, so
  /// this is the floor for the content that stays.
  static const double _heroContentMinimum = 234;

  /// Height of a compact band, for a screen too short to spend 43% of itself on
  /// a hero.
  ///
  /// Measured from `_HeroSlide` rather than chosen: the title, the metadata
  /// line, the 48 dp pills and the 48 dp bottom inset. The full-size band asked
  /// for 421 dp on the same 540 dp
  /// screen, which is what left the rails below with 165 dp posters instead of
  /// 260.
  ///
  /// **Not re-derived when the slide got shorter.** The chips this figure paid
  /// for are now terms in the metadata line and the two buttons are a few dp
  /// smaller, so the slide's content needs less than 236 dp - and the number
  /// stays anyway, because the band is not sized by what it contains, it is
  /// sized by what it must leave for the first rail. `_firstRailReserve` is
  /// computed against this figure, and the whole point of fixing the band at
  /// 236 was that the rail below it kept its full-height poster.
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
    // so a band shorter than the title, the metadata line and the buttons stacks
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
    // canvas, and the figure it shows to - `_heroCompactHeight` - is measured
    // from the slide's own widgets. It is deliberately not re-derived from
    // whatever the slide happens to contain today: the chips it used to pay for
    // are gone and the pills are a few dp shorter, so the content needs less
    // room than 236 dp - but the band is sized by what it must leave for the
    // first rail, and the rail's own reserve is computed against this exact
    // number. See `_heroCompactHeight`.
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

    // The band behind the rails needs the current slide's artwork from the
    // first frame, and `movie.backdrop` is already on the slide by then - it
    // comes off the catalog, not off a lookup. Reporting it here means the band
    // appears with the first paint instead of waiting on the detail fetch, which
    // may never answer: a failed lookup is swallowed below, and a band that only
    // ever appeared on a successful one would be blank for a title that had
    // perfectly good artwork all along. `_reportBackdrop` is a no-op when the
    // value has not moved, so the rotation timer cannot reach the page through
    // this.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportBackdrop();
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
          // Unclipped, because the slide's artwork runs *above* the band: the
          // backdrop bleeds up under the page's opaque top chrome instead of
          // starting hard at the band's top edge. Nothing else paints outside
          // the band, so this costs no behaviour - it only stops the overflow
          // from being cut.
          clipBehavior: Clip.none,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: totalSlides,
              onPageChanged: _onPageChanged,
              // Same reason as the stack above: the slides' art bleeds up
              // under the chrome, out of the viewport's own box.
              clipBehavior: Clip.none,
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
                  onArtworkChanged: (url) => _onArtworkChanged(movie.id, url),
                );
              },
            ),

            // Slide indicator: thin horizontal segments, bottom-right.
            //
            // The centred row of round dots was the last web-carousel tell in
            // the band. Netflix's television hero marks position with short
            // horizontal dashes at the bottom right instead - the active one
            // wider and opaque, the rest dimmed - so position reads at a glance
            // from a sofa without a centred row of dots pulling the eye to the
            // middle of the picture.
            //
            // Drawn on a television but **not** in the traversal order. Each
            // segment is a `FocusableCard`, and directional traversal from the
            // hero CTA finds it before it finds the first rail, because it is
            // the nearest focusable node below the button. One DOWN jumped the
            // carousel instead of moving into content, which is precisely the
            // "focus is erratic, the highlight gets lost" report, and it is
            // invisible besides: a dash a few dp tall is not something a user
            // from a sofa is meant to find. The arrows below already carry the
            // `_isHovering` guard for the same reason; the indicator needs the
            // same treatment.
            //
            // Rotation still runs on its timer, and the poster in the hero
            // carries the artwork, so a slide is still reachable - by waiting
            // rather than by hunting for a segment.
            if (totalSlides > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: screenWidth < 600 ? ZplaySpacing.s20 : ZplaySpacing.s48,
                child: Focus(
                  // On a television the indicator is decoration, not controls.
                  //
                  // Both flags, and neither alone was enough - measured on the
                  // device. `skipTraversal` removes the row from the traversal
                  // order, so nothing moves focus *to* it, but the node stays
                  // focusable and traversal from the hero CTA landed on it
                  // anyway. Focus then sat on an invisible row of marks with
                  // no ring drawn anywhere, and every arrow key after that went
                  // nowhere a user could see. `canRequestFocus: false` is what
                  // actually closes it.
                  //
                  // Pointer devices keep both: the segments stay visible and
                  // clickable, which is what a mouse or a finger is for.
                  canRequestFocus:
                      FormFactorService.of(context) != FormFactor.television,
                  skipTraversal:
                      FormFactorService.of(context) == FormFactor.television,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: List.generate(totalSlides, (i) {
                      final active = i == _index;
                      return FocusableCard(
                        onTap: () => _goTo(i),
                        builder: (_, state) => AnimatedContainer(
                          duration: ZplayMotion.base,
                          curve: ZplayMotion.standard,
                          margin: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s2,
                          ),
                          width: active ? 28 : 12,
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: ZplayRadius.fullAll,
                            color: active
                                ? tokens.textPrimary
                                : tokens.textDisabled,
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
// Hero Meta Line — genres, year, runtime, joined by interpuncts.
// ─────────────────────────────────────────────────────────────────────────────

/// The reference app's single metadata line: `Movie · Documentary · 2026 ·
/// 1h 47m · 13+`, in that order, read left to right as one sentence.
///
/// **One string, not a row of widgets.** The terms and their `·` separators are
/// joined into one `Text`, so the spacing either side of every interpunct is a
/// property of the font and `Movie · Documentary` and `2026 · 1h 47m` carry the
/// same rhythm. A `Row` of separate terms with padding between them can only be
/// spaced by eye, and a `Wrap` of them would put a second line into a column
/// whose height is the load-bearing part of this page - see [maxLines] for why
/// that is not a trade worth making.
class _HeroMetaLine extends StatelessWidget {
  final List<String> genres;
  final String? year;
  final String? runtime;

  /// Null whenever the source has no certification to report - see the call site
  /// for why the reference's trailing `13+` is not invented here.
  final String? certification;

  /// The IMDb score, drawn as a badge in front of the line rather than as a term
  /// in it. `8.6` sitting between two interpuncts reads as a year, and the badge
  /// is what tells it apart.
  final String? leadingRating;

  const _HeroMetaLine({
    required this.genres,
    this.year,
    this.runtime,
    this.certification,
    this.leadingRating,
  });

  /// The interpunct and the two spaces either side of it, as one string.
  ///
  /// The reference's separators are tight; the spaces are what keep the line
  /// readable as words rather than as a run of glyphs.
  static const String _separator = ' · ';

  /// How many genres the line carries.
  ///
  /// Three, and the number is the one the genre chips used to show. It is also
  /// what keeps the line one line: `Action · Adventure · Thriller · Drama ·
  /// Science Fiction · 2026 · 1h 47m` at `ZplayType.body` is roughly 320 dp, and
  /// the hero's own column is capped at 680 dp - so four or more genres still
  /// fit, and the cap is there for the narrow case rather than for the wide one.
  static const int _genreCount = 3;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // The reference's own order, and the order its reading depends on: what it
    // is about, then when it came out, then how long it runs, then who may watch
    // it. Empty and whitespace-only terms are dropped rather than joined by two
    // interpuncts with nothing between them, which catalogs produce whenever a
    // field is absent.
    final terms = <String>[
      ...genres
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .take(_genreCount),
      if (year != null && year!.trim().isNotEmpty) year!.trim(),
      if (runtime != null && runtime!.trim().isNotEmpty) runtime!.trim(),
      if (certification != null && certification!.trim().isNotEmpty)
        certification!.trim(),
    ];

    final line = terms.join(_separator);

    if (line.isEmpty && (leadingRating == null || leadingRating!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final ratingBadge =
        (leadingRating == null || leadingRating!.isEmpty)
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s8,
              vertical: ZplaySpacing.s4,
            ),
            decoration: BoxDecoration(
              color: tokens.warning.withValues(alpha: ZplayOpacity.overlayHover),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: tokens.warning.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, size: 16, color: tokens.warning),
                const SizedBox(width: ZplaySpacing.s4),
                Text(
                  leadingRating!,
                  style: ZplayType.bodyNumeric
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: tokens.warning),
                ),
              ],
            ),
          );

    if (ratingBadge == null) {
      return Text(
        line,
        // One line, always. The hero's column is bottom-aligned inside a band
        // whose height `_heroCompactHeight` fixes at 236 dp, so a metadata line
        // that wrapped would push the title off the top of the band - which is
        // the exact failure `_heroContentMinimum` exists to prevent. A long line
        // is truncated instead, and the score and the year, which are the terms
        // a viewer reads first, are the ones at its head.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ZplayType.body.toStyle(color: tokens.textEmphasis),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ratingBadge,
        if (line.isNotEmpty) ...[
          const SizedBox(width: ZplaySpacing.s8),
          Flexible(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZplayType.body.toStyle(color: tokens.textEmphasis),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Slide — a single featured title within the carousel.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSlide extends StatefulWidget {
  final Movie movie;
  final MovieDetail? detail;
  final double screenWidth;

  /// Height the band actually has, so the slide can drop the parts of itself that
  /// do not fit instead of overflowing the band. See [build].
  final double bandHeight;

  /// Reports the artwork URL this slide is actually painting, or null when
  /// every candidate failed. Forwarded from [HeroArtwork]; the carousel keeps
  /// the page's blurred band in step with it.
  final ValueChanged<String?>? onArtworkChanged;

  const _HeroSlide({
    required this.movie,
    required this.detail,
    required this.screenWidth,
    required this.bandHeight,
    this.onArtworkChanged,
  });

  @override
  State<_HeroSlide> createState() => _HeroSlideState();
}

/// The slide's state, and the owner of its Ken Burns drift.
///
/// The controller belongs to the slide rather than to the carousel: one per
/// slide on screen, driving a scale on the artwork alone. [AnimatedBuilder]
/// rebuilds only its own transform subtree per tick, so the drift never
/// rebuilds the slide - let alone the page - and it is time driven rather than
/// scroll driven, so scrolling the rails past the hero costs nothing.
class _HeroSlideState extends State<_HeroSlide>
    with SingleTickerProviderStateMixin {
  /// Band height at which the title stops being the display size: the title,
  /// its gaps, the metadata line, the two buttons and the bottom inset. The
  /// name is the one thing a hero cannot lose, so on a short band it gives way
  /// in size rather than in existence. Measured from this widget, not
  /// estimated - the first version of the chrome-aware hero used a single
  /// 228 dp floor for the whole column and clipped the title.
  static const double _titleShrinkBudget = 300;

  /// Slow ambient drift on the artwork: roughly 1.0 -> 1.06 across a slide's
  /// lifetime.
  ///
  /// The span is the slide's lifetime - the auto-rotate interval
  /// (`HomePageSettings.heroRotateSeconds`) - and not a `ZplayMotion` duration:
  /// those (120/200/320 ms) are interactive feedback times, and a 6% scale at
  /// that speed is a pop, not a drift. The indicator's own transitions stay on
  /// `ZplayMotion` as they always were.
  late final AnimationController _kenBurns;

  /// The shell this page is mounted inside, or null when it is mounted alone -
  /// the cheap answer to "is Home the slot on screen", which is what pauses the
  /// drift.
  AppShellController? _shell;

  @override
  void initState() {
    super.initState();
    _kenBurns = AnimationController(
      vsync: this,
      duration: Duration(seconds: HomePageSettings.heroRotateSeconds.value),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppShellScope.of(context);
    if (!identical(controller, _shell)) {
      _shell?.current.removeListener(_onShellSlotChanged);
      _shell = controller;
      _shell?.current.addListener(_onShellSlotChanged);
    }
    _onShellSlotChanged();
  }

  /// Runs the drift only while Home is the slot on screen.
  ///
  /// The shell's `IndexedStack` already mutes tickers for hidden slots; this is
  /// the observable that actually says "nobody is looking at this", and it
  /// costs one listener. A completed drift parks at its end value rather than
  /// restarting on every rebuild.
  void _onShellSlotChanged() {
    if (!mounted) return;
    final atHome = _shell == null || _shell!.current.value == ShellSlot.home;
    if (atHome) {
      if (!_kenBurns.isAnimating && !_kenBurns.isCompleted) _kenBurns.forward();
    } else {
      _kenBurns.stop();
    }
  }

  @override
  void dispose() {
    _shell?.current.removeListener(_onShellSlotChanged);
    _kenBurns.dispose();
    super.dispose();
  }

  void _openDetails(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(box.size.center(Offset.zero));
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: widget.movie),
        tapPosition: offset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final detail = widget.detail;
    final bandHeight = widget.bandHeight;
    final isCompact = widget.screenWidth < 600;
    final tokens = context.tokens;
    final heroStyle = HomePageSettings.heroStyle.value;

    // What fits in the band, in the order the slide gives things up.
    //
    // The band is sized against the space the page actually has left after its
    // chrome and the rail below, which on a 540 dp television is 236 dp - far
    // less than this column's natural height, so a band bounded only from above
    // overflows. The column is bottom-aligned, so the title is what disappears:
    // the first version of that change shipped a hero with the poster's name
    // cut off by the top of the band.
    //
    // The name is therefore the one thing that is resized rather than dropped -
    // see `_titleShrinkBudget`. The block is title, metadata line, actions and
    // nothing else, so there is no second thing left to give up.
    final shrinkTitle = bandHeight < _titleShrinkBudget;

    // Wide artwork, in the order the hero prefers it - see
    // [heroWideArtworkCandidates]: `MovieDetail.background`, then
    // `Movie.backdrop`, then metahub's keyless still, then the poster. The
    // wide candidates first, so a title with no background anywhere else still
    // fills the band instead of leaving a black gap. [HeroArtwork] walks the
    // same list on load errors, so a dead URL is a skipped candidate rather
    // than a blank band.
    //
    // **The poster is the last resort against a black band.** A poster is 2:3
    // and a hero band is roughly 16:9, so filling the band with one crops two
    // thirds of the frame away or stretches it - which is why it is dead last
    // on the list and only ever paints when every wide candidate has failed to
    // load; and the old code did both at once, painting a blurred, 50%-dimmed
    // copy of the poster over the whole band behind the text. That is the
    // flat, washed-out look this replaces. But a black band is strictly worse
    // than imperfect art: a very new title can have no wide art anywhere, and
    // the poster is the one image left. [HeroArtwork] centre-crops it (see the
    // fit there) and the logo/title treatment still carries the text side.
    final artwork = heroWideArtworkCandidates(
      detail?.background,
      movie.backdrop,
      movie.id,
      movie.poster,
    );
    final year = detail?.year ?? movie.year;
    final rating = detail?.imdbRating;
    final genres = detail?.genres ?? const <String>[];
    final logo = detail?.logo;

    // How far the artwork runs above the band, to the top of the page box: the
    // backdrop bleeds up under the page's top chrome instead of starting hard
    // at the band's top edge. The chrome is opaque and paints over it (see
    // `_GlassAppBar` for why that bar cannot be transparent), so this is
    // structural - the art has no top edge inside the page - rather than a
    // second visible region.
    final bleedTop = _HomePageState._topInsetFor(context);

    return Stack(
      fit: StackFit.expand,
      // Unclipped, for the same reason the carousel's own stack is: the art
      // above the band is overflow by design.
      clipBehavior: Clip.none,
      children: [
        // ── Background ──
        ColoredBox(color: tokens.bg),
        if (artwork.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: -bleedTop,
            bottom: 0,
            child: ClipRect(
              child: AnimatedBuilder(
                // The drift rebuilds only this transform; the image below is
                // the `child`, so it is built once and never rebuilt per tick.
                animation: _kenBurns,
                child: HeroArtwork(
                  candidates: artwork,
                  onActiveUrlChanged: widget.onArtworkChanged,
                ),
                builder: (context, child) => Transform.scale(
                  // 1.0 -> 1.06 across the slide's lifetime. The `ClipRect`
                  // above is the crop the zoom happens inside, so the drift
                  // never paints past the art's own region.
                  scale: 1.0 + 0.06 * _kenBurns.value,
                  child: child,
                ),
              ),
            ),
          ),

        // The scrim, and the only one.
        //
        // Text sits on top of the artwork, so legibility must not depend on
        // what the picture happens to be doing underneath it. One bottom
        // gradient, transparent to `tokens.bg`: nothing over the top of the
        // picture, growing to fully opaque behind the title treatment, the
        // metadata line and the pills, where a bright still would eat them.
        //
        // The horizontal-and-foot scrim pair this replaces layered into an
        // effective ~99% over the whole left half and most of the top - the
        // artwork was the only thing carrying the hero and it was being
        // erased. One scrim, one axis, art intact.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.45, 1.0],
                colors: [
                  tokens.bg.withValues(alpha: 0.0),
                  tokens.bg.withValues(alpha: 0.60),
                  tokens.bg,
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
                  // Title / clearlogo, and the block leads with it: the logo
                  // when the detail carries one, the plain name otherwise -
                  // never both. See `_HeroTitle`.
                  _HeroTitle(
                    title: movie.name,
                    logoUrl: logo,
                    isCompact: isCompact || heroStyle == HeroStyle.minimalist,
                    // A short band gets the smaller title, so the name is never
                    // the thing that gets cut. The 46 px title is two lines of
                    // 54 dp; at 32 px it is one line of 38, which is the
                    // difference between the slide fitting and the name
                    // disappearing off the top of the band.
                    shrink: shrinkTitle,
                  ),

                  SizedBox(
                    height: heroStyle == HeroStyle.minimalist
                        ? ZplaySpacing.s8
                        : ZplaySpacing.s16,
                  ),

                  // One metadata line, in the reference's own order:
                  // `Movie · Documentary · 2026 · 1h 47m · 13+`.
                  //
                  // **A row of chips became this line.** The genres used to be
                  // pills of their own on the immersive style, and the year and
                  // runtime were loose text with a dot widget between them. That
                  // is the same facts in three visual registers, and on a 236 dp
                  // television band the chips were also the row that went first
                  // when space ran short - so the genres, the year and the runtime
                  // could each be present or absent depending on the window,
                  // which is not what a metadata line is for.
                  //
                  // One line, never wrapped: the hero's column is bottom-aligned
                  // inside a band whose height is fixed at 236 dp on a
                  // television, so a second line here pushes the title off the
                  // top of the band. See `_HeroMetaLine`.
                  _HeroMetaLine(
                    genres: genres,
                    year: year,
                    runtime: detail?.runtime,
                    // Stremio's `meta` object carries no certificate field, and
                    // the app fetches no TMDb certification
                    // (`HeroMediaResolver` asks TMDb for `videos` and nothing
                    // else), so there is nothing truthful to put here. The
                    // reference's trailing `13+` is the one term this app cannot
                    // invent without guessing at a rating it does not know.
                    certification: null,
                    // The IMDb score keeps its own badge: it is a number with a
                    // star, not a word in a sentence, and reading `8.6` between
                    // two interpuncts reads as a year.
                    leadingRating: rating,
                  ),

                  // No genre chips here any more. The genres are terms in the
                  // metadata line above, in the reference's own order, and a
                  // second register for the same words was the clearest symptom
                  // that the hero had grown three visual languages at once.
                  //
                  // That removes the chips' `_chipsBudget` too: the slide no
                  // longer has a second thing to give up, so the band budget in
                  // `_HeroCarouselState` is measured against the title, the
                  // metadata line and the pills - and nothing that is not
                  // drawn.
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
                          return PillButton(
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
                            label: 'Watch Now',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () => _openDetails(context),
                          );
                        },
                      ),
                      if (heroStyle != HeroStyle.minimalist) ...[
                        SizedBox(
                          width: isCompact ? ZplaySpacing.s8 : ZplaySpacing.s12,
                        ),
                        Builder(
                          builder: (context) {
                            return PillButton(
                              label: 'Details',
                              icon: Icons.info_outline_rounded,
                              variant: PillVariant.secondary,
                              onPressed: () => _openDetails(context),
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
                      // hero: same pill height as the two beside it, and it only
                      // appears when a key exists.
                      if (movie.trailerKey != null &&
                          movie.trailerKey!.isNotEmpty) ...[
                        SizedBox(
                          width: isCompact ? ZplaySpacing.s8 : ZplaySpacing.s12,
                        ),
                        Builder(
                          builder: (context) => _TrailerButton(
                            trailerKey: movie.trailerKey!,
                          ),
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

/// Opens a hero title's trailer in YouTube.
///
/// TMDb resolves a trailer to a YouTube video *key*, and neither Media3 nor
/// mpv can play a `youtube.com/watch` URL - there is no extractor in this app and
/// no dependency that would provide one. So the hero does not pretend to be a
/// video surface: it hands the key to YouTube, which the device already knows
/// how to play, over an intent the Android manifest already declares.
///
/// A third [PillButton] rather than a Material one, so the row is three pills
/// of one height and one shape rather than two pills beside an outlined
/// rectangle. `ActivateIntent` - which is what the remote's centre key sends -
/// comes from [FocusableCard] inside it.
class _TrailerButton extends StatelessWidget {
  final String trailerKey;

  const _TrailerButton({required this.trailerKey});

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
    return PillButton(
      label: 'Trailer',
      icon: Icons.play_circle_outline_rounded,
      variant: PillVariant.secondary,
      onPressed: () => _open(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Title — the clearlogo when it decodes, the plain title the rest of the
// time. One or the other, never both: see `_HeroLogoSlot` for why that has to
// be decided above the image widget.
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

  /// Either the title as text or the title's own logo - **never both at once.**
  ///
  /// The text is this widget's resting state and the logo replaces it. Which one
  /// is showing is owned here, because a `CachedNetworkImage` cannot express
  /// "show me the text *instead of* the image once the image is on screen": its
  /// `placeholder` is drawn *while* loading and its `errorWidget` only on a
  /// failure, so passing the text to both leaves the framework choosing, and a
  /// logo that loads leaves nothing in this widget able to take the text back
  /// off the screen.
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

    // The logo is a *slot*, filled or not - never both filled and not.
    final logoSlot = _HeroLogoSlot(
      logoUrl: logoUrl,
      fallback: titleText,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: logoUrl == null || logoUrl!.isEmpty
            ? titleText
            : logoSlot,
      ),
    );
  }
}

/// Holds the text title until a logo has actually decoded, then shows the logo
/// alone.
///
/// This exists because of how `cached_network_image` composes its slots, which is
/// the whole of the double-rendered-title report. With a `placeholder` set, the
/// package passes the placeholder to `OctoImage` as `placeholderBuilder`, and
/// `OctoImage` wires that into `Image.frameBuilder`. On the frame where the
/// image completes, octo_image's frame builder does **not** return the image
/// alone - it returns a `Stack`:
///
/// ```dart
/// return _stack(
///   _image(context, child),   // the logo, fading in
///   _placeholder(context),    // the text, fading out over fadeOutDuration
/// );
/// ```
///
/// with `fadeOutDuration` defaulting to a full second. The text is therefore
/// still in the tree, still painting at decreasing opacity, for that second
/// after the logo is already on screen - and for the whole of that second the
/// clear logo's white wordmark sits *inside* the text of the same title, which
/// is exactly the "title drawn twice, boxy outline on top of the other" that was
/// reported. The text then disappears on its own, so the fault was visible for
/// about a second and never on a static screenshot.
///
/// Nothing in that package can suppress the crossfade: `fadeOutDuration` and
/// `fadeOutCurve` are the only handles and both are the transition, not the
/// removal - `FadeWidget` collapses to `SizedBox.shrink()` on completion, not at
/// the start. So the decision is taken above the image instead: this widget
/// builds the text, and swaps it for the image once the image is ready.
class _HeroLogoSlot extends StatefulWidget {
  final String? logoUrl;

  /// Drawn for the whole of loading, and kept for good if the logo never
  /// arrives.
  final Widget fallback;

  const _HeroLogoSlot({required this.logoUrl, required this.fallback});

  @override
  State<_HeroLogoSlot> createState() => _HeroLogoSlotState();
}

class _HeroLogoSlotState extends State<_HeroLogoSlot> {
  /// Built once per URL rather than per build: the provider holds the decoded
  /// frame, so re-creating it on every rebuild of the rotating carousel would
  /// re-resolve a logo that is already in memory.
  ImageProvider? _provider;

  /// Set once the logo has failed, so a dead URL stops costing a request on
  /// every rebuild. The band rebuilds several times a minute while it rotates.
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider ??= _providerFor(widget.logoUrl);
  }

  @override
  void didUpdateWidget(covariant _HeroLogoSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) {
      _provider = _providerFor(widget.logoUrl);
      _failed = false;
    }
  }

  /// 512 physical pixels, matching the `memCacheWidth` the logo used to be
  /// fetched at: a clear logo is a wordmark, so the decode is small.
  ///
  /// `maxWidth`, not `memCacheWidth` - the widget spells the bound the second
  /// way and hands it to its own provider, which spells it the first. The
  /// provider is what this widget needs, because it is what has to be resolved
  /// *outside* the build for the text to be swapped out rather than stacked
  /// under the logo.
  static ImageProvider? _providerFor(String? url) {
    if (url == null || url.isEmpty) return null;
    return CachedNetworkImageProvider(
      url,
      cacheManager: AppImageCache.manager,
      maxWidth: 512,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null || _failed) return widget.fallback;

    return Image(
      image: provider,
      fit: BoxFit.contain,
      alignment: Alignment.bottomLeft,
      filterQuality: FilterQuality.medium,
      // The only line here that decides what is on screen. Until a frame has
      // decoded the text is the whole answer; the moment one exists the text is
      // not in the tree at all. There is no frame on which both are painted,
      // which is what `placeholder` + octo_image's `Stack` could not promise.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null && !wasSynchronouslyLoaded) return widget.fallback;
        // `wasSynchronouslyLoaded` is a disk-cache hit: the frame is already
        // decoded, so the logo replaces the text on this very frame.
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _failed) return;
          setState(() => _failed = true);
        });
        return widget.fallback;
      },
    );
  }
}
