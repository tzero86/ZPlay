import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/m3u_models.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/layout/form_factor.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_network.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/iptv/iptv_storage.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../utils/navigation/route_transitions.dart';
import 'iptv_player_page.dart';
import '../../services/storage/app_image_cache.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/player/player_glass.dart';

class IptvPortalBrowserPage extends StatefulWidget {
  final VerifiedPortal? portal;
  final M3uPlaylist? m3uPlaylist;
  final bool returning;
  final void Function(String streamUrl, String channelName)? onStreamSelected;

  const IptvPortalBrowserPage({
    super.key,
    this.portal,
    this.m3uPlaylist,
    this.returning = false,
    this.onStreamSelected,
  });

  @override
  State<IptvPortalBrowserPage> createState() => _IptvPortalBrowserPageState();
}

class _IptvPortalBrowserPageState extends State<IptvPortalBrowserPage> {
  static const String favoritesCategoryId = '__favorites__';

  IptvSection _activeSection = IptvSection.live;
  bool _isLoading = true;
  String? _errorMessage;

  List<IptvCategory> _categories = [];
  String _selectedCategoryId = '';
  List<IptvStream> _allStreams = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _catSearchCtrl = TextEditingController();
  String _searchQuery = '';
  String _catSearchQuery = '';

  // Scroll Controllers with Desktop Arrow Navigation
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();

  bool _isHoveringCategories = false;
  bool _isHoveringContent = false;
  bool _canScrollCatUp = false;
  bool _canScrollCatDown = false;
  bool _canScrollContentUp = false;
  bool _canScrollContentDown = false;

  // Stream Health / Alive Checker State
  bool _isCheckingAlive = false;
  int _aliveChecked = 0;
  int _aliveTotal = 0;
  Set<String> _aliveStreamIds = {};
  bool _cancelAlive = false;

  // Favorited Streams in this Portal
  Set<String> _favoriteStreamIds = {};

  String get _storageKey {
    if (widget.portal != null) {
      return IptvPortalFavoritesStore.portalKey(widget.portal!.portal);
    } else if (widget.m3uPlaylist != null) {
      return 'm3u_${widget.m3uPlaylist!.id}';
    }
    return '';
  }

  // Static in-memory EPG cache shared across rows to avoid duplicate network fetches
  static final Map<String, List<EpgEntry>> _sharedEpgCache = {};

  @override
  void initState() {
    super.initState();
    final name = widget.portal?.name ?? widget.m3uPlaylist?.name ?? 'IPTV Portal';
    DiscordRpcService.instance.setWatchingLiveTv(channelName: 'Portal: $name');
    _categoryScrollController.addListener(_updateCategoryScrollState);
    _contentScrollController.addListener(_updateContentScrollState);
    IptvSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    _loadFavorites();
    _loadSectionData();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadFavorites() async {
    final key = _storageKey;
    if (key.isEmpty) return;
    final favs = await IptvPortalFavoritesStore.load(key);
    if (mounted) {
      setState(() => _favoriteStreamIds = favs);
    }
  }

  Future<void> _toggleFavoriteStream(String streamId) async {
    final key = _storageKey;
    if (key.isEmpty) return;
    setState(() {
      if (_favoriteStreamIds.contains(streamId)) {
        _favoriteStreamIds.remove(streamId);
      } else {
        _favoriteStreamIds.add(streamId);
      }
    });
    await IptvPortalFavoritesStore.save(key, _favoriteStreamIds);
  }

  @override
  void dispose() {
    _cancelAlive = true;
    IptvSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _categoryScrollController.removeListener(_updateCategoryScrollState);
    _contentScrollController.removeListener(_updateContentScrollState);
    _categoryScrollController.dispose();
    _contentScrollController.dispose();
    _searchCtrl.dispose();
    _catSearchCtrl.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _showBrowserCustomizer(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return Dialog(
          // A dialog carries its own surface: fill only, no resting outline.
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.lgAll),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: tokens.accent, size: 20),
                      const SizedBox(width: ZplaySpacing.s8),
                      Text(
                        'Customize Portal Browser',
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  // Was a hairline divider; hierarchy comes from the type above.
                  Text(
                    'Channel Stream Layout Mode',
                    style: ZplayType.label.toStyle(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<PortalBrowserLayout>(
                    valueListenable: IptvSettings.browserLayout,
                    builder: (context, layout, _) {
                      return SegmentedTabs<PortalBrowserLayout>(
                        selected: layout,
                        onSelected: (l) {
                          IptvSettings.setBrowserLayout(l);
                        },
                        options: [
                          for (final l in PortalBrowserLayout.values)
                            SegmentedTabOption(value: l, label: l.label),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  ValueListenableBuilder<PortalBrowserLayout>(
                    valueListenable: IptvSettings.browserLayout,
                    builder: (context, layout, _) {
                      if (layout != PortalBrowserLayout.grid) return const SizedBox.shrink();
                      return ValueListenableBuilder<int>(
                        valueListenable: IptvSettings.browserGridColumns,
                        builder: (context, cols, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Grid Stream Columns', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                                  Text('$cols Cols', style: ZplayType.label.toStyle(color: tokens.accent)),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: tokens.accent,
                                  inactiveTrackColor: tokens.borderStrong,
                                  thumbColor: tokens.accent,
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: cols.toDouble(),
                                  min: 2,
                                  max: 6,
                                  divisions: 4,
                                  onChanged: (val) => IptvSettings.setBrowserGridColumns(val.round()),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showStreamLogos,
                    builder: (context, showLogos, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show Channel Stream Logos', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                        value: showLogos,
                        activeColor: tokens.accent,
                        onChanged: (val) => IptvSettings.setShowStreamLogos(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showEpgSnippet,
                    builder: (context, showEpg, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show EPG "Now Playing" Snippet', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                        value: showEpg,
                        activeColor: tokens.accent,
                        onChanged: (val) => IptvSettings.setShowEpgSnippet(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showCategoryCount,
                    builder: (context, showCount, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show Category Stream Counts', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                        value: showCount,
                        activeColor: tokens.accent,
                        onChanged: (val) => IptvSettings.setShowCategoryCount(val),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateCategoryScrollState() {
    if (!_categoryScrollController.hasClients) return;
    final canUp = _categoryScrollController.position.pixels > 10;
    final canDown = _categoryScrollController.position.pixels <
        _categoryScrollController.position.maxScrollExtent - 10;
    if (canUp != _canScrollCatUp || canDown != _canScrollCatDown) {
      setState(() {
        _canScrollCatUp = canUp;
        _canScrollCatDown = canDown;
      });
    }
  }

  void _updateContentScrollState() {
    if (!_contentScrollController.hasClients) return;
    final canUp = _contentScrollController.position.pixels > 10;
    final canDown = _contentScrollController.position.pixels <
        _contentScrollController.position.maxScrollExtent - 10;
    if (canUp != _canScrollContentUp || canDown != _canScrollContentDown) {
      setState(() {
        _canScrollContentUp = canUp;
        _canScrollContentDown = canDown;
      });
    }
  }

  void _scrollCategories(double delta) {
    if (!_categoryScrollController.hasClients) return;
    final target = (_categoryScrollController.position.pixels + delta)
        .clamp(0.0, _categoryScrollController.position.maxScrollExtent);
    _categoryScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollContent(double delta) {
    if (!_contentScrollController.hasClients) return;
    final target = (_contentScrollController.position.pixels + delta)
        .clamp(0.0, _contentScrollController.position.maxScrollExtent);
    _contentScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 750;
  }

  String _selectedCategoryName() {
    if (_selectedCategoryId == favoritesCategoryId) return '⭐ Favorites';
    if (_selectedCategoryId.isEmpty) return 'All Categories';
    final found = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => const IptvCategory(id: '', name: 'All Categories'),
    );
    return found.name;
  }

  Future<void> _loadSectionData() async {
    if (widget.portal == null && widget.m3uPlaylist == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _catSearchQuery = '';
      _catSearchCtrl.clear();
    });

    try {
      if (widget.portal != null) {
        final p = widget.portal!.portal;
        final cats = await IptvClient.categories(p, _activeSection);
        final streams = await IptvClient.streams(p, _activeSection, '');

        if (!mounted) return;
        setState(() {
          _categories = [
            const IptvCategory(id: '', name: 'All Categories'),
            const IptvCategory(id: favoritesCategoryId, name: 'Favorites'),
            ...cats,
          ];
          _selectedCategoryId = '';
          _allStreams = streams;
          _isLoading = false;
        });

        if (_activeSection == IptvSection.live) {
          _loadSavedAliveSnapshot();
        }
      } else if (widget.m3uPlaylist != null) {
        final pl = widget.m3uPlaylist!;
        final groupNames = pl.channels
            .map((c) => c.group.isNotEmpty ? c.group : 'General')
            .toSet()
            .toList();

        final cats = groupNames
            .map((g) => IptvCategory(id: g, name: g))
            .toList();

        final streams = pl.channels
            .map((c) => IptvStream(
                  streamId: c.url,
                  name: c.name,
                  icon: c.logo,
                  categoryId: c.group.isNotEmpty ? c.group : 'General',
                  containerExt: 'm3u8',
                  kind: 'live',
                ))
            .toList();

        if (!mounted) return;
        setState(() {
          _categories = [
            const IptvCategory(id: '', name: 'All Categories'),
            const IptvCategory(id: favoritesCategoryId, name: 'Favorites'),
            ...cats,
          ];
          _selectedCategoryId = '';
          _allStreams = streams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load content: $e';
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCategoryScrollState();
      _updateContentScrollState();
    });
  }

  Future<void> _loadSavedAliveSnapshot() async {
    if (widget.portal == null) return;
    final key = IptvAliveStore.portalKey(widget.portal!.portal);
    final snap = await IptvAliveStore.load(key);
    if (snap != null && mounted) {
      setState(() {
        _aliveStreamIds = snap.aliveIds;
      });
    }
  }

  Future<void> _startAliveCheck() async {
    if (widget.portal == null || _activeSection != IptvSection.live || _isCheckingAlive) return;

    final p = widget.portal!.portal;
    final filtered = _filteredStreams();
    if (filtered.isEmpty) return;

    setState(() {
      _isCheckingAlive = true;
      _aliveChecked = 0;
      _aliveTotal = filtered.length;
      _cancelAlive = false;
    });

    final entries = filtered
        .map((s) => MapEntry(s.streamId, IptvClient.streamUrl(p, s)))
        .toList();

    final aliveSet = Set<String>.from(_aliveStreamIds);

    await IptvAliveChecker.launchCheck(
      streams: entries,
      isCancelled: () => _cancelAlive,
      onResult: (id, alive) async {
        if (alive) {
          aliveSet.add(id);
          if (mounted) setState(() => _aliveStreamIds = aliveSet);
        }
      },
      onProgress: (prog) async {
        if (mounted) {
          setState(() {
            _aliveChecked = prog.checked;
            _aliveTotal = prog.total;
          });
        }
      },
      onDone: () async {
        if (mounted) {
          setState(() => _isCheckingAlive = false);
          final key = IptvAliveStore.portalKey(p);
          await IptvAliveStore.save(
            key,
            AliveSnapshot(
              checkedAt: DateTime.now().millisecondsSinceEpoch,
              aliveIds: aliveSet,
            ),
          );
        }
      },
    );
  }

  List<IptvCategory> _filteredCategories() {
    if (_catSearchQuery.trim().isEmpty) return _categories;
    final q = _catSearchQuery.toLowerCase();
    return _categories.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  List<IptvStream> _filteredStreams() {
    return _allStreams.where((s) {
      if (_selectedCategoryId == favoritesCategoryId) {
        if (!_favoriteStreamIds.contains(s.streamId)) return false;
      } else if (_selectedCategoryId.isNotEmpty) {
        if (s.categoryId != _selectedCategoryId) return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      return s.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  int _countForCategory(String catId) {
    if (catId == favoritesCategoryId) {
      return _allStreams.where((s) => _favoriteStreamIds.contains(s.streamId)).length;
    }
    if (catId.isEmpty) return _allStreams.length;
    return _allStreams.where((s) => s.categoryId == catId).length;
  }

  /// A channel whose URL could not be built. Reported rather than pushed into
  /// the player, where an empty URL used to produce a black screen with no
  /// message at all.
  void _reportUnplayable(IptvStream stream) {
    debugPrint('[IPTV] "${stream.name}" has no playable stream URL');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${stream.name}" has no playable stream. '
            'Reconnect the portal or remove it and add another.'),
      ),
    );
  }

  void _playStream(IptvStream stream) {
    if (widget.returning && widget.onStreamSelected != null) {
      final url = widget.portal != null
          ? IptvClient.streamUrl(widget.portal!.portal, stream)
          : stream.streamId;
      if (url.isEmpty) {
        _reportUnplayable(stream);
        return;
      }
      widget.onStreamSelected!(url, stream.name);
      Navigator.pop(context);
      return;
    }
    final isLive = _activeSection == IptvSection.live;
    final currentList = _filteredStreams();
    final clickedIndex = currentList.indexWhere((s) => s.streamId == stream.streamId);
    final initialIndex = clickedIndex >= 0 ? clickedIndex : 0;

    final currentCat = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => IptvCategory(id: '', name: isLive ? 'Live Channels' : (_activeSection == IptvSection.vod ? 'Movies' : 'Series')),
    );

    if (widget.portal != null) {
      final p = widget.portal!;
      // A hit with no URL can only fail silently in the player, so it is
      // dropped here rather than handed over.
      final hits = currentList
          .map((s) => ChannelHit(
                portal: p,
                stream: s,
                streamUrl: IptvClient.streamUrl(p.portal, s),
              ))
          .where((h) => h.streamUrl.isNotEmpty)
          .toList();
      if (hits.isEmpty) {
        _reportUnplayable(stream);
        return;
      }

      final ch = HardcodedChannel(
        id: stream.streamId,
        name: stream.name,
        short: isLive ? 'LIVE' : (_activeSection == IptvSection.vod ? 'VOD' : 'SERIES'),
        category: currentCat.name,
        keywords: [stream.name],
        gradient: [context.tokens.accent, context.tokens.info],
      );

      Navigator.push(
        context,
        LiquidRevealRoute(
          page: IptvPlayerPage(
            channel: ch,
            hits: hits.isNotEmpty
                ? hits
                : [
                    ChannelHit(
                      portal: p,
                      stream: stream,
                      streamUrl: IptvClient.streamUrl(p.portal, stream),
                    ),
                  ],
            initialHitIndex: initialIndex,
            isLive: isLive,
            categoryTitle: currentCat.name,
          ),
        ),
      );
    } else if (widget.m3uPlaylist != null) {
      final hits = currentList.map((s) => ChannelHit(
        portal: VerifiedPortal(
          portal: IptvPortal(url: s.streamId, username: '', password: '', source: 'M3U'),
          name: widget.m3uPlaylist!.name,
          expiry: '',
          maxConnections: '1',
          activeConnections: '0',
        ),
        stream: s,
        streamUrl: s.streamId,
      )).toList();

      final ch = HardcodedChannel(
        id: stream.streamId,
        name: stream.name,
        short: isLive ? 'LIVE' : 'VOD',
        category: currentCat.name,
        keywords: [stream.name],
        gradient: [context.tokens.accent, context.tokens.info],
      );

      Navigator.push(
        context,
        LiquidRevealRoute(
          page: IptvPlayerPage(
            channel: ch,
            hits: hits.isNotEmpty
                ? hits
                : [
                    ChannelHit(
                      portal: VerifiedPortal(
                        portal: IptvPortal(url: stream.streamId, username: '', password: '', source: 'M3U'),
                        name: widget.m3uPlaylist!.name,
                        expiry: '',
                        maxConnections: '1',
                        activeConnections: '0',
                      ),
                      stream: stream,
                      streamUrl: stream.streamId,
                    ),
                  ],
            initialHitIndex: initialIndex,
            isLive: isLive,
            categoryTitle: currentCat.name,
          ),
        ),
      );
    }
  }

  Future<void> _openSeriesEpisodes(IptvStream series) async {
    if (widget.returning && widget.onStreamSelected != null) {
      // A series carries kind 'series', which IptvClient.streamUrl has no arm
      // for: it fell through to the default and handed '' to the player, so
      // choosing an episode from this list could only ever fail silently.
      // episodeUrl is the Xtream /series/<user>/<pass>/<id>.<ext> path these
      // entries need.
      final url = widget.portal != null
          ? IptvClient.episodeUrl(
              widget.portal!.portal,
              IptvEpisode(
                id: series.streamId,
                title: series.name,
                containerExt: series.containerExt,
                season: 0,
                episode: 0,
                plot: '',
                image: series.icon,
              ),
            )
          : series.streamId;
      if (url.isEmpty) {
        debugPrint('[IPTV] Series "${series.name}" resolved to an empty URL');
        return;
      }
      widget.onStreamSelected!(url, series.name);
      Navigator.pop(context);
      return;
    }
    if (widget.portal == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SeriesEpisodesSheet(
        portal: widget.portal!,
        series: series,
      ),
    );
  }  void _showMobileCategorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final tokens = ctx.tokens;
            final cats = _filteredCategories();
            return Container(
              height: MediaQuery.sizeOf(context).height * 0.75,
              decoration: BoxDecoration(
                // Sheet surface only: no top hairline, the rounded top reads as chrome.
                color: tokens.surfaceOverlay,
                borderRadius: ZplayRadius.sheetTop,
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: ZplaySpacing.s8, bottom: ZplaySpacing.s12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded, color: tokens.accent, size: 20),
                        const SizedBox(width: ZplaySpacing.s8),
                        Text(
                          'Select Category',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                        ),
                        const Spacer(),
                        Text(
                          '${_categories.length} total',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ZplaySpacing.s12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _catSearchCtrl,
                        style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Filter categories…',
                          hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                          prefixIcon: Icon(Icons.search_rounded, color: tokens.textMuted, size: 18),
                          suffixIcon: _catSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 16),
                                  onPressed: () {
                                    _catSearchCtrl.clear();
                                    setState(() => _catSearchQuery = '');
                                    setSheetState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: tokens.surface,
                          border: const OutlineInputBorder(
                            borderRadius: ZplayRadius.smAll,
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s8),
                        ),
                        onChanged: (v) {
                          setState(() => _catSearchQuery = v);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: ZplaySpacing.s8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cats.length,
                      itemExtent: 50.0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemBuilder: (ctx, i) {
                        final cat = cats[i];
                        final isSelected = _selectedCategoryId == cat.id;
                        final count = _countForCategory(cat.id);
                        return _CategoryListRow(
                          category: cat,
                          count: count,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() => _selectedCategoryId = cat.id);
                            _contentScrollController.jumpTo(0);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final title = widget.portal?.name.isNotEmpty == true
        ? widget.portal!.name
        : (widget.m3uPlaylist?.name ?? 'IPTV Portal');

    final isDesktop = _isDesktop(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      // The pushed route paints the same ambient canvas as Home and Discover;
      // everything below sits on it rather than on a flat fill.
      body: AnimatedAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── TOP APPLICATION HEADER ──
              // This is the pushed route's own top chrome, so it is transparent:
              // no fill band, no bottom hairline, the canvas stays visible.
              if (isDesktop)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s20,
                    vertical: ZplaySpacing.s12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary, size: 22),
                        tooltip: 'Back',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: ZplaySpacing.s8),

                      // Portal emblem — bare accent glyph, no boxed chrome.
                      Icon(Icons.settings_input_antenna_rounded, color: tokens.accent, size: 20),
                      const SizedBox(width: ZplaySpacing.s12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZplayType.title.toStyle(color: tokens.textPrimary),
                            ),
                            if (widget.portal != null) ...[
                              const SizedBox(height: ZplaySpacing.s2),
                              Row(
                                children: [
                                  Text(
                                    'Expiry: ${widget.portal!.expiry}',
                                    style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                  ),
                                  const SizedBox(width: ZplaySpacing.s12),
                                  Container(width: 3, height: 3, decoration: BoxDecoration(color: tokens.textMuted, shape: BoxShape.circle)),
                                  const SizedBox(width: ZplaySpacing.s12),
                                  Text(
                                    'Connections: ${widget.portal!.activeConnections}/${widget.portal!.maxConnections}',
                                    style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: ZplaySpacing.s16),

                      // ── SECTION SWITCHER TABS ──
                      // No pill container: the selected tab's own accent fill is
                      // the only box in the group.
                      if (widget.portal != null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSectionTab('Live TV', Icons.live_tv_rounded, IptvSection.live),
                            const SizedBox(width: ZplaySpacing.s4),
                            _buildSectionTab('Movies', Icons.movie_rounded, IptvSection.vod),
                            const SizedBox(width: ZplaySpacing.s4),
                            _buildSectionTab('TV Series', Icons.tv_rounded, IptvSection.series),
                          ],
                        ),
                        const SizedBox(width: ZplaySpacing.s16),
                      ],

                      // Search Bar
                      SizedBox(
                        width: 240,
                        height: 40,
                        child: TextField(
                          controller: _searchCtrl,
                          style: ZplayType.body.toStyle(color: tokens.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search channels…',
                            hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                            prefixIcon: Icon(Icons.search_rounded, color: tokens.accent, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: tokens.surface,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: ZplaySpacing.s12),
                            border: const OutlineInputBorder(
                              borderRadius: ZplayRadius.smAll,
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),

                      // Alive Sniffer Action
                      if (_activeSection == IptvSection.live && widget.portal != null) ...[
                        const SizedBox(width: ZplaySpacing.s12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isCheckingAlive ? tokens.danger : tokens.accent,
                            foregroundColor: tokens.onAccent,
                            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: ZplaySpacing.s8),
                            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                          ),
                          icon: _isCheckingAlive
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.speed_rounded, size: 16),
                          label: Text(
                            _isCheckingAlive ? 'Stop ($_aliveChecked/$_aliveTotal)' : 'Check Health',
                            style: ZplayType.label.toStyle(color: tokens.onAccent),
                          ),
                          onPressed: _isCheckingAlive ? () => setState(() => _cancelAlive = true) : _startAliveCheck,
                        ),
                      ],

                      const SizedBox(width: ZplaySpacing.s8),

                      IconButton(
                        icon: Icon(Icons.tune_rounded, color: tokens.textSecondary, size: 20),
                        tooltip: 'Customize Portal Browser Layout',
                        onPressed: () => _showBrowserCustomizer(context),
                      ),
                    ],
                  ),
                )
            else
              // ── MOBILE RESPONSIVE HEADER ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZplaySpacing.s12,
                  ZplaySpacing.s8,
                  ZplaySpacing.s12,
                  ZplaySpacing.s8,
                ),
                child: Column(
                  children: [
                    // Top Bar: Back, Portal Title, Health button
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: ZplaySpacing.s4),
                        Icon(Icons.settings_input_antenna_rounded, color: tokens.accent, size: 16),
                        const SizedBox(width: ZplaySpacing.s8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.title.toStyle(color: tokens.textPrimary),
                              ),
                              if (widget.portal != null)
                                Text(
                                  'Conn: ${widget.portal!.activeConnections}/${widget.portal!.maxConnections} • ${widget.portal!.expiry}',
                                  style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (_activeSection == IptvSection.live && widget.portal != null)
                          IconButton(
                            tooltip: 'Check Health',
                            icon: _isCheckingAlive
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: tokens.danger),
                                  )
                                : Icon(Icons.speed_rounded, color: tokens.accent, size: 20),
                            onPressed: _isCheckingAlive ? () => setState(() => _cancelAlive = true) : _startAliveCheck,
                          ),
                        IconButton(
                          icon: Icon(Icons.tune_rounded, color: tokens.textSecondary, size: 20),
                          tooltip: 'Customize',
                          onPressed: () => _showBrowserCustomizer(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: ZplaySpacing.s8),

                    // Controls Bar: Category Selector Chip + Section Tabs
                    Row(
                      children: [
                        // Mobile Category Chip — a remote can land here, so it is a
                        // FocusableInkWell; with no box, the accent folder icon is
                        // what marks it as the category control.
                        FocusableInkWell(
                          onTap: () => _showMobileCategorySheet(context),
                          borderRadius: ZplayRadius.smAll,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s8,
                              vertical: ZplaySpacing.s4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_rounded, color: tokens.accent, size: 15),
                                const SizedBox(width: ZplaySpacing.s8),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.32),
                                  child: Text(
                                    _selectedCategoryName(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ZplayType.label.toStyle(color: tokens.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: ZplaySpacing.s4),
                                Icon(Icons.arrow_drop_down_rounded, color: tokens.accent, size: 18),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: ZplaySpacing.s8),

                        // Section Switchers
                        if (widget.portal != null)
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSectionTab('Live', Icons.live_tv_rounded, IptvSection.live),
                                  const SizedBox(width: ZplaySpacing.s2),
                                  _buildSectionTab('Movies', Icons.movie_rounded, IptvSection.vod),
                                  const SizedBox(width: ZplaySpacing.s2),
                                  _buildSectionTab('Series', Icons.tv_rounded, IptvSection.series),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: ZplaySpacing.s8),

                    // Search Input
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchCtrl,
                        style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search in this category…',
                          hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                          prefixIcon: Icon(Icons.search_rounded, color: tokens.accent, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: tokens.surface,
                          border: const OutlineInputBorder(
                            borderRadius: ZplayRadius.smAll,
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: ZplaySpacing.s8,
                            horizontal: ZplaySpacing.s8,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ],
                ),
              ),

            // ── MAIN CONTENT (SPLIT VIEW ON DESKTOP, FULL-WIDTH ON MOBILE) ──
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: tokens.accent))
                  : _errorMessage != null
                      ? ErrorView(
                          error: _errorMessage,
                          onRetry: _loadSectionData,
                          title: 'Could not load this portal',
                        )
                      : isDesktop
                          ? Row(
                              children: [
                                // ── LEFT CATEGORIES PANEL ──
                                // Same canvas as the content beside it; the split is
                                // carried by spacing, not by a fill or a divider.
                                SizedBox(
                                  width: IptvSettings.sidebarWidth.value,
                                  child: Column(
                                    children: [
                                      // Categories Search Filter
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          ZplaySpacing.s12,
                                          ZplaySpacing.s12,
                                          ZplaySpacing.s12,
                                          ZplaySpacing.s8,
                                        ),
                                        child: SizedBox(
                                          height: 38,
                                          child: TextField(
                                            controller: _catSearchCtrl,
                                            style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                                            decoration: InputDecoration(
                                              hintText: 'Filter categories…',
                                              hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                                              prefixIcon: Icon(Icons.filter_list_rounded, color: tokens.textMuted, size: 18),
                                              suffixIcon: _catSearchQuery.isNotEmpty
                                                  ? IconButton(
                                                      icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 16),
                                                      onPressed: () {
                                                        _catSearchCtrl.clear();
                                                        setState(() => _catSearchQuery = '');
                                                      },
                                                    )
                                                  : null,
                                              filled: true,
                                              fillColor: tokens.surface,
                                              border: const OutlineInputBorder(
                                                borderRadius: ZplayRadius.smAll,
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s8),
                                            ),
                                            onChanged: (v) => setState(() => _catSearchQuery = v),
                                          ),
                                        ),
                                      ),

                                      // Category List with Desktop Vertical Scroll Arrows
                                      Expanded(
                                        child: MouseRegion(
                                          onEnter: (_) => setState(() => _isHoveringCategories = true),
                                          onExit: (_) => setState(() => _isHoveringCategories = false),
                                          child: Stack(
                                            children: [
                                              ListView.builder(
                                                controller: _categoryScrollController,
                                                itemExtent: 46.0,
                                                cacheExtent: 300.0,
                                                addAutomaticKeepAlives: false,
                                                addRepaintBoundaries: true,
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: ZplaySpacing.s8,
                                                  vertical: ZplaySpacing.s4,
                                                ),
                                                itemCount: _filteredCategories().length,
                                                itemBuilder: (context, index) {
                                                  final cat = _filteredCategories()[index];
                                                  final isSelected = _selectedCategoryId == cat.id;
                                                  final count = _countForCategory(cat.id);

                                                  return _CategoryListRow(
                                                    category: cat,
                                                    count: count,
                                                    isSelected: isSelected,
                                                    onTap: () {
                                                      setState(() => _selectedCategoryId = cat.id);
                                                      _contentScrollController.jumpTo(0);
                                                    },
                                                  );
                                                },
                                              ),

                                              // Desktop Category Scroll Up Arrow
                                              if (_isHoveringCategories && _canScrollCatUp)
                                                Positioned(
                                                  top: ZplaySpacing.s4,
                                                  left: 0,
                                                  right: 0,
                                                  child: Center(
                                                    child: _VerticalScrollButton(
                                                      icon: Icons.keyboard_arrow_up_rounded,
                                                      onTap: () => _scrollCategories(-240),
                                                    ),
                                                  ),
                                                ),

                                              // Desktop Category Scroll Down Arrow
                                              if (_isHoveringCategories && _canScrollCatDown)
                                                Positioned(
                                                  bottom: ZplaySpacing.s4,
                                                  left: 0,
                                                  right: 0,
                                                  child: Center(
                                                    child: _VerticalScrollButton(
                                                      icon: Icons.keyboard_arrow_down_rounded,
                                                      onTap: () => _scrollCategories(240),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── RIGHT CONTENT PANEL ──
                                Expanded(
                                  child: MouseRegion(
                                    onEnter: (_) => setState(() => _isHoveringContent = true),
                                    onExit: (_) => setState(() => _isHoveringContent = false),
                                    child: Stack(
                                      children: [
                                        _buildMainContent(),

                                        // Desktop Content Scroll Up Arrow
                                        if (_isHoveringContent && _canScrollContentUp)
                                          Positioned(
                                            top: 14,
                                            right: 28,
                                            child: _VerticalScrollButton(
                                              icon: Icons.keyboard_arrow_up_rounded,
                                              onTap: () => _scrollContent(-450),
                                            ),
                                          ),

                                        // Desktop Content Scroll Down Arrow
                                        if (_isHoveringContent && _canScrollContentDown)
                                          Positioned(
                                            bottom: 14,
                                            right: 28,
                                            child: _VerticalScrollButton(
                                              icon: Icons.keyboard_arrow_down_rounded,
                                              onTap: () => _scrollContent(450),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _buildMainContent(),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildSectionTab(String label, IconData icon, IptvSection section) {
    final tokens = context.tokens;
    final isSelected = _activeSection == section;

    return FocusableCard(
      onTap: () {
        if (_activeSection != section) {
          setState(() => _activeSection = section);
          _loadSectionData();
        }
      },
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s12,
            vertical: ZplaySpacing.s8,
          ),
          decoration: BoxDecoration(
            // The selected tab is the only accent fill; unselected tabs are
            // text-only, so the group reads without a container behind it.
            color: isSelected ? tokens.accent : Colors.transparent,
            borderRadius: ZplayRadius.smAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? tokens.onAccent : tokens.textSecondary,
                size: 16,
              ),
              const SizedBox(width: ZplaySpacing.s8),
              Text(
                label,
                style: ZplayType.label
                    .copyWith(weight: isSelected ? FontWeight.w700 : FontWeight.w500)
                    .toStyle(color: isSelected ? tokens.onAccent : tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final tokens = context.tokens;
    final streams = _filteredStreams();
    if (streams.isEmpty) {
      if (_selectedCategoryId == favoritesCategoryId) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s16),
                decoration: BoxDecoration(
                  color: tokens.warning.withValues(alpha: ZplayOpacity.overlayHover),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_outline_rounded, color: tokens.warning, size: 48),
              ),
              const SizedBox(height: ZplaySpacing.s16),
              Text(
                'No Favorited Channels',
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'Tap the star icon on any channel to save it to your Favorites.',
                textAlign: TextAlign.center,
                style: ZplayType.body.toStyle(color: tokens.textMuted),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off_rounded, color: tokens.textDisabled, size: 48),
            const SizedBox(height: ZplaySpacing.s12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No streams matching "$_searchQuery"'
                  : 'No streams available in this category.',
              textAlign: TextAlign.center,
              style: ZplayType.body.toStyle(color: tokens.textMuted),
            ),
          ],
        ),
      );
    }

    final isDesktop = _isDesktop(context);

    if (_activeSection == IptvSection.live) {
      final layout = IptvSettings.browserLayout.value;

      if (layout == PortalBrowserLayout.grid) {
        final screenW = MediaQuery.sizeOf(context).width;
        int gridCols = IptvSettings.browserGridColumns.value;
        if (!isDesktop) {
          gridCols = screenW > 600 ? 3 : 2;
        }

        return GridView.builder(
          controller: _contentScrollController,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            childAspectRatio: 1.25,
            crossAxisSpacing: isDesktop ? 14 : 10,
            mainAxisSpacing: isDesktop ? 14 : 10,
          ),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return _LiveChannelGridCard(
              key: ValueKey(stream.streamId),
              index: index + 1,
              stream: stream,
              portal: widget.portal,
              isAlive: isAlive,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _playStream(stream),
            );
          },
        );
      } else if (layout == PortalBrowserLayout.compactList) {
        return ListView.builder(
          controller: _contentScrollController,
          itemExtent: 52.0,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _LiveChannelCompactListRow(
                key: ValueKey(stream.streamId),
                index: index + 1,
                stream: stream,
                portal: widget.portal,
                isAlive: isAlive,
                isFavorite: isFav,
                onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
                onTap: () => _playStream(stream),
              ),
            );
          },
        );
      } else {
        // Detailed List view
        return ListView.builder(
          controller: _contentScrollController,
          itemExtent: 78.0,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LiveChannelListRow(
                key: ValueKey(stream.streamId),
                index: index + 1,
                stream: stream,
                portal: widget.portal,
                isAlive: isAlive,
                isFavorite: isFav,
                onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
                onTap: () => _playStream(stream),
              ),
            );
          },
        );
      }
    } else {
      // ── MOVIES & SERIES GRID VIEW ──
      final screenW = MediaQuery.sizeOf(context).width;
      final sidebarW = isDesktop ? IptvSettings.sidebarWidth.value : 0.0;
      final width = isDesktop ? (screenW - sidebarW) : screenW;
      int crossAxisCount = 2;
      if (width > 1200) {
        crossAxisCount = 6;
      } else if (width > 900) {
        crossAxisCount = 5;
      } else if (width > 650) {
        crossAxisCount = 4;
      } else if (width > 420) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2;
      }

      return GridView.builder(
        controller: _contentScrollController,
        cacheExtent: 400.0,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.68,
          crossAxisSpacing: isDesktop ? 14 : 10,
          mainAxisSpacing: isDesktop ? 14 : 10,
        ),
        itemCount: streams.length,
        itemBuilder: (context, index) {
          final stream = streams[index];
          final isFav = _favoriteStreamIds.contains(stream.streamId);

          if (_activeSection == IptvSection.series) {
            return _VodSeriesCard(
              key: ValueKey(stream.streamId),
              stream: stream,
              isSeries: true,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _openSeriesEpisodes(stream),
            );
          } else {
            return _VodSeriesCard(
              key: ValueKey(stream.streamId),
              stream: stream,
              isSeries: false,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _playStream(stream),
            );
          }
        },
      );
    }
  }
}

class _CategoryListRow extends StatelessWidget {
  final IptvCategory category;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryListRow({
    required this.category,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isFavCategory = category.id == _IptvPortalBrowserPageState.favoritesCategoryId;
    final showCount = IptvSettings.showCategoryCount.value;

    return RepaintBoundary(
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s12,
              vertical: ZplaySpacing.s8,
            ),
            decoration: BoxDecoration(
              // Selection is a single accent wash; hover is a faint surface
              // lift. Neither draws a border, and unselected rows stay flat.
              color: isSelected
                  ? tokens.accentSubtle
                  : (state.highlighted ? tokens.borderSubtle : Colors.transparent),
              borderRadius: ZplayRadius.smAll,
            ),
            child: Row(
              children: [
                // A 3.5 dp accent tick marks the selected row without an outline.
                Container(
                  width: 3.5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? tokens.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s8),
                if (isFavCategory) ...[
                  Icon(Icons.star_rounded, color: tokens.warning, size: 16),
                  const SizedBox(width: ZplaySpacing.s8),
                ],
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.label
                        .copyWith(weight: isSelected ? FontWeight.w700 : FontWeight.w500)
                        .toStyle(color: isSelected ? tokens.textPrimary : tokens.textMuted),
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: ZplaySpacing.s8),
                  Text(
                    '$count',
                    style: ZplayType.caption.toStyle(
                      color: isSelected ? tokens.accent : tokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelListRow> createState() => _LiveChannelListRowState();
}

class _LiveChannelListRowState extends State<_LiveChannelListRow> {
  List<EpgEntry>? _cachedEpg;

  @override
  void initState() {
    super.initState();
    _cachedEpg = _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId];
  }

  void _loadEpg() async {
    if (!IptvSettings.showEpgSnippet.value) return;
    if (_cachedEpg != null || widget.portal == null || widget.stream.streamId.isEmpty) return;
    try {
      final entries = await IptvClient.shortEpg(widget.portal!.portal, widget.stream.streamId, limit: 2);
      if (mounted && entries.isNotEmpty) {
        _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId] = entries;
        setState(() => _cachedEpg = entries);
      }
    } catch (_) {}
  }

  /// Short identity label for the prototype's `.channel-logo-badge` slot: the
  /// first word of the real channel name, stripped of punctuation and capped at
  /// five characters. Nothing is invented — a name with no usable token falls
  /// back to its first alphanumeric character.
  static String _channelBadgeLabel(String name) {
    final first = name
        .trim()
        .split(RegExp(r'[\s|:·/–—]+'))
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
    final cleaned = first.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    final base = cleaned.isNotEmpty
        ? cleaned
        : name.trim().replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (base.isEmpty) return '—';
    return (base.length <= 5 ? base : base.substring(0, 5)).toUpperCase();
  }

  /// How far the now-airing programme has run, clamped to `0..1`.
  static double _nowAiringProgress(EpgEntry? entry) {
    if (entry == null) return 0.0;
    final total = entry.stop.difference(entry.start).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = DateTime.now().difference(entry.start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = widget.stream;
    final indexFormatted = widget.index.toString().padLeft(3, '0');
    final currentEpg = _cachedEpg?.isNotEmpty == true ? _cachedEpg!.first : null;
    final nextEpg = _cachedEpg != null && _cachedEpg!.length > 1 ? _cachedEpg![1] : null;
    final screenW = MediaQuery.sizeOf(context).width;
    final isVerySmall = screenW < 440;
    final isCompact = FormFactorService.of(context) == FormFactor.compact;
    final actionSize = isCompact ? 40.0 : kMinInteractiveDimension;
    final showLogo = IptvSettings.showStreamLogos.value;
    final showEpg = IptvSettings.showEpgSnippet.value;
    final meta = s.containerExt.toUpperCase();
    final badgeLabel = _channelBadgeLabel(s.name);
    final progress = _nowAiringProgress(currentEpg);

    return RepaintBoundary(
      child: FocusableCard(
        onTap: widget.onTap,
        builder: (context, state) => MouseRegion(
          // Pointer-only shortcut: FocusableCard owns tap; hover is kept only to fetch the EPG snippet lazily.
          onEnter: (_) => _loadEpg(),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: AnimatedContainer(
              duration: ZplayMotion.fast,
              curve: ZplayMotion.standard,
              constraints: BoxConstraints(minHeight: isCompact ? 48.0 : 56.0),
              padding: EdgeInsets.symmetric(
                horizontal: isVerySmall ? ZplaySpacing.s8 : ZplaySpacing.s12,
                vertical: ZplaySpacing.s8,
              ),
              decoration: BoxDecoration(
                color: state.highlighted ? tokens.borderStrong : tokens.surface,
                borderRadius: ZplayRadius.smAll,
              ),
              child: Row(
                children: [
                  // Index
                  if (!isVerySmall) ...[
                    SizedBox(
                      width: 30,
                      child: Text(
                        indexFormatted,
                        style: ZplayType.labelNumeric.toStyle(
                          color: tokens.textDisabled,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s8),
                  ],
  
                  // ── CHANNEL LOGO BAY ──
                  if (showLogo) ...[
                    Container(
                      width: isVerySmall ? 52 : 64,
                      height: isVerySmall ? 40 : 46,
                      padding: const EdgeInsets.all(ZplaySpacing.s4),
                      decoration: BoxDecoration(
                        color: tokens.bg,
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: s.icon.isNotEmpty
                          ? ClipRRect(
                              borderRadius: ZplayRadius.xsAll,
                              child: CachedNetworkImage(
                                imageUrl: s.icon,
                                cacheManager: AppImageCache.manager,
                                fit: BoxFit.contain,
                                memCacheWidth: 128,
                                errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: tokens.textDisabled, size: 20)),
                            )
                          : Icon(Icons.live_tv_rounded, color: tokens.textDisabled, size: 20),
                    ),
                    SizedBox(width: isVerySmall ? ZplaySpacing.s8 : ZplaySpacing.s12),
                  ],
  
                  // ── CHANNEL IDENTITY ──
                  // Prototype `.channel-logo-badge`: a short-name chip, then the
                  // name / real format tag stack.
                  Container(
                    constraints: const BoxConstraints(minWidth: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s8,
                      vertical: ZplaySpacing.s4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.borderStrong,
                      borderRadius: ZplayRadius.xsAll,
                    ),
                    child: Text(
                      badgeLabel,
                      textAlign: TextAlign.center,
                      style: ZplayType.caption
                          .copyWith(weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s12),

                  // Channel Title, Format Tag & EPG Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                        ),

                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.caption.toStyle(color: tokens.textMuted),
                          ),
                        ],

                        if (showEpg) ...[
                          const SizedBox(height: ZplaySpacing.s2),
                          if (currentEpg != null) ...[
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'NOW: ',
                                    style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                  ),
                                  TextSpan(
                                    text: currentEpg.title,
                                    style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                                  ),
                                  if (nextEpg != null) ...[
                                    TextSpan(
                                      text: '   NEXT: ',
                                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                    ),
                                    TextSpan(
                                      text: nextEpg.title,
                                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                    ),
                                  ],
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZplaySpacing.s2),
                            // Prototype `.epg-progress-bar` / `.epg-progress-fill`.
                            SizedBox(
                              height: ZplaySpacing.s4,
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: ZplayRadius.fullAll,
                                child: ColoredBox(
                                  color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    heightFactor: 1.0,
                                    child: ColoredBox(color: tokens.accent),
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            Text(
                              'Live Stream Feed',
                              style: ZplayType.caption.toStyle(color: tokens.textMuted),
                            ),
                        ],
                      ],
                    ),
                  ),
  
                  const SizedBox(width: ZplaySpacing.s8),

                  // LIVE tag — fill only, no outline (prototype `.channel-badge-live`).
                  if (widget.isAlive)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.danger,
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s4,
                          vertical: ZplaySpacing.s2,
                        ),
                        child: Text(
                          'LIVE',
                          style: ZplayType.overline
                              .copyWith(letterSpacing: 0.5)
                              .toStyle(color: tokens.textPrimary),
                        ),
                      ),
                    ),
  
                  const SizedBox(width: ZplaySpacing.s4),

                  // Favorite Button
                  SizedBox(
                    width: actionSize,
                    height: actionSize,
                    child: IconButton(
                      icon: Icon(
                        widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: widget.isFavorite ? tokens.warning : tokens.textMuted,
                        size: 21,
                      ),
                      tooltip: widget.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                      onPressed: widget.onToggleFavorite,
                    ),
                  ),

                  const SizedBox(width: ZplaySpacing.s4),

                  // Play affordance — own focus target, ring hugs the reserved
                  // target while the visible disc keeps its 32 dp size.
                  FocusableCard(
                    onTap: widget.onTap,
                    builder: (context, playState) => CardFocusRing(
                      focused: playState.focused,
                      radius: ZplayRadius.fullAll,
                      child: SizedBox(
                        width: actionSize,
                        height: actionSize,
                        child: Center(
                          child: AnimatedContainer(
                            duration: ZplayMotion.fast,
                            curve: ZplayMotion.standard,
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: (state.highlighted || playState.highlighted)
                                  ? tokens.accent
                                  : tokens.borderSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: tokens.onAccent,
                              size: 20,
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
        ),
      ),
    );
  }
}

class _LiveChannelGridCard extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelGridCard({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelGridCard> createState() => _LiveChannelGridCardState();
}

class _LiveChannelGridCardState extends State<_LiveChannelGridCard> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = widget.stream;
    final isCompact = FormFactorService.of(context) == FormFactor.compact;
    final actionSize = isCompact ? 40.0 : kMinInteractiveDimension;
    final showLogo = IptvSettings.showStreamLogos.value;

    return RepaintBoundary(
      child: FocusableCard(
        onTap: widget.onTap,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.mdAll,
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            padding: const EdgeInsets.all(ZplaySpacing.s8),
            decoration: BoxDecoration(
              color: state.highlighted ? tokens.borderStrong : tokens.surface,
              borderRadius: ZplayRadius.mdAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: logo/index + live badge + star
                Row(
                  children: [
                    if (showLogo && s.icon.isNotEmpty)
                      Container(
                        width: 44,
                        height: 32,
                        padding: const EdgeInsets.all(ZplaySpacing.s2),
                        decoration: BoxDecoration(
                          color: tokens.bg,
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: ClipRRect(
                          borderRadius: ZplayRadius.xsAll,
                          child: CachedNetworkImage(
                            imageUrl: s.icon,
                            cacheManager: AppImageCache.manager,
                            fit: BoxFit.contain,
                            memCacheWidth: 100,
                            errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: tokens.textDisabled, size: 16)),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s4,
                          vertical: ZplaySpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.borderSubtle,
                          borderRadius: ZplayRadius.xsAll,
                        ),
                        child: Text(
                          '#${widget.index}',
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        ),
                      ),

                    const Spacer(),

                    if (widget.isAlive)
                      Padding(
                        padding: const EdgeInsets.only(right: ZplaySpacing.s4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.danger,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s4,
                              vertical: ZplaySpacing.s2,
                            ),
                            child: Text(
                              'LIVE',
                              style: ZplayType.overline
                                  .copyWith(letterSpacing: 0.5)
                                  .toStyle(color: tokens.textPrimary),
                            ),
                          ),
                        ),
                      ),

                    // 48 dp focus target on non-compact; the star keeps its size.
                    SizedBox(
                      width: actionSize,
                      height: actionSize,
                      child: FocusableCard(
                        onTap: widget.onToggleFavorite,
                        builder: (context, starState) => CardFocusRing(
                          focused: starState.focused,
                          radius: ZplayRadius.fullAll,
                          child: Center(
                            child: Icon(
                              widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: widget.isFavorite ? tokens.warning : tokens.textMuted,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Channel Title
                Text(
                  s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),

                const SizedBox(height: ZplaySpacing.s4),

                // Bottom row: format tag + Play Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s4,
                        vertical: ZplaySpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Text(
                        s.containerExt.toUpperCase(),
                        style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
                      ),
                    ),
                    AnimatedContainer(
                      duration: ZplayMotion.fast,
                      curve: ZplayMotion.standard,
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: state.highlighted ? tokens.accent : tokens.borderSubtle,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: tokens.onAccent,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelCompactListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelCompactListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelCompactListRow> createState() => _LiveChannelCompactListRowState();
}

class _LiveChannelCompactListRowState extends State<_LiveChannelCompactListRow> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = widget.stream;
    final showLogo = IptvSettings.showStreamLogos.value;

    return RepaintBoundary(
      child: FocusableCard(
        onTap: widget.onTap,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s12,
              vertical: ZplaySpacing.s8,
            ),
            decoration: BoxDecoration(
              // Resting rows are a plain surface; highlight lifts the fill only.
              color: state.highlighted ? tokens.borderStrong : tokens.surface,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    widget.index.toString().padLeft(3, '0'),
                    style: ZplayType.labelNumeric.toStyle(color: tokens.textDisabled),
                  ),
                ),
                if (showLogo && s.icon.isNotEmpty) ...[
                  const SizedBox(width: ZplaySpacing.s8),
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: ClipRRect(
                      borderRadius: ZplayRadius.xsAll,
                      child: CachedNetworkImage(
                        imageUrl: s.icon,
                        cacheManager: AppImageCache.manager,
                        fit: BoxFit.contain,
                        memCacheWidth: 64,
                        errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: tokens.textDisabled, size: 14)),
                    ),
                  ),
                ],
                const SizedBox(width: ZplaySpacing.s8),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  ),
                ),
                if (widget.isAlive)
                  Padding(
                    padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.danger,
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s4,
                          vertical: ZplaySpacing.s2,
                        ),
                        child: Text(
                          'LIVE',
                          style: ZplayType.overline
                              .copyWith(letterSpacing: 0.5)
                              .toStyle(color: tokens.textPrimary),
                        ),
                      ),
                    ),
                  ),
                FocusableCard(
                  onTap: widget.onToggleFavorite,
                  builder: (context, starState) => CardFocusRing(
                    focused: starState.focused,
                    radius: ZplayRadius.fullAll,
                    child: Icon(
                      widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: widget.isFavorite ? tokens.warning : tokens.textMuted,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Icon(
                  Icons.play_arrow_rounded,
                  color: state.highlighted ? tokens.accent : tokens.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VodSeriesCard extends StatefulWidget {
  final IptvStream stream;
  final bool isSeries;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _VodSeriesCard({
    super.key,
    required this.stream,
    required this.isSeries,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_VodSeriesCard> createState() => _VodSeriesCardState();
}

class _VodSeriesCardState extends State<_VodSeriesCard> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = widget.stream;

    return RepaintBoundary(
      child: FocusableCard(
        onTap: widget.onTap,
        builder: (context, state) => AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          scale: state.highlighted ? 1.035 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CardFocusRing(
                  focused: state.focused,
                  radius: ZplayRadius.mdAll,
                  child: Container(
                    decoration: BoxDecoration(
                      // Fill only — no frame and no glow around the poster.
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                    ),
                    child: ClipRRect(
                      borderRadius: ZplayRadius.mdAll,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          s.icon.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.icon,
                                  cacheManager: AppImageCache.manager,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 256,
                                  errorWidget: (_, _, _) => Center(
                                    child: Icon(Icons.movie_rounded, color: tokens.textDisabled, size: 32),
                                  ))
                              : Center(
                                  child: Icon(Icons.movie_rounded, color: tokens.textDisabled, size: 32),
                                ),
                          // Over-art scrim: keeps the play glyph readable on any still.
                          if (state.highlighted)
                            Positioned.fill(
                              child: ColoredBox(
                                color: const Color(0x73000000),
                                child: Center(
                                  child: Icon(Icons.play_circle_fill_rounded, color: tokens.accent, size: 40),
                                ),
                              ),
                            ),
                          // Floating Favorite Star Button — its own focus target, so
                          // a remote can reach it and the ring marks it.
                          Positioned(
                            top: ZplaySpacing.s8,
                            right: ZplaySpacing.s8,
                            child: FocusableCard(
                              onTap: widget.onToggleFavorite,
                              builder: (context, starState) => CardFocusRing(
                                focused: starState.focused,
                                radius: ZplayRadius.fullAll,
                                child: Container(
                                  padding: const EdgeInsets.all(ZplaySpacing.s4),
                                  decoration: const BoxDecoration(
                                    // Scrim over artwork so the glyph stays legible.
                                    color: Color(0xBF000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: widget.isFavorite ? tokens.warning : tokens.textPrimary,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZplayType.caption.toStyle(color: tokens.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesEpisodesSheet extends StatefulWidget {
  final VerifiedPortal portal;
  final IptvStream series;

  const _SeriesEpisodesSheet({required this.portal, required this.series});

  @override
  State<_SeriesEpisodesSheet> createState() => _SeriesEpisodesSheetState();
}

class _SeriesEpisodesSheetState extends State<_SeriesEpisodesSheet> {
  bool _isLoading = true;
  List<IptvEpisode> _episodes = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    try {
      final eps = await IptvClient.seriesEpisodes(widget.portal.portal, widget.series.streamId);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _playEpisode(IptvEpisode ep) {
    final epIndex = _episodes.indexWhere((e) => e.id == ep.id);
    final initialIndex = epIndex >= 0 ? epIndex : 0;

    final hits = _episodes.map((e) {
      final s = IptvStream(
        streamId: e.id,
        name: '${widget.series.name} - S${e.season}E${e.episode} ${e.title}',
        icon: e.image.isNotEmpty ? e.image : widget.series.icon,
        categoryId: widget.series.categoryId,
        containerExt: e.containerExt,
        kind: 'series',
      );
      return ChannelHit(
        portal: widget.portal,
        stream: s,
        streamUrl: IptvClient.streamUrl(widget.portal.portal, s),
      );
    }).toList();

    final currentStream = (hits.isNotEmpty && initialIndex < hits.length)
        ? hits[initialIndex].stream
        : IptvStream(
            streamId: ep.id,
            name: '${widget.series.name} - S${ep.season}E${ep.episode} ${ep.title}',
            icon: ep.image.isNotEmpty ? ep.image : widget.series.icon,
            categoryId: widget.series.categoryId,
            containerExt: ep.containerExt,
            kind: 'series',
          );

    final ch = HardcodedChannel(
      id: ep.id,
      name: currentStream.name,
      short: 'TV',
      category: widget.series.name,
      keywords: [widget.series.name],
      gradient: [context.tokens.accent, context.tokens.info],
    );

    Navigator.pop(context);
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: IptvPlayerPage(
          channel: ch,
          hits: hits.isNotEmpty
              ? hits
              : [
                  ChannelHit(
                    portal: widget.portal,
                    stream: currentStream,
                    streamUrl: IptvClient.streamUrl(widget.portal.portal, currentStream),
                  ),
                ],
          initialHitIndex: initialIndex,
          isLive: false,
          categoryTitle: '${widget.series.name} Episodes',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        // Sheet surface only: no top hairline; the rounded top is the chrome.
        color: tokens.surfaceOverlay,
        borderRadius: ZplayRadius.sheetTop,
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: ZplaySpacing.s12, bottom: ZplaySpacing.s8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.series.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.title.toStyle(color: tokens.textPrimary),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: tokens.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: tokens.accent))
                : _error != null
                    ? ErrorView(
                        error: _error,
                        onRetry: _loadEpisodes,
                        title: 'Could not load episodes',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s20,
                          vertical: ZplaySpacing.s8,
                        ),
                        itemCount: _episodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: ZplaySpacing.s8),
                        itemBuilder: (context, index) {
                          final ep = _episodes[index];
                          return FocusableCard(
                            onTap: () => _playEpisode(ep),
                            builder: (context, state) => CardFocusRing(
                              focused: state.focused,
                              radius: ZplayRadius.smAll,
                              child: AnimatedContainer(
                                duration: ZplayMotion.fast,
                                curve: ZplayMotion.standard,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s12,
                                  vertical: ZplaySpacing.s12,
                                ),
                                decoration: BoxDecoration(
                                  color: state.highlighted ? tokens.borderStrong : tokens.surface,
                                  borderRadius: ZplayRadius.smAll,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: ZplaySpacing.s8,
                                        vertical: ZplaySpacing.s4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.accentSubtle,
                                        borderRadius: ZplayRadius.xsAll,
                                      ),
                                      child: Text(
                                        'S${ep.season}E${ep.episode}',
                                        style: ZplayType.label.toStyle(color: tokens.accent),
                                      ),
                                    ),
                                    const SizedBox(width: ZplaySpacing.s12),
                                    Expanded(
                                      child: Text(
                                        ep.title.isNotEmpty ? ep.title : 'Episode ${ep.episode}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                      ),
                                    ),
                                    const SizedBox(width: ZplaySpacing.s8),
                                    Icon(Icons.play_circle_fill_rounded, color: tokens.accent),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _VerticalScrollButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _VerticalScrollButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.fullAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            // Floats over content: an opaque raised fill keeps it legible; the
            // highlight turns it into the one accent. No outline, no shadow.
            color: state.highlighted ? tokens.accent : tokens.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: state.highlighted ? tokens.onAccent : tokens.textPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
