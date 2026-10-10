import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/manga/manga.dart';
import '../../models/manga/manga_chapter.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/manga/manga_service.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import 'manga_reader_page.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';

class MangaDetailsPage extends StatefulWidget {
  final Manga manga;

  const MangaDetailsPage({super.key, required this.manga});

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends State<MangaDetailsPage> {
  final MangaService _mangaService = MangaService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  Manga? _fullDetails;
  List<MangaChapter>? _chapters;
  Map<String, dynamic>? _historyEntry;
  bool _isLoading = true;

  // Chapter Pagination & Search
  String _chapterSearchQuery = '';
  int _currentChapterPage = 0;
  final int _chaptersPerPage = 50;

  @override
  void initState() {
    super.initState();
    AppThemeService.currentPalette.addListener(_onThemeChanged);
    _loadDetails();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    AppThemeService.currentPalette.removeListener(_onThemeChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final results = await Future.wait([
      _mangaService.getSeriesDetail(widget.manga.id),
      _mangaService.getChapters(widget.manga.id),
      _mangaService.getReadingHistory(),
    ]);

    final historyList = results[2] as List<Map<String, dynamic>>;
    Map<String, dynamic>? matchingHistory;
    try {
      matchingHistory = historyList.firstWhere((h) => h['manga']['id'] == widget.manga.id);
    } catch (_) {
      // No history found
    }

    if (mounted) {
      setState(() {
        _fullDetails = results[0] as Manga;
        _chapters = results[1] as List<MangaChapter>;
        _historyEntry = matchingHistory;
        _isLoading = false;
      });
    }
  }

  void _startReading(int chapterIndex, {int pageIndex = 0}) {
    if (_chapters == null || _chapters!.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MangaReaderPage(
          manga: _fullDetails ?? widget.manga,
          chapters: _chapters!,
          currentChapterIndex: chapterIndex,
          resumePageIndex: pageIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) {
      _loadDetails();
    });
  }

  List<MangaChapter> get _filteredChapters {
    if (_chapters == null) return [];
    if (_chapterSearchQuery.isEmpty) return _chapters!;

    final query = _chapterSearchQuery.toLowerCase();
    return _chapters!.where((c) =>
        c.name.toLowerCase().contains(query) ||
        c.number.toString().contains(query)).toList();
  }

  List<MangaChapter> get _paginatedChapters {
    final filtered = _filteredChapters;
    final startIndex = _currentChapterPage * _chaptersPerPage;
    if (startIndex >= filtered.length) return [];

    final endIndex = (startIndex + _chaptersPerPage).clamp(0, filtered.length);
    return filtered.sublist(startIndex, endIndex);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final displayManga = _fullDetails ?? widget.manga;
    final coverUrl = displayManga.coverNormal.isNotEmpty
        ? displayManga.coverNormal
        : displayManga.coverSmall;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // Background Hero Cover with ambient blur
          Positioned.fill(
            child: Hero(
              tag: 'manga_cover_${displayManga.id}',
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorWidget: (_, __, ___) => ColoredBox(color: tokens.bg)),
            ),
          ),

          // Dark Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tokens.bg.withValues(alpha: 0.65),
                    tokens.bg.withValues(alpha: 0.96),
                    tokens.bg,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          LiquidGlassView(
            pixelRatio: 0.25,
            refreshRate: LiquidGlassRefreshRate.low,
            backgroundWidget: _buildScrollableContent(displayManga),
            child: Stack(
              children: [
                _buildAppBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent(Manga manga) {
    final screen = MediaQuery.sizeOf(context);
    final isDesktop = screen.width >= 720;

    final tokens = context.tokens;
    final paginatedList = _paginatedChapters;
    final totalFiltered = _filteredChapters.length;
    final totalPages = (totalFiltered / _chaptersPerPage).ceil();

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).top + 60),
        ),

        // Responsive Metadata Header
        SliverToBoxAdapter(
          // One gutter for the whole page: it was 40/18 dp here while
          // [SectionHeader] below carries its own 16, so every heading, row and
          // block on this screen started on a different left edge.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
            child: isDesktop
                ? _buildDesktopHeader(manga)
                : _buildMobileHeader(manga),
          ),
        ),

        SliverToBoxAdapter(child: SizedBox(height: isDesktop ? 36 : 24)),

        // Synopsis Section
        if (manga.synopsis.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full-bleed: [SectionHeader] carries its own 8 dp top / 16 dp
                // side padding, so the heading lands on the page gutter without
                // this sliver wrapping it twice.
                const SectionHeader(title: 'Synopsis'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZplaySpacing.s16,
                    ZplaySpacing.s12,
                    ZplaySpacing.s16,
                    0,
                  ),
                  // It was a filled, bordered box. The synopsis is long-form
                  // copy, not a card, and the box was the only thing on the page
                  // drawing chrome around text - spacing and type weight already
                  // separate it from the metadata above.
                  child: Text(
                    manga.synopsis,
                    style: ZplayType.body
                        .copyWith(size: isDesktop ? 15 : 13.5, height: 1.55)
                        .toStyle(color: tokens.textEmphasis),
                  ),
                ),
              ],
            ),
          ),

        SliverToBoxAdapter(child: SizedBox(height: isDesktop ? 36 : 24)),

        // Chapters Header & Search Bar
        //
        // [SectionHeader] draws the count as a muted tabular number beside the
        // title. It was an accent-filled `accentSubtle` pill: accent is the
        // app's selection signal - what you are on, what is live - and a
        // section total is neither.
        SliverToBoxAdapter(
          child: isDesktop
              ? SectionHeader(
                  title: 'Chapters',
                  count: _chapters?.length,
                  trailing: SizedBox(
                    width: 250,
                    height: 40,
                    child: _buildSearchTextField(),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title: 'Chapters', count: _chapters?.length),
                    const SizedBox(height: ZplaySpacing.s12),
                    // Full-width on mobile, so it stays under the heading
                    // rather than beside it.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s16,
                      ),
                      child: SizedBox(
                        height: 42,
                        child: _buildSearchTextField(),
                      ),
                    ),
                  ],
                ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        if (_isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: CircularProgressIndicator(color: tokens.accent),
              ),
            ),
          )
        else if (paginatedList.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  _chapterSearchQuery.isNotEmpty
                      ? 'No chapters matching "$_chapterSearchQuery"'
                      : 'No chapters found.',
                  style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                ),
              ),
            ),
          )
        else ...[
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chapter = paginatedList[index];
                final originalIndex = _chapters!.indexOf(chapter);

                final isRead = _historyEntry != null &&
                    _historyEntry!['chapterIndex'] < originalIndex;
                final isCurrent = _historyEntry != null &&
                    _historyEntry!['chapterIndex'] == originalIndex;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s16,
                    vertical: 3.5,
                  ),
                  // It was a `ListTile` with an accent-or-hairline outline, a
                  // `tileColor` fill and Material's own focus wash on top:
                  // three indicators for one state. There is no resting border
                  // now, the ring is the only focus marker, and the fill answers
                  // the pointer only - a D-pad move must not repaint the row the
                  // user is aiming at.
                  child: FocusableCard(
                    onTap: () => _startReading(originalIndex),
                    builder: (_, state) => CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.smAll,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.smAll,
                          color: isCurrent
                              ? tokens.accentSubtle
                              : (state.hovered
                                  ? tokens.textPrimary.withValues(
                                      alpha: ZplayOpacity.overlayHover)
                                  : null),
                        ),
                        child: Row(
                          children: [
                            // The number keeps its circle: that fill is the
                            // chapter's own content, not chrome around it.
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? tokens.accentSubtle
                                    : tokens.borderSubtle,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  chapter.number > 0
                                      ? chapter.number.toStringAsFixed(
                                          chapter.number.truncateToDouble() ==
                                                  chapter.number
                                              ? 0
                                              : 1)
                                      : '#',
                                  style: ZplayType.caption
                                      .copyWith(weight: FontWeight.w700)
                                      .toStyle(color: tokens.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s12),
                            Expanded(
                              child: Text(
                                (chapter.name.isNotEmpty &&
                                        chapter.name.toLowerCase() != 'last read')
                                    ? chapter.name
                                    : (chapter.number > 0
                                        ? 'Chapter ${chapter.number.toStringAsFixed(chapter.number.truncateToDouble() == chapter.number ? 0 : 1)}'
                                        : 'Chapter'),
                                style: ZplayType.label
                                    .copyWith(
                                      size: isDesktop ? 14.5 : 13.5,
                                      weight: isCurrent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    )
                                    .toStyle(
                                      color: isRead
                                          ? tokens.textSecondary
                                          : tokens.textPrimary,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: tokens.textMuted,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: paginatedList.length,
            ),
          ),

          // Pagination Controls
          if (totalPages > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: 24.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ChromeGlyphAction(
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Previous chapter page',
                      onTap: _currentChapterPage > 0
                          ? () => setState(() => _currentChapterPage--)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Page ${_currentChapterPage + 1} of $totalPages',
                      style: ZplayType.body
                          .copyWith(size: 14.5)
                          .toStyle(color: tokens.textEmphasis),
                    ),
                    const SizedBox(width: 14),
                    _ChromeGlyphAction(
                      icon: Icons.chevron_right_rounded,
                      semanticLabel: 'Next chapter page',
                      onTap: _currentChapterPage < totalPages - 1
                          ? () => setState(() => _currentChapterPage++)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildSearchTextField() {
    final tokens = context.tokens;

    return TextField(
      controller: _searchController,
      onChanged: (val) {
        setState(() {
          _chapterSearchQuery = val;
          _currentChapterPage = 0;
        });
      },
      style: ZplayType.label.copyWith(size: 13.5).toStyle(color: tokens.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search chapters...',
        hintStyle: ZplayType.label.copyWith(size: 13.5).toStyle(color: tokens.textMuted),
        prefixIcon: Icon(Icons.search_rounded, color: tokens.accent, size: 18),
        // A `FocusableCard`, not an `IconButton`: the latter draws Material's
        // grey focus wash, which would be a second focus indicator in a page
        // that has exactly one.
        suffixIcon: _chapterSearchQuery.isNotEmpty
            ? _ChromeGlyphAction(
                icon: Icons.clear_rounded,
                semanticLabel: 'Clear chapter search',
                iconSize: 16,
                tapTarget: 36,
                color: tokens.textSecondary,
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _chapterSearchQuery = '';
                    _currentChapterPage = 0;
                  });
                },
              )
            : null,
        // A form field keeps its container - the fill is what says it is one -
        // but it sits on the page surface rather than a white wash, and only
        // focus spends the accent.
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: ZplayRadius.mdAll,
          borderSide: tokens.hairline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ZplayRadius.mdAll,
          borderSide: tokens.hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ZplayRadius.mdAll,
          borderSide: BorderSide(color: tokens.accent, width: 1.5),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Desktop Header (Side-by-side Cover + Details)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopHeader(Manga manga) {
    final tokens = context.tokens;
    final coverUrl = manga.coverNormal.isNotEmpty ? manga.coverNormal : manga.coverSmall;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover image, bare: the 28 dp black drop shadow it carried was depth
        // the hero art behind it already supplies, and the last drop shadow on
        // the page outside the glyph one.
        ClipRRect(
          borderRadius: ZplayRadius.mdAll,
          child: CachedNetworkImage(
            imageUrl: coverUrl,
            cacheManager: AppImageCache.manager,

            memCacheWidth: 600,
            width: 200,
            height: 290,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 200,
              height: 290,
              color: tokens.surfaceRaised,
              child: Icon(Icons.book_rounded, color: tokens.textMuted, size: 48),
            )),
        ),
        const SizedBox(width: 32),

        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                manga.title,
                style: ZplayType.display
                    .copyWith(size: 36, height: 1.15)
                    .toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: 12),
              if (manga.author.isNotEmpty || manga.year.isNotEmpty)
                Text(
                  '${manga.author}${manga.author.isNotEmpty && manga.year.isNotEmpty ? ' • ' : ''}${manga.year}',
                  style: ZplayType.subtitle
                      .copyWith(size: 16, weight: FontWeight.w500)
                      .toStyle(color: tokens.textEmphasis),
                ),
              const SizedBox(height: 18),

              // Tags as one muted line of text, the same shape
              // `details_page.dart`'s metadata row uses. Each was a filled,
              // bordered box - six chips at the hero's foot, chrome this
              // language writes metadata without.
              if (manga.tags.isNotEmpty)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: ZplaySpacing.s4,
                  children: _tagLine(manga.tags.take(6), ZplayType.body),
                ),

              const SizedBox(height: 24),

              // Action Buttons
              if (!_isLoading) _buildHeaderActionButtons(isFullWidth: false),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Mobile / Android Header (Stacked Poster + Full-width Title & Details)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMobileHeader(Manga manga) {
    final tokens = context.tokens;
    final coverUrl = manga.coverNormal.isNotEmpty ? manga.coverNormal : manga.coverSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Centered poster, bare. It wore a 1.5 dp `borderStrong` outline, an
        // accent glow and a black drop shadow: framing the cover three times on
        // a page whose every other edge is carried by spacing.
        Center(
          child: ClipRRect(
            borderRadius: ZplayRadius.mdAll,
            child: CachedNetworkImage(
              imageUrl: coverUrl,
              cacheManager: AppImageCache.manager,

              memCacheWidth: 495,
              width: 165,
              height: 240,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 165,
                height: 240,
                color: tokens.surfaceRaised,
                child: Icon(Icons.book_rounded, color: tokens.textMuted, size: 40),
              )),
          ),
        ),
        const SizedBox(height: 18),

        // Full-width Title (Horizontal, beautifully centered)
        Text(
          manga.title,
          textAlign: TextAlign.center,
          style: ZplayType.titleLarge
              .copyWith(letterSpacing: -0.3, height: 1.25)
              .toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: 8),

        // Author & Year
        if (manga.author.isNotEmpty || manga.year.isNotEmpty)
          Text(
            '${manga.author}${manga.author.isNotEmpty && manga.year.isNotEmpty ? ' • ' : ''}${manga.year}',
            textAlign: TextAlign.center,
            style: ZplayType.label
                .copyWith(size: 13.5, weight: FontWeight.w500)
                .toStyle(color: tokens.textEmphasis),
          ),
        const SizedBox(height: 14),

        // Tags, plain and centred: the same metadata line the desktop header
        // draws, with none of the boxes.
        if (manga.tags.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: ZplaySpacing.s4,
            children: _tagLine(manga.tags.take(5), ZplayType.caption),
          ),

        const SizedBox(height: 18),

        // Action Button
        if (!_isLoading) _buildHeaderActionButtons(isFullWidth: true),
      ],
    );
  }

  Widget _buildHeaderActionButtons({required bool isFullWidth}) {
    if (_historyEntry != null) {
      final chNum = (_chapters != null && _historyEntry!['chapterIndex'] < _chapters!.length)
          ? _chapters![_historyEntry!['chapterIndex']].number
          : '';
      final label = 'Resume Chapter ${chNum.toString().isNotEmpty ? chNum : ''}';

      return _buildActionButton(
        icon: Icons.play_arrow_rounded,
        label: label,
        isFullWidth: isFullWidth,
        onTap: () => _startReading(
          _historyEntry!['chapterIndex'],
          pageIndex: _historyEntry!['pageIndex'],
        ),
      );
    } else if (_chapters != null && _chapters!.isNotEmpty) {
      return _buildActionButton(
        icon: Icons.menu_book_rounded,
        label: 'Start Reading',
        isFullWidth: isFullWidth,
        onTap: () => _startReading(_chapters!.length - 1),
      );
    }
    return const SizedBox.shrink();
  }

  /// The page's primary action, as the shared [PillButton].
  ///
  /// It was an accent-filled `Container` with an `mdAll` radius and an accent
  /// `BoxShadow` glow, glyph and label in `onAccent`. The app's reference CTA is
  /// a light pill, and its focus ring is drawn over the control rather than by
  /// expanding it, so nothing around the button moves; the accent glow was the
  /// one place on this page where accent was decoration rather than state.
  ///
  /// [isFullWidth] survives: the mobile header stretches the pill to the column
  /// while the desktop header lets it hug its label.
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isFullWidth,
    required VoidCallback onTap,
  }) {
    return PillButton(
      label: label,
      icon: icon,
      expand: isFullWidth,
      onPressed: onTap,
    );
  }

  /// The tag line: muted text with '•' separators, the shape
  /// `details_page.dart`'s metadata row uses.
  ///
  /// It takes the tags already limited - the desktop header shows six and the
  /// mobile header five - and only draws them, so both headers read as one line
  /// of metadata instead of a row of chips.
  List<Widget> _tagLine(Iterable<String> tags, ZplayTextToken style) {
    final tokens = context.tokens;
    final list = tags.toList();
    final spaced = <Widget>[];

    for (var i = 0; i < list.length; i++) {
      spaced.add(Text(list[i], style: style.toStyle(color: tokens.textSecondary)));
      if (i < list.length - 1) {
        spaced.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
            child: Text(
              '•',
              style: ZplayType.body
                  .copyWith(size: 14)
                  .toStyle(color: tokens.textDisabled),
            ),
          ),
        );
      }
    }

    return spaced;
  }

  /// The route's own back affordance, over the hero art.
  ///
  /// It was a 16 dp [BackdropFilter] blur inside a `surfaceOverlay` box with a
  /// 1.2 dp `borderStrong` hairline and an `lgAll` radius: a rounded, bordered
  /// slab floating over the cover, the same band this page's language exists to
  /// remove. It is now the bare glyph in a 40 dp [FocusableCard], carrying the
  /// app's single focus ring and the drop shadow every glyph on art uses to stay
  /// legible. The route stays pushed, so this is still the page's top chrome.
  Widget _buildAppBar() {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topPadding + 10,
      left: 16,
      child: _ChromeGlyphAction(
        icon: Icons.arrow_back_ios_new_rounded,
        semanticLabel: 'Back',
        iconSize: 18,
        tapTarget: 40,
        overArt: true,
        color: context.tokens.textEmphasis,
        onTap: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// A bare glyph action: a [FocusableCard] carrying the app's single focus ring.
///
/// Each of these was an `IconButton` - the back affordance, the two pagination
/// chevrons, the search field's clear - and Material draws its own grey focus
/// wash over a focused one. Two indicators for one state, and the second was not
/// the app's. The ring is [CardFocusRing] now, the same 3 dp accent border every
/// card in the app wears, and there is no resting fill or border: these sit on
/// the artwork, not in a box.
///
/// Modelled on `anime_page.dart`'s `_AnimeChromeAction`, with `overArt` added
/// because only the back glyph floats on the hero with nothing behind it - the
/// drop shadow is what keeps that one legible over a bright cover, and it is the
/// app's constant glyph shadow rather than a per-surface one.
///
/// `onTap: null` is the disabled state: it draws the glyph in
/// [ZplayTokens.textDisabled] and takes `enabled: false`, so a remote cannot
/// land on a control that does nothing.
class _ChromeGlyphAction extends StatelessWidget {
  const _ChromeGlyphAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.iconSize = 24,
    this.tapTarget = 40,
    this.overArt = false,
    this.color,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double iconSize;
  final double tapTarget;

  /// Whether the glyph is drawn directly on artwork and so needs the app's drop
  /// shadow to stay legible.
  final bool overArt;

  /// The resting colour. Defaults to [ZplayTokens.textPrimary] when the action
  /// is live and [ZplayTokens.textDisabled] when it is not.
  final Color? color;

  /// The app's glyph shadow over art: 0.6 black under a 0.9-white glyph, the
  /// constant `anime_page.dart` and the Home row both use.
  static const Shadow _shadow = Shadow(
    color: Color(0x99000000),
    blurRadius: 6,
    offset: Offset(0, 1),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resting = color ?? (onTap == null ? tokens.textDisabled : tokens.textPrimary);

    return FocusableCard(
      enabled: onTap != null,
      onTap: onTap,
      builder: (_, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: SizedBox(
          width: tapTarget,
          height: tapTarget,
          child: Icon(
            icon,
            size: iconSize,
            semanticLabel: semanticLabel,
            color: state.highlighted && onTap != null ? tokens.textPrimary : resting,
            shadows: overArt ? const [_shadow] : null,
          ),
        ),
      ),
    );
  }
}
