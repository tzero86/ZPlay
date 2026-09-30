import 'package:flutter/material.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/content/content_settings.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../shell/app_shell_scope.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/movie/movie_card.dart';

class DiscoverPage extends StatefulWidget {
  final String? query;
  final bool isGenre;
  final AddonCatalog? initialCatalog;
  final InstalledAddon? initialAddon;

  const DiscoverPage({
    super.key,
    this.query,
    this.isGenre = false,
    this.initialCatalog,
    this.initialAddon,
  });

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  // Legacy query mode (when query is passed)
  bool get _isLegacyMode => widget.query != null && widget.query!.isNotEmpty;

  // Legacy state
  bool _legacyLoading = true;
  String? _legacyError;
  List<MovieSection> _legacySections = [];

  // Full Discover state
  List<({InstalledAddon addon, AddonCatalog catalog})> _allCatalogs = [];
  List<String> _availableTypes = [];
  String _selectedType = 'movie';

  /// Pseudo-type that narrows the catalog list to adult addons. Only offered
  /// while the global Adult Content switch is on and such an addon exists.
  static const String _adultType = '18+';

  ({InstalledAddon addon, AddonCatalog catalog})? _selectedCatalogEntry;
  final Map<String, String> _selectedExtras = {};

  final List<Movie> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final ScrollController _filtersScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);

    if (_isLegacyMode) {
      _fetchLegacyData();
    } else {
      _initDiscoverCatalogs();
    }
  }

  /// The shell keeps every slot mounted in one `IndexedStack`, so this page is
  /// built once at startup and never rebuilt on a slot switch. `initState` also
  /// runs before [AddonManager.initialize] has finished hydrating, so the
  /// catalog list it reads there is whatever happened to be in memory - usually
  /// nothing - and it is then never refreshed. Returning to Browse reloads it,
  /// which is the same reload cue Home uses (see `HomePage._onSlotChanged`).
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

  AppShellController? _shellController;
  ShellSlot? _lastSlot;

  void _onSlotChanged() {
    final slot = _shellController?.current.value;
    final returnedBrowse = slot == ShellSlot.browse && _lastSlot != ShellSlot.browse;
    _lastSlot = slot;
    if (!returnedBrowse || !mounted || _isLegacyMode) return;
    _initDiscoverCatalogs();
  }

  @override
  void dispose() {
    ContentSettings.adultEnabled.removeListener(_onAdultContentChanged);
    _shellController?.current.removeListener(_onSlotChanged);
    _scrollController.dispose();
    _filtersScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// The catalog list is adult-filtered at query time, so rebuild it under the
  /// new switch value and reload. The previous type/entry is preserved when it
  /// still exists (see [_initDiscoverCatalogs]).
  void _onAdultContentChanged() {
    if (!mounted) return;
    MetadataService.clearCatalogCache();
    if (_isLegacyMode) {
      _fetchLegacyData();
      return;
    }
    _initDiscoverCatalogs();
  }

  // ── Legacy Search / Genre Mode ──
  Future<void> _fetchLegacyData() async {
    setState(() {
      _legacyLoading = true;
      _legacyError = null;
    });

    try {
      final manager = AddonManager.instance;
      List<MovieSection> sections;

      if (widget.isGenre) {
        sections = await manager.fetchByGenre(widget.query!);
      } else {
        sections = await manager.searchAll(widget.query!);
      }

      if (!mounted) return;
      setState(() {
        _legacySections = sections;
        _legacyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _legacyError = e.toString();
        _legacyLoading = false;
      });
    }
  }

  // ── Full Discover Mode ──
  void _initDiscoverCatalogs() {
    final catalogs = AddonManager.instance.getAvailableDiscoverCatalogs();
    final types = <String>{};
    for (final entry in catalogs) {
      types.add(entry.catalog.type);
    }

    final sortedTypes = types.toList();
    const priority = ['movie', 'series', 'anime', 'collections', 'collection'];
    sortedTypes.sort((a, b) {
      final idxA = priority.indexOf(a);
      final idxB = priority.indexOf(b);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.compareTo(b);
    });

    // The 18+ entry is a view of the app's adult sources, so it is offered
    // whenever the global switch is on — even before any adult addon exists,
    // otherwise the filter silently looks missing. The empty view explains how
    // to add one.
    if (ContentSettings.adultEnabled.value &&
        !sortedTypes.contains(_adultType)) {
      sortedTypes.add(_adultType);
    }

    // Preserve the user's current type/entry across re-inits (e.g. the 18+
    // switch flipping the available catalog list). Falls back to the initial
    // catalog when the prior selection no longer exists.
    final hasPriorSelection =
        _availableTypes.isNotEmpty || _selectedCatalogEntry != null;
    final priorType = _selectedType;
    final priorEntry = _selectedCatalogEntry;

    String initialType;
    if (hasPriorSelection && sortedTypes.contains(priorType)) {
      initialType = priorType;
    } else {
      initialType =
          widget.initialCatalog?.type ??
          (sortedTypes.isNotEmpty ? sortedTypes.first : 'movie');
      if (!sortedTypes.contains(initialType) && sortedTypes.isNotEmpty) {
        initialType = sortedTypes.first;
      }
    }

    ({InstalledAddon addon, AddonCatalog catalog})? initialEntry;
    if (priorEntry != null) {
      for (final entry in catalogs) {
        if (entry.catalog.id == priorEntry.catalog.id &&
            entry.addon.manifest.id == priorEntry.addon.manifest.id) {
          initialEntry = entry;
          break;
        }
      }
    }
    if (initialEntry == null && widget.initialCatalog != null) {
      for (final entry in catalogs) {
        if (entry.catalog.id == widget.initialCatalog!.id &&
            (widget.initialAddon == null || entry.addon.manifest.id == widget.initialAddon!.manifest.id)) {
          initialEntry = entry;
          break;
        }
      }
    }

    initialEntry ??= catalogs.where((c) => c.catalog.type == initialType).firstOrNull ?? catalogs.firstOrNull;

    setState(() {
      _allCatalogs = catalogs;
      _availableTypes = sortedTypes;
      _selectedType = initialType;
      _selectedCatalogEntry = initialEntry;
    });

    _checkAndLoadCatalog();
  }

  List<({InstalledAddon addon, AddonCatalog catalog})> get _currentTypeCatalogs {
    if (_selectedType == _adultType) {
      return _allCatalogs.where((c) => c.addon.isAdultCapable).toList();
    }
    return _allCatalogs.where((c) => c.catalog.type == _selectedType).toList();
  }

  bool get _hasVisibleExtras {
    if (_selectedCatalogEntry == null) return false;
    return _selectedCatalogEntry!.catalog.extra.any((e) =>
        e.name != 'skip' && (e.name != 'search' || e.isRequired));
  }

  List<CatalogExtra> get _missingRequiredExtras {
    if (_selectedCatalogEntry == null) return const [];
    final catalog = _selectedCatalogEntry!.catalog;
    return catalog.requiredExtras.where((req) {
      final val = _selectedExtras[req.name];
      return val == null || val.trim().isEmpty;
    }).toList();
  }

  bool get _areRequiredExtrasSatisfied => _missingRequiredExtras.isEmpty;

  void _onTypeChanged(String type) {
    if (_selectedType == type) return;
    setState(() {
      _selectedType = type;
      // The 18+ entry is a cross-addon filter, so resolve the first catalog
      // through the same getter the chip row uses.
      _selectedCatalogEntry = _currentTypeCatalogs.firstOrNull;
      _selectedExtras.clear();
      _searchQuery = '';
      _isSearching = false;
      _searchController.clear();
    });
    _checkAndLoadCatalog();
  }

  void _onCatalogChanged(({InstalledAddon addon, AddonCatalog catalog}) entry) {
    if (_selectedCatalogEntry == entry) return;
    setState(() {
      _selectedCatalogEntry = entry;
      _selectedExtras.clear();
      _searchQuery = '';
      _isSearching = false;
      _searchController.clear();
    });
    _checkAndLoadCatalog();
  }

  void _onExtraOptionSelected(String extraName, String? value) {
    if (_selectedExtras[extraName] == value) return;
    setState(() {
      if (value == null || value.trim().isEmpty) {
        _selectedExtras.remove(extraName);
      } else {
        _selectedExtras[extraName] = value.trim();
      }
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _checkAndLoadCatalog();
  }

  void _onCustomExtraSubmitted(String extraName, String value) {
    if (value.trim().isEmpty) {
      setState(() {
        _selectedExtras.remove(extraName);
      });
    } else {
      setState(() {
        _selectedExtras[extraName] = value.trim();
      });
    }
    _checkAndLoadCatalog();
  }

  void _checkAndLoadCatalog() {
    if (_selectedCatalogEntry == null) {
      setState(() {
        _items.clear();
        _isLoading = false;
        _hasMore = false;
      });
      return;
    }

    if (!_areRequiredExtrasSatisfied) {
      // Gating: DO NOT fire network requests until required extras are selected!
      setState(() {
        _items.clear();
        _isLoading = false;
        _hasMore = false;
        _error = null;
      });
      return;
    }

    _loadItems(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && _hasMore) {
        _loadItems();
      }
    }
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (_selectedCatalogEntry == null) return;
    final entry = _selectedCatalogEntry!;

    if (refresh) {
      setState(() {
        _items.clear();
        _hasMore = true;
        _error = null;
      });
    }

    if (!_hasMore) return;
    if (!_areRequiredExtrasSatisfied) return;

    setState(() => _isLoading = true);

    try {
      List<Movie> newItems = [];

      final params = Map<String, String>.from(_selectedExtras);
      if (_searchQuery.isNotEmpty) {
        params['search'] = _searchQuery;
      }

      if (_isSearching && _searchQuery.isNotEmpty && !entry.catalog.supportsSkip) {
        newItems = await MetadataService.search(
          baseUrl: entry.addon.baseUrl,
          type: entry.catalog.type,
          catalogId: entry.catalog.id,
          query: _searchQuery,
        );
        _hasMore = false;
      } else {
        newItems = await MetadataService.fetchCatalog(
          baseUrl: entry.addon.baseUrl,
          type: entry.catalog.type,
          catalogId: entry.catalog.id,
          extraParams: params.isNotEmpty ? params : null,
          skip: entry.catalog.supportsSkip ? _items.length : 0,
        );

        if (!entry.catalog.supportsSkip) {
          _hasMore = false;
        }
      }

      if (!mounted) return;

      setState(() {
        if (newItems.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(newItems);
          if (newItems.length < 10) {
            _hasMore = false;
          }
        }
        _isLoading = false;
      });

      // Auto load more if screen not filled yet
      if (_hasMore && !_isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          if (_scrollController.position.maxScrollExtent <= 0) {
            _loadItems();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
      });
      _checkAndLoadCatalog();
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
    });
    _checkAndLoadCatalog();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
    _checkAndLoadCatalog();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLegacyMode) {
      return _buildLegacyScaffold();
    }
    return _buildDiscoverScaffold();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Full Discover UI
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDiscoverScaffold() {
    final tokens = context.tokens;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isCompactScreen = screenHeight < 520;

    final sizing = MovieCardSizing.fromWidth(screenWidth);

    final hasExtras = _hasVisibleExtras;
    final toolbarH = isCompactScreen ? 46.0 : kToolbarHeight;
    final selectorH = isCompactScreen ? 44.0 : 50.0;
    final extrasH = isCompactScreen ? 42.0 : 48.0;

    final headerHeight = topPadding + toolbarH + selectorH + (hasExtras ? extrasH : 0);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Main Content Grid ──
          Positioned.fill(
            child: _buildDiscoverContent(headerHeight, sizing, bottomInset),
          ),

          // ── Glass App Bar & Filters ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(
              topPadding,
              hasExtras,
              isCompactScreen: isCompactScreen,
              toolbarH: toolbarH,
              selectorH: selectorH,
              extrasH: extrasH,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverContent(double topOffset, MovieCardSizing sizing, double bottomInset) {
    final tokens = context.tokens;
    if (_selectedCatalogEntry == null) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s20,
            topOffset + 30,
            ZplaySpacing.s20,
            100,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.category_outlined, size: 48, color: tokens.textDisabled),
              const SizedBox(height: ZplaySpacing.s12),
              Text(
                _selectedType == _adultType
                    ? 'No 18+ sources yet.\nMark an addon as 18+ in Settings → Addons, or install one.'
                    : 'No catalogs available for "$_selectedType"',
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Required extra gating prompt
    if (!_areRequiredExtrasSatisfied) {
      return _buildRequiredExtraGatingPrompt(topOffset);
    }

    if (_items.isEmpty && _isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppThemeService.currentPalette.value.primaryColor),
      );
    }

    if (_items.isEmpty && _error != null) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s20,
            topOffset + 30,
            ZplaySpacing.s20,
            100,
          ),
          child: ErrorView(
            error: _error,
            onRetry: () => _loadItems(refresh: true),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s20,
            topOffset + 30,
            ZplaySpacing.s20,
            100,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_rounded, size: 48, color: tokens.textDisabled),
              const SizedBox(height: ZplaySpacing.s12),
              Text(
                'No titles found in this catalog',
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final columns = ((screenWidth - sizing.sidePadding * 2 + sizing.spacing) /
            (sizing.cardWidth + sizing.spacing))
        .floor()
        .clamp(2, 10);
    final double cardAspectRatio = sizing.cardWidth / sizing.totalHeight;

    return GridView.builder(
      controller: _scrollController,
      // The shell reserves its own chrome's space, so only the device safe area
      // and one gap are still owed here.
      padding: EdgeInsets.fromLTRB(
        sizing.sidePadding,
        topOffset + ZplaySpacing.s16,
        sizing.sidePadding,
        ZplaySpacing.s24 + bottomInset,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: cardAspectRatio,
        crossAxisSpacing: sizing.spacing,
        mainAxisSpacing: sizing.spacing,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: CircularProgressIndicator(color: AppThemeService.currentPalette.value.primaryColor),
          );
        }
        return MovieCard(movie: _items[index]);
      },
    );
  }

  Widget _buildRequiredExtraGatingPrompt(double topOffset) {
    final tokens = context.tokens;
    final missing = _missingRequiredExtras;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 420;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isNarrow ? ZplaySpacing.s16 : ZplaySpacing.s24,
          topOffset + ZplaySpacing.s20,
          isNarrow ? ZplaySpacing.s16 : ZplaySpacing.s24,
          120 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? ZplaySpacing.s20 : ZplaySpacing.s32,
            vertical: isNarrow ? ZplaySpacing.s20 : ZplaySpacing.s32,
          ),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: ZplayRadius.lgAll,
            border: Border.all(color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s16),
                decoration: BoxDecoration(
                  color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.tune_rounded, color: tokens.accent, size: 30),
              ),
              const SizedBox(height: ZplaySpacing.s16),
              Text(
                'Select Required Filter',
                style: ZplayType.title.toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'This catalog requires selecting ${missing.map((e) => e.name).join(' & ')} before loading titles.',
                textAlign: TextAlign.center,
                style: ZplayType.body.toStyle(color: tokens.textEmphasis),
              ),
              const SizedBox(height: ZplaySpacing.s20),
              // Quick selection chips for missing extras
              Wrap(
                spacing: ZplaySpacing.s8,
                runSpacing: ZplaySpacing.s8,
                alignment: WrapAlignment.center,
                children: missing.map((extra) {
                  if (extra.options.isNotEmpty) {
                    return PopupMenuButton<String>(
                      tooltip: extra.name,
                      constraints: const BoxConstraints(maxHeight: 360),
                      color: tokens.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: ZplayRadius.smAll,
                        side: tokens.hairline,
                      ),
                      onSelected: (val) => _onExtraOptionSelected(extra.name, val),
                      itemBuilder: (context) => extra.options
                          .map(
                            (opt) => PopupMenuItem<String>(
                              value: opt,
                              child: Text(
                                opt,
                                style: ZplayType.body.toStyle(
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s16,
                          vertical: ZplaySpacing.s8,
                        ),
                        decoration: BoxDecoration(
                          color: AppThemeService.currentPalette.value.primaryColor,
                          borderRadius: ZplayRadius.lgAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Select ${extra.name[0].toUpperCase()}${extra.name.substring(1)}',
                              style: ZplayType.label
                                  .copyWith(weight: FontWeight.w600)
                                  .toStyle(color: tokens.onAccent),
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            Icon(Icons.arrow_drop_down, color: tokens.onAccent, size: 20),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return ElevatedButton.icon(
                      onPressed: () => _showCustomExtraDialog(extra.name),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeService.currentPalette.value.primaryColor,
                        foregroundColor: tokens.onAccent,
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? ZplaySpacing.s16 : ZplaySpacing.s20,
                          vertical: isNarrow ? ZplaySpacing.s8 : ZplaySpacing.s12,
                        ),
                        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.lgAll),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(
                        'Enter ${extra.name}',
                        style: ZplayType.label.toStyle(),
                      ),
                    );
                  }
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomExtraDialog(String extraName) {
    final tokens = context.tokens;
    final controller = TextEditingController(text: _selectedExtras[extraName] ?? '');
    final screenWidth = MediaQuery.sizeOf(context).width;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: ZplayRadius.mdAll,
          side: tokens.hairline,
        ),
        title: Text(
          'Enter $extraName',
          style: ZplayType.title.toStyle(color: tokens.textPrimary),
        ),
        content: SizedBox(
          width: (screenWidth - 64).clamp(260.0, 420.0),
          child: TextField(
            controller: controller,
            autofocus: true,
            style: ZplayType.body.toStyle(color: tokens.textPrimary),
            decoration: InputDecoration(
              hintText: 'Type $extraName here...',
              hintStyle: ZplayType.body.toStyle(color: tokens.textDisabled),
              enabledBorder: UnderlineInputBorder(
                borderSide: tokens.hairlineStrong,
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppThemeService.currentPalette.value.primaryColor),
              ),
            ),
            onSubmitted: (val) {
              Navigator.pop(ctx);
              _onCustomExtraSubmitted(extraName, val);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: ZplayType.label.toStyle(color: tokens.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeService.currentPalette.value.primaryColor,
              foregroundColor: tokens.onAccent,
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _onCustomExtraSubmitted(extraName, controller.text);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    double topPadding,
    bool hasExtras, {
    bool isCompactScreen = false,
    double toolbarH = kToolbarHeight,
    double selectorH = 50.0,
    double extrasH = 48.0,
  }) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 400;

    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        // Opaque, where this was a 95/80% `#080A0F` gradient behind a 25px
        // blur. The blur is chrome, not artwork, and `#080A0F` is only the
        // ocean palette's page fill, so the bar stayed ocean-black under the
        // other palettes.
        color: tokens.bg,
        border: Border(bottom: tokens.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Title Row ──
          SizedBox(
            height: toolbarH,
            child: Row(
              children: [
                const SizedBox(width: ZplaySpacing.s8),
                // Discover is a Browse vertical now, so this page is normally
                // a shell slot with nothing below it to pop. Gated rather than
                // deleted so the legacy search and genre route, which is still
                // pushed with a query, keeps its back button. There is no
                // layout jump in practice: inside the shell the gate is always
                // false, so the row always starts at the gutter.
                if (Navigator.of(context).canPop())
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 19,
                      color: tokens.textPrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                const SizedBox(width: ZplaySpacing.s2),
                if (!_isSearching) ...[
                  Icon(Icons.explore_rounded, color: AppThemeService.currentPalette.value.primaryColor, size: 21),
                  const SizedBox(width: ZplaySpacing.s8),
                  Text(
                    'Discover',
                    style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                  ),
                ],
                if (_isSearching)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s12,
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: ZplayType.body.toStyle(color: tokens.textPrimary),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSearchSubmitted,
                        decoration: InputDecoration(
                          hintText: isNarrow
                              ? 'Search...'
                              : 'Search within ${_selectedCatalogEntry?.catalog.name ?? 'catalog'}...',
                          hintStyle: ZplayType.body.toStyle(
                            color: tokens.textSecondary,
                          ),
                          border: InputBorder.none,
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: tokens.textEmphasis,
                            ),
                            onPressed: _clearSearch,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),

                // Search toggle button
                if (!_isSearching &&
                    (_selectedCatalogEntry?.catalog.supportsSearch ?? false) &&
                    MetadataService.catalogSearchIsTrustworthy(
                        _selectedCatalogEntry?.addon.baseUrl ?? ''))
                  IconButton(
                    icon: Icon(
                      Icons.search_rounded,
                      color: tokens.textEmphasis,
                      size: 22,
                    ),
                    tooltip: 'Search catalog',
                    onPressed: () => setState(() => _isSearching = true),
                  ),
                const SizedBox(width: ZplaySpacing.s8),
              ],
            ),
          ),

          // ── Type and Catalog Selector Row ──
          Container(
            height: selectorH,
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
            ),
            child: Row(
              children: [
                // Type selector popup/dropdown
                if (_availableTypes.isNotEmpty) ...[
                  PopupMenuButton<String>(
                    tooltip: 'Content Type',
                    constraints: const BoxConstraints(maxHeight: 360),
                    color: tokens.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: ZplayRadius.smAll,
                      side: tokens.hairline,
                    ),
                    onSelected: _onTypeChanged,
                    itemBuilder: (context) => _availableTypes
                        .map(
                          (t) => PopupMenuItem<String>(
                            value: t,
                            child: Text(
                              '${t[0].toUpperCase()}${t.substring(1)}',
                              style: ZplayType.body.toStyle(
                                color: t == _selectedType
                                    ? AppThemeService.currentPalette.value.primaryColor
                                    : tokens.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
                        vertical: ZplaySpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.2),
                        borderRadius: ZplayRadius.lgAll,
                        border: Border.all(color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selectedType[0].toUpperCase()}${_selectedType.substring(1)}',
                            style: ZplayType.label.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(width: ZplaySpacing.s4),
                          Icon(
                            Icons.arrow_drop_down,
                            color: tokens.textEmphasis,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: isNarrow ? ZplaySpacing.s8 : ZplaySpacing.s12),
                ],

                // Catalog selector horizontal scroll
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _currentTypeCatalogs.map((entry) {
                        final isSelected = _selectedCatalogEntry == entry;
                        // The 18+ view mixes addons, so name the source.
                        final name =
                            '${AddonManager.instance.catalogDisplayName(entry.catalog)}'
                            '${_selectedType == _adultType ? ' · ${entry.addon.manifest.name}' : ''}';
                        final hasReq = entry.catalog.hasRequiredExtra;

                        return Padding(
                          padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                          child: FocusableCard(
                            onTap: () => _onCatalogChanged(entry),
                            builder: (context, state) => AnimatedContainer(
                              duration: ZplayMotion.base,
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
                                vertical: ZplaySpacing.s8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppThemeService.currentPalette.value.primaryColor
                                    : tokens.borderDefault,
                                borderRadius: ZplayRadius.lgAll,
                                border: Border.all(
                                  color: isSelected
                                      ? AppThemeService.currentPalette.value.primaryColor
                                      : tokens.borderStrong,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                        )
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: ZplayType.label.toStyle(
                                      color: isSelected
                                          ? tokens.onAccent
                                          : tokens.textEmphasis,
                                    ),
                                  ),
                                  if (hasReq) ...[
                                    const SizedBox(width: ZplaySpacing.s8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? tokens.borderStrong
                                            : tokens.warning.withValues(alpha: 0.25),
                                        borderRadius: ZplayRadius.smAll,
                                      ),
                                      child: Text(
                                        'Custom',
                                        style: ZplayType.caption.toStyle(
                                          color: isSelected
                                              ? tokens.onAccent
                                              : tokens.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Extra Selectors Row (Genre, Tag, Sort, Performer, etc.) ──
          if (hasExtras) ...[
            SizedBox(
              height: extrasH,
              child: ListView(
                controller: _filtersScrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
                  vertical: ZplaySpacing.s8,
                ),
                physics: const BouncingScrollPhysics(),
                children: _selectedCatalogEntry!.catalog.extra.map((extra) {
                  if (extra.name == 'skip' || (extra.name == 'search' && !extra.isRequired)) {
                    return const SizedBox.shrink();
                  }

                  final currentVal = _selectedExtras[extra.name];
                  final isReq = extra.isRequired;
                  final isSelected = currentVal != null && currentVal.isNotEmpty;

                  // Dropdown for extras with predefined options
                  if (extra.options.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                      child: PopupMenuButton<String?>(
                        tooltip: extra.name,
                        constraints: const BoxConstraints(maxHeight: 360),
                        color: tokens.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: ZplayRadius.smAll,
                          side: tokens.hairline,
                        ),
                        onSelected: (val) => _onExtraOptionSelected(extra.name, val),
                        itemBuilder: (context) => [
                          if (!isReq)
                            PopupMenuItem<String?>(
                              value: null,
                              child: Text(
                                'All ${extra.name}',
                                style: ZplayType.body.toStyle(
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                          ...extra.options.map(
                            (opt) => PopupMenuItem<String?>(
                              value: opt,
                              child: Text(
                                opt,
                                style: ZplayType.body.toStyle(
                                  color: opt == currentVal
                                      ? AppThemeService.currentPalette.value.primaryColor
                                      : tokens.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
                            vertical: ZplaySpacing.s8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppThemeService.currentPalette.value.primaryColor
                                : (isReq
                                    ? tokens.warning.withValues(alpha: ZplayOpacity.overlayHover)
                                    : tokens.borderDefault),
                            borderRadius: ZplayRadius.lgAll,
                            border: Border.all(
                              color: isSelected
                                  ? AppThemeService.currentPalette.value.primaryColor
                                  : (isReq
                                      ? tokens.warning.withValues(alpha: 0.4)
                                      : tokens.borderStrong),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${extra.name.toUpperCase()}: ${currentVal ?? (isReq ? "Required *" : "All")}',
                                style: ZplayType.label.toStyle(
                                  color: isSelected
                                      ? tokens.onAccent
                                      : (isReq ? tokens.warning : tokens.textEmphasis),
                                ),
                              ),
                              const SizedBox(width: ZplaySpacing.s4),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                                color: isSelected
                                    ? tokens.onAccent
                                    : (isReq ? tokens.warning : tokens.textEmphasis),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  // Text input chip for freeform extras (or search if isRequired)
                  return Padding(
                    padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                    child: FocusableCard(
                      onTap: () => _showCustomExtraDialog(extra.name),
                      builder: (context, state) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? ZplaySpacing.s12 : ZplaySpacing.s16,
                          vertical: ZplaySpacing.s8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppThemeService.currentPalette.value.primaryColor
                              : (isReq
                                  ? tokens.warning.withValues(alpha: ZplayOpacity.overlayHover)
                                  : tokens.borderDefault),
                          borderRadius: ZplayRadius.lgAll,
                          border: Border.all(
                            color: isSelected
                                ? AppThemeService.currentPalette.value.primaryColor
                                : (isReq
                                    ? tokens.warning.withValues(alpha: 0.4)
                                    : tokens.borderStrong),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${extra.name.toUpperCase()}: ${currentVal ?? (isReq ? "Required *" : "Enter")}',
                              style: ZplayType.label.toStyle(
                                color: isSelected
                                    ? tokens.onAccent
                                    : (isReq ? tokens.warning : tokens.textEmphasis),
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s4),
                            Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: isSelected
                                  ? tokens.onAccent
                                  : (isReq ? tokens.warning : tokens.textEmphasis),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Legacy Search/Genre Scaffold (Backwards compatibility)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildLegacyScaffold() {
    final tokens = context.tokens;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          if (_legacyLoading)
            Center(child: CircularProgressIndicator(color: AppThemeService.currentPalette.value.primaryColor))
          else if (_legacyError != null)
            ErrorView(error: _legacyError, onRetry: _fetchLegacyData)
          else if (_legacySections.isEmpty)
            Center(
              child: Text(
                'No results found for "${widget.query}"',
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
              ),
            )
          else
            _buildLegacySectionsList(topPadding + kToolbarHeight + 20),

          // App Bar — opaque like the shell's header, where this was a 60%
          // `#0A0C16` fill behind a 15px blur.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: kToolbarHeight + topPadding,
              padding: EdgeInsets.only(
                top: topPadding,
                left: ZplaySpacing.s16,
                right: ZplaySpacing.s16,
              ),
              decoration: BoxDecoration(
                color: tokens.bg,
                border: Border(bottom: tokens.hairline),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: tokens.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  Expanded(
                    child: Text(
                      widget.isGenre ? 'Genre: ${widget.query}' : 'Search: ${widget.query}',
                      style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacySectionsList(double topPadding) {
    final allMoviesMap = <String, Movie>{};
    for (var section in _legacySections) {
      for (var movie in section.movies) {
        if (!allMoviesMap.containsKey(movie.id)) {
          allMoviesMap[movie.id] = movie;
        }
      }
    }
    final allMovies = allMoviesMap.values.toList();
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final double cardAspectRatio = sizing.cardWidth / sizing.totalHeight;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        sizing.sidePadding,
        topPadding,
        sizing.sidePadding,
        110 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ((MediaQuery.sizeOf(context).width - sizing.sidePadding * 2 + sizing.spacing) /
                (sizing.cardWidth + sizing.spacing))
            .floor()
            .clamp(2, 10),
        childAspectRatio: cardAspectRatio,
        crossAxisSpacing: sizing.spacing,
        mainAxisSpacing: sizing.spacing,
      ),
      itemCount: allMovies.length,
      itemBuilder: (context, index) {
        return MovieCard(movie: allMovies[index]);
      },
    );
  }
}
