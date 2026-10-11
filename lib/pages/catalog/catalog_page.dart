import 'package:flutter/material.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/card_focus_expansion.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/movie/movie_card.dart';

class CatalogPage extends StatefulWidget {
  final MovieSection section;

  const CatalogPage({
    super.key,
    required this.section,
  });

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final List<Movie> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  final Map<String, String> _selectedExtras = {};
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final ScrollController _genreScrollController = ScrollController();

  bool _canScrollGenresLeft = false;
  bool _canScrollGenresRight = true;
  bool _isHoveringGenres = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _genreScrollController.addListener(_updateGenreScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateGenreScrollButtons();
    });
    _loadItems(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _genreScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && _hasMore) {
        _loadItems();
      }
    }
  }

  void _updateGenreScrollButtons() {
    if (!_genreScrollController.hasClients) return;
    setState(() {
      _canScrollGenresLeft = _genreScrollController.position.pixels > 0;
      _canScrollGenresRight =
          _genreScrollController.position.pixels < _genreScrollController.position.maxScrollExtent;
    });
  }

  void _scrollGenres(double directionMultiplier) {
    if (!_genreScrollController.hasClients) return;
    final viewportWidth = _genreScrollController.position.viewportDimension;
    final target = _genreScrollController.offset + (viewportWidth * 0.7 * directionMultiplier);
    _genreScrollController.animateTo(
      target.clamp(0.0, _genreScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _items.clear();
        _hasMore = true;
        _error = null;
      });
    }

    if (!_hasMore) return;

    // Check if all required extras are selected
    if (widget.section.catalog.hasRequiredExtra) {
      for (final req in widget.section.catalog.requiredExtras) {
        final val = _selectedExtras[req.name];
        if (val == null || val.trim().isEmpty) {
          setState(() {
            _isLoading = false;
            _hasMore = false;
          });
          return;
        }
      }
    }

    setState(() => _isLoading = true);

    try {
      List<Movie> newItems = [];

      if (_isSearching && _searchQuery.isNotEmpty) {
        if (refresh) {
          newItems = await MetadataService.search(
            baseUrl: widget.section.addonBaseUrl,
            type: widget.section.contentType,
            catalogId: widget.section.catalog.id,
            query: _searchQuery,
          );
          _hasMore = false;
        }
      } else {
        newItems = await MetadataService.fetchCatalog(
          baseUrl: widget.section.addonBaseUrl,
          type: widget.section.contentType,
          catalogId: widget.section.catalog.id,
          extraParams: _selectedExtras.isNotEmpty ? _selectedExtras : null,
          skip: _items.length,
        );
      }

      if (!mounted) return;

      setState(() {
        if (newItems.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(newItems);
        }
        _isLoading = false;
      });

      // If content doesn't fill the viewport yet, load more immediately.
      // This fixes fullscreen mode where the initial batch doesn't produce
      // enough scroll extent to ever trigger _onScroll.
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

  void _onExtraSelected(String extraName, String? value) {
    if (_selectedExtras[extraName] == value) return;
    setState(() {
      if (value == null || value.isEmpty) {
        _selectedExtras.remove(extraName);
      } else {
        _selectedExtras[extraName] = value;
      }
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadItems(refresh: true);
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
      });
      _loadItems(refresh: true);
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
      _selectedExtras.clear();
    });
    _loadItems(refresh: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
    _loadItems(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final tokens = context.tokens;
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    
    // Calculate safe top padding for grid based on if filters are available
    final selectableExtras = widget.section.catalog.selectableExtras;
    final hasFilters = selectableExtras.isNotEmpty && !_isSearching;
    final gridTopPadding =
        topPadding +
        kToolbarHeight +
        (hasFilters ? 60 : ZplaySpacing.s20) +
        ZplaySpacing.s20;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Main Content Grid ──
          if (_items.isEmpty && _isLoading)
            Center(
              child: CircularProgressIndicator(color: AppThemeService.currentPalette.value.primaryColor),
            )
          else if (_items.isEmpty && _error != null)
            ErrorView(
              error: _error,
              onRetry: () => _loadItems(refresh: true),
            )
          else if (_items.isEmpty)
            Center(
              child: Text(
                'No items found',
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
              ),
            )
          else
            // The band a focused card's pop may paint in - see
            // [PageContentTop]. `gridTopPadding` *is* where this page's own
            // chrome ends: the toolbar, the genre pill row and the gap under it.
            // Without it the pop was pinned to the window's own edge, 124 dp
            // above the first row, and painted over the toolbar and the pills.
            PageContentTop(
              value: gridTopPadding,
              child: GridView.builder(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  sizing.sidePadding,
                  gridTopPadding,
                  sizing.sidePadding,
                  // Bottom padding
                  ZplaySpacing.s40 + MediaQuery.paddingOf(context).bottom,
                ),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: ((MediaQuery.sizeOf(context).width - sizing.sidePadding * 2 + sizing.spacing) / (sizing.cardWidth + sizing.spacing)).floor().clamp(2, 10),
                  // `mainAxisExtent`, not `childAspectRatio` - the cell width here
                  // is `columns`-driven and wider than `sizing.cardWidth`, so a
                  // proportion would inflate every card's height. See
                  // `collection_grid_page.dart` for the full arithmetic.
                  mainAxisExtent: sizing.totalHeight,
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
              ),
            ),

          // ── App Bar & Filters ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // The shell family draws this band as an opaque palette surface with a
            // bottom hairline, not as a blurred wash over the grid.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.bg,
                border: Border(bottom: tokens.hairline),
              ),
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Row
                    SizedBox(
                      height: kToolbarHeight,
                      child: Row(
                        children: [
                          const SizedBox(width: ZplaySpacing.s8),
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                            color: tokens.textPrimary,
                            onPressed: () => Navigator.pop(context),
                          ),
                          if (!_isSearching)
                            Expanded(
                              child: Text(
                                widget.section.title,
                                style: ZplayType.title.toStyle(
                                  color: tokens.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (_isSearching)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: ZplaySpacing.s16,
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  autofocus: true,
                                  style: ZplayType.subtitle.toStyle(
                                    color: tokens.textPrimary,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: _onSearchSubmitted,
                                  decoration: InputDecoration(
                                    hintText: 'Search...',
                                    hintStyle: ZplayType.subtitle.toStyle(
                                      color: tokens.textMuted,
                                    ),
                                    border: InputBorder.none,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      color: tokens.textEmphasis,
                                      onPressed: _clearSearch,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (!_isSearching &&
                              widget.section.catalog.supportsSearch &&
                              MetadataService.catalogSearchIsTrustworthy(
                                  widget.section.addonBaseUrl))
                            IconButton(
                              icon: const Icon(Icons.search_rounded),
                              color: tokens.textEmphasis,
                              onPressed: () {
                                setState(() {
                                  _isSearching = true;
                                });
                              },
                            ),
                          if (!_isSearching)
                            const SizedBox(width: ZplaySpacing.s8),
                        ],
                      ),
                    ),
                    
                    // Selectable Extras Row (Genre, Tag, Sort, etc.)
                    if (hasFilters)
                      _buildFilterRow(selectableExtras, isDesktop),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(List<CatalogExtra> selectableExtras, bool isDesktop) {
    final tokens = context.tokens;
    if (selectableExtras.length == 1) {
      final singleExtra = selectableExtras.first;
      final options = singleExtra.options;
      return MouseRegion(
        onEnter: (_) => setState(() => _isHoveringGenres = true),
        onExit: (_) => setState(() => _isHoveringGenres = false),
        child: Stack(
          children: [
            SizedBox(
              height: 50,
              // The row's own 16 dp side margins live **outside** the scroll
              // view, not in its `padding`.
              //
              // A `padding` is content, so the scroll view's edges were the
              // display's edges: 0 and 960. Focus traffic reveals a pill by
              // railing it against the viewport's trailing edge, so the last
              // pill in the row was drawn with its fill - and its glow - on the
              // display's final pixel, and the scroll that got it there pushed
              // the first pill past x=0. Outside, the viewport is 16..944: the
              // row can never paint in either gutter, and the last pill is
              // revealed 16 dp short of the screen edge.
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s8,
                ),
                child: ListView.separated(
                  controller: _genreScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: options.length + (singleExtra.isRequired ? 0 : 1),
                  separatorBuilder: (context, index) => const SizedBox(width: ZplaySpacing.s8),
                  itemBuilder: (context, index) {
                    if (!singleExtra.isRequired) {
                      if (index == 0) {
                        return _GenreChip(
                          label: 'All',
                          isSelected: _selectedExtras[singleExtra.name] == null,
                          onTap: () => _onExtraSelected(singleExtra.name, null),
                        );
                      }
                      final opt = options[index - 1];
                      return _GenreChip(
                        label: opt,
                        isSelected: _selectedExtras[singleExtra.name] == opt,
                        onTap: () => _onExtraSelected(singleExtra.name, opt),
                      );
                    }
                    final opt = options[index];
                    return _GenreChip(
                      label: opt,
                      isSelected: _selectedExtras[singleExtra.name] == opt,
                      onTap: () => _onExtraSelected(singleExtra.name, opt),
                    );
                  },
                ),
              ),
            ),
            if (isDesktop) ...[
              if (_canScrollGenresLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    Icons.arrow_back_ios_new_rounded,
                    () => _scrollGenres(-1),
                    _isHoveringGenres,
                  ),
                ),
              if (_canScrollGenresRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    Icons.arrow_forward_ios_rounded,
                    () => _scrollGenres(1),
                    _isHoveringGenres,
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: 50,
      // Outside the scroll view, for the same reason as the pill row above: a
      // `padding` is content, so keeping it in would put the scroll view's edges
      // on the display's edges and let focus rail a chip against the last pixel.
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s16,
          vertical: ZplaySpacing.s8,
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: selectableExtras.length,
          separatorBuilder: (context, index) => const SizedBox(width: ZplaySpacing.s8),
          itemBuilder: (context, index) {
            final extra = selectableExtras[index];
            final currentVal = _selectedExtras[extra.name];
            final label = currentVal ?? (extra.isRequired ? 'Select ${extra.name}' : 'All ${extra.name}');
            return PopupMenuButton<String?>(
              tooltip: extra.name,
              color: tokens.surfaceOverlay,
              shape: RoundedRectangleBorder(
                borderRadius: ZplayRadius.smAll,
                side: BorderSide(color: tokens.borderStrong),
              ),
              onSelected: (val) => _onExtraSelected(extra.name, val),
              itemBuilder: (context) => [
                if (!extra.isRequired)
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text(
                      'All',
                      style: ZplayType.body.toStyle(color: tokens.textPrimary),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s12,
                  vertical: ZplaySpacing.s8,
                ),
                decoration: BoxDecoration(
                  color: currentVal != null ? AppThemeService.currentPalette.value.primaryColor : tokens.surface,
                  borderRadius: ZplayRadius.lgAll,
                  border: Border.all(
                    color: currentVal != null ? AppThemeService.currentPalette.value.primaryColor : tokens.borderStrong,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${extra.name.toUpperCase()}: $label',
                      style: ZplayType.label.toStyle(
                        color: currentVal != null
                            ? tokens.onAccent
                            : tokens.textEmphasis,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: currentVal != null
                          ? tokens.onAccent
                          : tokens.textEmphasis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap, bool isVisible) {
    final tokens = context.tokens;
    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: ZplayMotion.base,
        child: IgnorePointer(
          ignoring: !isVisible,
          // An invisible arrow must not be a focus stop. IgnorePointer blocks
          // taps but not focus, so without this a remote lands on a control
          // that is not on screen.
          child: FocusableCard(
            onTap: onTap,
            enabled: isVisible,
            builder: (context, state) => Container(
              margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4),
              padding: const EdgeInsets.all(ZplaySpacing.s8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Icon(icon, color: tokens.textPrimary, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Selection is a fill, focus is a ring, and the two are different questions.
    //
    // The pill used to answer both with the accent: selected was an opaque
    // accent fill, and focus painted nothing at all. A remote therefore walked
    // ten pills with nothing moving on screen, and the OK that followed applied
    // whichever filter the invisible focus had stopped on. [CardFocusRing] is
    // the app's one focus indicator and is painted over the pill's own edge, so
    // no layout moves when the ring arrives.
    //
    // The fill had to give the ring somewhere to be seen. Accent on accent -
    // an accent ring around an accent pill - is invisible, which is exactly the
    // state the user is left in after applying a filter, because focus stays on
    // the pill that was just applied. So selection is the accent *tint* the
    // tokens already define for a selected chip ([ZplayTokens.accentSubtle],
    // "selected chip, active row, badge background") behind an accent hairline:
    // still unmistakably "this filter is on" from ten feet, and the ring reads
    // as the remote's position on top of it, selected or not.
    //
    // The blur is gone with it. A zero-offset accent glow bled past the pill's
    // own edge and read as a second edge on the selected pill; on the last pill
    // of the row it bled into the display's final pixels, which is how the
    // selected fill came to touch the screen edge.
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        // The pill's own radius, so the ring hugs the shape it is drawn on.
        radius: ZplayRadius.lgAll,
        focused: state.focused,
        child: AnimatedContainer(
          duration: ZplayMotion.base,
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s16,
            vertical: ZplaySpacing.s4,
          ),
          decoration: BoxDecoration(
            color: isSelected ? tokens.accentSubtle : tokens.surface,
            borderRadius: ZplayRadius.lgAll,
            // Always drawn, only recoloured: the border is part of the pill's
            // box, so a border that came and went would resize the pill every
            // time a filter was applied.
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.borderStrong,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: ZplayType.label.toStyle(
              color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
            ),
          ),
        ),
      ),
    );
  }
}
