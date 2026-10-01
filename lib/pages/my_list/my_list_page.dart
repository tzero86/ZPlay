import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/my_list/my_list_item.dart';
import '../../services/content/content_settings.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../details/details_page.dart';
import '../../models/movie/movie.dart';
import '../../services/storage/app_image_cache.dart';
import '../../widgets/common/focusable_card.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({super.key});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  String _filterType = 'all'; // 'all', 'movie', 'series'
  String _sortBy = 'recent'; // 'recent', 'title', 'year'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MyListItem> _getFilteredAndSortedItems(List<MyListItem> allItems) {
    var filtered = allItems.where((item) {
      // 1. Filter by media type
      if (_filterType == 'movie' && item.type != 'movie') return false;
      if (_filterType == 'series' && item.type != 'series' && item.type != 'anime') return false;

      // 2. Filter by search query
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final title = item.title.toLowerCase();
        if (!title.contains(query)) return false;
      }
      return true;
    }).toList();

    // 3. Sort items
    switch (_sortBy) {
      case 'recent':
        filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case 'title':
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'year':
        filtered.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
    }
    return filtered;
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  void _navigateToDetail(MyListItem item) {
    final effectiveId = item.imdbId ??
        (item.tmdbId != null ? 'tmdb:${item.tmdbId}' : null) ??
        item.traktId?.toString() ??
        '';

    final movie = Movie(
      id: effectiveId,
      name: item.title,
      poster: item.poster,
      year: item.year?.toString(),
      type: item.type,
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
    );

    Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: movie),
        tapPosition: null,
      ),
    );
  }

  Future<void> _confirmRemove(MyListItem item) async {
    final tokens = context.tokens;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
        title: Text(
          'Remove from My List?',
          style: ZplayType.title.toStyle(color: tokens.textPrimary),
        ),
        content: Text(
          'Remove "${item.title}" from your list?',
          style: ZplayType.body.toStyle(color: tokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: ZplayType.label.toStyle(color: tokens.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.textPrimary,
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            ),
            child: Text('Remove', style: ZplayType.label.toStyle()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        MyListService.remove(item);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Ambient Background Glows ──
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.15),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: tokens.info.withValues(alpha: 0.1),
                    blurRadius: 140,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          // ── Main Content ──
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                MyListService.items,
                ContentSettings.adultEnabled,
              ]),
              builder: (context, _) {
                final allItems = MyListService.visibleItems;
                final movieCount = allItems.where((i) => i.type == 'movie').length;
                final seriesCount = allItems.where((i) => i.type == 'series' || i.type == 'anime').length;
                final displayedItems = _getFilteredAndSortedItems(allItems);

                return Column(
                  children: [
                    // ── Header Bar ──
                    _buildHeader(context, allItems.length),

                    // ── Filter Pills & Search Bar ──
                    _buildFilterToolbar(allItems.length, movieCount, seriesCount),

                    const SizedBox(height: ZplaySpacing.s12),

                    // ── Grid of Items ──
                    Expanded(
                      child: displayedItems.isEmpty
                          ? _buildEmptyState(allItems.isEmpty)
                          : GridView.builder(
                              padding: EdgeInsets.fromLTRB(
                                ZplaySpacing.s16,
                                ZplaySpacing.s12,
                                ZplaySpacing.s16,
                                ZplaySpacing.s24 +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _getCrossAxisCount(context),
                                childAspectRatio: 0.65,
                                crossAxisSpacing: ZplaySpacing.s12,
                                mainAxisSpacing: ZplaySpacing.s16,
                              ),
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final item = displayedItems[index];
                                return _MyListCard(
                                  item: item,
                                  onTap: () => _navigateToDetail(item),
                                  onRemove: () => _confirmRemove(item),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final tokens = context.tokens;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? ZplaySpacing.s12 : ZplaySpacing.s20,
        vertical: ZplaySpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(bottom: tokens.hairline),
      ),
      child: Row(
        children: [
          // My List is a tab of the library shell slot, not a pushed overlay, so the
          // back button only belongs here when there is genuinely a route underneath.
          if (Navigator.of(context).canPop())
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.arrow_back_ios_rounded,
                color: tokens.textPrimary,
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: tokens.surface,
                padding: const EdgeInsets.all(ZplaySpacing.s8),
              ),
            ),
          const SizedBox(width: ZplaySpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My List',
                  style: ZplayType.titleLarge.toStyle(
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  '$totalCount saved ${totalCount == 1 ? 'title' : 'titles'}',
                  style: ZplayType.bodySmall.toStyle(
                    color: tokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: ZplaySpacing.s8),

          // ── Cloud Sync Status & Refresh Button ──
          ValueListenableBuilder<bool>(
            valueListenable: MyListService.isSyncing,
            builder: (context, isSyncing, _) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s8,
                  vertical: ZplaySpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: tokens.accentSubtle,
                  borderRadius: ZplayRadius.lgAll,
                  border: Border.all(color: tokens.accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSyncing)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppThemeService.currentPalette.value.primaryColor),
                        ),
                      )
                    else
                      Icon(Icons.cloud_done_rounded, color: AppThemeService.currentPalette.value.primaryColor, size: 15),
                    const SizedBox(width: ZplaySpacing.s4),
                    Text(
                      isSyncing ? 'Syncing...' : 'Cloud Synced',
                      style: ZplayType.caption.toStyle(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: tokens.textEmphasis,
                        size: 14,
                      ),
                      onPressed: isSyncing ? null : () => MyListService.syncAll(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(int totalCount, int movieCount, int seriesCount) {
    final tokens = context.tokens;
    // On a television the filter pills and the search field share one row.
    //
    // Stacked, they cost 111 + 53 = 164 dp - 30% of a 540 dp screen - and on an
    // empty list that is 164 dp of controls above a centred icon and two lines of
    // text. There is also nothing to filter or to search, so the whole block is
    // chrome describing an absence.
    //
    // The same merge Browse got, for the same reason: one row, same controls,
    // same focus order. The search field goes last in that row rather than
    // disappearing, so a list of 200 titles is still searchable from a sofa.
    final television =
        FormFactorService.of(context) == FormFactor.television;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s8,
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                // Filter Tabs
                _buildFilterPill('all', 'All', totalCount),
                const SizedBox(width: ZplaySpacing.s8),
                _buildFilterPill('movie', 'Movies', movieCount),
                const SizedBox(width: ZplaySpacing.s8),
                _buildFilterPill('series', 'TV Shows', seriesCount),
                const SizedBox(width: ZplaySpacing.s16),

                // The search field, inline on a television.
                //
                // Not dropped: a saved list of 200 titles is still worth
                // searching from a sofa, and a control that is merely *hidden* on
                // TV is a control the remote can never reach. It is the same
                // field, in the same row, after the sort control.
                if (television) ...[
                  SizedBox(
                    width: 220,
                    child: _buildSearchField(tokens),
                  ),
                  const SizedBox(width: ZplaySpacing.s16),
                ],

                // Sort Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s12,
                    vertical: ZplaySpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: ZplayRadius.smAll,
                    border: Border.fromBorderSide(tokens.hairlineStrong),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      dropdownColor: tokens.surfaceOverlay,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textPrimary,
                      ),
                      icon: Icon(Icons.sort_rounded, color: AppThemeService.currentPalette.value.primaryColor, size: 16),
                      items: const [
                        DropdownMenuItem(value: 'recent', child: Text('Recently Added')),
                        DropdownMenuItem(value: 'title', child: Text('Alphabetical')),
                        DropdownMenuItem(value: 'year', child: Text('Release Year')),
                      ],
                      onChanged: (v) => setState(() => _sortBy = v!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // On a television the search field shares the pill row, so the block
          // is one row rather than two. See the note on this method.
          if (!television) ...[
          const SizedBox(height: ZplaySpacing.s8),

          // Search Field
          _buildSearchField(tokens),
          ],
        ],
      ),
    );
  }

  /// The saved-titles search field. One widget, two layouts: a full-width row on
  /// a pointer, and a fixed-width control in the pill row on a television.
  Widget _buildSearchField(ZplayTokens tokens) {
    return Container(
            height: 40,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.fromBorderSide(tokens.hairline),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: ZplayType.label.toStyle(color: tokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search saved titles...',
                hintStyle: ZplayType.label.toStyle(color: tokens.textDisabled),
                prefixIcon: Icon(Icons.search_rounded, color: tokens.textMuted, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: tokens.textSecondary,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: ZplaySpacing.s8,
                ),
              ),
            ),
    );
  }

  Widget _buildFilterPill(String type, String label, int count) {
    final tokens = context.tokens;
    final isSelected = _filterType == type;

    return FocusableCard(
      onTap: () => setState(() => _filterType = type),
      builder: (_, state) => AnimatedContainer(
        duration: ZplayMotion.base,
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s12,
          vertical: ZplaySpacing.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppThemeService.currentPalette.value.primaryColor : tokens.surface,
          borderRadius: ZplayRadius.lgAll,
          border: Border.all(
            color: isSelected ? AppThemeService.currentPalette.value.primaryColor : tokens.borderStrong,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ZplayType.label.toStyle(
                color: isSelected ? tokens.onAccent : tokens.textEmphasis,
              ),
            ),
            const SizedBox(width: ZplaySpacing.s4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s4,
                vertical: ZplaySpacing.s2,
              ),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accentPressed : tokens.surfaceRaised,
                borderRadius: ZplayRadius.smAll,
              ),
              child: Text(
                '$count',
                style: ZplayType.caption.toStyle(
                  color: isSelected ? tokens.onAccent : tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isListEmpty) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.accentSubtle,
              border: Border.all(color: tokens.accent),
            ),
            child: Icon(
              isListEmpty ? Icons.bookmark_border_rounded : Icons.search_off_rounded,
              size: 54,
              color: AppThemeService.currentPalette.value.primaryColor,
            ),
          ),
          const SizedBox(height: ZplaySpacing.s16),
          Text(
            isListEmpty ? 'Your list is empty' : 'No titles found',
            style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Text(
            isListEmpty
                ? 'Save your favorite movies and TV shows to watch anytime'
                : 'Try adjusting your search query or filter settings',
            textAlign: TextAlign.center,
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
          ),
          if (!isListEmpty) ...[
            const SizedBox(height: ZplaySpacing.s16),
            ElevatedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _filterType = 'all';
                  _searchQuery = '';
                });
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Reset Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeService.currentPalette.value.primaryColor,
                foregroundColor: tokens.onAccent,
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Hover Card Widget with Home Page Quality & Liquid Effects
// ─────────────────────────────────────────────────────────────────────────────

class _MyListCard extends StatelessWidget {
  const _MyListCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final MyListItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isMovie = item.type == 'movie';

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => GestureDetector(
        // Pointer-only shortcut: FocusableCard owns tap and activation, not long press.
        onLongPress: onRemove,
        child: AnimatedScale(
          scale: state.highlighted ? 1.04 : 1.0,
          duration: ZplayMotion.base,
          curve: ZplayMotion.standard,
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.mdAll,
            child: AnimatedContainer(
              duration: ZplayMotion.base,
              decoration: BoxDecoration(
                borderRadius: ZplayRadius.mdAll,
                border: Border.all(
                  color: state.highlighted
                      ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.8)
                      : tokens.borderDefault,
                  width: state.highlighted ? 1.8 : 1.0,
                ),
                boxShadow: state.highlighted
                    ? [
                        BoxShadow(
                          color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 18,
                          spreadRadius: 2,
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: ClipRRect(
                borderRadius: ZplayRadius.mdAll,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Poster Image
                    if (item.poster != null && item.poster!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.poster!,
                        cacheManager: AppImageCache.manager,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            _buildFallbackPoster(context))
                    else
                      _buildFallbackPoster(context),

                    // Bottom Gradient & Title Overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.5, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: state.highlighted ? 0.4 : 0.2),
                              Colors.black.withValues(alpha: 0.92),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Top Badges (Media Type & Trakt Source)
                    Positioned(
                      top: ZplaySpacing.s8,
                      left: ZplaySpacing.s8,
                      right: ZplaySpacing.s8,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Media Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s8,
                              vertical: ZplaySpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: isMovie
                                  ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.85)
                                  : tokens.info.withValues(alpha: 0.85),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              isMovie ? 'MOVIE' : 'SERIES',
                              style: ZplayType.overline.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),

                          // Cloud Sync Badge
                          if (item.source == MyListSource.trakt)
                            Container(
                              padding: const EdgeInsets.all(ZplaySpacing.s4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFED1C24).withValues(alpha: 0.5)),
                              ),
                              child: const Icon(Icons.cloud_done_rounded, color: Color(0xFFED1C24), size: 11),
                            )
                          else if (item.source == MyListSource.simkl)
                            Container(
                              padding: const EdgeInsets.all(ZplaySpacing.s4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00ADFF).withValues(alpha: 0.5)),
                              ),
                              child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF00ADFF), size: 11),
                            ),
                        ],
                      ),
                    ),

                    // Title & Metadata
                    Positioned(
                      left: ZplaySpacing.s8,
                      right: ZplaySpacing.s8,
                      bottom: ZplaySpacing.s8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          if (item.year != null)
                            Text(
                              '${item.year}',
                              style: ZplayType.caption.toStyle(
                                color: tokens.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Pointer-only, deliberately. On TV this overlay is
                    // unusable: the quick-delete below is a bare
                    // GestureDetector, so a remote cannot activate it, and the
                    // scrim would cover the poster a D-pad user is looking at.
                    // Gating on hover keeps the focused card clean instead of
                    // promising a control that cannot be used.
                    //
                    // TV is not left without a way to remove an item: the card is
                    // focusable and opens the details page, whose My List toggle
                    // is a FocusableCard and so answers to the centre key. The
                    // alternative — showing this overlay on focus instead — would
                    // cover the poster and would need a focus-holding Focus node,
                    // because the overlay unmounts the button being pressed.
                    // Revisit only if the details-page path goes away.
                    if (state.hovered)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Play/Details Button
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppThemeService.currentPalette.value.primaryColor,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: tokens.onAccent,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: ZplaySpacing.s12),

                                // Quick Delete Button
                                GestureDetector(
                                  onTap: onRemove,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: tokens.danger.withValues(alpha: 0.9),
                                    ),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: tokens.textPrimary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _buildFallbackPoster(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      color: tokens.surface,
      child: Center(
        child: Icon(
          item.type == 'movie' ? Icons.movie_rounded : Icons.tv_rounded,
          color: tokens.textDisabled,
          size: 38,
        ),
      ),
    );
  }
}
