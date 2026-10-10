import 'package:flutter/material.dart';

import '../../models/my_list/my_list_item.dart';
import '../../services/content/content_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../details/details_page.dart';
import '../../models/movie/movie.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/tab_strip.dart';
import '../../widgets/movie/movie_card.dart';

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

  /// The height of a grid cell, as a ratio of its width, for the shared card.
  ///
  /// The old card drew the title *over* the poster, so a cell could be the
  /// poster's own 1.54 and nothing else. [MovieCard] puts the title and the meta
  /// line in a block below the artwork, and that block has a fixed height
  /// (`MovieCardSizing.textBlockHeight`), so the ratio is a function of the cell
  /// width and cannot be a constant: the cell has to hold a 1.48 poster plus the
  /// block. [MovieCard]'s artwork is `Flexible`, so a rounding difference is
  /// absorbed by the poster rather than cropping the title - which is what put
  /// the card in a grid at all instead of a rail.
  double _gridChildAspectRatio(BuildContext context) {
    final crossAxisCount = _getCrossAxisCount(context);
    const spacing = ZplaySpacing.s12;
    const gutter = ZplaySpacing.s16;
    final available = MediaQuery.sizeOf(context).width -
        gutter * 2 -
        spacing * (crossAxisCount - 1);
    final cellWidth = available / crossAxisCount;
    final cellHeight =
        cellWidth * MovieCardSizing.posterRatio + MovieCardSizing.textBlockHeight;
    return cellWidth / cellHeight;
  }

  /// The shared card's input, and the details page's, from one place.
  ///
  /// The card and the route have to agree about the title, the poster, the year
  /// and the id, or tapping a card opens a different record than the one the
  /// user just read - so both read this.
  Movie _movieFor(MyListItem item) {
    final effectiveId = item.imdbId ??
        (item.tmdbId != null ? 'tmdb:${item.tmdbId}' : null) ??
        item.traktId?.toString() ??
        '';

    return Movie(
      id: effectiveId,
      name: item.title,
      poster: item.poster,
      year: item.year?.toString(),
      type: item.type,
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
    );
  }

  void _navigateToDetail(MyListItem item) {
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: _movieFor(item)),
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
          // ── Ambient canvas ──
          //
          // Two soft glows on the page canvas, one accent at two intensities -
          // the same canvas Home paints, and deliberately *not*
          // `AnimatedAmbientBackground`.
          //
          // That widget's 12 s controller passes `..repeat()`, so it never
          // settles: swapping it in here would hang `my_list_page_test`'s four
          // `pumpAndSettle()` calls, and the tests pin real behaviour (the empty
          // state, the grid, the long-press remove) rather than a screenshot, so
          // they are not the thing to relax. My List is a tab under the Library
          // switcher, which is offstage on a television until the user goes
          // there, so this is not the surface the shared animation was built
          // for either. The colours are the accent and only the accent: the
          // palette primary and `tokens.info` this used to mix were the second
          // accent the design audit flagged.
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
                    color: tokens.accent.withValues(alpha: 0.15),
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
                    color: tokens.accent.withValues(alpha: 0.08),
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
                final movieCount =
                    allItems.where((i) => i.type == 'movie').length;
                final seriesCount = allItems
                    .where((i) => i.type == 'series' || i.type == 'anime')
                    .length;
                final displayedItems = _getFilteredAndSortedItems(allItems);
                final television =
                    FormFactorService.of(context) == FormFactor.television;

                return Column(
                  children: [
                    // ── Header Bar ──
                    _buildHeader(
                      context,
                      allItems.length,
                      movieCount,
                      seriesCount,
                    ),

                    // ── Filter Strip & Search Bar ──
                    _buildFilterToolbar(television: television),

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
                                // The column count is this page's own
                                // responsive rule and is unchanged; only the
                                // cell's height now follows the card.
                                crossAxisCount: _getCrossAxisCount(context),
                                childAspectRatio:
                                    _gridChildAspectRatio(context),
                                crossAxisSpacing: ZplaySpacing.s12,
                                mainAxisSpacing: ZplaySpacing.s16,
                              ),
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final item = displayedItems[index];
                                // The shared card, so a saved title looks like
                                // the same title on a Home rail: one artwork
                                // pipeline, one focus ring, one focus
                                // expansion, one type badge. `GestureDetector`
                                // outside it carries the one thing the shared
                                // card has no slot for - the pointer
                                // long-press that asks to remove.
                                return GestureDetector(
                                  onLongPress: () => _confirmRemove(item),
                                  child: MovieCard(
                                    movie: _movieFor(item),
                                    onTap: () => _navigateToDetail(item),
                                  ),
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

  /// One muted line under the page title: the total, then the split the filter
  /// strip acts on.
  ///
  /// The per-type numbers used to sit in a little box on each filter pill. The
  /// pills are the shared [TabStrip] now, which has no count slot - and a count
  /// is not what a pill is for. One muted line carries all three, which is also
  /// the quieter reading: the numbers are context, not three more shapes on the
  /// row that holds the controls.
  String _savedSummary(int total, int movies, int series) {
    final titles = total == 1 ? '1 saved title' : '$total saved titles';
    if (total == 0) return titles;
    return '$titles · $movies ${movies == 1 ? 'movie' : 'movies'}'
        ' · $series ${series == 1 ? 'series' : 'series'}';
  }

  Widget _buildHeader(
    BuildContext context,
    int totalCount,
    int movieCount,
    int seriesCount,
  ) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final tokens = context.tokens;

    // No fill and no hairline. The header sits on the page canvas the ambience
    // below paints, and the shell's nav bar blends over the top of the page -
    // so an opaque strip pinned here is the "different app" seam in the one
    // place the bar just stopped drawing one. The title carries the structure:
    // large type, a muted line under it, spacing.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? ZplaySpacing.s12 : ZplaySpacing.s20,
        vertical: ZplaySpacing.s12,
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
                  _savedSummary(totalCount, movieCount, seriesCount),
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
          //
          // A status *line*, not a badge: it was a filled pill in a rounded
          // border, which made a passive piece of state - "your list is backed
          // up" - look like one more control beside the ones that are. The glyph
          // and the muted caption say it with type and [ZplaySpacing]; the
          // accent appears only while a sync is actually running.
          ValueListenableBuilder<bool>(
            valueListenable: MyListService.isSyncing,
            builder: (context, isSyncing, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSyncing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          tokens.accent,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.cloud_done_rounded,
                      color: tokens.textMuted,
                      size: 15,
                    ),
                  const SizedBox(width: ZplaySpacing.s4),
                  Text(
                    isSyncing ? 'Syncing...' : 'Cloud Synced',
                    style: ZplayType.caption.toStyle(
                      color: tokens.textSecondary,
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
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar({required bool television}) {
    final tokens = context.tokens;
    // On a television the filter strip and the search field share one row.
    //
    // Stacked, they cost 111 + 53 = 164 dp - 30% of a 540 dp screen - and on an
    // empty list that is 164 dp of controls above a centred icon and two lines of
    // text. There is also nothing to filter or to search, so the whole block is
    // chrome describing an absence.
    //
    // The same merge Browse got, for the same reason: one row, same controls,
    // same focus order. The search field goes last in that row rather than
    // disappearing, so a list of 200 titles is still searchable from a sofa.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s8,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // The shared single-choice strip, the same control Browse
              // switches its verticals with. It replaced three hand-rolled
              // accent pills, each carrying a fill, a border *and* a blurred
              // accent shadow - three edges and a second focus language for a
              // control whose only job is to say which filter is on. The strip
              // paints nothing at rest, marks the selection with an accent bar
              // under the label, and draws `CardFocusRing` and nothing else for
              // focus.
              Expanded(
                child: TabStrip<String>(
                  options: const [
                    TabStripOption(value: 'all', label: 'All'),
                    TabStripOption(value: 'movie', label: 'Movies'),
                    TabStripOption(value: 'series', label: 'TV Shows'),
                  ],
                  selected: _filterType,
                  onSelected: (type) => setState(() => _filterType = type),
                  semanticsLabel: 'Filter saved titles',
                  height: television ? ZplaySpacing.s48 : 44,
                ),
              ),

              // The search field, inline on a television.
              //
              // Not dropped: a saved list of 200 titles is still worth
              // searching from a sofa, and a control that is merely *hidden* on
              // TV is a control the remote can never reach. It is the same
              // field, in the same row, after the sort control.
              if (television) ...[
                const SizedBox(width: ZplaySpacing.s16),
                SizedBox(
                  width: 220,
                  child: _buildSearchField(tokens),
                ),
              ],

              const SizedBox(width: ZplaySpacing.s16),

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
                    icon: Icon(Icons.sort_rounded, color: tokens.accent, size: 16),
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

  Widget _buildEmptyState(bool isListEmpty) {
    final tokens = context.tokens;
    // No circle, no ring, no filled button box: a bare glyph, the title, the
    // muted line and - when a filter is what emptied the grid - the shared CTA
    // pill. It was a decorated circle with an accent border and an
    // `ElevatedButton`, which spent three shapes and a second button language
    // on a screen whose whole message is "there is nothing here yet".
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isListEmpty
                ? Icons.bookmark_border_rounded
                : Icons.search_off_rounded,
            size: 54,
            color: tokens.textDisabled,
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
            PillButton(
              label: 'Reset Filters',
              icon: Icons.filter_alt_off_rounded,
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _filterType = 'all';
                  _searchQuery = '';
                });
              },
            ),
          ],
        ],
      ),
    );
  }
}
