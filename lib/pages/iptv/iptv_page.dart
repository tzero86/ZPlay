import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/iptv/iptv_storage.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../shell/app_shell_scope.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../services/layout/form_factor.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/iptv/iptv_hero_carousel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/iptv/iptv_slider_section.dart';
import '../multinutz/multinutz_page.dart';
import 'iptv_channel_sheet.dart';
import 'iptv_player_page.dart';
import 'iptv_portals_modal.dart';
import 'iptv_search_page.dart';
import 'widgets/live_guide_band.dart';
import '../../services/storage/app_image_cache.dart';

class IptvPage extends StatefulWidget {
  const IptvPage({super.key});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  final IptvController _ctrl = IptvController.instance;
  final ScrollController _scrollController = ScrollController();

  List<HardcodedChannel> _featured = [];
  List<HardcodedChannel> _espnAndCollege = [];
  List<HardcodedChannel> _usSports = [];
  List<HardcodedChannel> _soccer = [];
  List<HardcodedChannel> _combat = [];
  List<HardcodedChannel> _racing = [];
  List<HardcodedChannel> _movies = [];
  List<HardcodedChannel> _news = [];
  List<HardcodedChannel> _arabic = [];
  List<HardcodedChannel> _discovery = [];
  List<HardcodedChannel> _kids = [];

  List<QuickChannel> _quickChannels = [];

  // (No return-slot state: the settings excursion below goes through the
  // shell, and the shell's own back guard returns to the previous slot.)
  @override
  void initState() {
    super.initState();
    DiscordRpcService.instance.setWatchingLiveTv(channelName: 'Live TV');
    IptvSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    _ctrl.init();
    _loadQuickChannels();
    _loadSections();
  }

  Future<void> _loadQuickChannels() async {
    final channels = await IptvQuickChannelStore.load();
    setState(() => _quickChannels = channels);
  }

  Future<void> _addQuickChannel(QuickChannel channel) async {
    await IptvQuickChannelStore.add(channel);
    setState(() => _quickChannels.add(channel));
  }

  Future<void> _removeQuickChannel(String id) async {
    await IptvQuickChannelStore.remove(id);
    setState(() => _quickChannels.removeWhere((c) => c.id == id));
  }

  void _showAddQuickChannelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddQuickChannelDialog(onAdd: _addQuickChannel),
    );
  }

  @override
  void dispose() {
    IptvSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _loadSections() {
    _featured = [
      HardcodedChannels.byId('espn_plus') ?? HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('ncaa_cbb') ?? HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('ufc')!,
      HardcodedChannels.byId('bein_sports')!,
      HardcodedChannels.byId('champions_league')!,
      HardcodedChannels.byId('f1')!,
      HardcodedChannels.byId('nba')!,
      HardcodedChannels.byId('hbo')!,
    ];
    _espnAndCollege = [
      HardcodedChannels.byId('espn_plus')!,
      HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('espn2')!,
      HardcodedChannels.byId('espnu')!,
      HardcodedChannels.byId('ncaa_cbb')!,
      HardcodedChannels.byId('ncaa_mens_cbb')!,
      HardcodedChannels.byId('ncaa_womens_cbb')!,
      HardcodedChannels.byId('sec_network')!,
      HardcodedChannels.byId('acc_network')!,
      HardcodedChannels.byId('big_ten_network')!,
      HardcodedChannels.byId('pac_12_network')!,
      HardcodedChannels.byId('espnews')!,
      HardcodedChannels.byId('espn_deportes')!,
      HardcodedChannels.byId('longhorn_network')!,
      HardcodedChannels.byId('bally_sports')!,
    ];
    _usSports = [
      HardcodedChannels.byId('nba')!,
      HardcodedChannels.byId('nfl')!,
      HardcodedChannels.byId('nfl_redzone')!,
      HardcodedChannels.byId('mlb')!,
      HardcodedChannels.byId('nhl')!,
      HardcodedChannels.byId('fox_sports')!,
      HardcodedChannels.byId('cbs_sports')!,
      HardcodedChannels.byId('nbc_sports')!,
      HardcodedChannels.byId('dazn')!,
      HardcodedChannels.byId('eurosport')!,
    ];
    _soccer = HardcodedChannels.byCategory('Soccer');
    _combat = HardcodedChannels.byCategory('Combat');
    _racing = HardcodedChannels.byCategory('Racing');
    _movies = HardcodedChannels.byCategory('Movies');
    _news = HardcodedChannels.byCategory('News');
    _arabic = HardcodedChannels.byCategory('Arabic');
    _discovery = HardcodedChannels.byCategory('Discovery');
    _kids = HardcodedChannels.byCategory('Kids');
  }

  /// The category the guide replaces. Named rather than inlined so the mapping
  /// between the guide and the user's category list is one place to look.
  static const String _guideCategory = 'Premier Live Broadcasts';

  Widget _buildLiveGuide(String title, List<HardcodedChannel> channels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ZplaySpacing.s8),
        SectionHeader(
          title: title,
          subtitle: 'Channel list and programme schedule',
          count: channels.length,
        ),
        const SizedBox(height: ZplaySpacing.s12),
        LiveGuideBand(
          channels: channels,
          onWatchLive: _watchChannelNow,
          onFindStreams: _openChannel,
        ),
        const SizedBox(height: ZplaySpacing.s24),
      ],
    );
  }

  void _openChannel(HardcodedChannel channel) {
    IptvChannelSheet.show(context, channel);
  }

  void _watchChannelNow(HardcodedChannel channel) async {
    // If we have saved hits, launch immediately, otherwise open sheet to scan
    final results = _ctrl.channelResults;
    if (_ctrl.activeHardcoded?.id == channel.id && results.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IptvPlayerPage(
            channel: channel,
            hits: results,
            initialHitIndex: 0,
          ),
        ),
      );
    } else {
      IptvChannelSheet.show(context, channel);
    }
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
        page: IptvSearchPage(quickChannels: _quickChannels),
        tapPosition: tapPosition,
      ),
    );
  }

  void _navigateToMultiStreams(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(page: const MultiNutzPage(), tapPosition: tapPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spotlightEnabled = IptvSettings.enableSpotlight.value;
    final visibleCategories = IptvSettings.visibleCategories.value;

    final Map<String, (String, List<HardcodedChannel>)> categoryMap = {
      'Premier Live Broadcasts': (
        'Top worldwide sporting events and championship channels',
        _featured,
      ),
      'ESPN & College Basketball (NCAA)': (
        'ESPN+, ESPN, ESPN2, ESPNU, NCAA Men\'s & Women\'s CBB, SEC & ACC',
        _espnAndCollege,
      ),
      'US Major Leagues & Sports': (
        'NBA TV, NFL Network, RedZone, MLB, NHL, Fox Sports & CBS Sports',
        _usSports,
      ),
      'Global Football & Soccer': (
        'UEFA Champions League, Premier League, beIN Sports, La Liga & Serie A',
        _soccer,
      ),
      'Combat & Martial Arts': (
        'UFC Fight Pass, WWE, AEW, World Boxing & PPV',
        _combat,
      ),
      'Motorsport & Racing': (
        'Formula 1, MotoGP, NASCAR Cup, IndyCar & Rally WRC',
        _racing,
      ),
      'Movies & Premium Networks': (
        'HBO, Showtime, Starz, Cinemax, Paramount & AMC',
        _movies,
      ),
      '24/7 Global News Networks': (
        'CNN, BBC World, Fox News, Sky News, Al Jazeera & Bloomberg',
        _news,
      ),
      'Arabic & Regional Hub': (
        'MBC, Rotana, OSN, Abu Dhabi TV, Dubai TV & Al Arabiya',
        _arabic,
      ),
      'Discovery & Documentaries': (
        'National Geographic, Discovery Channel, History & Animal Planet',
        _discovery,
      ),
      'Kids & Family': (
        'Cartoon Network, Disney Channel, Nickelodeon & Spacetoon',
        _kids,
      ),
      'US Region': (
        'ABC News Live, CBS News 24/7, NBC News Now, Weather Channel & more',
        HardcodedChannels.byCategory('US'),
      ),
      'UK Region': (
        'BBC One UK, ITV News, Sky News UK, Channel 4 & more',
        HardcodedChannels.byCategory('UK'),
      ),
      'Canada Region': (
        'CBC News, CTV News, TSN Sportsnet, Crave & Global News',
        HardcodedChannels.byCategory('CA'),
      ),
      'Bay Area': (
        'KTVU Fox 2, KPIX 5 CBS, KGO 7 ABC, KRON 4 & NBC Bay Area',
        HardcodedChannels.byCategory('Bay Area'),
      ),
      'International Sports': (
        'Willow Cricket, Fox Soccer Plus, GolTV, TUDN, Viaplay & more',
        HardcodedChannels.byCategory('Int. Sports'),
      ),
    };

    final listContent = RefreshIndicator(
      color: tokens.accent,
      backgroundColor: tokens.surface,
      onRefresh: () async {
        _ctrl.scrape();
      },
      child: ListView(
        controller: _scrollController,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          // Page controls first, in the scroll flow: the shell's top bar and
          // the Browse band already name this destination, so this strip is
          // content under shared chrome, not a second header. In-flow is what
          // keeps D-pad UP geometric: content, then strip, then the Browse
          // pills, then the shared menu, with no scope boundary anywhere in
          // between and no overlay to leave unfocusable.
          _IptvGlassAppBar(
            onSearchTap: _navigateToSearch,
            onSettingsTap: _navigateToSettings,
            onMultiStreamsTap: _navigateToMultiStreams,
            onSourcesTap: () => IptvPortalsModal.show(context),
          ),

          // 1. Full Bleed Spotlight Hero Carousel
          if (spotlightEnabled)
            IptvHeroCarousel(
              channels: _featured,
              onWatchNow: _watchChannelNow,
              onSourcesTap: _openChannel,
            )
          else
            const SizedBox(height: ZplaySpacing.s24),

          const SizedBox(height: ZplaySpacing.s20),

          // Quick Channels row (below hero, above categories)
          _QuickChannelsSlider(
            channels: _quickChannels,
            onChannelTap: _openChannel,
            onAddTap: _showAddQuickChannelDialog,
            onRemoveTap: _removeQuickChannel,
          ),
          const SizedBox(height: ZplaySpacing.s8),

          // 2. The premier channels are the guide, not a poster rail: the
          // prototype's Live TV pane is a channel list beside the schedule for
          // the selected channel, and the same eight channels were already
          // being listed twice - once as the top rail and once as cards. The
          // category keeps its place in the user's own order and visibility,
          // and every channel in it is still listed; it is the presentation
          // that changes. Every other category keeps its rail.
          //
          // 3. Curated Slider Sections (driven by user-customized category
          // visibility and order)
          for (final catName in visibleCategories)
            if (categoryMap.containsKey(catName) &&
                categoryMap[catName]!.$2.isNotEmpty)
              if (catName == _guideCategory)
                _buildLiveGuide(catName, categoryMap[catName]!.$2)
              else
                IptvSliderSection(
                  title: catName,
                  subtitle: categoryMap[catName]!.$1,
                  channels: categoryMap[catName]!.$2,
                  onChannelTap: _openChannel,
                ),

          // Trailing gap only: the dock used to reserve 90 px of clearance here.
          SizedBox(
            height: ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom,
          ),
        ],
      ),
    );
    final backgroundContent = IptvSettings.enableAmbientLights.value
        ? AnimatedAmbientBackground(child: listContent)
        : Container(color: tokens.bg, child: listContent);

    final overlayChildren = <Widget>[
      // Custom Scroll Track (Matching Home & Anime Page)
      if (MediaQuery.sizeOf(context).width > 800)
        Positioned(
          right: ZplaySpacing.s24,
          bottom: ZplaySpacing.s40,
          child: CustomScrollTrack(controller: _scrollController),
        ),
    ];

    return Scaffold(
      backgroundColor: tokens.bg,
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

          return Container(
            color: tokens.bg,
            child: Stack(
              children: [
                RepaintBoundary(child: backgroundContent),
                ...overlayChildren,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IptvGlassAppBar extends StatelessWidget {
  final Function(Offset? tapPosition) onSearchTap;
  final VoidCallback onSettingsTap;
  final Function(Offset? tapPosition) onMultiStreamsTap;
  final VoidCallback onSourcesTap;

  const _IptvGlassAppBar({
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.onMultiStreamsTap,
    required this.onSourcesTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tokens = context.tokens;
    final isExpanded = screenWidth >= 760;
    final isSmall = screenWidth < 420;

    final horizontalPadding = isSmall
        ? ZplaySpacing.s12
        : (screenWidth < 540 ? ZplaySpacing.s20 : ZplaySpacing.s24);
    // Every app-bar control is a focus target, so on anything that is not a
    // held phone it takes the full 48 dp minimum: the bar's buttons were 36-40
    // dp, which is under the size a five-way pad needs at ten feet.
    final buttonSize = FormFactorService.of(context) == FormFactor.compact
        ? (isSmall ? ZplaySpacing.s40 : ZplaySpacing.s48 - ZplaySpacing.s4)
        : kMinInteractiveDimension;
    final buttonSpacing = isSmall ? ZplaySpacing.s8 : ZplaySpacing.s12;

    // The second chrome is gone: the shell's top bar plus the Browse band
    // already name this destination, so this page is a content row under
    // shared chrome with no header of its own. (The page cannot read
    // `paddingOf` for its strip: Browse's band owns the status strip and
    // `removePadding` above it already spent it, so the dead `topPadding`
    // math sampled a zero.) Because the shell is one focus tree, D-pad UP
    // runs from the content to the Browse pills to the shared menu by
    // geometry alone - there is nothing to trap and no route for BACK to
    // unwind.
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isSmall ? ZplaySpacing.s8 : ZplaySpacing.s12,
        horizontalPadding,
        isSmall ? ZplaySpacing.s8 : ZplaySpacing.s12,
      ),
      // Opaque band, where this was a 76–80% `#080A0F` gradient fading to
      // transparent. Nothing blurs behind this bar and the shell already draws
      // the switcher chrome above the slot, so a translucent fill only let the
      // hero smear through underneath and left the bar's own text on a moving
      // background. `tokens.bg` over the literal also fixes a palette mismatch:
      // `#080A0F` is only the ocean palette's background, so the bar stayed
      // ocean-black under every other palette.
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(bottom: tokens.hairline),
      ),
      child: Row(
        children: [
          // The `LIVE TV` gradient badge that used to open this bar is gone:
          // the shell's top bar already names this destination, so the page was
          // drawing its own second copy of that chrome 48 dp below the real one.
          // The count beside it said `60+` while the catalogue holds more than
          // that, so it now reports the number of channels this vertical lists.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s8,
              vertical: ZplaySpacing.s4,
            ),
            decoration: BoxDecoration(
              color: tokens.borderDefault,
              borderRadius: ZplayRadius.xsAll,
            ),
            child: Text(
              '${HardcodedChannels.all.length} CHANNELS',
              style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
            ),
          ),

          const Spacer(),

          // Multi Streams Button
          _MultiStreamsAppBarButton(
            isExpanded: isExpanded,
            size: buttonSize,
            onTapWithPosition: onMultiStreamsTap,
          ),

          SizedBox(width: buttonSpacing),

          // Sources / Xtream Panels button
          _GlassActionButton(
            size: buttonSize,
            icon: Icons.settings_input_antenna_rounded,
            tooltip: 'Manage Portals & Playlists',
            onTap: onSourcesTap,
          ),

          SizedBox(width: buttonSpacing),

          // Search button
          _GlassActionButton(
            size: buttonSize,
            icon: Icons.search_rounded,
            tooltip: 'Search Channels',
            onTapWithPosition: onSearchTap,
          ),

          SizedBox(width: buttonSpacing),
          // Settings takes no reveal position, unlike Search: it is a shell slot.
          _GlassActionButton(
            size: buttonSize,
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _MultiStreamsAppBarButton extends StatefulWidget {
  final bool isExpanded;
  final double size;
  final Function(Offset? position)? onTapWithPosition;

  const _MultiStreamsAppBarButton({
    required this.isExpanded,
    this.size = ZplaySpacing.s40,
    this.onTapWithPosition,
  });

  @override
  State<_MultiStreamsAppBarButton> createState() =>
      _MultiStreamsAppBarButtonState();
}

class _MultiStreamsAppBarButtonState extends State<_MultiStreamsAppBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final iconSize = (widget.size * 0.48).clamp(16.0, 19.0);

    // Was a `MouseRegion` over a `GestureDetector` with no `Focus` node, so a
    // remote could neither land on Multi Streams nor open it. Same shape and
    // same fix as `_GlassActionButton` below.
    return FocusableCard(
      onTap: () => widget.onTapWithPosition?.call(null),
      builder: (context, state) {
        final highlighted = _hovered || state.focused;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: Tooltip(
              message: 'Multi Streams (Multi-View Window)',
              child: AnimatedContainer(
                duration: ZplayMotion.base,
                height: widget.size,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isExpanded ? ZplaySpacing.s12 : ZplaySpacing.s0,
                ),
                decoration: BoxDecoration(
                  // No resting border and no glow. The bar's own focus ring is
                  // the only outline this button draws, and a soft shadow under
                  // it put a second, blurred edge inside the crisp one.
                  color: highlighted ? tokens.borderStrong : tokens.borderDefault,
                  borderRadius: ZplayRadius.smAll,
                ),
                child: widget.isExpanded
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.dashboard_rounded,
                            color: tokens.info,
                            size: iconSize,
                          ),
                          const SizedBox(width: ZplaySpacing.s8),
                          Text(
                            'Multi Streams',
                            style: ZplayType.label.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(width: ZplaySpacing.s8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s4,
                              vertical: ZplaySpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [tokens.accent, tokens.info],
                              ),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              'MULTI',
                              style: ZplayType.overline.toStyle(
                                color: tokens.onAccent,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: Center(
                          child: Icon(
                            Icons.dashboard_rounded,
                            color: _hovered ? tokens.info : tokens.textPrimary,
                            size: iconSize,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback? onTap;
  final Function(Offset? position)? onTapWithPosition;

  const _GlassActionButton({
    required this.icon,
    required this.tooltip,
    this.size = ZplaySpacing.s40,
    this.onTap,
    this.onTapWithPosition,
  });

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Was a `MouseRegion` over a `GestureDetector` with no `Focus` node
    // anywhere, so traversal skipped it and the centre button had nothing to
    // activate. `FocusableCard` now owns activation and the highlight, so a
    // remote lands on every control in this strip the same way a pointer does.
    // The pointer hover is kept and simply joins the focus state, so the
    // desktop look is unchanged and a remote gets the same feedback a mouse
    // would.
    return FocusableCard(
      onTap: widget.onTapWithPosition != null
          ? () => widget.onTapWithPosition!(null)
          : widget.onTap,
      builder: (context, state) {
        final highlighted = _hovered || state.focused;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: Tooltip(
              message: widget.tooltip,
              child: AnimatedContainer(
                duration: ZplayMotion.base,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  // Fill only. The accent border and the glow that used to sit
                  // here were a second edge under the focus ring, which is the
                  // one outline this design gives a control.
                  color: highlighted
                      ? tokens.borderStrong
                      : tokens.borderDefault,
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  widget.icon,
                  color: highlighted ? tokens.textPrimary : tokens.textEmphasis,
                  size: (widget.size * 0.5).clamp(16.0, 20.0),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Channels Slider (user-added channels)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickChannelsSlider extends StatefulWidget {
  final List<QuickChannel> channels;
  final Function(HardcodedChannel) onChannelTap;
  final VoidCallback onAddTap;
  final Function(String) onRemoveTap;

  const _QuickChannelsSlider({
    required this.channels,
    required this.onChannelTap,
    required this.onAddTap,
    required this.onRemoveTap,
  });

  @override
  State<_QuickChannelsSlider> createState() => _QuickChannelsSliderState();
}

class _QuickChannelsSliderState extends State<_QuickChannelsSlider> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  /// Drives the desktop scroll arrows. It was a `final bool` pinned to false,
  /// so the arrows were built at `left: -50` on every frame - off screen and
  /// still focusable, which is a focus target a remote can land on and not see.
  /// They are only built while the pointer is over the row now.
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateButtons);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateButtons() {
    if (!_scrollController.hasClients) return;
    final canLeft = _scrollController.position.pixels > 10;
    final canRight =
        _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 10;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double dir) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final amount = viewport * 0.75 * dir;
    final target = (_scrollController.position.pixels + amount).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: ZplayMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width < 600
        ? 140.0
        : width < 1000
        ? 160.0
        : 180.0;
    final posterH = cardWidth * 1.35;
    final totalH = posterH + 60;
    final isDesktop =
        !kIsWeb &&
        (Theme.of(context).platform == TargetPlatform.windows ||
            Theme.of(context).platform == TargetPlatform.macOS ||
            Theme.of(context).platform == TargetPlatform.linux);

    return MouseRegion(
      onEnter: (_) {
        if (isDesktop) setState(() => _isHovering = true);
      },
      onExit: (_) {
        if (isDesktop) setState(() => _isHovering = false);
      },
      child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Quick Channels',
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                color: tokens.accent,
                tooltip: 'Add Quick Channel',
                onPressed: widget.onAddTap,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s4,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.channels.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: ZplaySpacing.s12),
                  itemBuilder: (context, index) {
                    if (index == widget.channels.length) {
                      return SizedBox(
                        width: cardWidth,
                        child: _QuickAddCard(onTap: widget.onAddTap),
                      );
                    }
                    final ch = widget.channels[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _QuickChannelCard(
                        channel: ch,
                        onTap: () {
                          final hc = HardcodedChannel(
                            id: 'qc_${ch.id}',
                            name: ch.name,
                            short: ch.short,
                            category: ch.category,
                            keywords: ch.keywords,
                            gradient: ch.gradient,
                            iconUrl: ch.iconUrl,
                          );
                          widget.onChannelTap(hc);
                        },
                        onRemove: () => widget.onRemoveTap(ch.id),
                      ),
                    );
                  },
                ),
                // Desktop scroll arrows
                if (isDesktop && _isHovering) ...[
                  AnimatedPositioned(
                    duration: ZplayMotion.fast,
                    curve: ZplayMotion.standard,
                    left: _canScrollLeft && _isHovering ? 2 : -50,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: Icon(
                          Icons.chevron_left_rounded,
                          color: tokens.textEmphasis,
                        ),
                        onPressed: _canScrollLeft ? () => _scroll(-1) : null,
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: ZplayMotion.fast,
                    curve: ZplayMotion.standard,
                    right: _canScrollRight && _isHovering ? 2 : -50,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: Icon(
                          Icons.chevron_right_rounded,
                          color: tokens.textEmphasis,
                        ),
                        onPressed: _canScrollRight ? () => _scroll(1) : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _QuickChannelCard extends StatelessWidget {
  final QuickChannel channel;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QuickChannelCard({
    required this.channel,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => GestureDetector(
        // Pointer-only shortcut: FocusableCard owns tap and activation, not long press.
        onLongPress: onRemove,
        child: CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.smAll,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: channel.gradient,
                  ),
                  // The coloured glow on highlight is gone: it was a blurred
                  // second edge under the card's own focus ring.
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: channel.iconUrl != null
                            ? CachedNetworkImage(
                                imageUrl: channel.iconUrl!,
                                cacheManager: AppImageCache.manager,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) =>
                                    _QuickChannelIcon(channel.short),
                              )
                            : _QuickChannelIcon(channel.short),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            style: ZplayType.label.toStyle(
                              color: tokens.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            channel.category,
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
              // Remove button — always visible, and a real focus target: the
              // 20 dp dot this replaces was neither reachable nor pressable
              // from a remote. The disc stays small; the target around it is
              // the form factor's minimum.
              Positioned(
                top: 0,
                right: 0,
                child: FocusableCard(
                  onTap: onRemove,
                  builder: (context, closeState) => CardFocusRing(
                    focused: closeState.focused,
                    radius: ZplayRadius.fullAll,
                    child: SizedBox(
                      width: FormFactorService.of(context) == FormFactor.compact
                          ? 40.0
                          : kMinInteractiveDimension,
                      height: FormFactorService.of(context) == FormFactor.compact
                          ? 40.0
                          : kMinInteractiveDimension,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(ZplaySpacing.s4),
                          decoration: BoxDecoration(
                            color: tokens.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: tokens.textPrimary,
                            size: 14,
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
      ),
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickAddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: Container(
          decoration: BoxDecoration(
            // A resting 2 dp accent border sat here, directly under the focus
            // ring the card draws in the same colour at the same width, so the
            // focused card read as a 4 dp double edge. The fill and the accent
            // glyph carry the affordance; the ring marks the focus.
            borderRadius: ZplayRadius.smAll,
            color: tokens.surface,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: tokens.accent, size: 36),
              const SizedBox(height: 8),
              Text(
                'Add Channel',
                style: ZplayType.label.toStyle(color: tokens.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChannelIcon extends StatelessWidget {
  final String short;
  const _QuickChannelIcon(this.short);

  @override
  Widget build(BuildContext context) {
    return Text(
      short,
      style: ZplayType.titleLarge.toStyle(color: context.tokens.textPrimary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Quick Channel Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _AddQuickChannelDialog extends StatefulWidget {
  final void Function(QuickChannel) onAdd;

  const _AddQuickChannelDialog({required this.onAdd});

  @override
  State<_AddQuickChannelDialog> createState() => _AddQuickChannelDialogState();
}

class _AddQuickChannelDialogState extends State<_AddQuickChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _shortCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();

  List<Color> _gradient = [const Color(0xFF7C5CFF), const Color(0xFF1A1A1A)];
  final List<List<Color>> _presetGradients = [
    [const Color(0xFF7C5CFF), const Color(0xFF1A1A1A)],
    [const Color(0xFFCC0000), const Color(0xFF1A1A1A)],
    [const Color(0xFF003366), const Color(0xFF0066CC)],
    [const Color(0xFFD4AF37), const Color(0xFF1A1A1A)],
    [const Color(0xFF00AA00), const Color(0xFF1A1A1A)],
    [const Color(0xFFFF6D00), const Color(0xFF1A1A1A)],
    [const Color(0xFF0066CC), const Color(0xFF003366)],
    [const Color(0xFFCC0000), const Color(0xFF001965)],
  ];

  String _selectedCategory = 'Quick';
  final List<String> _categories = [
    'Quick',
    'US',
    'UK',
    'CA',
    'Bay Area',
    'Sports',
    'News',
    'Movies',
    'Int. Sports',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AlertDialog(
      backgroundColor: tokens.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
      title: Text(
        'Add Quick Channel',
        style: ZplayType.title.toStyle(color: tokens.textPrimary),
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: ZplayType.body.toStyle(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Channel Name',
                    labelStyle: ZplayType.body.toStyle(
                      color: tokens.textEmphasis,
                    ),
                    border: const UnderlineInputBorder(),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _shortCtrl,
                        style: ZplayType.body.toStyle(
                          color: tokens.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Short Code (optional)',
                          labelStyle: ZplayType.body.toStyle(
                            color: tokens.textEmphasis,
                          ),
                          border: const UnderlineInputBorder(),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: tokens.accent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        dropdownColor: tokens.surfaceOverlay,
                        style: ZplayType.body.toStyle(
                          color: tokens.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Category',
                          labelStyle: ZplayType.body.toStyle(
                            color: tokens.textEmphasis,
                          ),
                          border: const UnderlineInputBorder(),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: tokens.accent),
                          ),
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: ZplayType.body.toStyle(
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedCategory = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _keywordsCtrl,
                  style: ZplayType.body.toStyle(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Keywords (comma-separated)',
                    labelStyle: ZplayType.body.toStyle(
                      color: tokens.textEmphasis,
                    ),
                    hintText: 'e.g. cnn, news, international',
                    hintStyle: ZplayType.body.toStyle(color: tokens.textMuted),
                    border: const UnderlineInputBorder(),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gradient',
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textEmphasis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _presetGradients.map((g) {
                    final isSelected = _gradient == g;
                    return FocusableCard(
                      onTap: () => setState(() => _gradient = g),
                      builder: (context, state) => CardFocusRing(
                        focused: state.focused,
                        radius: ZplayRadius.smAll,
                        child: Container(
                          width:
                              FormFactorService.of(context) == FormFactor.compact
                              ? 36
                              : kMinInteractiveDimension,
                          height:
                              FormFactorService.of(context) == FormFactor.compact
                              ? 36
                              : kMinInteractiveDimension,
                          decoration: BoxDecoration(
                            borderRadius: ZplayRadius.smAll,
                            gradient: LinearGradient(colors: g),
                            border: Border.all(
                              color: isSelected
                                  ? tokens.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: ZplayType.label.toStyle(color: tokens.textEmphasis),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.accent,
            foregroundColor: tokens.onAccent,
            shape: const RoundedRectangleBorder(
              borderRadius: ZplayRadius.smAll,
            ),
          ),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
              final shortVal = _shortCtrl.text.trim().isEmpty
                  ? _nameCtrl.text
                        .trim()
                        .substring(
                          0,
                          _nameCtrl.text.trim().length > 3
                              ? 3
                              : _nameCtrl.text.trim().length,
                        )
                        .toUpperCase()
                  : _shortCtrl.text.trim().toUpperCase();
              final channel = QuickChannel(
                id: id,
                name: _nameCtrl.text.trim(),
                short: shortVal,
                category: _selectedCategory,
                keywords: _keywordsCtrl.text
                    .trim()
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                gradient: _gradient,
              );
              widget.onAdd(channel);
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
