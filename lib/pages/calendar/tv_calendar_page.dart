import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../services/calendar/tv_calendar_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../details/details_page.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';

class TvCalendarPage extends StatefulWidget {
  const TvCalendarPage({super.key});

  @override
  State<TvCalendarPage> createState() => _TvCalendarPageState();
}

class _TvCalendarPageState extends State<TvCalendarPage> {
  final TvCalendarService _service = TvCalendarService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _dayScrollController = ScrollController();
  final ScrollController _networkScrollController = ScrollController();

  List<DateTime> _availableDays = [];
  late DateTime _selectedDay;
  List<TvCalendarEntryModel> _allDayEpisodes = [];

  bool _isLoadingDays = true;
  bool _isLoadingEpisodes = false;
  String _searchQuery = '';
  String _selectedNetwork = 'All';

  static const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _availableDays = _service.getAiringDays(daysAhead: 21);
    _isLoadingDays = false;
    _loadEpisodesForSelectedDay();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dayScrollController.dispose();
    _networkScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodesForSelectedDay({bool forceRefresh = false}) async {
    setState(() => _isLoadingEpisodes = true);

    try {
      final episodes = await _service.getEpisodesForDay(
        _selectedDay,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _allDayEpisodes = episodes;
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEpisodes = false);
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _onDaySelected(DateTime day) {
    if (_isSameDay(day, _selectedDay)) return;
    setState(() => _selectedDay = day);
    _loadEpisodesForSelectedDay();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
  }

  void _onNetworkSelected(String network) {
    setState(() => _selectedNetwork = network);
  }

  void _scrollTimeline(int direction) {
    if (!_dayScrollController.hasClients) return;
    final target = _dayScrollController.offset + (direction * 220.0);
    _dayScrollController.animateTo(
      target.clamp(0.0, _dayScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollNetworks(int direction) {
    if (!_networkScrollController.hasClients) return;
    final target = _networkScrollController.offset + (direction * 180.0);
    _networkScrollController.animateTo(
      target.clamp(0.0, _networkScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  List<TvCalendarEntryModel> get _filteredEpisodes {
    return _allDayEpisodes.where((ep) {
      // Network filter
      if (_selectedNetwork != 'All') {
        final net = (ep.network ?? '').trim().toLowerCase();
        final sel = _selectedNetwork.trim().toLowerCase();
        if (sel == 'other') {
          // Check if it doesn't match standard known platforms
          if (net.isEmpty) return true;
        } else if (!net.contains(sel)) {
          return false;
        }
      }

      // Search query filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchShow = ep.showTitle.toLowerCase().contains(q);
        final matchEp = ep.episodeTitle.toLowerCase().contains(q);
        final matchNet = (ep.network ?? '').toLowerCase().contains(q);
        if (!matchShow && !matchEp && !matchNet) return false;
      }

      return true;
    }).toList();
  }

  Map<String, int> get _networkCounts {
    final map = <String, int>{'All': _allDayEpisodes.length};

    for (final ep in _allDayEpisodes) {
      final net = ep.network?.trim();
      if (net != null && net.isNotEmpty) {
        map[net] = (map[net] ?? 0) + 1;
      }
    }
    return map;
  }

  List<String> get _computedNetworks {
    final counts = _networkCounts;
    final otherNets = counts.keys.where((k) => k != 'All').toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    return ['All', ...otherNets];
  }

  void _openShowDetails(TvCalendarEntryModel entry) {
    final imdbId = entry.imdbId ?? '';
    final movie = Movie(
      id: imdbId.isNotEmpty ? imdbId : entry.showTitle,
      name: entry.showTitle,
      type: 'series',
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
      poster: entry.posterUrl,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsPage(movie: movie)),
    );
  }

  String _formatWeekdayShort(DateTime dt) => _weekdaysShort[dt.weekday - 1];
  String _formatMonthShort(DateTime dt) => _monthsShort[dt.month - 1];
  String _formatFullDate(DateTime dt) {
    final weekday = _weekdaysFull[dt.weekday - 1];
    final month = _monthsFull[dt.month - 1];
    return '$weekday, $month ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: AnimatedAmbientBackground(
        child: RefreshIndicator(
          color: tokens.accent,
          backgroundColor: tokens.surfaceRaised,
          onRefresh: () => _loadEpisodesForSelectedDay(forceRefresh: true),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ── Quiet Page Header (scrolls away with the content) ──
              SliverToBoxAdapter(child: _buildTopBar(palette, isMobile)),

              // ── Day Timeline Selector with Left/Right Arrows ──
              if (!_isLoadingDays && _availableDays.isNotEmpty)
                SliverToBoxAdapter(child: _buildDayTimeline(palette, isMobile)),

              // ── Network Filter Bar (Netflix, HBO, Apple TV+, etc.) ──
              if (!_isLoadingEpisodes && _allDayEpisodes.isNotEmpty)
                SliverToBoxAdapter(child: _buildNetworkFilterBar(palette, isMobile)),

              // ── Main Episodes Feed ──
              ..._buildEpisodesContent(palette, screenWidth, isMobile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppThemePalette palette, bool isMobile) {
    final tokens = context.tokens;
    final canPop = Navigator.of(context).canPop();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        MediaQuery.paddingOf(context).top + 12,
        isMobile ? 16 : 24,
        6,
      ),
      child: Row(
        children: [
          // Back affordance — this page is a pushed route.
          if (canPop)
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary, size: 22),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
              splashRadius: 20,
            ),
          if (canPop) const SizedBox(width: 8),

          // Title & (non-mobile) subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TV Shows Airing Calendar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                ),
                if (!isMobile)
                  Text(
                    'Upcoming broadcast & streaming episodes with live network filters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Filter / Search Input
          Container(
            width: isMobile ? 110 : 180,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
              borderRadius: ZplayRadius.smAll,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: ZplayType.label.copyWith(size: 13).toStyle(color: tokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Filter shows...',
                hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: tokens.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayTimeline(AppThemePalette palette, bool isMobile) {
    final tokens = context.tokens;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      height: 78,
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 20,
        vertical: 4,
      ),
      child: Row(
        children: [
          // Left Scroll Arrow
          _buildTimelineArrow(
            icon: Icons.chevron_left_rounded,
            palette: palette,
            onTap: () => _scrollTimeline(-1),
          ),
          const SizedBox(width: 6),

          // Timeline Days List
          Expanded(
            child: ListView.separated(
              controller: _dayScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _availableDays.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final day = _availableDays[index];
                final isSelected = _isSameDay(day, _selectedDay);
                final isToday = _isSameDay(day, today);

                final weekdayStr = isToday
                    ? 'TODAY'
                    : (_isSameDay(day, today.add(const Duration(days: 1)))
                        ? 'TOMORROW'
                        : _formatWeekdayShort(day).toUpperCase());
                final dayNumStr = day.day.toString();
                final monthStr = _formatMonthShort(day);

                return FocusableCard(
                  onTap: () => _onDaySelected(day),
                  builder: (context, state) => CardFocusRing(
                    focused: state.focused,
                    radius: BorderRadius.circular(ZplayRadius.md),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: isToday ? 90 : 76,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? tokens.accentSubtle : tokens.surface,
                        borderRadius: BorderRadius.circular(ZplayRadius.md),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            weekdayStr,
                            style: ZplayType.caption
                                .copyWith(
                                  size: 10.5,
                                  weight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                )
                                .toStyle(
                                  color: isSelected
                                      ? tokens.accent
                                      : (isToday ? tokens.textPrimary : tokens.textSecondary),
                                ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayNumStr,
                                style: ZplayType.title
                                    .copyWith(
                                      size: 17,
                                      weight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                    )
                                    .toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                monthStr,
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 6),
          // Right Scroll Arrow
          _buildTimelineArrow(
            icon: Icons.chevron_right_rounded,
            palette: palette,
            onTap: () => _scrollTimeline(1),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkFilterBar(AppThemePalette palette, bool isMobile) {
    final tokens = context.tokens;
    final networks = _computedNetworks;
    final counts = _networkCounts;

    return Container(
      height: 38,
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 20,
        vertical: 4,
      ),
      child: Row(
        children: [
          // Filter label icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
              borderRadius: BorderRadius.circular(ZplayRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: palette.primaryColor.withValues(alpha: 0.8),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 4),
                  Text(
                    'Network:',
                    style: ZplayType.caption
                        .copyWith(size: 11.5, weight: FontWeight.w700)
                        .toStyle(color: tokens.textEmphasis),
                  ),
                ],
              ],
            ),
          ),

          // Left Network Arrow
          _buildMiniArrow(
            icon: Icons.chevron_left_rounded,
            onTap: () => _scrollNetworks(-1),
          ),
          const SizedBox(width: 4),

          // Networks Scrollable Chips
          Expanded(
            child: ListView.separated(
              controller: _networkScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: networks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final net = networks[index];
                final isSelected = (_selectedNetwork == net);
                final count = counts[net] ?? 0;

                return FocusableCard(
                  onTap: () => _onNetworkSelected(net),
                  builder: (context, state) => CardFocusRing(
                    focused: state.focused,
                    radius: BorderRadius.circular(ZplayRadius.sm),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? tokens.accentSubtle : tokens.surface,
                        borderRadius: BorderRadius.circular(ZplayRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (net == 'All')
                            Icon(
                              Icons.all_inclusive_rounded,
                              size: 13,
                              color: isSelected ? tokens.accent : tokens.textEmphasis,
                            )
                          else
                            Icon(
                              _getNetworkIcon(net),
                              size: 13,
                              color: isSelected ? tokens.accent : tokens.textEmphasis,
                            ),
                          const SizedBox(width: 5),
                          Text(
                            net,
                            style: ZplayType.caption
                                .copyWith(size: 12, weight: isSelected ? FontWeight.w800 : FontWeight.w600)
                                .toStyle(
                                  color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                                ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tokens.accent.withValues(alpha: 0.35)
                                  : tokens.borderDefault,
                              borderRadius: BorderRadius.circular(ZplayRadius.xs),
                            ),
                            child: Text(
                              '$count',
                              style: ZplayType.overline
                                  .copyWith(weight: FontWeight.w700)
                                  .toStyle(
                                    color: isSelected ? tokens.textPrimary : tokens.textSecondary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 4),
          // Right Network Arrow
          _buildMiniArrow(
            icon: Icons.chevron_right_rounded,
            onTap: () => _scrollNetworks(1),
          ),
        ],
      ),
    );
  }

  IconData _getNetworkIcon(String network) {
    final n = network.toLowerCase();
    if (n.contains('netflix') || n.contains('hbo') || n.contains('apple') || n.contains('disney') || n.contains('amazon') || n.contains('prime') || n.contains('hulu') || n.contains('paramount') || n.contains('peacock')) {
      return Icons.play_circle_fill_rounded;
    }
    if (n.contains('crunchyroll') || n.contains('anime') || n.contains('tokyo')) {
      return Icons.animation_rounded;
    }
    return Icons.tv_rounded;
  }

  Widget _buildTimelineArrow({
    required IconData icon,
    required AppThemePalette palette,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: BorderRadius.circular(ZplayRadius.md),
        child: Container(
          width: 32,
          height: 74,
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
            borderRadius: BorderRadius.circular(ZplayRadius.md),
          ),
          child: Center(
            child: Icon(
              icon,
              color: tokens.textEmphasis,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniArrow({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: BorderRadius.circular(ZplayRadius.sm),
        child: Container(
          width: 24,
          height: 32,
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
            borderRadius: BorderRadius.circular(ZplayRadius.sm),
          ),
          child: Center(
            child: Icon(
              icon,
              color: tokens.textEmphasis,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEpisodesContent(AppThemePalette palette, double screenWidth, bool isMobile) {
    final tokens = context.tokens;

    if (_isLoadingEpisodes && _allDayEpisodes.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: tokens.accent),
          ),
        ),
      ];
    }

    final episodes = _filteredEpisodes;

    if (episodes.isEmpty) {
      final isNetworkFiltered = _selectedNetwork != 'All';
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNetworkFiltered ? Icons.filter_alt_off_rounded : Icons.tv_off_rounded,
                  size: 48,
                  color: tokens.textDisabled,
                ),
                const SizedBox(height: 12),
                Text(
                  isNetworkFiltered
                      ? 'No episodes on $_selectedNetwork for this day'
                      : 'No episodes found for this day',
                  style: ZplayType.title
                      .copyWith(size: 16, weight: FontWeight.w700)
                      .toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 6),
                Text(
                  isNetworkFiltered
                      ? 'Try selecting "All" or a different network above'
                      : 'Select another day from the timeline above',
                  style: ZplayType.label.toStyle(color: tokens.textMuted),
                ),
                if (isNetworkFiltered) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _onNetworkSelected('All'),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Show All Networks'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZplayRadius.sm)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ];
    }

    final dateTitle = _formatFullDate(_selectedDay);

    return [
        // Day Header Summary
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 28,
              10,
              isMobile ? 16 : 28,
              10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dateTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.title
                        .copyWith(size: isMobile ? 15 : 19, letterSpacing: -0.2)
                        .toStyle(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accentSubtle,
                    borderRadius: BorderRadius.circular(ZplayRadius.sm),
                    border: Border.all(
                      color: tokens.accent,
                    ),
                  ),
                  child: Text(
                    _selectedNetwork == 'All'
                        ? '${episodes.length} Episodes Airing'
                        : '${episodes.length} on $_selectedNetwork',
                    style: ZplayType.bodySmall
                        .copyWith(weight: FontWeight.w700)
                        .toStyle(color: tokens.accent),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Episodes Grid / List
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: 6,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isMobile ? 650 : 440,
              mainAxisExtent: 142,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = episodes[index];
                return _EpisodeCalendarCard(
                  entry: entry,
                  palette: palette,
                  onTap: () => _openShowDetails(entry),
                );
              },
              childCount: episodes.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 48),
        ),
    ];
  }
}

class _EpisodeCalendarCard extends StatelessWidget {
  final TvCalendarEntryModel entry;
  final AppThemePalette palette;
  final VoidCallback onTap;

  const _EpisodeCalendarCard({
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final posterUrl = entry.posterUrl ?? '';
    final airTimeStr = entry.airTimeFormatted ?? '';
    final epCode = entry.episodeCode;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) {
        final isHovered = state.highlighted;
        return CardFocusRing(
          focused: state.focused,
          radius: BorderRadius.circular(ZplayRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isHovered ? tokens.surfaceOverlay : tokens.surface,
              borderRadius: BorderRadius.circular(ZplayRadius.md),
            ),
            child: Row(
            children: [
              // Poster Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(ZplayRadius.md)),
                child: SizedBox(
                  width: 95,
                  height: double.infinity,
                  child: posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: posterUrl,
                          cacheManager: AppImageCache.manager,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                            child: Center(
                              child: Icon(Icons.tv_rounded, color: tokens.textDisabled, size: 28),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                            child: Center(
                              child: Icon(Icons.tv_rounded, color: tokens.textDisabled, size: 28),
                            ),
                          ))
                      : Container(
                          color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                          child: Center(
                            child: Icon(Icons.tv_rounded, color: tokens.textDisabled, size: 28),
                          ),
                        ),
                ),
              ),

              // Info Column
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Badge wrap (season/episode code + network badge + airtime)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: tokens.accentSubtle,
                              borderRadius: BorderRadius.circular(ZplayRadius.sm),
                            ),
                            child: Text(
                              epCode,
                              style: ZplayType.caption
                                  .copyWith(weight: FontWeight.w800)
                                  .toStyle(color: tokens.accent),
                            ),
                          ),
                          if (entry.network != null && entry.network!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              constraints: const BoxConstraints(maxWidth: 100),
                              decoration: BoxDecoration(
                                color: tokens.borderDefault,
                                borderRadius: BorderRadius.circular(ZplayRadius.xs),
                              ),
                              child: Text(
                                entry.network!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.caption
                                    .copyWith(size: 10.5, weight: FontWeight.w600)
                                    .toStyle(color: tokens.textEmphasis),
                              ),
                            ),
                          if (airTimeStr.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: tokens.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  airTimeStr,
                                  style: ZplayType.caption
                                      .copyWith(weight: FontWeight.w600)
                                      .toStyle(color: tokens.textEmphasis),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // Show Title
                      Text(
                        entry.showTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.subtitle
                            .copyWith(
                              size: 14.5,
                              weight: FontWeight.w800,
                              letterSpacing: -0.2,
                            )
                            .toStyle(color: tokens.textPrimary),
                      ),
                      const SizedBox(height: 2),

                      // Episode Title
                      Text(
                        entry.episodeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.bodySmall
                            .copyWith(size: 12.5, weight: FontWeight.w500)
                            .toStyle(color: tokens.textEmphasis),
                      ),
                      if (entry.overview != null && entry.overview!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          entry.overview!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.caption.toStyle(color: tokens.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Arrow Action
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: isHovered ? tokens.accent : tokens.textDisabled,
                  size: 22,
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
