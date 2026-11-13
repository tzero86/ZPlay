import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';

import '../../services/trakt/trakt_list_source.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/movie/movie.dart';
import '../../services/layout/form_factor.dart';
import '../../services/content/content_settings.dart';

import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/metadata/metahub_art.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/collections/collections_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/card_focus_expansion.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/rail_skeleton.dart';

import '../../widgets/home/continue_watching_slider.dart';
import '../../widgets/home/hero_banner.dart';
import '../../widgets/movie/movie_card.dart';
import '../../widgets/movie/movie_slider_section.dart';
import '../ai/wewatch_quiz_page.dart';
import '../calendar/tv_calendar_page.dart';
import '../../shell/app_shell_scope.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../widgets/p2p/p2p_warning_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../../services/window/window_service.dart';
import '../../services/storage/app_image_cache.dart';
import 'home_chrome_metrics.dart';

/// The ten-foot row's content height: 36 = 4 + [_televisionControlHeight] + 4.
///
/// The actions are held to it, so the row is this tall whether they are both
/// switched on or both switched off.
const double _televisionControlHeight = 28;

/// The pointer row's content height: 52 = 4 + [_pointerControlHeight] + 4.
///
/// 44 is the touch minimum, which is what the two actions present off a
/// television.
const double _pointerControlHeight = 44;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _manager = AddonManager.instance;
  final ScrollController _scrollController = ScrollController();

  /// Bumped when the *user* scrolls the page with the remote - up or down at the
  /// end of the traversal. Every popped card hears it through [PageScrollPulse]
  /// and takes its copy down at once, so the details never travel over the row
  /// the page is scrolling into view.
  ///
  /// The focus-reveal scroll is deliberately *not* announced: that scroll exists
  /// to show the card that just took focus, so its pop belongs with it, and a
  /// card that had to be scrolled to must still open. Only the key-driven scroll
  /// in [_scrollPageForKey] bumps this.
  final ValueNotifier<int> _pageScrollPulse = ValueNotifier<int>(0);

  /// How far one UP or DOWN moves the page, in logical pixels. Roughly two rail
  /// pitches, so a press carries the focus past the row it is leaving rather
  /// than nudging the page a few pixels at a time.
  static const double _keyScrollStep = 120;

  bool _loading = true;
  final List<MovieSection> _sections = [];
  String? _error;

  List<Movie> _featuredMovies = [];

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

  /// The shell controller this page is subscribed to, if it is mounted inside
  /// the shell at all, plus the slot the last notification reported. Both are
  /// needed to spot a *return* to Home rather than any other switch.
  AppShellController? _shellController;
  ShellSlot? _lastSlot;

  List<MovieSection> get _visibleSections => visibleHomeSections(
    _sections,
    hideArtless: HomePageSettings.hideArtlessRails.value,
  );

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

  /// The two controls in the page's own top row, in the row's own order.
  ///
  /// Owned here rather than by the row, because something outside the row needs
  /// to name them: the shell's bar, which hands DOWN out of its own rows into
  /// this row (`AppShellController.pageTopChrome`). The row itself is stateless
  /// and is rebuilt on every scroll tick.
  ///
  /// Keyed to the buttons that are actually on screen: a `FocusNode` whose
  /// control has been switched off in Settings is not attached, so it has no
  /// context and no rect, and the bar reads that as "there is nothing under me"
  /// rather than focusing nothing.
  final FocusNode _quizFocus = FocusNode(debugLabel: 'Home AI quiz');
  final FocusNode _calendarFocus = FocusNode(debugLabel: 'Home calendar');

  /// The page's own top row as an entry point, or null when neither of its two
  /// actions is on screen.
  ///
  /// The row's *first* control, so a hand-over lands the way the row reads and
  /// `Right` walks to the other one. The shell's bar is the only caller; see
  /// `AppShellState._handOverDownToPage`.
  FocusNode? get _chromeEntry {
    for (final node in <FocusNode>[_quizFocus, _calendarFocus]) {
      if (node.context != null) return node;
    }
    return null;
  }

  /// Publishes [_chromeEntry] for the shell's bar, and republishes whenever the
  /// row's own furniture changes: the two settings that switch it off are read
  /// through [_onSettingsChanged], so that is the one other moment the answer can
  /// move.
  void _publishChromeEntry() {
    final shell = _shellController;
    if (shell == null) return;
    final entry = _chromeEntry;
    if (identical(shell.pageTopChrome, entry)) return;
    shell.pageTopChrome = entry;
  }

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
    final viewportBox =
        _pageKey.currentContext?.findRenderObject() as RenderBox?;
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
  /// Room left above an anchored rail's cards for the rail's own title.
  static const double _tvRowTitleReserve = 64;

  /// Shortest focus target the row anchor applies to: taller than any ten-foot
  /// control (48 dp), shorter than any rail card.
  static const double _tvMinAnchoredHeight = 72;

  void _revealFocused(FocusNode? node) {
    if (!mounted || node?.context == null) return;
    if (!_scrollController.hasClients) return;
    final viewportBox =
        _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
      return;
    }

    final targetBox = node!.context!.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached || !targetBox.hasSize) return;

    final targetGlobal = targetBox.localToGlobal(Offset.zero);
    final viewportGlobal = viewportBox.localToGlobal(Offset.zero);
    final targetTop = targetGlobal.dy - viewportGlobal.dy;
    final targetBottom = targetTop + targetBox.size.height;
    final viewportHeight = viewportBox.size.height;

    // Do not scroll for whole-page or very large containers.
    if (targetBox.size.height >= viewportHeight * 0.85) return;

    final topInset = homeTopInsetFor(context);
    // **The Netflix row anchor (television).** Every move between rails lands
    // the focused row at the same height, just under the bar with room for its
    // title, instead of scrolling "just enough". "Just enough" parked the last
    // visible rail on the bottom edge, so a card that popped there had to push
    // its details panel up over the rail above - the vertical-navigation mess.
    // Anchored high, the panel always opens downward into empty space, and the
    // eye always finds the focused row in the same place.
    // Cards only: a 48 dp control (a rail's See All, a chip) keeps the minimal
    // reveal, so moving onto one never drags the page.
    //
    // Ahead of the "inside the bar" early return on purpose: moving UP lands
    // focus on a rail that is still tucked under the bar, and that is exactly
    // the rail that has to be brought down to the anchor. Only for targets in
    // this page's own scroll view - the bar's own items never get here.
    final inPageScroll =
        Scrollable.maybeOf(node.context!, axis: Axis.vertical)?.position ==
        _scrollController.position;
    if (FormFactorService.hasRemoteInput &&
        inPageScroll &&
        targetBox.size.height >= _tvMinAnchoredHeight &&
        targetBox.size.height < viewportHeight * 0.5) {
      final position = _scrollController.position;
      final anchorTop = topInset + _tvRowTitleReserve;
      final next = (position.pixels + (targetTop - anchorTop)).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((next - position.pixels).abs() > 1.0) {
        _scrollController.animateTo(
          next,
          duration: ZplayMotion.base,
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    // If the focused target is the page's own chrome (the bar or the filter row
    // above the list), do not scroll. A target *in* the list that is merely
    // scrolled under the bar - the hero's CTA after the rails were anchored -
    // is exactly what has to be revealed, so it does not take this exit.
    if (targetBottom <= topInset && !inPageScroll) return;

    // **A target inside the hero is revealed as the whole band, not as itself.**
    //
    // Revealing a CTA by its own rect scrolls until *it* clears the bar, which
    // drags everything above it - the title, the metadata, the rating badge -
    // under the bar to do it. Measured on the television: focusing "Watch Now"
    // put the band's top row at y=-12, so "2025 · 47 min" was sliced through the
    // middle of the text. The band is one unit and scrolling must move the
    // whole of it.
    final heroTop = _heroBandTop();
    // Inside the band means between its top *and its bottom*. Testing the top
    // alone counted every rail below the hero as "in the hero", so the reveal
    // never scrolled down to a rail at all.
    final heroHeight =
        (_heroKey.currentContext?.findRenderObject() as RenderBox?)
            ?.size
            .height;
    final inHero =
        heroTop != null &&
        targetTop >= heroTop &&
        (heroHeight == null || targetTop < heroTop + heroHeight);
    if (inHero) {
      final position = _scrollController.position;
      // Scroll *up* by exactly how far the band is intruding. `heroTop` is
      // measured in the viewport's coordinates, so a negative value means the
      // band is already above the bar's underside and the correction is
      // `topInset - heroTop`; a positive one means the band is clear and the
      // correction is zero. Signed, then clamped at 0, because scrolling up
      // past the top of the list is not a position this list can hold.
      final intrusion = topInset - heroTop;
      final next = (position.pixels - math.max(0.0, intrusion)).clamp(
        0.0,
        position.maxScrollExtent,
      );
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
      targetOffset = (position.pixels + delta).clamp(
        0.0,
        position.maxScrollExtent,
      );
    } else if (targetTop < visibleTop) {
      final delta = visibleTop - targetTop;
      targetOffset = (position.pixels - delta).clamp(
        0.0,
        position.maxScrollExtent,
      );
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
    final viewportBox =
        _pageKey.currentContext?.findRenderObject() as RenderBox?;
    final node = FocusManager.instance.primaryFocus;
    if (position == null ||
        viewportBox == null ||
        !viewportBox.attached ||
        !viewportBox.hasSize ||
        node?.context == null) {
      return false;
    }

    final targetBox = node!.context!.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached || !targetBox.hasSize) {
      return false;
    }

    final targetGlobal = targetBox.localToGlobal(Offset.zero);
    final viewportGlobal = viewportBox.localToGlobal(Offset.zero);
    final targetTop = targetGlobal.dy - viewportGlobal.dy;
    final targetBottom = targetTop + targetBox.size.height;
    final topInset = homeTopInsetFor(context);

    // If the focused widget is in the top bar or filter bar, never scroll here -
    // let directional traversal move focus down into the page content.
    if (targetBottom <= topInset) return false;

    final visibleTop = topInset + ZplaySpacing.s8;
    final visibleBottom = viewportBox.size.height - ZplaySpacing.s16;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (position.pixels <= 0) return false;
      // A television anchors the focused rail just under the bar (see
      // [_revealFocused]), which is inside the usual edge tolerance - so there
      // UP must be traversal, and the page only scrolls for a target actually
      // tucked under the bar.
      final upEdge = FormFactorService.hasRemoteInput
          ? topInset
          : visibleTop + _edgeTolerance;
      if (targetTop > upEdge) return false;
      // The user is scrolling the page: tell any popped card to get out of the
      // way before the page moves under it (see [_pageScrollPulse]).
      _pageScrollPulse.value++;
      _scrollController.animateTo(
        math.max(0, position.pixels - _keyScrollStep),
        duration: ZplayMotion.base,
        curve: Curves.easeOutCubic,
      );
      return true;
    }

    if (position.pixels >= position.maxScrollExtent) return false;
    if (targetBottom < visibleBottom - _edgeTolerance) return false;
    // Same announcement as the up branch: the page is about to move under a
    // popped card, so the card comes down first.
    _pageScrollPulse.value++;
    _scrollController.animateTo(
      math.min(position.maxScrollExtent, position.pixels + _keyScrollStep),
      duration: ZplayMotion.base,
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  List<Movie> get _visibleFeaturedMovies => pickFeatured(_visibleSections);

  /// The catalogue and the cached recommendations were both built under the old
  /// switch value, so both caches go immediately.
  ///
  /// The rails already on screen are left as they are rather than blanked: the
  /// cleared caches are what the next load reads, and a shelf that empties
  /// itself on a toggle is a worse answer than one that catches up.
  void _onAdultContentChanged() {
    if (!mounted) return;
    MetadataService.clearCatalogCache();
    HomePageSettings.clearRecommendationCache();
  }

  /// Curated rails are local, so a toggle takes effect without a reload: the
  /// switch only adds or drops them from the rail list.
  void _onCollectionsChanged() {
    if (!mounted) return;
    if (!_isHomeVisible) return;
    _injectCuratedSections();
  }

  /// Preferences key for the one-shot cold-start splash.
  static const String _introSeenKey = 'home_intro_seen';

  /// Whether the splash is on screen.
  ///
  /// Starts false and is set true only after the stored flag says this install
  /// has not seen it. The flag cannot be a `static` like the first version: a
  /// process restart dropped it and replayed the splash for a user who had
  /// already been through it, while a warm rebuild could never show it again.
  bool _showIntro = false;

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
  /// the art moved. See `_HeroBannerState._reportBackdrop`.
  void _onHeroBackdropChanged(String? url) {
    if (!mounted || url == _heroBackdropUrl) return;
    setState(() => _heroBackdropUrl = url);
  }

  @override
  void initState() {
    super.initState();
    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    MyListService.items.addListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.addListener(_onSettingsChanged);
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);
    CollectionsService.showOnHome.addListener(_onCollectionsChanged);
    CollectionsService.collections.addListener(_onCollectionsChanged);
    FocusManager.instance.addListener(_onPrimaryFocusChanged);

    _resolveIntro();

    _loadHome();
  }

  /// Decides whether this launch gets the splash, then starts or skips it.
  ///
  /// The stored flag is written when the splash is *shown*, not when it is
  /// dismissed: an app killed mid-splash has still shown it, and a flag written
  /// on dismiss would replay the splash on the next launch.
  ///
  /// Failing to read the flag takes the no-splash route. A splash on every
  /// launch is the bug this flag exists to fix, so the uncertain path must not
  /// be the one that shows it; a failed *write* only costs one extra splash,
  /// which is the behaviour without the flag at all.
  Future<void> _resolveIntro() async {
    SharedPreferences? prefs;
    var seen = true;
    try {
      prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_introSeenKey) ?? false;
    } catch (e) {
      debugPrint('[HomePage] intro flag read failed: $e');
    }

    if (!mounted) return;

    if (seen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
      return;
    }

    // Not awaited: the splash must not wait on a disk write.
    unawaited(prefs?.setBool(_introSeenKey, true));

    setState(() => _showIntro = true);
    _playIntro();
  }

  static bool _hasRunStartupDialogs = false;

  bool get _isHomeVisible {
    final controller = _shellController;
    return controller == null || controller.current.value == ShellSlot.home;
  }

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
    if (returnedHome && mounted) {
      _loadHome();
    }
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
    final chromeAbove = homeTopInsetFor(context);

    // A full card, at the width this screen gives it.
    final natural = MovieCardSizing.fromWidth(size.width).totalHeight;
    if (homeIsTelevision(context)) {
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
    final remaining =
        size.height - chromeAbove - heroHeight - 38 - ZplaySpacing.s12;
    return remaining.clamp(120.0, double.infinity);
  }

  Future<void> _runStartupDialogs() async {
    if (_hasRunStartupDialogs || !mounted) return;
    _hasRunStartupDialogs = true;

    await _checkP2pWarning();
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
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    MyListService.items.removeListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.removeListener(_onSettingsChanged);
    ContentSettings.adultEnabled.removeListener(_onAdultContentChanged);
    CollectionsService.showOnHome.removeListener(_onCollectionsChanged);
    CollectionsService.collections.removeListener(_onCollectionsChanged);
    _shellController?.current.removeListener(_onSlotChanged);
    // Cleared before the nodes die, because the bar's hand-over reads this at
    // key time and the shell outlives this page: a handle left behind would be a
    // disposed node the remote could be sent to.
    _shellController?.pageTopChrome = null;
    _quizFocus.dispose();
    _calendarFocus.dispose();
    _scrollController.dispose();
    _pageScrollPulse.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (!_isHomeVisible) return;
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
    } catch (e) {
      debugPrint('[HomePage] Trakt public sections failed: $e');
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

  /// Dismisses the splash the moment it is tapped.
  ///
  /// The pending [_playIntro] cannot be cancelled, but it can be made inert: it
  /// re-checks [_showIntro] after every wait, so a skip wins over the timer
  /// rather than the timer re-showing or re-running anything. Startup dialogs
  /// are idempotent through [_hasRunStartupDialogs], so whichever of the two
  /// finishes first runs them once.
  void _skipIntro() {
    if (!_showIntro) return;
    setState(() => _showIntro = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupDialogs();
    });
  }

  Future<void> _playIntro() async {
    // Show intro for 1.8 seconds so it feels fast and allows full shader pre-warming
    await Future.delayed(const Duration(milliseconds: 1800));

    // If still loading critical data, wait a bit longer (up to a timeout or until ready)
    while (_showIntro && _loading && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // A tap may have dismissed the splash while those waits were running. The
    // late completion must then be a no-op, not a second dismissal.
    if (!mounted || !_showIntro) return;

    setState(() => _showIntro = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupDialogs();
    });
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
        traktPublic
            .then((_) {
              if (mounted) _injectTraktPublicSections();
            })
            .catchError((Object error) {
              debugPrint('[HomePage] Trakt public sections failed: $error');
            }),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// The height of the row's own content, and the ceiling the row's icon buttons
  /// are held to so they cannot set the chrome's height by themselves.
  static double _controlHeightFor(BuildContext context) =>
      homeIsTelevision(context)
      ? _televisionControlHeight
      : _pointerControlHeight;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final tokens = context.tokens;
    final visibleSections = _visibleSections;

    final featured = _visibleFeaturedMovies;
    final hasContent = visibleSections.isNotEmpty;

    // Whether this page is being drawn for a television. The hero is a band on a
    // pointer and an overlay here, and the rail budget in `_railHeightFor`
    // branches on the same answer - the two have to agree or the layout and its
    // arithmetic drift apart, which is how the posters came to be 37% smaller
    // than the design intended.
    final television = homeIsTelevision(context);

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
    // `homeTopInsetFor` is the page's chrome plus the band the shell's nav bar
    // occupies: the bar is painted over this page rather than stacked above it,
    // so the shell hands the page the bar's own height as `padding.top` instead
    // of laying the page out below it. Charging that band here is what keeps
    // every pixel of the page where it was, and what lets the hero's bleed reach
    // the window's top edge under the bar.
    final appBarInset = homeTopInsetFor(context);

    final slots = <Widget>[
      // When the tabs are *not* in the control row - a narrow pointer window -
      // they are the head of the scroll content, directly under it. This is
      // content, not chrome, so it scrolls away, which is correct: it is a
      // control, and a control that floats over the content would cover the
      // first rail. The row's own inset above it is the scroll view's padding,
      // so nothing is ever hidden behind the row.
      if (!HomePageSettings.enableSpotlight.value)
        // Nothing to reserve here: the control row's inset is the padding below.
        // This used to add `topPadding + 76` as a second leading spacer, which
        // double-counted the bar and pushed the first rail a whole bar down.
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
        HeroBanner(
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
        HeroBanner(
          key: _heroKey,
          movies: featured,
          onHeightChanged: (height) {
            if (mounted && height != _heroBandHeight) {
              setState(() => _heroBandHeight = height);
            }
          },
          onBackdropChanged: _onHeroBackdropChanged,
        ),
      // One feed, so the rail is everything watched. The type filter existed to
      // match the All/Movies/Series/Anime tabs, and that split is Browse's now.
      const ContinueWatchingSlider(title: 'Continue Watching'),
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
              _loading
                  // Saying "nothing to show" while the addons are still
                  // answering is a lie the user can see through: the shelf
                  // fills in seconds later. Naming the wait tells them to
                  // leave it alone.
                  ? 'Loading your library...'
                  : 'Nothing on the shelf yet. Add an addon in Settings, or pull down to refresh.',
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
              // A pointer rail is a poster with its name and metadata, not an
              // anonymous thumbnail. Landscape stays the television shape: at
              // ten feet the row's heading identifies the category and the
              // extra cards across matter more than a caption nobody can read.
              // On desktop and mobile the viewer scans a rail with a mouse or
              // thumb, so removing the poster's text block removed the only
              // way to tell one title from another without opening it.
              artwork: FormFactorService.of(context) == FormFactor.television
                  ? CardArtwork.landscape
                  : CardArtwork.poster,
              showCalendarButton:
                  calEnabled && i >= (visibleSections.length - 2),
              // A Trakt public rail's catalog is synthetic - `trakt_trending` is
              // not an addon endpoint, so See All would open a CatalogPage that
              // asks Cinemeta for a catalog that does not exist. Curated rails
              // are synthetic for the same reason.
              showSeeAll:
                  !visibleSections[i].catalog.id.startsWith('curated_') &&
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
              child: PageScrollPulse(
                notifier: _pageScrollPulse,
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

    // The shell's bar hands DOWN into this page's own top row through the handle
    // published here. Deferred one frame because the row it names is built by
    // this very frame - a `FocusNode` has no context until its control has been
    // laid out - and idempotent, so the several rebuilds a slide rotation causes
    // cost the shell nothing. See `_chromeEntry`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishChromeEntry();
    });

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
      // ── Immersive nav: transparent over the hero, tinted past a nudge ──
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _GlassAppBar(
          topPadding: topPadding,
          scrollController: _scrollController,
          quizFocus: _quizFocus,
          calendarFocus: _calendarFocus,
        ),
      ),

      // ── Custom Scroll Track ──
      //
      // Gated on the input, not on the width. The width test alone was read as
      // "desktop only", and a 960 dp television is wider than the 800 it asked
      // for - so the ten-foot canvas was handed a 55 x 412 dp grab pill that
      // covered the rail cards and their See All links from the moment the page
      // moved until a second or so after it stopped. There is no pointer on a
      // television to grab it with, and the remote has its own way to scroll:
      // the D-pad moves focus and `_revealFocused` follows it. The width stays
      // as the *room* test and not the input test: the pill is 412 dp tall, so
      // a window narrower than this has nowhere to put it on any input.
      if (!FormFactorService.hasRemoteInput &&
          MediaQuery.sizeOf(context).width > 800)
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

    return GestureDetector(
      // Stable handle for the splash: it is the only full-screen overlay on
      // Home, and a test that taps "the page" must be able to name it.
      key: const Key('home-intro'),
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _skipIntro,
      child: Semantics(
        // One node for the whole splash: the logo and wordmark are decorative,
        // and the only action is the skip. Without `container` the label would
        // annotate the child nodes instead of being announced as the button.
        container: true,
        excludeSemantics: true,
        button: true,
        label: 'Skip intro',
        onTap: _skipIntro,
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
  /// The chrome above the page's own row, as the shell reports it: its nav bar's
  /// height on tablet, desktop and television - the bar is painted over this
  /// page, so the page pays for its band - and the status bar strip on a phone,
  /// where the bar is at the foot. The row is offset by this plus its own 4 dp,
  /// and the box this widget paints is as tall as both.
  final double topPadding;
  final ScrollController? scrollController;

  /// The page's own focus nodes for its two actions, in the row's order.
  ///
  /// Supplied by the page rather than owned here: the row is rebuilt on every
  /// scroll tick, and something outside it has to name these controls - the
  /// shell's DOWN out of its nav bar. See `_HomePageState._chromeEntry`.
  final FocusNode quizFocus;
  final FocusNode calendarFocus;

  const _GlassAppBar({
    required this.topPadding,
    required this.quizFocus,
    required this.calendarFocus,
    this.scrollController,
  });

  /// Scroll distance over which the nav fades from invisible-over-art to a
  /// calm tinted bar. Small on purpose: one nudge past the top should settle
  /// the chrome before the first rail reaches it.
  ///
  /// The shell's nav bar uses the same 32 dp to settle its own fill
  /// (`_AppShellState._navBlendThreshold`), reading this page's scroll from its
  /// scroll notifications, so the bar across the top of the window settles with
  /// the row inside the page rather than one trailing the other.
  static const double _scrollThreshold = 32.0;

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
    final rowHeight = _HomePageState._controlHeightFor(context);
    final ButtonStyle rowButton = IconButton.styleFrom(
      // 44 dp square on a pointer - Material 3's own visual default is 40, and
      // 44 is the touch minimum - and the 32 dp the ten-foot row has always used
      // there, where a 48 dp box would set the chrome's height by itself.
      minimumSize: Size(television ? 32 : 44, rowHeight),
      maximumSize: Size(television ? 32 : 44, rowHeight),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    // Icon shadows keep the glyphs legible over bright art at offset 0, where
    // there is no tint behind them. Constant rather than scroll-driven: harmless
    // over the tinted bar, and one less thing rebuilding per scroll pixel.
    // The 0.6 black under a 0.9-white glyph clears WCAG AA over art.
    const iconShadow = Shadow(
      color: Color(0x99000000),
      blurRadius: 6,
      offset: Offset(0, 1),
    );
    // The row's focus indicator, around the node the page owns.
    //
    // So that the shell's bar can hand DOWN into this row and a remote can see
    // where it landed. The
    // ring is drawn over the button rather than around it, so the row is the same
    // height and the buttons are in the same places with the ring on them - the
    // app's one focus indicator, and without it this row was the only control on
    // the screen that a remote could stand on with nothing to show for it.
    //
    // `AnimatedBuilder` rather than a `ListenableBuilder` so the button itself is
    // held as the child: a focus change repaints the ring and does not rebuild
    // the button beside it.
    Widget withRing(FocusNode node, Widget button) => AnimatedBuilder(
      animation: node,
      child: button,
      builder: (context, child) => CardFocusRing(
        focused: node.hasFocus,
        // The top bar's own rows are pills at this size, and this row shares
        // the band with them.
        radius: ZplayRadius.fullAll,
        child: child!,
      ),
    );
    Widget row() {
      return Row(
        children: [
          // A phone has no shell top bar to carry the brand - the shell draws a
          // bottom bar there - so Home wears the mark itself. Every other form
          // factor already has it in the shell's leading corner, and drawing it
          // here too would put two ZPlays in one screen.
          if (FormFactorService.of(context) == FormFactor.compact) ...[
            _HomeBrand(tokens: tokens),
            const SizedBox(width: ZplaySpacing.s8),
          ],
          // The page's two actions sit at the row's end, and the free space
          // falls before them. The All/Movies/Series/Anime pills used to lead
          // this row; Browse owns that split now, so Home is one feed and the
          // row keeps only what is the page's.
          const Spacer(),
          // AI Taste Profile Quiz
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableAiQuiz,
            builder: (context, aiQuizEnabled, _) {
              if (!aiQuizEnabled) return const SizedBox.shrink();
              return withRing(
                quizFocus,
                IconButton(
                  focusNode: quizFocus,
                  icon: const Icon(
                    Icons.auto_awesome_rounded,
                    shadows: [iconShadow],
                  ),
                  color: tokens.accent,
                  iconSize: television ? 18 : 22,
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
                ),
              );
            },
          ),
          // TV Shows Airing Calendar
          ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableCalendar,
            builder: (context, calEnabled, _) {
              if (!calEnabled) return const SizedBox.shrink();
              return withRing(
                calendarFocus,
                IconButton(
                  focusNode: calendarFocus,
                  icon: const Icon(
                    Icons.calendar_month_rounded,
                    shadows: [iconShadow],
                  ),
                  color: tokens.textEmphasis,
                  iconSize: television ? 18 : 22,
                  tooltip: 'TV Airing Calendar',
                  style: rowButton,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TvCalendarPage()),
                    );
                  },
                ),
              );
            },
          ),
        ],
      );
    }

    // Transparent at offset 0 so the hero reads full-bleed; tinted past a
    // nudge so a rail heading can never draw through the actions unreadably.
    // The old opaque bar fixed the bleed by paying chrome on every frame; the
    // scroll-driven tint fixes it only where it happens - everywhere but the
    // top. Height is still `homeAppBarHeightFor + topPadding` exactly, so the
    // scroll view's top padding keeps reserving it and nothing hides behind it
    // at any offset. Scroll-driven, not animated, so reduced-motion users get
    // no parallax or fade choreography - just the offset-mapped tint.
    Widget chrome(double t) {
      // No row, no band. The scrim and the tint are chrome for the control row,
      // so with both of its actions off they were painting an empty bar across
      // the top of Home. Nothing is laid out either: the band's height is
      // charged to the page through `homeTopInsetFor`, which now returns the same
      // answer, so the hero bleeds to the window's top edge.
      if (!homeHasControlRow(context)) {
        return const SizedBox.shrink();
      }
      final barHeight = homeAppBarHeightFor(context) + topPadding;
      final tint = tokens.bg.withValues(alpha: 0.82 * t);
      final hairline = tokens.hairline.color.withValues(alpha: t);
      final content = Container(
        padding: EdgeInsets.only(
          // 4 + the row's own content + 4 keeps `homeAppBarHeightFor` exact.
          top: topPadding + ZplaySpacing.s4,
          bottom: ZplaySpacing.s4,
          left: ZplaySpacing.s20,
          right: ZplaySpacing.s8,
        ),
        // The row is pinned to its own height rather than left to wrap, so the
        // chrome is `homeAppBarHeightFor` whatever the actions are gated to: with
        // the quiz and the calendar both switched off there would otherwise be
        // no child left to give the row a height, and the scroll inset would
        // reserve space for a row that is not there.
        height: barHeight,
        decoration: BoxDecoration(color: tint),
        // The hairline is painted, not laid out. A border on `decoration`
        // subtracts its own width from the child's box, so putting it there
        // shrank the 28 dp row to 27 and moved every measurement beneath it up
        // a pixel - which is exactly what `tv_chrome_density_test` caught. This
        // is how the bar carried it before the rewrite.
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairline, width: 1.0)),
        ),
        child: row(),
      );
      if (t <= 0.001) {
        // Top of the page: no tint, no hairline - just a top scrim behind the
        // actions so they read over bright art, fading to nothing by the row's
        // underside so the hero below meets the chrome without a seam.
        return RepaintBoundary(
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: barHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.38),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              content,
            ],
          ),
        );
      }
      // Scrolled: the tint above carries the legibility, and a small
      // strip-local blur settles it into the art. Strip-local, not the
      // full-screen `BackdropFilter` the backdrop band's doc warns about: the
      // blur region is this row only, and it is skipped entirely at offset 0.
      // Where `GlassSettings` wraps the overlay stack in `LiquidGlassView`,
      // that pass owns the refraction and this tint is its base.
      return RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: content,
          ),
        ),
      );
    }

    final controller = scrollController;
    if (controller == null) return chrome(0);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final offset = controller.hasClients ? controller.offset : 0.0;
        final t = (offset / _scrollThreshold).clamp(0.0, 1.0);
        return chrome(t);
      },
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
                  // Matches the hero's own wide-art crop: the band is the same
                  // still defocused, so a different alignment would show the
                  // rails a different slice of the picture than the hero.
                  alignment: Alignment.topCenter,
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

/// The rails Home actually shows: what the addons returned, minus the rows that
/// cannot be read.
///
/// [hideArtless] is the setting (on by default) and the rule it gates is a fact
/// about the layout, not a taste about content. Home's rails are landscape
/// tiles, and a landscape tile carries **no name text** - the row's heading is
/// the only label and the picture is the identification (see [CardArtwork]). A
/// tile that resolves no art is therefore not a card with an empty placeholder
/// in it; it is an empty rectangle, and a rail of them is a strip the user
/// cannot read, name or choose between. That is what a Debrid addon's torrent
/// catalogue looks like on Home - a row of blanks above the shelf you can
/// actually use.
///
/// The test is per rail and deliberately generous: **one** item that can draw
/// keeps the whole row. Art is the item's own poster, its own backdrop, or the
/// keyless metahub still its IMDb id names - which is where most catalogue items
/// get their picture from - so a normal addon rail, whose items carry `tt` ids,
/// is never dropped for art it can fall back on.
///
/// Empty sections are dropped too, which the caller used to do for itself.
List<MovieSection> visibleHomeSections(
  List<MovieSection> sections, {
  required bool hideArtless,
}) {
  final visible = <MovieSection>[];
  for (final section in sections) {
    if (section.movies.isEmpty) continue;
    if (hideArtless && !_railCanDrawArt(section)) continue;
    visible.add(section);
  }
  return visible;
}

/// Whether anything in [section] can draw. See [visibleHomeSections].
bool _railCanDrawArt(MovieSection section) {
  for (final movie in section.movies) {
    if (_canDrawArt(movie)) return true;
  }
  return false;
}

/// Whether [movie] resolves to a picture at all: its own poster, its own
/// backdrop, or the metahub still its id names.
bool _canDrawArt(Movie movie) {
  final poster = movie.poster;
  if (poster != null && poster.trim().isNotEmpty) return true;
  final backdrop = movie.backdrop;
  if (backdrop != null && backdrop.trim().isNotEmpty) return true;
  return MetahubArt.isUsableId(movie.id);
}

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

/// The ZPlay mark, for the one form factor whose shell bar cannot carry it.
///
/// The shell's top bar puts the brand in its leading corner on tablet, desktop
/// and television. A phone gets the shell's *bottom* bar instead, so Home's own
/// control row is where the brand belongs there - the same plate the shell
/// draws, with the name beside it, because a mark alone on a page whose name
/// the user is looking at for the first time says less than it could.
///
/// Not a control: the bottom bar's Home destination is already the way home, so
/// this adds no focus target of its own.
class _HomeBrand extends StatelessWidget {
  const _HomeBrand({required this.tokens});

  final ZplayTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accentSubtle,
        borderRadius: ZplayRadius.xsAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s8,
          vertical: ZplaySpacing.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZplayLogo(size: ZplaySpacing.s24),
            const SizedBox(width: ZplaySpacing.s8),
            Text(
              'ZPlay',
              style: ZplayType.title.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
