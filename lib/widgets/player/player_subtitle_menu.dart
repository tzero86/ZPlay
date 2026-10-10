import 'package:flutter/material.dart';
import 'package:zplay/models/subtitle/subtitle_model.dart';
import 'package:zplay/services/subtitles/subtitle_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';
import '../common/focusable_card.dart';

/// Full-featured subtitle selection, search, and timing menu.
/// Responsive across mobile portrait, mobile landscape, tablet, and desktop screens.
class PlayerSubtitleMenu extends StatefulWidget {
  final List<SubtitleLanguageGroup> groups;
  final List<PlayerEmbeddedSubtitle> embeddedSubtitles;
  final int? selectedEmbeddedIndex;
  final SubtitleVariant? selectedVariant;
  final bool isSubtitleEnabled;
  final String movieTitle;
  final String? imdbId;
  final int? season;
  final int? episode;
  final int? year;
  final double delaySec;
  final ValueChanged<SubtitleVariant?> onSelectVariant;
  final ValueChanged<PlayerEmbeddedSubtitle> onSelectEmbedded;
  final VoidCallback onToggleOff;
  final VoidCallback onOpenSyncBar;
  final VoidCallback onOpenStyleBar;
  final VoidCallback onOpenTextSync;
  final VoidCallback onClose;

  const PlayerSubtitleMenu({
    super.key,
    required this.groups,
    this.embeddedSubtitles = const [],
    this.selectedEmbeddedIndex,
    this.selectedVariant,
    required this.isSubtitleEnabled,
    required this.movieTitle,
    this.imdbId,
    this.season,
    this.episode,
    this.year,
    required this.delaySec,
    required this.onSelectVariant,
    required this.onSelectEmbedded,
    required this.onToggleOff,
    required this.onOpenSyncBar,
    required this.onOpenStyleBar,
    required this.onOpenTextSync,
    required this.onClose,
  });

  @override
  State<PlayerSubtitleMenu> createState() => _PlayerSubtitleMenuState();
}

class _PlayerSubtitleMenuState extends State<PlayerSubtitleMenu> {
  String? _selectedLanguage;
  String _sourceFilter = 'all'; // 'all', 'embedded', 'external'
  bool _filterHI = false;
  bool _filterForced = false;
  List<SubtitleLanguageGroup> _dynamicGroups = [];
  bool _isLoadingSearch = false;
  String? _searchQuery;

  static String cleanMediaTitle(String raw) {
    var name = raw;
    name = name.replaceAll(RegExp(r'\.(mkv|mp4|avi|webm|ts|mov|m4v|srt|vtt)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[._]'), ' ');
    name = name.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|ds4k|webrip|web-dl|bluray|brrip|h264|x264|h265|x265|hevc|10bit|ddp5\.1|dd5\.1|atmos|aac|ac3|dts|flac|remux|hdr|dv|proper|repack|hdtv)\b', caseSensitive: false), ' ');
    name = name.replaceAll(RegExp(r'-[a-zA-Z0-9]+$'), '');
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  void initState() {
    super.initState();
    _dynamicGroups = List.from(widget.groups);
    if (widget.selectedEmbeddedIndex != null) {
      _selectedLanguage = '__embedded__';
    } else if (widget.selectedVariant != null) {
      _selectedLanguage = widget.selectedVariant!.language;
    } else if (_dynamicGroups.isNotEmpty) {
      final hasEn = _dynamicGroups.where((g) => g.language.toLowerCase() == 'english' || g.language.toLowerCase() == 'en').firstOrNull;
      _selectedLanguage = hasEn?.language ?? _dynamicGroups.first.language;
    } else if (widget.embeddedSubtitles.isNotEmpty) {
      _selectedLanguage = '__embedded__';
    } else {
      _selectedLanguage = '__all__';
    }

    if (_dynamicGroups.isEmpty && widget.embeddedSubtitles.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchOnline();
      });
    }
  }

  @override
  void didUpdateWidget(PlayerSubtitleMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groups.isNotEmpty && widget.groups != oldWidget.groups) {
      setState(() {
        _dynamicGroups = _mergeGroups(_dynamicGroups, widget.groups);
        if (_selectedLanguage == null || _selectedLanguage == '__all__' || (_selectedLanguage == '__embedded__' && widget.selectedEmbeddedIndex == null)) {
          final hasEn = _dynamicGroups.where((g) => g.language.toLowerCase() == 'english' || g.language.toLowerCase() == 'en').firstOrNull;
          _selectedLanguage = hasEn?.language ?? _dynamicGroups.first.language;
        }
      });
    }
  }

  static List<SubtitleLanguageGroup> _mergeGroups(
    List<SubtitleLanguageGroup> base,
    List<SubtitleLanguageGroup> additional,
  ) {
    final Map<String, List<SubtitleVariant>> map = {};
    for (final g in base) {
      map.putIfAbsent(g.language, () => []).addAll(g.variants);
    }
    for (final g in additional) {
      final list = map.putIfAbsent(g.language, () => []);
      for (final v in g.variants) {
        if (!list.any((existing) => existing.downloadUrl == v.downloadUrl)) {
          list.add(v);
        }
      }
    }
    final sortedKeys = map.keys.toList()..sort((a, b) => a.compareTo(b));
    return sortedKeys.map((lang) => SubtitleLanguageGroup(language: lang, variants: map[lang]!)).toList();
  }

  Future<void> _searchOnline() async {
    setState(() => _isLoadingSearch = true);
    try {
      int? year = widget.year;
      final rawTitle = widget.movieTitle;
      if (year == null) {
        final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawTitle);
        if (yMatch != null) year = int.tryParse(yMatch.group(1)!);
      }

      final query = _searchQuery?.isNotEmpty == true
          ? _searchQuery!
          : cleanMediaTitle(rawTitle);

      debugPrint('[PlayerSubtitleMenu] Searching subtitles online for: "$query" (year: $year, imdb: ${widget.imdbId})');
      final results = await SubtitleService().fetchAllSubtitles(
        query,
        imdbId: widget.imdbId,
        season: widget.season,
        episode: widget.episode,
        year: year,
      );
      debugPrint('[PlayerSubtitleMenu] Found ${results.length} subtitle language groups');
      if (mounted) {
        setState(() {
          _dynamicGroups = _mergeGroups(widget.groups, results);
          if (_dynamicGroups.isNotEmpty && _selectedLanguage == null) {
            _selectedLanguage = _dynamicGroups.first.language;
          }
        });
      }
    } catch (e) {
      debugPrint('[PlayerSubtitleMenu] search error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSearch = false);
    }
  }

  String _getLanguageEmoji(String lang) {
    final l = lang.toLowerCase();
    if (l.contains('en') || l.contains('eng')) return '🇺🇸';
    if (l.contains('ar') || l.contains('ara')) return '🇸🇦';
    if (l.contains('es') || l.contains('spa')) return '🇪🇸';
    if (l.contains('fr') || l.contains('fre')) return '🇫🇷';
    if (l.contains('de') || l.contains('ger')) return '🇩🇪';
    if (l.contains('it') || l.contains('ita')) return '🇮🇹';
    if (l.contains('pt') || l.contains('por')) return '🇧🇷';
    if (l.contains('ru') || l.contains('rus')) return '🇷🇺';
    if (l.contains('ja') || l.contains('jpn')) return '🇯🇵';
    if (l.contains('ko') || l.contains('kor')) return '🇰🇷';
    if (l.contains('zh') || l.contains('chi')) return '🇨🇳';
    if (l.contains('hi') || l.contains('hin')) return '🇮🇳';
    if (l.contains('tr') || l.contains('tur')) return '🇹🇷';
    return '🌐';
  }

  List<SubtitleVariant> _getFilteredVariants() {
    List<SubtitleVariant> all = [];
    if (_selectedLanguage == '__all__' || _selectedLanguage == null) {
      all = _dynamicGroups.expand((g) => g.variants).toList();
    } else {
      final g = _dynamicGroups.firstWhere(
        (group) => group.language == _selectedLanguage,
        orElse: () => SubtitleLanguageGroup(language: '', variants: []),
      );
      all = g.variants;
    }

    return all.where((v) {
      if (_filterHI && !(v.title.contains('[CC]') || v.title.contains('SDH') || v.title.contains('HI'))) {
        return false;
      }
      if (_filterForced && !v.title.toLowerCase().contains('forced')) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final totalVariantsCount = _dynamicGroups.fold<int>(0, (sum, g) => sum + g.variants.length);
    final isOff = !widget.isSubtitleEnabled || (widget.selectedVariant == null && widget.selectedEmbeddedIndex == null);
    final filteredVariants = _getFilteredVariants();
    final screen = MediaQuery.sizeOf(context);

    // Responsive Breakpoints
    final isCompact = screen.width < 560; // Mobile portrait or narrow screen
    final isLandscapeMobile = screen.height < 450 && screen.width >= 560; // Mobile landscape

    // Compute responsive dimensions
    final double cardWidth;
    if (isCompact) {
      cardWidth = (screen.width - 24).clamp(280.0, 520.0);
    } else if (isLandscapeMobile) {
      cardWidth = (screen.width - 48).clamp(460.0, 600.0);
    } else {
      cardWidth = (540.0).clamp(400.0, screen.width - 48);
    }

    final double cardHeight;
    if (isLandscapeMobile) {
      cardHeight = (screen.height - 56).clamp(200.0, screen.height - 48);
    } else if (isCompact) {
      cardHeight = (screen.height * 0.65).clamp(340.0, 520.0);
    } else {
      cardHeight = (screen.height * 0.65).clamp(380.0, 540.0);
    }

    final headerPaddingV = (isLandscapeMobile || isCompact) ? 8.0 : 12.0;
    final buttonSize = (isLandscapeMobile || isCompact) ? 30.0 : 34.0;
    final iconSize = (isLandscapeMobile || isCompact) ? 15.0 : 17.0;
    final tokens = context.tokens;

    return PlayerGlassCard(
      width: cardWidth,
      height: cardHeight,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 1. Header Bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: headerPaddingV),
            decoration: BoxDecoration(border: Border(bottom: tokens.hairline)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title and badge
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Subtitles',
                        style: ZplayType.subtitle
                            .copyWith(size: 14.5, weight: FontWeight.w700)
                            .toStyle(color: PlayerTheme.ink),
                      ),
                      if (totalVariantsCount > 0) ...[
                        const SizedBox(width: ZplaySpacing.s8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: PlayerTheme.raised,
                            borderRadius: ZplayRadius.fullAll,
                          ),
                          child: Text(
                            '$totalVariantsCount',
                            style: ZplayType.overline
                                .copyWith(size: 10.5, weight: FontWeight.w700)
                                .toStyle(color: PlayerTheme.inkSubtle),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Header Action Icons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Online Search Trigger
                    PlayerIconButton(
                      size: buttonSize,
                      iconSize: iconSize,
                      icon: _isLoadingSearch
                          ? SizedBox(
                              width: iconSize,
                              height: iconSize,
                              child: CircularProgressIndicator(
                                color: PlayerTheme.accent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh Online Subtitles',
                      onPressed: _isLoadingSearch ? null : _searchOnline,
                    ),
                    const SizedBox(width: 3),

                    // Subtitle Delay Bar (external subtitles only)
                    if (widget.selectedEmbeddedIndex == null) ...[
                      PlayerIconButton(
                        size: buttonSize,
                        iconSize: iconSize,
                        icon: const Icon(Icons.timer_outlined),
                        tooltip: 'Subtitle Sync Bar',
                        showActiveBadge: widget.delaySec != 0,
                        onPressed: () {
                          widget.onClose();
                          widget.onOpenSyncBar();
                        },
                      ),
                      const SizedBox(width: 3),
                    ],

                    // Subtitle Appearance Style Bar
                    PlayerIconButton(
                      size: buttonSize,
                      iconSize: iconSize,
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: 'Subtitle Appearance',
                      onPressed: () {
                        widget.onClose();
                        widget.onOpenStyleBar();
                      },
                    ),
                    const SizedBox(width: 3),

                    // Text Sync to Speech (Actor Dialogue Listening Sync - external subtitles only)
                    if (widget.selectedEmbeddedIndex == null) ...[
                      PlayerIconButton(
                        size: buttonSize,
                        iconSize: iconSize,
                        icon: const Icon(Icons.text_fields_rounded),
                        tooltip: 'Speech Text Sync',
                        onPressed: () {
                          widget.onClose();
                          widget.onOpenTextSync();
                        },
                      ),
                      const SizedBox(width: ZplaySpacing.s4),
                    ],

                    // Close Button
                    PlayerIconButton(
                      size: buttonSize,
                      iconSize: iconSize,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Responsive Content Body
          Expanded(
            child: isCompact
                ? _buildCompactLayout(context, isOff, filteredVariants, totalVariantsCount)
                : _buildDesktopLayout(context, isOff, filteredVariants, totalVariantsCount, isLandscapeMobile),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Compact / Mobile Layout (Top Horizontal Category Bar + Full-width List)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildCompactLayout(
    BuildContext context,
    bool isOff,
    List<SubtitleVariant> filteredVariants,
    int totalVariantsCount,
  ) {
    return Column(
      children: [
        // Horizontal Scrollable Category & Language Selector
        _buildHorizontalLanguageBar(isOff, totalVariantsCount),

        // Filter Chips Toolbar
        if (_selectedLanguage != '__embedded__') _buildFilterToolbar(compact: true),

        // Subtitles List / Embedded List
        Expanded(
          child: _selectedLanguage == '__embedded__'
              ? _buildEmbeddedList(compact: true)
              : _buildVariantList(filteredVariants, compact: true),
        ),

        // Bottom Search Trigger
        if (_selectedLanguage != '__embedded__') _buildBottomSearchBar(compact: true),
      ],
    );
  }

  Widget _buildHorizontalLanguageBar(bool isOff, int totalVariantsCount) {
    final tokens = AppThemeService.currentTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.bg.withValues(alpha: 0.125),
        border: Border(bottom: tokens.hairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // Off Button
            _buildLanguagePill(
              label: 'Off',
              isSelected: isOff,
              icon: Icon(
                Icons.block_rounded,
                size: 13,
                color: isOff ? tokens.textPrimary : PlayerTheme.inkSubtle,
              ),
              onTap: () {
                widget.onToggleOff();
                widget.onClose();
              },
            ),
            const SizedBox(width: 6),

            // Embedded Subtitles Pill
            if (widget.embeddedSubtitles.isNotEmpty) ...[
              _buildLanguagePill(
                label: 'Embedded',
                emoji: '⚡',
                count: widget.embeddedSubtitles.length,
                isSelected: _selectedLanguage == '__embedded__',
                onTap: () => setState(() => _selectedLanguage = '__embedded__'),
              ),
              const SizedBox(width: 6),
            ],

            // All Languages Pill
            if (_dynamicGroups.isNotEmpty) ...[
              _buildLanguagePill(
                label: 'All',
                emoji: '🌐',
                count: totalVariantsCount,
                isSelected: _selectedLanguage == '__all__',
                onTap: () => setState(() => _selectedLanguage = '__all__'),
              ),
              const SizedBox(width: 6),

              // Individual Languages
              ..._dynamicGroups.map((g) {
                final isSelected = _selectedLanguage == g.language;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildLanguagePill(
                    label: g.language,
                    emoji: _getLanguageEmoji(g.language),
                    count: g.variants.length,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedLanguage = g.language),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLanguagePill({
    required String label,
    String? emoji,
    Widget? icon,
    int? count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final tokens = AppThemeService.currentTokens;
    return FocusableInkWell(
      borderRadius: ZplayRadius.lgAll,
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected ? PlayerTheme.accent.withValues(alpha: 0.35) : PlayerTheme.raised,
        borderRadius: ZplayRadius.lgAll,
        border: Border.all(
          color: isSelected ? PlayerTheme.accent : PlayerTheme.edgeSoft,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon,
            const SizedBox(width: 5),
          ] else if (emoji != null) ...[
            Text(emoji, style: ZplayType.caption.toStyle()),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: ZplayType.caption
                .copyWith(
                  size: 11.5,
                  weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                )
                .toStyle(
                  color: isSelected ? PlayerTheme.ink : PlayerTheme.inkMuted,
                ),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? PlayerTheme.accent : PlayerTheme.surfaceHover,
                borderRadius: ZplayRadius.fullAll,
              ),
              child: Text(
                '$count',
                style: ZplayType.overline
                    .copyWith(size: 9.5, weight: FontWeight.w700)
                    .toStyle(
                      color: isSelected ? tokens.onAccent : PlayerTheme.inkSubtle,
                    ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Desktop / Tablet / Wide Layout (2-Column: Left Sidebar + Right List)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(
    BuildContext context,
    bool isOff,
    List<SubtitleVariant> filteredVariants,
    int totalVariantsCount,
    bool isLandscapeMobile,
  ) {
    final sidebarWidth = isLandscapeMobile ? 138.0 : 155.0;
    final tokens = AppThemeService.currentTokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Language Sidebar
        Container(
          width: sidebarWidth,
          decoration: BoxDecoration(
            color: tokens.bg.withValues(alpha: 0.133),
            border: Border(right: tokens.hairline),
          ),
          child: ListView(
            padding: const EdgeInsets.all(7),
            physics: const BouncingScrollPhysics(),
            children: [
              // Subtitles Off Button
              FocusableInkWell(
                borderRadius: ZplayRadius.smAll,
                onTap: () {
                  widget.onToggleOff();
                  widget.onClose();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: isOff ? PlayerTheme.raised : Colors.transparent,
                    borderRadius: ZplayRadius.smAll,
                    border: Border.all(
                      color: isOff ? PlayerTheme.edge : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: isOff ? PlayerTheme.accent : PlayerTheme.raised,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: isOff
                            ? Icon(
                                Icons.check_rounded,
                                size: 9.5,
                                color: tokens.onAccent,
                              )
                            : null,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Off',
                        style: ZplayType.bodySmall
                            .copyWith(size: 12, weight: FontWeight.w600)
                            .toStyle(color: PlayerTheme.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),

              // Embedded Subtitles Category
              if (widget.embeddedSubtitles.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    left: ZplaySpacing.s8,
                    top: 10,
                    bottom: ZplaySpacing.s4,
                  ),
                  child: Text(
                    'EMBEDDED',
                    style: ZplayType.overline
                        .copyWith(size: 9, weight: FontWeight.w700)
                        .toStyle(color: PlayerTheme.inkSubtle),
                  ),
                ),
                FocusableInkWell(
                  borderRadius: ZplayRadius.smAll,
                  onTap: () => setState(() => _selectedLanguage = '__embedded__'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: _selectedLanguage == '__embedded__' ? PlayerTheme.raised : Colors.transparent,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: _selectedLanguage == '__embedded__' ? PlayerTheme.edge : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('⚡', style: ZplayType.caption.toStyle()),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Embedded',
                            style: ZplayType.caption
                                .copyWith(size: 11.5, weight: FontWeight.w600)
                                .toStyle(color: PlayerTheme.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: PlayerTheme.accent.withValues(alpha: 0.35),
                            borderRadius: ZplayRadius.fullAll,
                          ),
                          child: Text(
                            '${widget.embeddedSubtitles.length}',
                            style: ZplayType.overline
                                .copyWith(size: 9, weight: FontWeight.w700)
                                .toStyle(color: tokens.onAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_dynamicGroups.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    left: ZplaySpacing.s8,
                    top: 10,
                    bottom: ZplaySpacing.s4,
                  ),
                  child: Text(
                    'LANGUAGES',
                    style: ZplayType.overline
                        .copyWith(size: 9, weight: FontWeight.w700)
                        .toStyle(color: PlayerTheme.inkSubtle),
                  ),
                ),

                // All Languages Option
                FocusableInkWell(
                  borderRadius: ZplayRadius.smAll,
                  onTap: () => setState(() => _selectedLanguage = '__all__'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: _selectedLanguage == '__all__' ? PlayerTheme.raised : Colors.transparent,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: _selectedLanguage == '__all__' ? PlayerTheme.edge : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('🌐', style: ZplayType.caption.toStyle()),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'All Languages',
                            style: ZplayType.caption
                                .copyWith(size: 11.5)
                                .toStyle(color: PlayerTheme.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$totalVariantsCount',
                          style: ZplayType.overline
                              .copyWith(size: 9.5)
                              .toStyle(color: PlayerTheme.inkSubtle),
                        ),
                      ],
                    ),
                  ),
                ),

                // Individual Language Groups
                ..._dynamicGroups.map((g) {
                  final isSelected = _selectedLanguage == g.language;
                  return FocusableInkWell(
                    borderRadius: ZplayRadius.smAll,
                    onTap: () => setState(() => _selectedLanguage = g.language),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? PlayerTheme.raised : Colors.transparent,
                        borderRadius: ZplayRadius.smAll,
                        border: Border.all(
                          color: isSelected ? PlayerTheme.edge : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _getLanguageEmoji(g.language),
                            style: ZplayType.caption.toStyle(),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              g.language,
                              style: ZplayType.caption
                                  .copyWith(
                                    size: 11.5,
                                    weight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  )
                                  .toStyle(
                                    color: isSelected
                                        ? PlayerTheme.ink
                                        : PlayerTheme.inkMuted,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${g.variants.length}',
                            style: ZplayType.overline
                                .copyWith(size: 9.5)
                                .toStyle(color: PlayerTheme.inkSubtle),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),

        // Right Variants & Search Panel
        Expanded(
          child: _selectedLanguage == '__embedded__'
              ? _buildEmbeddedList(compact: false)
              : Column(
                  children: [
                    _buildFilterToolbar(compact: false),
                    Expanded(child: _buildVariantList(filteredVariants, compact: false)),
                    _buildBottomSearchBar(compact: false),
                  ],
                ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared Filter Toolbar
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildFilterToolbar({required bool compact}) {
    final tokens = AppThemeService.currentTokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 6 : 7),
      decoration: BoxDecoration(border: Border(bottom: tokens.hairline)),
      child: Row(
        children: [
          PlayerToggleChip(
            active: _sourceFilter == 'all',
            label: 'All',
            onClick: () => setState(() => _sourceFilter = 'all'),
          ),
          const SizedBox(width: 5),
          PlayerToggleChip(
            active: _filterHI,
            label: 'HI / CC',
            onClick: () => setState(() => _filterHI = !_filterHI),
          ),
          const SizedBox(width: 5),
          PlayerToggleChip(
            active: _filterForced,
            label: 'Forced',
            onClick: () => setState(() => _filterForced = !_filterForced),
          ),
          const Spacer(),
          if (compact)
            FocusableCard(
              onTap: _searchOnline,
              builder: (context, _) => Row(
                children: [
                  Icon(Icons.search_rounded, size: 13, color: PlayerTheme.accent),
                  const SizedBox(width: ZplaySpacing.s4),
                  Text(
                    'Search Online',
                    style: ZplayType.caption
                        .copyWith(weight: FontWeight.w600)
                        .toStyle(color: PlayerTheme.accent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Embedded Subtitles List
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildEmbeddedList({required bool compact}) {
    return ListView.builder(
      padding: const EdgeInsets.all(7),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.embeddedSubtitles.length,
      itemBuilder: (context, i) {
        final tokens = context.tokens;
        final track = widget.embeddedSubtitles[i];
        final isSelected = widget.isSubtitleEnabled && widget.selectedEmbeddedIndex == track.index;

        return FocusableInkWell(
          borderRadius: ZplayRadius.smAll,
          onTap: () {
            widget.onSelectEmbedded(track);
            widget.onClose();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZplaySpacing.s8),
            margin: const EdgeInsets.only(bottom: ZplaySpacing.s4),
            decoration: BoxDecoration(
              color: isSelected ? PlayerTheme.raised : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: isSelected ? PlayerTheme.edge : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? PlayerTheme.accent : PlayerTheme.raised,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          size: 10.5,
                          color: tokens.onAccent,
                        )
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (track.language != null && track.language!.isNotEmpty) ...[
                            Text(
                              _getLanguageEmoji(track.language!),
                              style: ZplayType.bodySmall.toStyle(),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              track.title,
                              style: ZplayType.bodySmall
                                  .copyWith(
                                    weight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  )
                                  .toStyle(
                                    color: isSelected
                                        ? PlayerTheme.ink
                                        : PlayerTheme.inkMuted,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: PlayerTheme.accent.withValues(alpha: 0.18),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              'EMBEDDED',
                              style: ZplayType.overline
                                  .copyWith(size: 8.5, weight: FontWeight.w700)
                                  .toStyle(color: PlayerTheme.accent),
                            ),
                          ),
                          if (track.language != null && track.language!.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(
                              track.language!.toUpperCase(),
                              style: ZplayType.overline
                                  .copyWith(size: 9)
                                  .toStyle(color: PlayerTheme.inkSubtle),
                            ),
                          ],
                          if (track.codec != null && track.codec!.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(
                              track.codec!.toUpperCase(),
                              style: ZplayType.overline
                                  .copyWith(size: 9, weight: FontWeight.w400)
                                  .toStyle(color: PlayerTheme.inkSubtle),
                            ),
                          ],
                          const SizedBox(width: 5),
                          Text(
                            '#${track.index + 1}',
                            style: ZplayType.overline
                                .copyWith(size: 9, weight: FontWeight.w400)
                                .toStyle(color: PlayerTheme.inkDisabled),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // External Subtitle Variants List
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildVariantList(List<SubtitleVariant> filteredVariants, {required bool compact}) {
    final tokens = AppThemeService.currentTokens;
    if (_isLoadingSearch && filteredVariants.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: PlayerTheme.accent,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 10),
            Text(
              'Searching subtitles...',
              style: ZplayType.bodySmall.toStyle(color: PlayerTheme.inkMuted),
            ),
          ],
        ),
      );
    }

    if (filteredVariants.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subtitles_off_rounded,
                size: 30,
                color: PlayerTheme.inkSubtle,
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                'No subtitles available.',
                style: ZplayType.bodySmall
                    .copyWith(size: 12.5)
                    .toStyle(color: PlayerTheme.inkMuted),
              ),
              const SizedBox(height: ZplaySpacing.s12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: PlayerTheme.accent,
                  foregroundColor: tokens.onAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: ZplaySpacing.s8,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZplayRadius.smAll,
                  ),
                ),
                icon: const Icon(Icons.search_rounded, size: 15),
                label: Text(
                  'Search Online Providers',
                  style: ZplayType.caption.copyWith(size: 11.5).toStyle(),
                ),
                onPressed: _searchOnline,
              ),
            ],
          ),
        ),
      );
    }

    final hasLoadingBanner = _isLoadingSearch;
    final totalItemCount = filteredVariants.length + (hasLoadingBanner ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.all(7),
      physics: const BouncingScrollPhysics(),
      itemCount: totalItemCount,
      itemBuilder: (context, i) {
        if (hasLoadingBanner && i == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: PlayerTheme.accent.withValues(alpha: 0.12),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(color: PlayerTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: PlayerTheme.accent),
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Text(
                  'Searching additional subtitles online...',
                  style: ZplayType.caption.toStyle(color: PlayerTheme.accent),
                ),
              ],
            ),
          );
        }

        final variantIndex = hasLoadingBanner ? i - 1 : i;
        final variant = filteredVariants[variantIndex];
        final isSelected = widget.isSubtitleEnabled && widget.selectedVariant?.downloadUrl == variant.downloadUrl;

        final isHI = variant.title.contains('[CC]') || variant.title.contains('SDH') || variant.title.contains('HI');
        final isForced = variant.title.toLowerCase().contains('forced');

        return FocusableInkWell(
          borderRadius: ZplayRadius.smAll,
          onTap: () {
            widget.onSelectVariant(variant);
            widget.onClose();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
            margin: const EdgeInsets.only(bottom: ZplaySpacing.s4),
            decoration: BoxDecoration(
              color: isSelected ? PlayerTheme.raised : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: isSelected ? PlayerTheme.edge : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? PlayerTheme.accent : PlayerTheme.raised,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          size: 10.5,
                          color: tokens.onAccent,
                        )
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (variant.language.isNotEmpty) ...[
                            Text(
                              _getLanguageEmoji(variant.language),
                              style: ZplayType.bodySmall.toStyle(),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              variant.title,
                              style: ZplayType.bodySmall
                                  .copyWith(
                                    weight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  )
                                  .toStyle(
                                    color: isSelected
                                        ? PlayerTheme.ink
                                        : PlayerTheme.inkMuted,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: PlayerTheme.raised,
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              variant.providerName.toUpperCase(),
                              style: ZplayType.overline
                                  .copyWith(size: 8.5, weight: FontWeight.w700)
                                  .toStyle(color: PlayerTheme.inkSubtle),
                            ),
                          ),
                          if (variant.format.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4, vertical: 1),
                              decoration: BoxDecoration(
                                color: tokens.borderDefault,
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                variant.format.toUpperCase(),
                                style: ZplayType.overline
                                    .copyWith(size: 8.5, weight: FontWeight.w400)
                                    .toStyle(color: PlayerTheme.inkSubtle),
                              ),
                            ),
                          if (isHI)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4, vertical: 1),
                              decoration: BoxDecoration(
                                color: tokens.success.withValues(alpha: 0.133),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                'HI / CC',
                                style: ZplayType.overline
                                    .copyWith(size: 8.5, weight: FontWeight.w700)
                                    .toStyle(color: tokens.success),
                              ),
                            ),
                          if (isForced)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4, vertical: 1),
                              decoration: BoxDecoration(
                                color: tokens.warning.withValues(alpha: 0.133),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                'FORCED',
                                style: ZplayType.overline
                                    .copyWith(size: 8.5, weight: FontWeight.w700)
                                    .toStyle(color: tokens.warning),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Bottom Search Trigger
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBottomSearchBar({required bool compact}) {
    final tokens = AppThemeService.currentTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s12,
        vertical: 7,
      ),
      decoration: BoxDecoration(border: Border(top: tokens.hairline)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          FocusableCard(
            onTap: _searchOnline,
            builder: (context, _) {
              return Row(
                children: [
                  Icon(Icons.search_rounded, size: 13, color: PlayerTheme.accent),
                  const SizedBox(width: 5),
                  Text(
                    'Find more subtitles',
                    style: ZplayType.caption
                        .copyWith(size: 11.5, weight: FontWeight.w600)
                        .toStyle(color: PlayerTheme.inkMuted),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
