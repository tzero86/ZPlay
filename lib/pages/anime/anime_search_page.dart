import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/anime/anime_slider_section.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/horizontal_edge_fade.dart';
import '../../widgets/common/rail_skeleton.dart';
import '../../widgets/movie/movie_card.dart';
import 'anime_details_page.dart';

import '../../services/anime_arabic/anime_arabic_service.dart';
import '../anime_arabic/anime_arabic_details_page.dart';

class AnimeSearchPage extends StatefulWidget {
  final bool initialArabicMode;

  const AnimeSearchPage({
    super.key,
    this.initialArabicMode = false,
  });

  @override
  State<AnimeSearchPage> createState() => _AnimeSearchPageState();
}

class _AnimeSearchPageState extends State<AnimeSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Drives the header tint. The band lives in the `appBar` slot and cannot
  /// listen to the body from there, so the body's own controller maps its
  /// offset onto this.
  final ScrollController _scrollController = ScrollController();

  /// The filter chip row's own horizontal scroll, tracked by
  /// [HorizontalEdgeFade] so overflow reads the same way it does everywhere.
  final ScrollController _filterScrollController = ScrollController();

  /// How far the page scrolls before the header reaches its full tint. The
  /// band is transparent at rest, so the shell nav above it sits on the canvas
  /// rather than on a band the page painted.
  static const double _bandBlendThreshold = 32.0;
  final ValueNotifier<double> _bandTint = ValueNotifier<double>(0);

  bool _isArabicMode = false;
  Timer? _debounce;
  bool _isLoading = false;
  bool _allowAdult = false;
  List<AnimeMedia> _allResults = [];
  final Map<int, ArabicAnimeCard> _arabicCardsMap = {};

  // Filter selections
  String? _genre;
  int? _year;
  String? _season;
  String? _format;
  String? _status;
  String _sort = 'TRENDING_DESC';

  // Discovery sliders when search is empty and no filters
  List<AnimeMedia> _trendingList = [];
  List<AnimeMedia> _popularSeasonList = [];
  List<AnimeMedia> _topRatedList = [];
  bool _loadingInitial = true;

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Hentai', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life',
    'Sports', 'Supernatural', 'Thriller',
  ];

  static const _seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
  static const _formats = ['TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'MUSIC'];
  static const _statuses = ['RELEASING', 'FINISHED', 'NOT_YET_RELEASED', 'CANCELLED', 'HIATUS'];
  static const _sorts = <String, String>{
    'TRENDING_DESC': 'Trending',
    'POPULARITY_DESC': 'Most Popular',
    'SCORE_DESC': 'Top Rated',
    'FAVOURITES_DESC': 'Most Favorited',
    'START_DATE_DESC': 'Newest',
    'START_DATE': 'Oldest',
    'TITLE_ROMAJI': 'Title (A-Z)',
  };

  @override
  void initState() {
    super.initState();
    _isArabicMode = widget.initialArabicMode;
    _scrollController.addListener(_syncBand);
    _loadInitialSliders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_syncBand);
    _scrollController.dispose();
    _filterScrollController.dispose();
    _bandTint.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Maps the body's offset onto the header tint — no animation of its own, so
  /// the band is exactly as dark as the content that has gone under it.
  void _syncBand() {
    if (!_scrollController.hasClients) return;
    final t = (_scrollController.offset / _bandBlendThreshold).clamp(0.0, 1.0);
    if ((_bandTint.value - t).abs() > 0.01) _bandTint.value = t;
  }

  bool get _hasActiveFilters =>
      _genre != null ||
      _year != null ||
      _season != null ||
      _format != null ||
      _status != null ||
      _sort != 'TRENDING_DESC';

  void _loadInitialSliders() async {
    setState(() => _loadingInitial = true);
    try {
      if (_isArabicMode) {
        final feed = await AnimeArabicService.instance.getHome();
        if (mounted) {
          setState(() {
            _trendingList = (feed.trending.isNotEmpty ? feed.trending : feed.spotlight)
                .map((c) {
                  _arabicCardsMap[c.slug.hashCode.abs()] = c;
                  return c.toAnimeMedia();
                }).toList();
            _popularSeasonList = feed.recentEpisodes
                .map((c) {
                  _arabicCardsMap[c.slug.hashCode.abs()] = c;
                  return c.toAnimeMedia();
                }).toList();
            _topRatedList = (feed.topSeasonal.isNotEmpty ? feed.topSeasonal : feed.legendary)
                .map((c) {
                  _arabicCardsMap[c.slug.hashCode.abs()] = c;
                  return c.toAnimeMedia();
                }).toList();
            _loadingInitial = false;
          });
        }
        return;
      }

      final results = await Future.wait([
        AnilistService.instance.fetchTrendingAnime(page: 1, perPage: 20),
        AnilistService.instance.fetchPopularThisSeason(page: 1, perPage: 20),
        AnilistService.instance.fetchTopRated(page: 1, perPage: 20),
      ]);

      if (mounted) {
        setState(() {
          _trendingList = results[0];
          _popularSeasonList = results[1];
          _topRatedList = results[2];
          _loadingInitial = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty && !_hasActiveFilters) {
      setState(() {
        _allResults.clear();
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _performSearch(trimmed);
    });
  }

  void _performSearch([String? query]) async {
    final q = (query ?? _searchController.text).trim();
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isArabicMode) {
        final cards = await AnimeArabicService.instance.search(q);
        if (!mounted) return;
        final list = <AnimeMedia>[];
        for (final c in cards) {
          _arabicCardsMap[c.slug.hashCode.abs()] = c;
          list.add(c.toAnimeMedia());
        }
        setState(() {
          _allResults = list;
          _isLoading = false;
        });
        return;
      }

      final results = await AnilistService.instance.searchAnime(
        q,
        genre: _genre,
        year: _year,
        season: _season,
        format: _format,
        status: _status,
        sort: _sort,
        isAdult: _allowAdult,
        perPage: 35,
      );
      if (!mounted) return;

      setState(() {
        _allResults = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _allResults = [];
      });
    }
  }

  void _toggleAdult(bool val) {
    setState(() {
      _allowAdult = val;
    });
    _performSearch();
  }

  void _resetFilters() {
    setState(() {
      _genre = null;
      _year = null;
      _season = null;
      _format = null;
      _status = null;
      _sort = 'TRENDING_DESC';
    });
    if (_searchController.text.trim().isNotEmpty) {
      _performSearch();
    } else {
      setState(() {
        _allResults.clear();
      });
    }
  }

  Future<void> _pickFromList<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    required T? current,
    required void Function(T?) onSelected,
  }) async {
    final tokens = context.tokens;
    final picked = await showModalBottomSheet<_PickResult<T>>(
      context: context,
      backgroundColor: tokens.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.sheetTop),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          minChildSize: 0.35,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              // Top drag indicator
              Container(
                margin: const EdgeInsets.only(
                  top: ZplaySpacing.s12,
                  bottom: ZplaySpacing.s8,
                ),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.textPrimary.withValues(alpha: 0.25),
                  borderRadius: ZplayRadius.xsAll,
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 16, 12),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: ZplayType.title.toStyle(color: tokens.textPrimary),
                    ),
                    const Spacer(),
                    if (current != null)
                      _chip(
                        onTap: () =>
                            Navigator.of(ctx).pop(_PickResult<T>(null, true)),
                        child: Text(
                          'Clear',
                          style: ZplayType.label.toStyle(color: tokens.accent),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(color: tokens.borderSubtle, height: 1),

              // Options list. Each row is a [FocusableCard] so a remote can
              // reach it, with the app's single ring marking where it is; the
              // old `Material` + `InkWell` row was pointer-only.
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final v = items[i];
                    final selected = v == current;
                    return FocusableCard(
                      onTap: () =>
                          Navigator.of(ctx).pop(_PickResult<T>(v, false)),
                      builder: (context, state) => CardFocusRing(
                        focused: state.focused,
                        radius: ZplayRadius.smAll,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                            vertical: ZplaySpacing.s2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s16,
                            vertical: ZplaySpacing.s12,
                          ),
                          decoration: BoxDecoration(
                            // Selection is data state, so it keeps its accent
                            // wash; nothing draws a border box around it.
                            color: selected ? tokens.accentSubtle : null,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label(v),
                                  style: ZplayType.subtitle
                                      .copyWith(
                                        weight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      )
                                      .toStyle(
                                        color: selected
                                            ? tokens.accent
                                            : tokens.textPrimary,
                                      ),
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check_rounded,
                                  color: tokens.accent,
                                  size: 20,
                                ),
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
      },
    );

    if (picked != null) {
      if (picked.cleared) {
        setState(() {
          onSelected(null);
        });
        _performSearch();
      } else if (picked.value != null) {
        setState(() {
          onSelected(picked.value);
        });
        _performSearch();
      }
    }
  }

  void _pickYear() {
    final now = DateTime.now().year;
    final years = List.generate(40, (i) => now + 1 - i);
    _pickFromList<int>(
      title: 'Release Year',
      items: years,
      label: (y) => '$y',
      current: _year,
      onSelected: (v) => _year = v,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

  /// The quiet body every header chip wears: one surface fill, no border and no
  /// state colour of its own. Data state is carried by the glyph and label the
  /// caller puts inside it, focus by [CardFocusRing] alone — so nothing about a
  /// chip changes size or paints a second indicator when focus arrives.
  Widget _chipSurface(Widget child) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s12,
        vertical: ZplaySpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.smAll,
      ),
      child: child,
    );
  }

  /// One reachable chip in the header.
  ///
  /// The filter row was `Material` + `InkWell`, which is pointer-only — no key,
  /// remote or D-pad event could reach it, and it painted Material's own focus
  /// overlay. The language and adult pills were already [FocusableCard]s; the
  /// filter buttons now are too, so the whole row is one focus language.
  Widget _chip({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: _chipSurface(child),
      ),
    );
  }

  Widget _buildFilterDropdownButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: ZplaySpacing.s8),
      child: _chip(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ZplayType.label
                  .copyWith(
                    weight: active ? FontWeight.w700 : FontWeight.w600,
                  )
                  .toStyle(
                    color: active ? tokens.accent : tokens.textEmphasis,
                  ),
            ),
            const SizedBox(width: ZplaySpacing.s4),
            Icon(
              Icons.expand_more_rounded,
              size: 15,
              color: active ? tokens.accent : tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(AnimeMedia anime) {
    if (_isArabicMode || anime.isArabic || _arabicCardsMap.containsKey(anime.id)) {
      final card = _arabicCardsMap[anime.id] ??
          ArabicAnimeCard(
            slug: (anime.slug != null && anime.slug!.isNotEmpty)
                ? anime.slug!
                : anime.titleEnglish.toLowerCase().replaceAll(' ', '-'),
            title: anime.displayTitle,
            cover: anime.coverUrl,
          );
      Navigator.push(
        context,
        CinematicSlideRoute(
          page: AnimeArabicDetailsPage(anime: card),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      CinematicSlideRoute(
        page: AnimeDetailsPage(anime: anime),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isSearching = _searchController.text.trim().isNotEmpty || _hasActiveFilters;

    // Split search results into format sliders
    final tvSeries = _allResults
        .where((a) => a.format.toUpperCase() == 'TV' || a.format.toUpperCase() == 'TV_SHORT')
        .toList();
    final movies = _allResults
        .where((a) => a.format.toUpperCase() == 'MOVIE')
        .toList();
    final ovasAndOthers = _allResults
        .where((a) =>
            a.format.toUpperCase() != 'TV' &&
            a.format.toUpperCase() != 'TV_SHORT' &&
            a.format.toUpperCase() != 'MOVIE')
        .toList();

    final tokens = context.tokens;
    // The rail placeholders draw at the geometry the real cards arrive at, so
    // nothing moves when the results land. Built here rather than per branch
    // because both loading paths share it.
    final skeletonSizing = MovieCardSizing.fromWidth(
      MediaQuery.sizeOf(context).width,
    );
    if (_bandTint.value > 0) {
      // Swapping between the results and discovery lists replaces the body's
      // scrollable, and a fresh list attaches with no scroll event at all; the
      // band is re-mapped once that frame is laid out so a tinted header is
      // never left over a list that is back at its top.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncBand();
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 62),
        // Transparent at rest, `tokens.bg` once ~32 dp of the page has gone
        // under it — and no hairline in either state. An opaque band across a
        // page's top is the seam this work removes; the field and chips carry
        // their own `tokens.surface`, so the canvas stays visible around them.
        //
        // The rows are the `child`, built once, so no scroll pixel rebuilds the
        // field or the chips.
        child: ValueListenableBuilder<double>(
          valueListenable: _bandTint,
          builder: (context, tint, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.bg.withValues(alpha: 0.82 * tint),
            ),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.only(top: topPadding + 4, bottom: 8),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Back Button + Search Bar + 18+ Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                          color: tokens.textPrimary,
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                // An input keeps a fill and its hairline; what
                                // is gone is the opaque band that used to wrap
                                // the whole bar.
                                color: tokens.surface,
                                borderRadius: ZplayRadius.smAll,
                                border: Border.fromBorderSide(tokens.hairline),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                autofocus: true,
                                style: ZplayType.subtitle.toStyle(
                                  color: tokens.textPrimary,
                                ),
                                textInputAction: TextInputAction.search,
                                onChanged: _onSearchChanged,
                                onSubmitted: _performSearch,
                                decoration: InputDecoration(
                                  hintText: 'Search anime, movies, OVAs...',
                                  hintStyle: ZplayType.body.toStyle(
                                    color: tokens.textMuted,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: ZplaySpacing.s16,
                                    vertical: ZplaySpacing.s12,
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                          color: tokens.textEmphasis,
                                          onPressed: () {
                                            _searchController.clear();
                                            _onSearchChanged('');
                                          },
                                        )
                                      : Icon(
                                          Icons.search_rounded,
                                          size: 20,
                                          color: tokens.textSecondary,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Language Switcher Pill (General vs Arabic Anime)
                        Padding(
                          padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                          child: _chip(
                            onTap: () {
                              setState(() {
                                _isArabicMode = !_isArabicMode;
                                _allResults.clear();
                              });
                              if (_searchController.text.trim().isNotEmpty) {
                                _performSearch(_searchController.text.trim());
                              } else {
                                _loadInitialSliders();
                              }
                            },
                            // State is label brightness and weight, not a fill
                            // or a coloured border: the accent marks the mode
                            // the page is in, the fill stays constant.
                            child: Text(
                              _isArabicMode ? '🇸🇦 Arabic' : '🇯🇵 Anime',
                              style: ZplayType.label
                                  .copyWith(
                                    weight: _isArabicMode
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  )
                                  .toStyle(
                                    color: _isArabicMode
                                        ? tokens.accent
                                        : tokens.textEmphasis,
                                  ),
                            ),
                          ),
                        ),

                        // 18+ Adult Toggle Pill (only in general mode)
                        if (!_isArabicMode)
                          Padding(
                            padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                            child: _chip(
                              onTap: () => _toggleAdult(!_allowAdult),
                              // The checkbox glyph already carries the state;
                              // the accent and weight agree with it, and the
                              // fill and box never change.
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _allowAdult
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: _allowAdult
                                        ? tokens.accent
                                        : tokens.textSecondary,
                                  ),
                                  const SizedBox(width: ZplaySpacing.s4),
                                  Text(
                                    '18+',
                                    style: ZplayType.label
                                        .copyWith(
                                          weight: _allowAdult
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        )
                                        .toStyle(
                                          color: _allowAdult
                                              ? tokens.accent
                                              : tokens.textEmphasis,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Custom Dropdown Menu Buttons
                  SizedBox(
                    height: 38,
                    // The row overflows on a narrow or TV-sized canvas, so it
                    // signals that the same way every other horizontal row in
                    // the app does.
                    child: HorizontalEdgeFade(
                      scrollController: _filterScrollController,
                      child: ListView(
                        controller: _filterScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s16,
                        ),
                        children: [
                        // Sort Dropdown
                        _buildFilterDropdownButton(
                          label: 'Sort: ${_sorts[_sort] ?? "Trending"}',
                          active: _sort != 'TRENDING_DESC',
                          onTap: () => _pickFromList<String>(
                            title: 'Sort By',
                            items: _sorts.keys.toList(),
                            label: (k) => _sorts[k]!,
                            current: _sort,
                            onSelected: (v) => _sort = v ?? 'TRENDING_DESC',
                          ),
                        ),

                        // Genre Dropdown
                        _buildFilterDropdownButton(
                          label: _genre ?? 'Genre',
                          active: _genre != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Genre',
                            items: _genres,
                            label: (g) => g,
                            current: _genre,
                            onSelected: (v) => _genre = v,
                          ),
                        ),

                        // Year Dropdown
                        _buildFilterDropdownButton(
                          label: _year != null ? '$_year' : 'Year',
                          active: _year != null,
                          onTap: _pickYear,
                        ),

                        // Season Dropdown
                        _buildFilterDropdownButton(
                          label: _season != null ? _capitalize(_season!) : 'Season',
                          active: _season != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Season',
                            items: _seasons,
                            label: (s) => _capitalize(s),
                            current: _season,
                            onSelected: (v) => _season = v,
                          ),
                        ),

                        // Format Dropdown
                        _buildFilterDropdownButton(
                          label: _format ?? 'Format',
                          active: _format != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Format',
                            items: _formats,
                            label: (f) => f,
                            current: _format,
                            onSelected: (v) => _format = v,
                          ),
                        ),

                        // Status Dropdown
                        _buildFilterDropdownButton(
                          label: _status != null ? _capitalize(_status!.replaceAll('_', ' ')) : 'Status',
                          active: _status != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Status',
                            items: _statuses,
                            label: (s) => _capitalize(s.replaceAll('_', ' ')),
                            current: _status,
                            onSelected: (v) => _status = v,
                          ),
                        ),

                        // Reset Button
                        if (_hasActiveFilters)
                          Padding(
                            padding: const EdgeInsets.only(right: ZplaySpacing.s8),
                            child: _chip(
                              onTap: _resetFilters,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: tokens.textEmphasis,
                                  ),
                                  const SizedBox(width: ZplaySpacing.s4),
                                  Text(
                                    'Reset',
                                    style: ZplayType.label.toStyle(
                                      color: tokens.textEmphasis,
                                    ),
                                  ),
                                ],
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
        ),
      ),
      body: AnimatedAmbientBackground(
        child: Stack(
          children: [
            // Content Area
            if (_isLoading || (_loadingInitial && _allResults.isEmpty && _trendingList.isEmpty))
              // The page's real shape while the rails are in flight: the shared
              // rail placeholders, at the same offset the results themselves
              // start at, rather than a bare spinner that says nothing about
              // what is coming. Every rail in the app loads like this.
              ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: topPadding + kToolbarHeight + 80,
                  bottom: 40,
                ),
                children: [
                  RailSkeleton(sizing: skeletonSizing, showHeader: true),
                  const SizedBox(height: ZplaySpacing.s24),
                  RailSkeleton(
                    sizing: skeletonSizing,
                    showHeader: true,
                    count: 5,
                  ),
                ],
              )
            else if (isSearching && _allResults.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 64,
                      color: tokens.textDisabled,
                    ),
                    const SizedBox(height: ZplaySpacing.s16),
                    Text(
                      'No anime found matching your criteria',
                      style: ZplayType.subtitle.toStyle(
                        color: tokens.textEmphasis,
                      ),
                    ),
                    const SizedBox(height: ZplaySpacing.s8),
                    Text(
                      'Try different keywords or clearing filters',
                      style: ZplayType.body.toStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              )
            else if (_allResults.isNotEmpty)
              ListView(
                clipBehavior: Clip.none,
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: topPadding + kToolbarHeight + 80,
                  bottom: 40,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  if (tvSeries.isNotEmpty)
                    AnimeSliderSection(
                      title: 'Anime TV Series',
                      subtitle: '${tvSeries.length} Results',
                      animeList: tvSeries,
                      onAnimeTap: _openDetails,
                    ),
                  if (movies.isNotEmpty)
                    AnimeSliderSection(
                      title: 'Anime Movies',
                      subtitle: '${movies.length} Results',
                      animeList: movies,
                      onAnimeTap: _openDetails,
                    ),
                  if (ovasAndOthers.isNotEmpty)
                    AnimeSliderSection(
                      title: 'OVAs, ONAs & Specials',
                      subtitle: '${ovasAndOthers.length} Results',
                      animeList: ovasAndOthers,
                      onAnimeTap: _openDetails,
                    ),
                ],
              )
            else
              // Discovery Sliders when not searching
              ListView(
                clipBehavior: Clip.none,
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: topPadding + kToolbarHeight + 80,
                  bottom: 40,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  if (_trendingList.isNotEmpty)
                    AnimeSliderSection(
                      title: 'Trending Anime',
                      animeList: _trendingList,
                      onAnimeTap: _openDetails,
                    ),
                  if (_popularSeasonList.isNotEmpty)
                    AnimeSliderSection(
                      title: 'Popular This Season',
                      animeList: _popularSeasonList,
                      onAnimeTap: _openDetails,
                    ),
                  if (_topRatedList.isNotEmpty)
                    AnimeSliderSection(
                      title: 'All-Time Top Rated',
                      animeList: _topRatedList,
                      onAnimeTap: _openDetails,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PickResult<T> {
  final T? value;
  final bool cleared;
  _PickResult(this.value, this.cleared);
}
