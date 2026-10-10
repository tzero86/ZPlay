import 'package:flutter/material.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/content/content_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../shell/app_shell_scope.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/rail_skeleton.dart';
import '../../widgets/movie/movie_card.dart';
import '../../widgets/movie/movie_slider_section.dart';

/// Browse's 18+ vertical: every catalog belonging to an addon that may serve
/// adult content.
///
/// The source is [AddonManager.getAvailableDiscoverCatalogs] filtered on
/// [InstalledAddon.isAdultCapable] - the same filter Discover's own `18+`
/// pseudo-type applies, over the same addon list. A catalog `type` carries no
/// maturity flag of its own, so "adult catalog" can only mean "a catalog an
/// adult-capable addon published"; that is what this page lists, and it is why
/// Cinemeta (seeded `hybrid`) appears here alongside a strictly NSFW addon.
///
/// Which addons reach the list is still [ContentSettings.adultEnabled]'s call:
/// [AddonManager.activeCatalogAddons] excludes NSFW-only addons while the switch
/// is off. Browse hides this whole vertical in that case, so the page is only
/// ever mounted with the switch on - but it subscribes anyway and reloads on a
/// flip, because the shell keeps every slot mounted and a switch flipped in
/// Settings while this page sits hidden must not be answered by a stale list.
class AdultPage extends StatefulWidget {
  const AdultPage({super.key});

  @override
  State<AdultPage> createState() => _AdultPageState();
}

class _AdultPageState extends State<AdultPage> {
  final List<MovieSection> _sections = [];
  bool _loading = true;
  String? _error;

  /// The adult-capable catalogs, as addon + catalog pairs.
  ///
  /// Held separately from [_sections] because a catalog can fail or answer
  /// empty while others succeed: the rail list and the source list have to stay
  /// distinguishable to tell "this source had nothing" from "no sources".
  List<({InstalledAddon addon, AddonCatalog catalog})> _sources = const [];

  AppShellController? _shellController;
  ShellSlot? _lastSlot;

  /// The rails list, watched only to know when a rail heading has slid under
  /// the floating header. See [_AdultHeader].
  final ScrollController _railsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);
    _reload();
  }

  /// The shell keeps every slot mounted in one `IndexedStack`, so this page is
  /// built once at startup and never rebuilt on a slot switch. `initState` also
  /// runs before [AddonManager.initialize] has finished hydrating, so the list
  /// read there is whatever is in memory - usually nothing. Returning to Browse
  /// reloads it, the same reload cue Home and Discover use.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppShellScope.of(context);
    if (identical(controller, _shellController)) return;
    _shellController?.current.removeListener(_onSlotChanged);
    _shellController = controller;
    _lastSlot = controller?.current.value;
    controller?.current.addListener(_onSlotChanged);
  }

  void _onSlotChanged() {
    final slot = _shellController?.current.value;
    final returnedBrowse = slot == ShellSlot.browse && _lastSlot != ShellSlot.browse;
    _lastSlot = slot;
    if (!returnedBrowse || !mounted) return;
    _reload();
  }

  /// The addon list is adult-filtered at query time, so the catalog cache and
  /// the source list are both rebuilt under the new switch value.
  void _onAdultContentChanged() {
    if (!mounted) return;
    MetadataService.clearCatalogCache();
    _reload();
  }

  @override
  void dispose() {
    ContentSettings.adultEnabled.removeListener(_onAdultContentChanged);
    _shellController?.current.removeListener(_onSlotChanged);
    _railsScroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Read once, before any await: the addon getter and this filter both read
    // the switch and the addon list synchronously, and a second read after the
    // awaits could be against a list the user has since changed.
    final sources = [
      for (final entry in AddonManager.instance.getAvailableDiscoverCatalogs())
        if (entry.addon.isAdultCapable) entry,
    ];

    // Catalogs that demand a required extra before they will answer are
    // selector-only (Stremio's Performer, Tag): there is nothing to show until
    // someone picks a value, and firing the request anyway would 404. They are
    // left out of the rails and still counted in [_sources], so the empty state
    // can tell "this addon has catalogs" from "this addon has nothing to show".
    final fetchable = [
      for (final entry in sources)
        if (entry.catalog.canAutoLoadOnHome) entry,
    ];

    if (fetchable.isEmpty) {
      _apply(sources: sources, sections: const []);
      return;
    }

    // Per catalog, not per addon: one dead catalog must not take the addon's
    // other rails down with it, and one slow one must not hold the rest past the
    // timeout - the bound `AddonManager`'s own home path uses.
    final loaded = await Future.wait(
      fetchable.map((entry) async {
        try {
          final movies = await MetadataService.fetchCatalog(
            baseUrl: entry.addon.baseUrl,
            type: entry.catalog.type,
            catalogId: entry.catalog.id,
          ).timeout(const Duration(seconds: 10));
          if (movies.isEmpty) return _fetched(entry);
          return _fetched(
            entry,
            section: MovieSection(
              title: AddonManager.instance.catalogDisplayName(entry.catalog),
              subtitle: entry.addon.manifest.name,
              contentType: entry.catalog.type,
              addonBaseUrl: entry.addon.baseUrl,
              catalog: entry.catalog,
              movies: movies,
            ),
          );
        } catch (error) {
          return _fetched(entry, error: error.toString());
        }
      }),
    );

    _apply(
      sources: sources,
      sections: [
        for (final result in loaded)
          if (result.section != null) result.section!,
      ],
      // Every fetchable catalog failed. Anything less is a normal partial
      // result - one broken source must not replace the rails that did answer
      // with an error page.
      error: loaded.every((result) => result.error != null)
          ? 'No 18+ source answered. Check your connection and try again.'
          : null,
    );
  }

  /// Publishes a finished load, unless the page went away while the requests
  /// were in flight.
  ///
  /// One writer rather than three `setState` calls at the three exits above,
  /// because the shell's `IndexedStack` keeps this page mounted for the whole
  /// session: a `setState` after a dispose is the crash this guards.
  void _apply({
    required List<({InstalledAddon addon, AddonCatalog catalog})> sources,
    required List<MovieSection> sections,
    String? error,
  }) {
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _sections
        ..clear()
        ..addAll(sections);
      _error = error;
      _loading = false;
    });
  }

  /// Cards must fit the space this page actually has. Home's hero and its rails
  /// share the screen; here the header band and the first rail do, so the
  /// budget is the screen minus that band minus the rail's own header row.
  double _railHeightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final natural = MovieCardSizing.fromWidth(size.width).totalHeight;
    final ceiling = size.height -
        _headerHeight(context) -
        // The rail's own header row, then the gap under it.
        _railHeaderHeight -
        ZplaySpacing.s12;
    return natural <= ceiling ? natural : ceiling;
  }

  /// The band above the first rail: its padding and its two text lines where
  /// they are drawn.
  ///
  /// Declared as constants rather than measured from a laid-out widget because
  /// three things have to agree on this number - the rail list's top padding,
  /// the skeleton above it, and the budget a card is sized against - and a
  /// measurement would only be available after the first frame, by which point
  /// the first rail has already been laid out against the wrong value.
  double _headerHeight(BuildContext context) {
    final titleH =
        _showsTitle ? _titleHeight + ZplaySpacing.s8 + _noteHeight : 0.0;
    return titleH + ZplaySpacing.s16 + ZplaySpacing.s12;
  }

  /// Whether the band names this vertical.
  ///
  /// A television does not: the switcher band above already says which vertical
  /// is showing, and a page title costs 10% of a 540 dp screen to say it twice.
  /// A phone keeps it, because there is no rail to name the destination.
  bool get _showsTitle =>
      FormFactorService.of(context) != FormFactor.television;

  static final double _titleHeight =
      ZplayType.titleLarge.size * ZplayType.titleLarge.height;

  static final double _noteHeight =
      ZplayType.caption.size * ZplayType.caption.height;

  /// A rail's header row: one title line at `titleLarge`, then the gap under it
  /// that `MovieSliderSection` puts between the row and the cards.
  static final double _railHeaderHeight = _titleHeight + ZplaySpacing.s12;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.bg,
      // The dark canvas first, then the content, then the band: the band is a
      // `Positioned` overlay rather than a layout sibling, so it holds still
      // while the rails scroll under it and the list below pays for it as top
      // padding. It paints no fill of its own at rest - the shell's nav bar
      // rests on the canvas here - and only tints once a rail has actually slid
      // under it (see [_AdultHeader]). Browse has already spent the shell's top
      // inset on its own switcher band (`browse_page.dart` clears the top
      // padding before mounting a vertical), so this page spends nothing.
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedAmbientBackground()),
          Positioned.fill(child: _buildContent(context)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _AdultHeader(
              showTitle: _showsTitle,
              scrollController: _railsScroll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return _buildLoading(context);
    // The header band is a `Positioned` overlay, so a centred state would sit
    // underneath it. Both terminal states are padded by the band's own height
    // instead, which is also why each one stays inside its own scroll view.
    final topInset = _headerHeight(context);
    if (_error != null) {
      return _padded(
        ErrorView(
          error: _error,
          title: 'Could not load 18+ sources',
          onRetry: _reload,
        ),
        topInset,
      );
    }
    if (_sections.isEmpty) return _padded(_buildEmpty(), topInset);
    return _buildRails(context);
  }

  /// A terminal state, inset below the header band and clear of the device's
  /// own bottom inset.
  Widget _padded(Widget child, double topInset) => Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        ZplaySpacing.s24,
        topInset + ZplaySpacing.s32,
        ZplaySpacing.s24,
        ZplaySpacing.s32 + MediaQuery.paddingOf(context).bottom,
      ),
      child: child,
    ),
  );

  Widget _buildLoading(BuildContext context) {
    // A rail's worth of card-shaped placeholders rather than a spinner: the
    // geometry is already known, so the real rails land without a jump. This
    // page has no hero, so the skeleton is only the header band and two rails.
    final sizing = MovieCardSizing.fromWidth(
      MediaQuery.sizeOf(context).width,
      availableHeight: _railHeightFor(context),
    );
    return ListView(
      clipBehavior: Clip.none,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: _headerHeight(context)),
      children: [
        RailSkeleton(sizing: sizing, showHeader: true),
        RailSkeleton(sizing: sizing, count: 5),
      ],
    );
  }

  /// The body of the empty state. [_padded] owns the scroll view and the
  /// insets, so this is the content alone.
  Widget _buildEmpty() {
    final tokens = context.tokens;

    // Two empty states, not one, because they ask the user for different things:
    // no adult-capable addon at all is an install problem, while addons that
    // exist but answered with nothing is a wait problem. Collapsing them into
    // "no results" would send someone to Settings for a catalog that is already
    // configured.
    final noAddons = _sources.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          noAddons ? Icons.eighteen_up_rating_outlined : Icons.inbox_rounded,
          size: 48,
          color: tokens.textDisabled,
        ),
        const SizedBox(height: ZplaySpacing.s12),
        Text(
          noAddons
              ? 'No 18+ sources yet.'
              : '18+ sources found nothing to show.',
          style: ZplayType.title.toStyle(color: tokens.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZplaySpacing.s8),
        Text(
          noAddons
              ? 'Mark an addon as 18+ or hybrid in Settings → Addons, or install one.'
              : 'The addons this page lists answered with no titles. Try again in a moment.',
          style: ZplayType.body.toStyle(color: tokens.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZplaySpacing.s20),
        // A bare pill rather than the bordered box this used to be: the
        // affirmative action is the app's [PillButton], which already carries
        // the shared focus ring and the app's single accent. A second,
        // hand-rolled bordered control here would be a second look for the same
        // thing.
        PillButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          variant: PillVariant.secondary,
          onPressed: _reload,
        ),
      ],
    );
  }

  Widget _buildRails(BuildContext context) {
    final railHeight = _railHeightFor(context);

    return ListView.builder(
      controller: _railsScroll,
      // `Clip.none` like every other stacked page: the rails are wider than a
      // phone and are meant to bleed to the edge.
      clipBehavior: Clip.none,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // Top padding rather than a leading spacer: the header band is a
      // `Positioned` overlay above the list, so its height has to be paid here
      // or the first rail would slide under it while scrolling.
      padding: EdgeInsets.only(top: _headerHeight(context)),
      itemCount: _sections.length + 1,
      itemBuilder: (context, index) {
        if (index == _sections.length) {
          return SizedBox(
            height: ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom,
          );
        }
        final section = _sections[index];
        return MovieSliderSection(
          section: section,
          // Every rail here came from a real addon catalog, so See All opens a
          // catalog page that can actually fetch it. Home hides the control for
          // its synthetic Trakt and curated rails; there is nothing synthetic
          // here to hide it for.
          maxHeight: railHeight,
        );
      },
    );
  }
}

/// The band above the rails.
///
/// Transparent at rest, and that is the point: the shell's nav bar is painted
/// over this page and rests on whatever the page draws in the top strip, so an
/// opaque band there is the seam the shell's blend exists to remove. This page
/// is a Browse vertical, so the switcher band above it has already paid the
/// shell's inset and this band starts below it.
///
/// A television draws no title at all ([_AdultPageState._showsTitle]), so there
/// the band is pure breathing room above the first rail and never needs a fill.
/// A phone keeps the title, and the rails scroll under it; the tint below is
/// Home's answer, applied only once content has actually reached the band - at
/// offset 0 there is nothing under it, because the list's own top padding
/// reserves exactly this height. No hairline in either state.
class _AdultHeader extends StatelessWidget {
  const _AdultHeader({required this.showTitle, required this.scrollController});

  /// False on a television, and false wherever [_AdultPageState._headerHeight]
  /// was not charged for the two text lines - the band and the budget a card is
  /// sized against have to agree about what is drawn, or the rails are sized
  /// against chrome that is not on screen.
  final bool showTitle;

  /// The rails list, read only for its offset. Not attached while a terminal
  /// state is showing, which is what the `hasClients` guard covers.
  final ScrollController scrollController;

  /// How far the list travels before the tint is at full strength. Short by
  /// design: the tint exists for the moment a rail heading slides under the
  /// title, and that is a few pixels away.
  static const double _tintOverScroll = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, child) {
        final offset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;
        final t = (offset / _tintOverScroll).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.bg.withValues(alpha: 0.82 * t),
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZplaySpacing.s20,
          ZplaySpacing.s16,
          ZplaySpacing.s20,
          ZplaySpacing.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTitle) ...[
              Text(
                '18+',
                style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'Titles from the addons marked 18+ or hybrid.',
                style: ZplayType.caption.toStyle(color: tokens.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One catalog's outcome.
///
/// A record rather than a bare `MovieSection?` because an empty answer and a
/// failed one are different facts, and the page only calls the whole load
/// failed when *every* catalog failed. Collapsing them at the fetch site would
/// make a working source that returned nothing look like a broken network.
typedef _CatalogResult = ({
  ({InstalledAddon addon, AddonCatalog catalog}) source,
  MovieSection? section,
  String? error,
});

_CatalogResult _fetched(
  ({InstalledAddon addon, AddonCatalog catalog}) source, {
  MovieSection? section,
  String? error,
}) =>
    (source: source, section: section, error: error);
