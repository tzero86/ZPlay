import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/link.dart';
import '../../models/movie/video.dart';
import '../../models/movie/movie_detail.dart';

import '../../models/stream/stream_model.dart';
import '../../services/diagnostics/crash_breadcrumbs.dart';
import '../../models/subtitle/subtitle_model.dart';
import './player_screen.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/debrid/debrid_rejection_store.dart';
import '../../services/stream/stream_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/scraper/builtin_providers_settings_service.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/player/stream_bitrate_badge.dart';
import '../settings/settings_page.dart';
import '../details/details_page.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../services/storage/app_image_cache.dart';

// ---------------------------------------------------------------------------
// WatchScreen
// ---------------------------------------------------------------------------
class WatchScreen extends StatefulWidget {
  final MovieDetail detail;
  final Video? selectedEpisode;
  final String type;
  final Duration? initialPosition;

  final bool isCollection;

  const WatchScreen({
    super.key,
    required this.detail,
    this.selectedEpisode,
    required this.type,
    this.initialPosition,
    this.isCollection = false,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with SingleTickerProviderStateMixin {
  bool get _isCollection =>
      widget.isCollection ||
      widget.type == 'collections' ||
      widget.type == 'collection' ||
      widget.detail.isCollection ||
      (widget.selectedEpisode != null &&
          widget.selectedEpisode!.id.startsWith('tt') &&
          (widget.detail.type == 'collections' ||
              widget.detail.type == 'collection' ||
              widget.detail.isCollection));

  // Stream sources
  final List<StreamSource> _sources = [];
  final List<StreamSource> _pendingSources = [];
  final List<SubtitleVariant> _discoveredSubtitles = [];
  final Set<String> _seenSubtitleUrls = {};
  Timer? _sourceBatchTimer;
  bool _isLoadingSources = true;
  StreamSubscription<StreamSource>? _streamSub;

  void _recordSubtitles(List<SubtitleVariant>? subs) {
    if (subs == null || subs.isEmpty) return;
    for (final s in subs) {
      if (_seenSubtitleUrls.add(s.downloadUrl.toLowerCase())) {
        _discoveredSubtitles.add(s);
      }
    }
  }

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Scroll
  final ScrollController _sourcesScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  // Addon priority caching
  Map<String, int>? _cachedAddonOrder;
  Map<String, int> get _addonOrder {
    if (_cachedAddonOrder != null) return _cachedAddonOrder!;
    final map = <String, int>{};
    final allAddons = AddonManager.instance.addons;
    for (int i = 0; i < allAddons.length; i++) {
      final a = allAddons[i];
      map[a.manifest.name.toLowerCase()] = i;
      map[a.manifest.id.toLowerCase()] = i;
      if (a.manifest.id == 'builtin.zplayhttp' || a.baseUrl == 'builtin:zplayhttp') {
        map['zplayhttp'] = i;
      }
      if (a.manifest.id == 'builtin.zplay' || a.baseUrl == 'builtin:zplay') {
        map['zplay'] = i;
      }
    }
    return _cachedAddonOrder = map;
  }

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
    _loadDebridState();
    _loadStreams();

    // A hash remembered as refused while this screen is open (the player writes
    // one the moment a provider refuses) has to reach the list, so the badge and
    // the ordering follow without a reopen.
    DebridRejectionStore.revision.addListener(_onRejectionsChanged);
  }

  @override
  void dispose() {
    DebridRejectionStore.revision.removeListener(_onRejectionsChanged);
    _streamSub?.cancel();
    _streamSub = null;
    StreamService.stopAllScrapers();
    _sourceBatchTimer?.cancel();
    _animController.dispose();
    _sourcesScrollController.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  /// The rejection memory changed somewhere (the player remembers a refusal),
  /// so the badges and the ordering of the source list are stale.
  void _onRejectionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStreams() async {
    _streamSub?.cancel();
    _streamSub = null;
    StreamService.stopAllScrapers();

    final streamId = widget.selectedEpisode?.id ?? widget.detail.id;

    // 1. Immediately inject any embedded streams from the video (e.g. Torbox/Debrid direct streams)
    if (widget.selectedEpisode != null && widget.selectedEpisode!.streams.isNotEmpty) {
      for (final s in widget.selectedEpisode!.streams) {
        _recordSubtitles(s.subtitles);
      }
      _pendingSources.addAll(widget.selectedEpisode!.streams);
      _flushPendingSources();
    }

    final isColl = _isCollection;
    final effectiveType = isColl ? 'movie' : widget.type;
    final effectiveTitle = (isColl && widget.selectedEpisode != null)
        ? widget.selectedEpisode!.title
        : widget.detail.name;
    final epReleased = widget.selectedEpisode?.released;
    final effectiveYear = (isColl && epReleased != null && epReleased.length >= 4)
        ? int.tryParse(epReleased.substring(0, 4))
        : int.tryParse(widget.detail.year ?? '');
    final effectiveSeason = isColl ? null : widget.selectedEpisode?.season;
    final effectiveEpisode = isColl ? null : widget.selectedEpisode?.episode;

    _streamSub = StreamService.fetchStreams(
      type: effectiveType,
      id: streamId,
      title: effectiveTitle,
      year: effectiveYear,
      season: effectiveSeason,
      episode: effectiveEpisode,
      genres: widget.detail.genres,
    ).listen(
      (source) {
        if (!mounted) return;
        _recordSubtitles(source.subtitles);
        _pendingSources.add(source);
        if (_sources.isEmpty) {
          _flushPendingSources();
        } else {
          _sourceBatchTimer ??= Timer(
            const Duration(milliseconds: 50),
            _flushPendingSources,
          );
        }
      },
      onError: (_) {},
      onDone: () {
        _flushPendingSources();
        if (mounted && _isLoadingSources) {
          setState(() => _isLoadingSources = false);
        }
      },
    );
  }

  void _flushPendingSources() {
    _sourceBatchTimer?.cancel();
    _sourceBatchTimer = null;
    if (!mounted || _pendingSources.isEmpty) return;

    final batch = List<StreamSource>.of(_pendingSources);
    _pendingSources.clear();
    setState(() {
      _sources.addAll(batch);
    });
  }

  String? _selectedAddonFilter;
  String? _selectedSizeFilter;
  String _selectedTypeFilter = 'all'; // 'all', 'debrid', 'torrent', 'direct'
  String _selectedSeederFilter = 'all'; // 'all', 'most', '50+', '20+', '5+', '1+'
  String _selectedAudioFilter = 'all'; // 'all', 'multi', 'english', 'hindi', 'german', 'french', 'spanish', 'spanish_castilian', 'spanish_latino', 'russian', 'japanese', 'italian'

  /// Whether torrent sources will be resolved by a Debrid service rather than by
  /// the local P2P engine, so the list can count and label them accordingly.
  bool _debridReady = false;
  String? _debridServiceName;

  Future<void> _loadDebridState() async {
    final ready = DebridService.isDebridReady.value;
    final service = ready ? await DebridService().getSelectedService() : null;
    if (!mounted) return;
    setState(() {
      _debridReady = ready;
      _debridServiceName = service;
    });
  }

  /// A Debrid source is either a link an addon already resolved for us, or a
  /// magnet that our active Debrid service will resolve in the cloud.
  bool _isDebridSource(StreamSource s) =>
      s.isDebridPlayable(debridReady: _debridReady);

  List<StreamSource> get _filteredSources {
    var list = List<StreamSource>.from(_sources);
    if (_selectedAddonFilter != null) {
      list = list.where((s) => s.addonName == _selectedAddonFilter).toList();
    }
    if (_selectedTypeFilter == 'debrid') {
      list = list.where(_isDebridSource).toList();
    } else if (_selectedTypeFilter == 'torrent') {
      list = list.where((s) => s.isTorrent).toList();
    } else if (_selectedTypeFilter == 'direct') {
      list = list.where((s) => s.isHttpDirect).toList();
    }
    if (_selectedSizeFilter != null) {
      switch (_selectedSizeFilter) {
        case '<1gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz < 1024 * 1024 * 1024;
          }).toList();
          break;
        case '1-5gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz >= 1024 * 1024 * 1024 && sz <= 5.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '5-15gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 5.0 * 1024 * 1024 * 1024 && sz <= 15.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '15-30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 15.0 * 1024 * 1024 * 1024 && sz <= 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '>30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
      }
    }

    if (_selectedSeederFilter == '50+') {
      list = list.where((s) => (s.seeders ?? 0) >= 50).toList();
    } else if (_selectedSeederFilter == '20+') {
      list = list.where((s) => (s.seeders ?? 0) >= 20).toList();
    } else if (_selectedSeederFilter == '5+') {
      list = list.where((s) => (s.seeders ?? 0) >= 5).toList();
    } else if (_selectedSeederFilter == '1+') {
      list = list.where((s) => (s.seeders ?? 0) >= 1).toList();
    }

    // Filter by audio language / dub
    if (_selectedAudioFilter != 'all') {
      list = list
          .where((s) => s.hasAudioLanguage(_selectedAudioFilter,
              mediaTitle: widget.detail.name))
          .toList();
    }

    // Filter by active status of built-in providers. Torrents stay listed while a
    // Debrid service can resolve them, even with the local P2P engine switched off.
    if (!AddonManager.instance.isZplayActive && !_debridReady) {
      list = list.where((s) => !s.isTorrent || s.isDebrid).toList();
    }
    if (!AddonManager.instance.isZplayHttpActive) {
      list = list.where((s) => s.addonName.toLowerCase() != 'zplayhttp').toList();
    }

    // Cached dynamic addon priority lookup from user's installed addons order
    final addonOrder = _addonOrder;
    final isCustomBuiltin = BuiltinProvidersSettingsService.instance.isCustom;

    list.sort((a, b) {
      final isHttpA = a.addonName.toLowerCase() == 'zplayhttp';
      final isHttpB = b.addonName.toLowerCase() == 'zplayhttp';

      // When custom Built-in providers mode is active, provider rank strictly dictates order
      if (isCustomBuiltin && isHttpA && isHttpB) {
        final pidA = a.providerId ?? BuiltinProvidersSettingsService.detectProviderId(a);
        final pidB = b.providerId ?? BuiltinProvidersSettingsService.detectProviderId(b);
        final rankA = BuiltinProvidersSettingsService.instance.getProviderRank(pidA);
        final rankB = BuiltinProvidersSettingsService.instance.getProviderRank(pidB);
        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
        // Within the same provider, sort by secondary filter / quality:
        if (_selectedSeederFilter == 'most') {
          return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
        } else if (_selectedSizeFilter == 'largest') {
          return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
        } else if (_selectedSizeFilter == 'smallest') {
          return (a.sizeBytes ?? double.infinity).compareTo(b.sizeBytes ?? double.infinity);
        } else {
          final qComp = b.qualityRank.compareTo(a.qualityRank);
          if (qComp != 0) return qComp;
          return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
        }
      }

      // Addon-level order comparison
      final orderA = addonOrder[a.addonName.toLowerCase()] ?? 999;
      final orderB = addonOrder[b.addonName.toLowerCase()] ?? 999;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // Standard sort across streams of the same addon
      if (_selectedSeederFilter == 'most') {
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      } else if (_selectedSizeFilter == 'largest') {
        return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
      } else if (_selectedSizeFilter == 'smallest') {
        return (a.sizeBytes ?? double.infinity).compareTo(b.sizeBytes ?? double.infinity);
      } else {
        final qComp = b.qualityRank.compareTo(a.qualityRank);
        if (qComp != 0) return qComp;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      }
    });

    // Torrents the provider has already refused sink to the bottom, keeping the
    // ranking above intact inside both groups. They stay listed and selectable:
    // this is information, not an error, and a refusal only holds until the
    // provider changes its mind. Partitioned by hand because sort() is not
    // stable and would shuffle the ranking it just produced.
    final usable = <StreamSource>[];
    final refused = <StreamSource>[];
    for (final s in list) {
      (DebridRejectionStore.instance.isRejected(s.infoHash) ? refused : usable)
          .add(s);
    }
    return <StreamSource>[...usable, ...refused];
  }

  /// The ranked remainder behind [index] in the visible list, minus the torrents
  /// a provider has already refused. This is what the player walks when the
  /// source at [index] fails, and handing it back a refused torrent would only
  /// spend one of its attempts.
  List<StreamSource> _alternativesAfter(List<StreamSource> list, int index) {
    final store = DebridRejectionStore.instance;
    return list
        .skip(index + 1)
        .where((s) => !store.isRejected(s.infoHash))
        .toList();
  }

  String _getSeederFilterLabel(String filter) {
    switch (filter) {
      case 'most':
        return 'Most Seeds';
      case '50+':
        return '50+ Seeds';
      case '20+':
        return '20+ Seeds';
      case '5+':
        return '5+ Seeds';
      case '1+':
        return 'Active Seeds';
      default:
        return 'All Seeds';
    }
  }

  String _getSizeFilterLabel(String? filter) {
    switch (filter) {
      case '<1gb':
        return '< 1 GB';
      case '1-5gb':
        return '1–5 GB';
      case '5-15gb':
        return '5–15 GB';
      case '15-30gb':
        return '15–30 GB';
      case '>30gb':
        return '> 30 GB';
      case 'largest':
        return 'Largest';
      case 'smallest':
        return 'Smallest';
      default:
        return 'All Sizes';
    }
  }

  bool _isDesktop() => MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bgUrl = widget.detail.background ?? widget.detail.poster;
    final isDesktop = _isDesktop();

    final background = Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: context.tokens.bg)),
        if (bgUrl != null) _buildBackdrop(bgUrl, screenSize, isDesktop),
      ],
    );
    final content = Stack(
      children: [
        SafeArea(
          child: isDesktop
              ? _buildDesktopLayout(screenSize)
              : _buildMobileLayout(screenSize),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          child: _buildBackButton(),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: context.tokens.bg,
      body: ValueListenableBuilder<bool>(
        valueListenable: GlassSettings.enabled,
        builder: (context, enabled, _) {
          if (enabled) {
            return LiquidGlassView(
              realTimeCapture: true,
              useSync: true,
              pixelRatio: 0.85,
              refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
              regionCapture: true,
              backgroundWidget: background,
              child: content,
            );
          }
          return Stack(children: [background, content]);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Backdrop
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackdrop(String url, Size screenSize, bool isDesktop) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            cacheManager: AppImageCache.manager,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => ColoredBox(color: context.tokens.bg)),
          // Left-to-right dimming: dark on left (text side), lighter on right
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  context.tokens.bg.withValues(alpha: isDesktop ? 0.92 : 0.88),
                  context.tokens.bg.withValues(alpha: isDesktop ? 0.70 : 0.60),
                  context.tokens.bg.withValues(alpha: isDesktop ? 0.20 : 0.15),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Bottom vertical gradient for legibility
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.tokens.bg.withValues(alpha: 0.30),
                  context.tokens.bg.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Desktop: side-by-side 60/40
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(Size screenSize) {
    final isWide = screenSize.width >= 1500;
    final leftFlex = isWide ? 5 : 5;
    final rightFlex = isWide ? 5 : 6;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 60,
            left: 48,
            right: 0,
            bottom: 24,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: info region
              Expanded(
                flex: leftFlex,
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: _buildInfoRegion(isDesktop: true),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s32),
              // Right: sources panel (extends to right edge)
              Expanded(
                flex: rightFlex,
                child: Padding(
                  padding: const EdgeInsets.only(right: ZplaySpacing.s24),
                  child: _buildSourcesPanel(isDesktop: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mobile: stacked vertically
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(Size screenSize) {
    final filtered = _filteredSources;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          controller: _mainScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Top padding ──
            const SliverPadding(padding: EdgeInsets.only(top: 60)),

            // ── Info region (single box) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                child: _buildInfoRegion(isDesktop: false),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(top: ZplaySpacing.s24)),

            // ── Sources header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.stream_rounded,
                              color: context.tokens.accent,
                              size: 20,
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            Text(
                              'Watch Sources',
                              style: ZplayType.title.toStyle(
                                color: context.tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _isLoadingSources
                              ? (filtered.isEmpty
                                  ? 'Searching sources...'
                                  : '${filtered.length} found · Searching...')
                              : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
                          style: ZplayType.bodySmall.toStyle(
                            color: context.tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
                          _buildTypeChip(
                            'debrid',
                            '⚡ ${_debridServiceName ?? 'Debrid'} (${_sources.where(_isDebridSource).length})',
                            Icons.bolt_rounded,
                            context.tokens.info,
                          ),
                          _buildTypeChip(
                            'torrent',
                            '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                            Icons.share_rounded,
                            context.tokens.accent,
                          ),
                          _buildTypeChip(
                            'direct',
                            '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                            Icons.link_rounded,
                            context.tokens.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: ZplaySpacing.s8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildSeederFilterDropdown(),
                          _buildSizeFilterDropdown(),
                          _buildAddonFilterDropdown(),
                          _buildAudioFilterDropdown(),
                        ],
                      ),
                    ],
                    const SizedBox(height: ZplaySpacing.s16),
                  ],
                ),
              ),
            ),

            // ── Sources list (virtualized!) ──
            if (_isLoadingSources && filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                sliver: SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
                    child: _buildShimmerCard(),
                  ),
                ),
              )
            else if (!_isLoadingSources && filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                  child: _buildEmptyState(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                sliver: SliverList.builder(
                  itemCount: filtered.length + (_isLoadingSources ? 2 : 0),
                  itemBuilder: (context, index) {
                    if (index >= filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
                        child: _buildShimmerCard(),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
                      child: _SourceCard(
                        source: filtered[index],
                        backdropUrl:
                            widget.detail.background ?? widget.detail.poster,
                        logoUrl: widget.detail.logo,
                        detail: widget.detail,
                        episode: widget.selectedEpisode,
                        initialPosition: widget.initialPosition,
                        initialSubtitles: _discoveredSubtitles,
                        alternatives: _alternativesAfter(filtered, index),
                      ),
                    );
                  },
                ),
              ),

            // ── Bottom padding ──
            const SliverPadding(padding: EdgeInsets.only(bottom: ZplaySpacing.s24)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Info Region
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInfoRegion({required bool isDesktop}) {
    final meta = widget.detail;
    final ep = widget.selectedEpisode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Episode info header (if applicable)
        if (ep != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: 6),
            decoration: BoxDecoration(
              color: context.tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(color: context.tokens.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              _isCollection
                  ? 'PART ${ep.episode ?? 1}'
                  : 'S${ep.season ?? '?' }E${ep.episode ?? '?' }',
              style: ZplayType.label
                  .copyWith(weight: FontWeight.w700, letterSpacing: 0.5)
                  .toStyle(color: context.tokens.accent),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s12),
        ],

        // Logo or title
        _buildLogoOrTitle(meta, isDesktop),
        const SizedBox(height: ZplaySpacing.s12),

        // Episode title (if applicable, different from series title)
        if (ep != null && ep.title.isNotEmpty && ep.title != meta.name)
          Padding(
            padding: const EdgeInsets.only(bottom: ZplaySpacing.s12),
            child: Text(
              ep.title,
              style: ZplayType.title.toStyle(
                color: context.tokens.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),

        // Meta row
        _buildMetaRow(meta),
        const SizedBox(height: ZplaySpacing.s16),

        // Genre pills
        if (meta.genres.isNotEmpty) ...[
          _buildGenrePills(meta.genres),
          const SizedBox(height: ZplaySpacing.s24),
        ],

        // Synopsis
        if (_getSynopsis() != null) ...[
          _buildSynopsis(_getSynopsis()!),
          const SizedBox(height: ZplaySpacing.s24),
        ],

        // Director
        if (meta.director.isNotEmpty) ...[
          _buildLabelChips('DIRECTOR', meta.director),
          const SizedBox(height: ZplaySpacing.s16),
        ],

        // Cast
        if (meta.cast.isNotEmpty) ...[
          _buildLabelChips('CAST', meta.cast.take(8).toList()),
          const SizedBox(height: ZplaySpacing.s24),
        ],

        // Action bar
        _buildActionBar(),
        const SizedBox(height: ZplaySpacing.s24),
      ],
    );
  }

  String? _getSynopsis() {
    final ep = widget.selectedEpisode;
    if (ep != null && ep.overview != null && ep.overview!.isNotEmpty) {
      return ep.overview;
    }
    return widget.detail.description;
  }

  Widget _buildLogoOrTitle(MovieDetail meta, bool isDesktop) {
    if (meta.logo != null && meta.logo!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 380 : 260,
          maxHeight: isDesktop ? 120 : 80,
        ),
        child: CachedNetworkImage(
          imageUrl: meta.logo!,
          cacheManager: AppImageCache.manager,
          alignment: Alignment.bottomLeft,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _buildTextTitle(meta.name, isDesktop)),
      );
    }
    return _buildTextTitle(meta.name, isDesktop);
  }

  Widget _buildTextTitle(String text, bool isDesktop) {
    return Text(
      text,
      style: ZplayType.display
          .copyWith(size: isDesktop ? 36 : 28)
          .toStyle(color: context.tokens.textPrimary)
          .copyWith(
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
    );
  }

  Widget _buildMetaRow(MovieDetail meta) {
    final items = <Widget>[];

    if (meta.year != null && meta.year!.isNotEmpty) {
      items.add(
        Text(
          meta.year!,
          style: ZplayType.body
              .copyWith(weight: FontWeight.w600)
              .toStyle(color: context.tokens.textPrimary),
        ),
      );
    }

    if (meta.runtime != null && meta.runtime!.isNotEmpty) {
      items.add(
        Text(
          meta.runtime!,
          style: ZplayType.body
              .toStyle(color: context.tokens.textSecondary),
        ),
      );
    }

    if (meta.imdbRating != null && meta.imdbRating!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8, vertical: 3),
          decoration: BoxDecoration(
            color: context.tokens.warning.withValues(alpha: ZplayOpacity.overlayHover),
            borderRadius: ZplayRadius.xsAll,
            border: Border.all(color: context.tokens.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, color: context.tokens.warning, size: 14),
              const SizedBox(width: 3),
              Text(
                meta.imdbRating!,
                style: ZplayType.bodySmall
                    .copyWith(weight: FontWeight.w700)
                    .toStyle(color: context.tokens.warning),
              ),
            ],
          ),
        ),
      );
    }

    final spaced = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
            child: Text(
              '·',
              style: ZplayType.body.toStyle(color: context.tokens.textMuted),
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: spaced,
    );
  }

  Widget _buildGenrePills(List<String> genres) {
    return Wrap(
      spacing: ZplaySpacing.s8,
      runSpacing: ZplaySpacing.s8,
      children: genres
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: 6),
              decoration: BoxDecoration(
                color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderDefault),
                borderRadius: ZplayRadius.fullAll,
                border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium)),
              ),
              child: Text(
                g,
                style: ZplayType.bodySmall
                    .copyWith(weight: FontWeight.w500)
                    .toStyle(color: context.tokens.textSecondary),
              ),
            ),
          )
          .toList(),
    );
  }

  bool _synopsisExpanded = false;

  Widget _buildSynopsis(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ZplayType.body
                .copyWith(height: 1.6)
                .toStyle(color: context.tokens.textSecondary),
          ),
          secondChild: Text(
            text,
            style: ZplayType.body
                .copyWith(height: 1.6)
                .toStyle(color: context.tokens.textSecondary),
          ),
          crossFadeState: _synopsisExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: ZplayType.body.copyWith(height: 1.6).toStyle(),
              ),
              maxLines: 3,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);

            if (!painter.didExceedMaxLines) return const SizedBox.shrink();

            return FocusableCard(
              onTap: () =>
                  setState(() => _synopsisExpanded = !_synopsisExpanded),
              builder: (context, _) => Text(
                _synopsisExpanded ? 'Show less' : 'Read more',
                style: ZplayType.label
                    .copyWith(weight: FontWeight.w600)
                    .toStyle(color: context.tokens.accent),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLabelChips(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ZplayType.caption
              .copyWith(weight: FontWeight.w600, letterSpacing: 1.0)
              .toStyle(color: context.tokens.textMuted),
        ),
        const SizedBox(height: ZplaySpacing.s8),
        Wrap(
          spacing: ZplaySpacing.s8,
          runSpacing: ZplaySpacing.s8,
          children: items
              .map(
                (name) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: context.tokens.surfaceRaised,
                    borderRadius: ZplayRadius.fullAll,
                  ),
                  child: Text(
                    name,
                    style: ZplayType.bodySmall.toStyle(color: context.tokens.textSecondary),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final links = widget.detail.links.take(4).toList();

    // Fallback if no links provided by addon
    if (links.isEmpty && widget.detail.id.startsWith('tt')) {
      links.add(
        Link(
          name: 'IMDb',
          category: 'imdb',
          url: 'https://www.imdb.com/title/${widget.detail.id}/',
        ),
      );
    }

    if (links.isEmpty) {
      // Generic fallback
      final query = Uri.encodeComponent(
        '${widget.detail.name} ${widget.detail.year ?? ''}',
      );
      links.add(
        Link(
          name: 'Search',
          category: 'web',
          url: 'https://google.com/search?q=$query',
        ),
      );
    }

    return Row(
      children: links.map((link) {
        IconData icon = Icons.link_rounded;
        final nameLower = link.name.toLowerCase();
        final catLower = link.category.toLowerCase();

        if (nameLower.contains('imdb') || catLower.contains('imdb')) {
          icon = Icons.movie_creation_outlined;
        } else if (nameLower.contains('trailer') || catLower.contains('trailer')) {
          icon = Icons.play_circle_outline;
        } else if (nameLower.contains('wiki') || catLower.contains('wiki')) {
          icon = Icons.article_outlined;
        } else if (nameLower.contains('search') || catLower.contains('search')) {
          icon = Icons.search_rounded;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: link == links.last ? 0 : ZplaySpacing.s12),
            child: _buildActionButton(
              icon,
              link.name,
              onTap: () async {
                HapticFeedback.lightImpact();
                final uri = Uri.parse(link.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    return FocusableCard(
      onTap: onTap,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.tokens.surface.withValues(alpha: 0.6),
          borderRadius: ZplayRadius.smAll,
          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.tokens.textSecondary, size: 22),
            const SizedBox(height: ZplaySpacing.s4),
            Text(
              label,
              style: ZplayType.caption.toStyle(color: context.tokens.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sources Panel
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSourcesPanel({required bool isDesktop}) {
    final filtered = _filteredSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stream_rounded, color: context.tokens.accent, size: 20),
                const SizedBox(width: ZplaySpacing.s8),
                Text(
                  'Watch Sources',
                  style: ZplayType.title.toStyle(
                    color: context.tokens.textPrimary,
                  ),
                ),
              ],
            ),
            Text(
              _isLoadingSources
                  ? (filtered.isEmpty
                      ? 'Searching sources...'
                      : '${filtered.length} found · Searching...')
                  : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
              style: ZplayType.bodySmall.toStyle(
                color: context.tokens.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stream Type Filter Bar (All / Debrid / Torrents / Direct HTTP)
        if (_sources.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
              _buildTypeChip(
                'debrid',
                '⚡ ${_debridServiceName ?? 'Debrid'} (${_sources.where(_isDebridSource).length})',
                Icons.bolt_rounded,
                context.tokens.info,
              ),
              _buildTypeChip(
                'torrent',
                '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                Icons.share_rounded,
                context.tokens.accent,
              ),
              _buildTypeChip(
                'direct',
                '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                Icons.link_rounded,
                context.tokens.success,
              ),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSeederFilterDropdown(),
              _buildSizeFilterDropdown(),
              _buildAddonFilterDropdown(),
              _buildAudioFilterDropdown(),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s12),
        ],

        // Source list
        if (isDesktop)
          Expanded(
            child: _buildSourcesList(filtered, isDesktop),
          )
        else
          _buildSourcesList(filtered, isDesktop),
      ],
    );
  }

  Widget _buildTypeChip(String typeKey, String label, IconData icon, Color? color) {
    final isSelected = _selectedTypeFilter == typeKey;
    final activeColor = color ?? context.tokens.accent;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.25),
      backgroundColor: context.tokens.surface,
      labelStyle: ZplayType.caption
          .copyWith(weight: isSelected ? FontWeight.w700 : FontWeight.w500)
          .toStyle(
            color: isSelected
                ? context.tokens.textPrimary
                : context.tokens.textEmphasis,
          ),
      side: BorderSide(
        color: isSelected ? activeColor : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
        width: isSelected ? 1.5 : 1.0,
      ),
      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedTypeFilter = typeKey;
          });
        }
      },
    );
  }

  Widget _buildSourcesList(List<StreamSource> sources, bool isDesktop) {
    if (_isLoadingSources && sources.isEmpty) {
      return _buildShimmerList();
    }

    if (!_isLoadingSources && sources.isEmpty) {
      return _buildEmptyState();
    }

    final list = ListView.separated(
      controller: isDesktop ? _sourcesScrollController : null,
      shrinkWrap: !isDesktop,
      physics: isDesktop
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: sources.length + (_isLoadingSources ? 2 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
      itemBuilder: (context, index) {
        if (index >= sources.length) {
          return _buildShimmerCard();
        }
        return _SourceCard(
          source: sources[index],
          backdropUrl: widget.detail.background ?? widget.detail.poster,
          logoUrl: widget.detail.logo,
          detail: widget.detail,
          episode: widget.selectedEpisode,
          initialPosition: widget.initialPosition,
          initialSubtitles: _discoveredSubtitles,
          playsViaDebrid: _debridReady && sources[index].isMagnet,
          debridServiceName: _debridServiceName,
          alternatives: _alternativesAfter(sources, index),
        );
      },
    );

    return list;
  }

  Widget _buildSeederFilterDropdown() {
    final currentText = _getSeederFilterLabel(_selectedSeederFilter);

    return Builder(
      builder: (buttonContext) {
        return FocusableCard(
          onTap: () => _isDesktop()
              ? _showSeederGlassDropdown(buttonContext)
              : _showSeederBottomSheet(),
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ZplayRadius.mdAll,
              boxShadow: [
                BoxShadow(
                  color: context.tokens.bg.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(
                    color: _selectedSeederFilter != 'all'
                        ? context.tokens.success.withValues(alpha: 0.6)
                        : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: _selectedSeederFilter != 'all'
                          ? context.tokens.success
                          : context.tokens.textEmphasis,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w600)
                          .toStyle(
                            color: _selectedSeederFilter != 'all'
                                ? context.tokens.success
                                : context.tokens.textPrimary,
                          ),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: context.tokens.textEmphasis,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSeederGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [
                        BoxShadow(
                          color: context.tokens.bg.withValues(alpha: 0.60),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(ZplaySpacing.s8),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSeederDropdownItem('All Seeds', 'all'),
                              const SizedBox(height: ZplaySpacing.s4),
                              Container(
                                height: 1,
                                color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              _buildSeederDropdownItem('Most Seeds (High to Low)', 'most'),
                              _buildSeederDropdownItem('50+ Seeds', '50+'),
                              _buildSeederDropdownItem('20+ Seeds', '20+'),
                              _buildSeederDropdownItem('5+ Seeds', '5+'),
                              _buildSeederDropdownItem('Active Seeds (>0)', '1+'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeederDropdownItem(String title, String value) {
    final isSelected = _selectedSeederFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSeederFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: ZplayRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          color: isSelected
              ? context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ZplayType.body
                    .copyWith(
                      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    )
                    .toStyle(
                      color: isSelected
                          ? context.tokens.textPrimary
                          : context.tokens.textEmphasis,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: context.tokens.success, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeFilterDropdown() {
    final currentText = _getSizeFilterLabel(_selectedSizeFilter);

    return Builder(
      builder: (buttonContext) {
        return FocusableCard(
          onTap: () => _isDesktop()
              ? _showSizeGlassDropdown(buttonContext)
              : _showSizeBottomSheet(),
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ZplayRadius.mdAll,
              boxShadow: [
                BoxShadow(
                  color: context.tokens.bg.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.data_usage_rounded,
                      color: context.tokens.textEmphasis,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w600)
                          .toStyle(color: context.tokens.textPrimary),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: context.tokens.textEmphasis,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSizeGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [
                        BoxShadow(
                          color: context.tokens.bg.withValues(alpha: 0.60),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(ZplaySpacing.s8),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSizeDropdownItem('All Sizes', null),
                              const SizedBox(height: ZplaySpacing.s4),
                              Container(
                                height: 1,
                                color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              _buildSizeDropdownItem('< 1 GB', '<1gb'),
                              _buildSizeDropdownItem('1 GB – 5 GB', '1-5gb'),
                              _buildSizeDropdownItem('5 GB – 15 GB', '5-15gb'),
                              _buildSizeDropdownItem('15 GB – 30 GB', '15-30gb'),
                              _buildSizeDropdownItem('> 30 GB', '>30gb'),
                              const SizedBox(height: ZplaySpacing.s4),
                              Container(
                                height: 1,
                                color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              _buildSizeDropdownItem('Largest First', 'largest'),
                              _buildSizeDropdownItem('Smallest First', 'smallest'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSizeDropdownItem(String title, String? value) {
    final isSelected = _selectedSizeFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSizeFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: ZplayRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          color: isSelected
              ? context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ZplayType.body
                    .copyWith(
                      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    )
                    .toStyle(
                      color: isSelected
                          ? context.tokens.textPrimary
                          : context.tokens.textEmphasis,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: context.tokens.textPrimary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAddonFilterDropdown() {
    final addons = _sources.map((e) => e.addonName).toSet().toList();
    if (addons.isEmpty) return const SizedBox.shrink();
    final currentText = _selectedAddonFilter ?? 'All Sources';

    return Builder(
      builder: (buttonContext) {
        return FocusableCard(
          onTap: () => _isDesktop()
              ? _showGlassDropdown(buttonContext, addons)
              : _showAddonBottomSheet(addons),
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ZplayRadius.mdAll,
              boxShadow: [
                BoxShadow(
                  color: context.tokens.bg.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentText,
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w600)
                          .toStyle(color: context.tokens.textPrimary),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: context.tokens.textEmphasis,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGlassDropdown(BuildContext buttonContext, List<String> addons) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(
                        0,
                        (openAbove ? 10 : -10) * (1 - value),
                      ),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [
                        BoxShadow(
                          color: context.tokens.bg.withValues(alpha: 0.60),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(ZplaySpacing.s8),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownItem('All Sources', null),
                              const SizedBox(height: ZplaySpacing.s4),
                              Container(
                                height: 1,
                                color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              ...addons.map((a) => _buildDropdownItem(a, a)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownItem(String title, String? value) {
    final isSelected = _selectedAddonFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAddonFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: ZplayRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s12, horizontal: ZplaySpacing.s16),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          color: isSelected
              ? context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ZplayType.subtitle
                    .copyWith(
                      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    )
                    .toStyle(
                      color: isSelected
                          ? context.tokens.textPrimary
                          : context.tokens.textEmphasis,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: context.tokens.textPrimary, size: 20),
          ],
        ),
      ),
    );
  }

  String _getAudioFilterLabel(String key) {
    switch (key) {
      case 'multi':
        return '🌐 Multi-Audio';
      case 'english':
        return '🇺🇸 English / Orig';
      case 'hindi':
        return '🇮🇳 Hindi / Indian';
      case 'german':
        return '🇩🇪 German';
      case 'french':
        return '🇫🇷 French';
      case 'spanish_castilian':
        return '🇪🇸 Spanish (Castilian)';
      case 'spanish_latino':
        return '🇲🇽 Spanish (Latin)';
      case 'spanish':
        return '🌎 All Spanish';
      case 'russian':
        return '🇷🇺 Russian';
      case 'japanese':
        return '🇯🇵 Japanese';
      case 'italian':
        return '🇮🇹 Italian';
      default:
        return 'All Audio';
    }
  }

  Widget _buildAudioFilterDropdown() {
    final currentText = _getAudioFilterLabel(_selectedAudioFilter);
    final isActive = _selectedAudioFilter != 'all';

    return Builder(
      builder: (buttonContext) {
        return FocusableCard(
          onTap: () => _isDesktop()
              ? _showAudioGlassDropdown(buttonContext)
              : _showAudioBottomSheet(),
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ZplayRadius.mdAll,
              boxShadow: [
                BoxShadow(
                  color: context.tokens.bg.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(
                    color: isActive
                        ? context.tokens.accent.withValues(alpha: 0.6)
                        : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.audiotrack_rounded,
                      color: isActive ? context.tokens.accent : context.tokens.textEmphasis,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w600)
                          .toStyle(
                            color: isActive ? context.tokens.accent : context.tokens.textPrimary,
                          ),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: context.tokens.textEmphasis,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAudioGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    const double dialogWidth = 240.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: ZplayRadius.mdAll,
                    boxShadow: [
                      BoxShadow(
                        color: context.tokens.bg.withValues(alpha: 0.40),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: PerformanceLiquidLens(
                    style: PerformanceGlassStyles.menu,
                    child: Container(
                      width: dialogWidth,
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
                      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s8, horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAudioDropdownItem('All Audio', 'all'),
                            const SizedBox(height: ZplaySpacing.s4),
                            Container(
                              height: 1,
                              color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                            ),
                            const SizedBox(height: ZplaySpacing.s4),
                            _buildAudioDropdownItem('🌐 Multi-Audio', 'multi'),
                            _buildAudioDropdownItem('🇺🇸 English / Orig', 'english'),
                            _buildAudioDropdownItem('🇮🇳 Hindi / Indian', 'hindi'),
                            _buildAudioDropdownItem('🇩🇪 German', 'german'),
                            _buildAudioDropdownItem('🇫🇷 French', 'french'),
                            _buildAudioDropdownItem('🇪🇸 Spanish (Castilian)', 'spanish_castilian'),
                            _buildAudioDropdownItem('🇲🇽 Spanish (Latin)', 'spanish_latino'),
                            _buildAudioDropdownItem('🌎 All Spanish', 'spanish'),
                            _buildAudioDropdownItem('🇷🇺 Russian', 'russian'),
                            _buildAudioDropdownItem('🇯🇵 Japanese', 'japanese'),
                            _buildAudioDropdownItem('🇮🇹 Italian', 'italian'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAudioDropdownItem(String title, String value) {
    final isSelected = _selectedAudioFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAudioFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: ZplayRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          color: isSelected
              ? context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ZplayType.body
                    .copyWith(
                      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    )
                    .toStyle(
                      color: isSelected
                          ? context.tokens.textPrimary
                          : context.tokens.textEmphasis,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: context.tokens.accent, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassBottomSheetContainer({
    required BuildContext context,
    required Widget header,
    required Widget content,
  }) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: ZplaySpacing.s12),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.lgAll,
          color: context.tokens.surfaceOverlay.withValues(alpha: 0.96),
          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong)),
          boxShadow: [
            BoxShadow(
              color: context.tokens.bg.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: ZplayRadius.lgAll,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: ZplaySpacing.s12),
                      decoration: BoxDecoration(
                        color: context.tokens.textPrimary.withValues(alpha: 0.3),
                        borderRadius: ZplayRadius.xsAll,
                      ),
                    ),
                  ),
                  header,
                  const SizedBox(height: ZplaySpacing.s8),
                  Divider(
                    color: context.tokens.textPrimary.withValues(
                      alpha: ZplayOpacity.borderMedium,
                    ),
                    height: 1,
                  ),
                  const SizedBox(height: ZplaySpacing.s8),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheetItem({
    required String title,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: ZplayRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s12, horizontal: ZplaySpacing.s16),
        margin: const EdgeInsets.only(bottom: ZplaySpacing.s4),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          color: isSelected
              ? activeColor.withValues(alpha: ZplayOpacity.overlayHover)
              : Colors.transparent,
          border: isSelected
              ? Border.all(color: activeColor.withValues(alpha: 0.4))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ZplayType.subtitle
                    .copyWith(
                      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    )
                    .toStyle(
                      color: isSelected
                          ? context.tokens.textPrimary
                          : context.tokens.textEmphasis,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: activeColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAudioBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: context.tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  Icons.audiotrack_rounded,
                  color: context.tokens.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Text(
                  'Audio & Dub Language',
                  style: ZplayType.subtitle
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: context.tokens.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.tokens.textSecondary, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Audio',
                    isSelected: _selectedAudioFilter == 'all',
                    activeColor: context.tokens.accent,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🌐 Multi-Audio',
                    isSelected: _selectedAudioFilter == 'multi',
                    activeColor: context.tokens.accent,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'multi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇺🇸 English / Original',
                    isSelected: _selectedAudioFilter == 'english',
                    activeColor: context.tokens.accent,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'english');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇳 Hindi / Indian',
                    isSelected: _selectedAudioFilter == 'hindi',
                    activeColor: context.tokens.warning,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'hindi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇩🇪 German',
                    isSelected: _selectedAudioFilter == 'german',
                    activeColor: context.tokens.warning,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'german');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇫🇷 French',
                    isSelected: _selectedAudioFilter == 'french',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'french');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇪🇸 Spanish (Castilian)',
                    isSelected: _selectedAudioFilter == 'spanish_castilian',
                    activeColor: context.tokens.warning,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish_castilian');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇲🇽 Spanish (Latin)',
                    isSelected: _selectedAudioFilter == 'spanish_latino',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish_latino');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🌎 All Spanish',
                    isSelected: _selectedAudioFilter == 'spanish',
                    activeColor: context.tokens.warning,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇷🇺 Russian',
                    isSelected: _selectedAudioFilter == 'russian',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'russian');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇯🇵 Japanese',
                    isSelected: _selectedAudioFilter == 'japanese',
                    activeColor: context.tokens.danger,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'japanese');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇹 Italian',
                    isSelected: _selectedAudioFilter == 'italian',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'italian');
                      Navigator.pop(ctx);
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

  void _showSeederBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: context.tokens.success.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  Icons.people_alt_rounded,
                  color: context.tokens.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Text(
                  'Seeders Filter',
                  style: ZplayType.subtitle
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: context.tokens.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.tokens.textSecondary, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Seeds',
                    isSelected: _selectedSeederFilter == 'all',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Most Seeds (High to Low)',
                    isSelected: _selectedSeederFilter == 'most',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'most');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '50+ Seeds',
                    isSelected: _selectedSeederFilter == '50+',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = '50+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '20+ Seeds',
                    isSelected: _selectedSeederFilter == '20+',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = '20+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5+ Seeds',
                    isSelected: _selectedSeederFilter == '5+',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = '5+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Active Seeds (>0)',
                    isSelected: _selectedSeederFilter == '1+',
                    activeColor: context.tokens.success,
                    onTap: () {
                      setState(() => _selectedSeederFilter = '1+');
                      Navigator.pop(ctx);
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

  void _showSizeBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: context.tokens.info.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  color: context.tokens.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Text(
                  'File Size Filter',
                  style: ZplayType.subtitle
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: context.tokens.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.tokens.textSecondary, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sizes',
                    isSelected: _selectedSizeFilter == null,
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Largest First',
                    isSelected: _selectedSizeFilter == 'largest',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'largest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Smallest First',
                    isSelected: _selectedSizeFilter == 'smallest',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'smallest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '< 1 GB',
                    isSelected: _selectedSizeFilter == '<1gb',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = '<1gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '1 - 5 GB',
                    isSelected: _selectedSizeFilter == '1-5gb',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = '1-5gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5 - 15 GB',
                    isSelected: _selectedSizeFilter == '5-15gb',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = '5-15gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '15 - 30 GB',
                    isSelected: _selectedSizeFilter == '15-30gb',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = '15-30gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '> 30 GB',
                    isSelected: _selectedSizeFilter == '>30gb',
                    activeColor: context.tokens.info,
                    onTap: () {
                      setState(() => _selectedSizeFilter = '>30gb');
                      Navigator.pop(ctx);
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

  void _showAddonBottomSheet(List<String> addons) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  Icons.extension_rounded,
                  color: context.tokens.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Text(
                  'Source Provider',
                  style: ZplayType.subtitle
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: context.tokens.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.tokens.textSecondary, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sources',
                    isSelected: _selectedAddonFilter == null,
                    activeColor: context.tokens.textPrimary,
                    onTap: () {
                      setState(() => _selectedAddonFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  for (final addon in addons)
                    _buildBottomSheetItem(
                      title: addon,
                      isSelected: _selectedAddonFilter == addon,
                      activeColor: context.tokens.textPrimary,
                      onTap: () {
                        setState(() => _selectedAddonFilter = addon);
                        Navigator.pop(ctx);
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

  Widget _buildEmptyState() {
    return const _EmptySourcesStateWidget();
  }

  Widget _buildShimmerList() {
    return Column(
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
          child: _buildShimmerCard(),
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return const RepaintBoundary(child: _ShimmerCard());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Back Button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackButton() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.tokens.bg.withValues(alpha: 0.7),
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong)),
      ),
      child: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: context.tokens.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source Card
// ─────────────────────────────────────────────────────────────────────────────
class _SourceCard extends StatefulWidget {
  final StreamSource source;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail detail;
  final Video? episode;
  final Duration? initialPosition;
  final List<SubtitleVariant>? initialSubtitles;

  /// Set when this torrent will be played through the user's Debrid service
  /// instead of the local P2P engine. Carries the service name for the badge.
  final bool playsViaDebrid;
  final String? debridServiceName;

  /// The ranked remainder behind this source, so the player can walk it when
  /// this pick fails. Empty for the last entry of the list.
  final List<StreamSource> alternatives;

  const _SourceCard({
    required this.source,
    this.backdropUrl,
    this.logoUrl,
    required this.detail,
    this.episode,
    this.initialPosition,
    this.initialSubtitles,
    this.playsViaDebrid = false,
    this.debridServiceName,
    this.alternatives = const [],
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  /// Longest stored rejection reason that still fits the badge row. Anything
  /// longer falls back to plain 'Unavailable', because a chip is not a sentence.
  static const int _rejectionBadgeMaxChars = 24;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final badges = <Widget>[];

    // Quality badge
    if (s.quality != null) {
      Color badgeColor;
      switch (s.quality) {
        case '4K':
          badgeColor = context.tokens.accent;
          break;
        case '1080p':
          badgeColor = context.tokens.info;
          break;
        case '720p':
          badgeColor = context.tokens.textSecondary;
          break;
        default:
          badgeColor = context.tokens.danger;
      }
      badges.add(_badge(s.quality!, badgeColor));
    }

    if (s.isHDR) badges.add(_badge('HDR', context.tokens.warning));
    if (widget.playsViaDebrid) {
      badges.add(
        _badge(
          '⚡ ${widget.debridServiceName ?? 'Debrid'}',
          context.tokens.info,
        ),
      );
    }
    // A source the provider has already refused, kept in the list because a
    // refusal can be superseded. Quiet on purpose: this is information, not an
    // error, and it only points the user at the sources above it.
    if (DebridRejectionStore.instance.isRejected(s.infoHash)) {
      final String? reason = DebridRejectionStore.instance.reasonFor(s.infoHash);
      final bool shortReason = reason != null &&
          reason.isNotEmpty &&
          reason.length <= _rejectionBadgeMaxChars;
      badges.add(
        _badge(shortReason ? reason : 'Unavailable', context.tokens.textMuted),
      );
    }
    if (s.codec != null) badges.add(_badge(s.codec!, context.tokens.textMuted));
    badges.add(
      StreamBitrateBadge(
        source: s,
        runtimeMinutes: int.tryParse(widget.detail.runtime ?? ''),
      ),
    );
    if (s.fileSize != null) badges.add(_badge(s.fileSize!, context.tokens.textMuted));
    if (s.seeders != null) {
      final seederColor = s.seeders! >= 20
          ? context.tokens.success
          : (s.seeders! >= 5
                ? context.tokens.warning
                : context.tokens.danger);
      badges.add(_badge('👤 ${s.seeders} Seeds', seederColor));
    }

    // Audio Language / Dub badge
    final audioBadge = s.getAudioBadge(mediaTitle: widget.detail.name);
    if (audioBadge != null) {
      Color audioBadgeColor;
      if (audioBadge.contains('MULTI')) {
        audioBadgeColor = context.tokens.accent;
      } else if (audioBadge.contains('HINDI') ||
          audioBadge.contains('TELUGU') ||
          audioBadge.contains('TAMIL') ||
          audioBadge.contains('MALAYALAM') ||
          audioBadge.contains('KANNADA') ||
          audioBadge.contains('PUNJABI')) {
        audioBadgeColor = context.tokens.warning;
      } else if (audioBadge.contains('GER')) {
        audioBadgeColor = context.tokens.warning;
      } else if (audioBadge.contains('FRE')) {
        audioBadgeColor = context.tokens.info;
      } else if (audioBadge.contains('CAST')) {
        audioBadgeColor = context.tokens.warning;
      } else if (audioBadge.contains('LAT')) {
        audioBadgeColor = context.tokens.success;
      } else if (audioBadge.contains('SPA')) {
        audioBadgeColor = context.tokens.warning;
      } else if (audioBadge.contains('RUS')) {
        audioBadgeColor = context.tokens.info;
      } else if (audioBadge.contains('JPN')) {
        audioBadgeColor = context.tokens.danger;
      } else if (audioBadge.contains('ITA')) {
        audioBadgeColor = context.tokens.success;
      } else {
        audioBadgeColor = context.tokens.textMuted;
      }
      badges.add(_badge(audioBadge, audioBadgeColor));
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ClipRRect(
        borderRadius: ZplayRadius.smAll,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: ZplayRadius.smAll,
            onTap: () {
              HapticFeedback.lightImpact();

              if (s.externalUrl != null && s.externalUrl!.isNotEmpty) {
                if (s.externalUrl!.startsWith('stremio://')) {
                  // Example: stremio:///detail/movie/tt28479262
                  final uriStr = s.externalUrl!.replaceFirst(
                    'stremio:///',
                    'stremio://',
                  );
                  final uri = Uri.parse(uriStr);
                  final segments = uri.pathSegments;
                  if (uri.host == 'detail' && segments.length >= 2) {
                    final type = segments[0];
                    final id = segments[1];
                    final movie = Movie(
                      id: id,
                      type: type,
                      name: s.name ?? 'Unknown',
                      addonBaseUrl: 'https://v3-cinemeta.strem.io',
                    );
                    Navigator.push(
                      context,
                      CinematicSlideRoute(page: DetailsPage(movie: movie)),
                    );
                    return;
                  }
                  return;
                } else {
                  // Fallback for http URLs or other schemes
                  launchUrl(
                    Uri.parse(s.externalUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                  return;
                }
              }

              final isColl = widget.detail.isCollection;
              final effectiveTitle = (isColl && widget.episode != null && widget.episode!.title.isNotEmpty)
                  ? widget.episode!.title
                  : s.displayTitle;

              CrashBreadcrumbs.stream(
                'open',
                title: s.displayTitle,
                addon: s.addonName,
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    source: s,
                    title: effectiveTitle,
                    backdropUrl: widget.backdropUrl,
                    logoUrl: widget.logoUrl,
                    detail: widget.detail,
                    episode: widget.episode,
                    initialPosition: widget.initialPosition,
                    initialSubtitles: widget.initialSubtitles,
                    alternatives: widget.alternatives.isEmpty
                        ? null
                        : widget.alternatives,
                  ),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _hovered
                    ? context.tokens.surfaceRaised.withValues(alpha: 0.9)
                    : context.tokens.surface.withValues(alpha: 0.7),
                borderRadius: ZplayRadius.smAll,
                border: Border.all(
                  color: _hovered
                      ? context.tokens.accent.withValues(alpha: 0.3)
                      : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderSubtle),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: context.tokens.accent.withValues(alpha: ZplayOpacity.borderDefault),
                          blurRadius: 16,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // Addon icon
                  _AddonSourceIcon(addonName: s.addonName),
                  const SizedBox(width: ZplaySpacing.s12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (s.addonName.toLowerCase() == 'zplayhttp' &&
                                  s.providerName != null &&
                                  s.providerName!.isNotEmpty)
                              ? 'ZPlayHTTP · ${s.providerName}'
                              : (s.name != null && s.name!.isNotEmpty
                                  ? s.name!
                                  : s.addonName),
                          style: ZplayType.label
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: context.tokens.textPrimary),
                        ),
                        if (s.title != null && s.title!.isNotEmpty) ...[
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            s.title!,
                            style: ZplayType.bodySmall.toStyle(color: context.tokens.textMuted),
                          ),
                        ],
                        if (s.description != null &&
                            s.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            s.description!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.bodySmall
                                .copyWith(height: 1.3)
                                .toStyle(color: context.tokens.textSecondary),
                          ),
                        ],
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: ZplaySpacing.s8),
                          Wrap(spacing: 4, runSpacing: 4, children: badges),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  if (s.isMagnet && s.magnetUrl != null) ...[
                    _CopyMagnetButton(magnetUrl: s.magnetUrl!),
                    const SizedBox(width: ZplaySpacing.s8),
                  ],
                  // Play chevron
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? context.tokens.accent.withValues(alpha: 0.2)
                          : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderSubtle),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: _hovered ? context.tokens.accent : context.tokens.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ZplayOpacity.overlayHover),
        borderRadius: ZplayRadius.xsAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: ZplayType.caption
            .copyWith(weight: FontWeight.w700, letterSpacing: 0.3)
            .toStyle(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Addon Source Icon / App Logo
// ─────────────────────────────────────────────────────────────────────────────
class _AddonSourceIcon extends StatelessWidget {
  final String addonName;

  const _AddonSourceIcon({required this.addonName});

  @override
  Widget build(BuildContext context) {
    final nameLower = addonName.trim().toLowerCase();
    final isBuiltIn = nameLower == 'zplay' ||
        nameLower == 'zplayhttp' ||
        nameLower.startsWith('builtin');

    if (isBuiltIn) {
      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
          borderRadius: ZplayRadius.smAll,
          border: Border.all(
            color: context.tokens.accent.withValues(alpha: 0.25),
          ),
        ),
        child: const ZplayLogo(size: 30),
      );
    }

    final logoUrl = AddonManager.instance.getAddonLogo(addonName);

    if (logoUrl != null && logoUrl.isNotEmpty) {
      if (logoUrl.startsWith('asset:')) {
        final assetPath = logoUrl.substring('asset:'.length);
        return Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
            borderRadius: ZplayRadius.smAll,
            border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong)),
          ),
          child: ClipRRect(
            borderRadius: ZplayRadius.xsAll,
            child: Image.asset(
              assetPath,
              width: 30,
              height: 30,
              fit: BoxFit.contain,
            ),
          ),
        );
      }

      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(ZplaySpacing.s4),
        decoration: BoxDecoration(
          color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
          borderRadius: ZplayRadius.smAll,
          border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong)),
        ),
        child: ClipRRect(
          borderRadius: ZplayRadius.xsAll,
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            cacheManager: AppImageCache.manager,
            memCacheWidth: 96,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            placeholder: (context, url) => Container(
              color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.tokens.accent,
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildFallbackIcon()),
        ),
      );
    }

    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    final firstLetter = addonName.isNotEmpty ? addonName[0].toUpperCase() : 'A';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppThemeService.currentTokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: AppThemeService.currentTokens.accent.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: ZplayType.title
              .copyWith(weight: FontWeight.w700)
              .toStyle(color: AppThemeService.currentTokens.accent),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Copy Magnet Button
// ─────────────────────────────────────────────────────────────────────────────
class _CopyMagnetButton extends StatefulWidget {
  final String magnetUrl;

  const _CopyMagnetButton({required this.magnetUrl});

  @override
  State<_CopyMagnetButton> createState() => _CopyMagnetButtonState();
}

class _CopyMagnetButtonState extends State<_CopyMagnetButton> {
  bool _copied = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.magnetUrl));
    HapticFeedback.lightImpact();

    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: context.tokens.success, size: 18),
            const SizedBox(width: ZplaySpacing.s8),
            Text(
              'Magnet link copied to clipboard',
              style: ZplayType.label
                  .copyWith(weight: FontWeight.w600)
                  .toStyle(color: context.tokens.textPrimary),
            ),
          ],
        ),
        backgroundColor: context.tokens.surfaceRaised,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: _copied ? 'Copied!' : 'Copy Magnet Link',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _copy,
            borderRadius: ZplayRadius.mdAll,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _copied
                    ? context.tokens.success.withValues(alpha: 0.2)
                    : (_hovered
                        ? context.tokens.info.withValues(alpha: 0.18)
                        : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderSubtle)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _copied
                      ? context.tokens.success.withValues(alpha: 0.5)
                      : (_hovered
                          ? context.tokens.info.withValues(alpha: 0.4)
                          : context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderDefault)),
                  width: 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.link_rounded,
                  key: ValueKey(_copied),
                  color: _copied
                      ? context.tokens.success
                      : (_hovered ? context.tokens.info : context.tokens.textSecondary),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer Card
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.tokens.surface.withValues(alpha: 0.5),
            borderRadius: ZplayRadius.smAll,
            border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint)),
          ),
          child: Row(
            children: [
              _shimmerBox(40, 40, 10),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(double.infinity, 12, 4),
                    const SizedBox(height: ZplaySpacing.s8),
                    _shimmerBox(180, 10, 4),
                    const SizedBox(height: ZplaySpacing.s8),
                    Row(
                      children: [
                        _shimmerBox(40, 16, 4),
                        const SizedBox(width: ZplaySpacing.s4),
                        _shimmerBox(50, 16, 4),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              _shimmerBox(36, 36, 18),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(double width, double height, double radius) {
    final shimmerValue = _controller.value;
    final gradientStart = shimmerValue - 0.3;
    final gradientEnd = shimmerValue + 0.3;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            context.tokens.surfaceRaised.withValues(alpha: 0.5),
            context.tokens.surfaceRaised.withValues(alpha: 0.8),
            context.tokens.surfaceRaised.withValues(alpha: 0.5),
          ],
          stops: [
            (gradientStart).clamp(0.0, 1.0),
            (shimmerValue).clamp(0.0, 1.0),
            (gradientEnd).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}

class _EmptySourcesStateWidget extends StatefulWidget {
  const _EmptySourcesStateWidget();

  @override
  State<_EmptySourcesStateWidget> createState() =>
      _EmptySourcesStateWidgetState();
}

class _EmptySourcesStateWidgetState extends State<_EmptySourcesStateWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    // Run the entrance once. A perpetual pulse kept this whole state ticking.
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static card content — identical on every platform.
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s48, horizontal: ZplaySpacing.s24),
      decoration: BoxDecoration(
        color: context.tokens.surfaceRaised.withValues(alpha: 0.94),
        border: Border.all(color: context.tokens.textPrimary.withValues(alpha: ZplayOpacity.borderDefault)),
        borderRadius: ZplayRadius.lgAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(ZplaySpacing.s16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.tokens.accent.withValues(alpha: ZplayOpacity.borderMedium),
              border: Border.all(
                color: context.tokens.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.radar_rounded,
              color: context.tokens.accent,
              size: 40,
            ),
          ),
          const SizedBox(height: ZplaySpacing.s24),
          Text(
            'No sources found',
            style: ZplayType.title
                .copyWith(weight: FontWeight.w500)
                .toStyle(color: context.tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              'No streams found. Install more addons from Settings or try another title.',
              textAlign: TextAlign.center,
              style: ZplayType.body
                  .copyWith(height: 1.5)
                  .toStyle(color: context.tokens.textSecondary),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s32),
          FocusableCard(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            builder: (context, state) {
              final isHovering = state.highlighted;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.xlAll,
                  gradient: LinearGradient(
                    colors: [context.tokens.accent, context.tokens.success],
                  ),
                  boxShadow: isHovering
                      ? [
                          BoxShadow(
                            color: context.tokens.accent.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: AnimatedScale(
                  scale: isHovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.extension_rounded,
                        color: context.tokens.textPrimary,
                        size: 18,
                      ),
                      const SizedBox(width: ZplaySpacing.s8),
                      Text(
                        'Install Addons',
                        style: ZplayType.body
                            .copyWith(weight: FontWeight.w600)
                            .toStyle(color: context.tokens.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    // The glass card — blur is static, not animated
    final glassCard = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: context.tokens.bg.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: cardContent,
    );

    // Only the initial fade/scale is animated (runs once, then stops)
    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: _scaleAnim.value, child: child),
        );
      },
      child: glassCard,
    );
  }
}
