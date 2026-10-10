import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/book/book_result.dart';
import '../../services/books/bookracy_service.dart';
import '../../services/books/continue_reading_service.dart';
import '../../services/books/reader_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/card_badges.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/tab_strip.dart';
import 'book_detail_sheet.dart';
import 'widgets/continue_reading_slider.dart';
import 'widgets/reader_customization_sheet.dart';
import 'widgets/reader_design_tokens.dart';
import '../../services/storage/app_image_cache.dart';

/// One entry of the shelf's font-engine selector.
///
/// The prototype names Kindle's *Bookerly Serif*; the reader ships Georgia as
/// its serif (`ReaderTokens.defaultSerifFont`) and has no Bookerly face, so the
/// slot carries the face that actually renders. The other two are shipped as
/// named.
@immutable
class _FontEngine {
  const _FontEngine(this.label, this.family);

  final String label;

  /// The value written to `ReaderSettingsData.fontFamily`.
  final String family;
}

const List<_FontEngine> _fontEngines = [
  _FontEngine('Poppins', 'Poppins'),
  _FontEngine('Georgia Serif', ReaderTokens.defaultSerifFont),
  _FontEngine('OpenDyslexic', 'OpenDyslexic'),
];

class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BookResult> _books = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String _currentQuery = 'fantasy';
  String? _selectedFormat; // 'epub', 'pdf', or null for all
  int _currentPage = 1;
  bool _hasMore = true;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_loadingMore && !_loading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadBooks({bool resetPage = true}) async {
    if (resetPage) {
      _currentPage = 1;
      _hasMore = true;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await BookracyService.instance.searchBooks(
        query: _currentQuery,
        page: _currentPage,
        limit: 80,
        formatFilter: _selectedFormat,
      );

      if (!mounted) return;
      setState(() {
        _books = results;
        _loading = false;
        _hasMore = results.length >= 20;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load books: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      _currentPage++;
      final more = await BookracyService.instance.searchBooks(
        query: _currentQuery,
        page: _currentPage,
        limit: 80,
        formatFilter: _selectedFormat,
      );

      if (!mounted) return;
      setState(() {
        _books.addAll(more);
        _loadingMore = false;
        if (more.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 380), () {
      final trimmed = query.trim();
      setState(() {
        _currentQuery = trimmed.isNotEmpty ? trimmed : 'fantasy';
      });
      _loadBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Ambient Animated Background ──
          const Positioned.fill(
            child: AnimatedAmbientBackground(),
          ),

          // ── Main Content ──
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Top App Bar & Search Header
                SliverToBoxAdapter(
                  child: _buildHeader(),
                ),

                // E-Reader control banner: font engine + type size/margins
                SliverToBoxAdapter(
                  child: _buildReaderControlBanner(isMobile),
                ),

                // Filters (Language & Formats)
                SliverToBoxAdapter(
                  child: _buildFilters(),
                ),

                // Continue Reading Horizontal Slider
                const SliverToBoxAdapter(
                  child: ContinueReadingSlider(),
                ),

                // Catalog Title. The shared rail header, so the shelf's heading
                // is the same object every other rail in the app uses: one
                // semibold title and a muted tabular count, with no accent bar
                // and no box. The header bakes a 16 dp inset of its own; the
                // 8 dp either side below add up to the grid's 24 dp gutter, so
                // the heading and the covers land on the same line.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ZplaySpacing.s8,
                      ZplaySpacing.s8,
                      ZplaySpacing.s8,
                      ZplaySpacing.s4,
                    ),
                    child: SectionHeader(
                      title: _searchController.text.trim().isNotEmpty
                          ? 'Results for "${_searchController.text.trim()}"'
                          : 'Discover Books',
                      count:
                          !_loading && _books.isNotEmpty ? _books.length : null,
                    ),
                  ),
                ),

                // Grid / Loading / Error
                if (_loading)
                  _BooksSkeleton(isMobile: isMobile)
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(
                      title: 'Could not load books',
                      error: _error,
                      onRetry: () => _loadBooks(),
                    ),
                  )
                else if (_books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, color: tokens.textMuted, size: 56),
                          const SizedBox(height: ZplaySpacing.s12),
                          Text(
                            'No books found',
                            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            'Try searching for another title, author, or language',
                            style: ZplayType.label.toStyle(color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                    sliver: SliverGrid(
                      gridDelegate: _booksGridDelegate(isMobile),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final book = _books[index];
                          return _BookCard(
                            book: book,
                            onTap: () => BookDetailSheet.show(context, book),
                          );
                        },
                        childCount: _books.length,
                      ),
                    ),
                  ),

                // Loading More Indicator
                if (_loadingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s32),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                  ),

                SliverToBoxAdapter(
                  // The SafeArea above is bottom:false, so the trailing gap carries the gesture inset.
                  child: SizedBox(height: ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom),
                ),
              ],
            ),
          ),
          // ── Custom Scroll Track (Desktop Only) ──
          if (MediaQuery.sizeOf(context).width > 800)
            Positioned(
              right: 24,
              bottom: 40,
              child: CustomScrollTrack(controller: _scrollController),
            ),

        ],
      ),
    );
  }

  /// The page's own control row.
  ///
  /// It is the search field and nothing else. The boxed "Books" chip that used
  /// to lead this row is gone for the reason Anime's brand pill is gone: the
  /// shell's top bar carries the brand and Browse's own switcher already says
  /// which vertical is showing, so a second named box here was 10% of a 540 dp
  /// canvas spent repeating chrome the user is already looking at. The search
  /// field was always the row's real job and now keeps the space.
  ///
  /// The field is the shared one - the same fill, radius and hairline the
  /// Search page types into - and it is capped at 540 dp and anchored left, so
  /// it reads as a field rather than as a banner spanning a television.
  Widget _buildHeader() {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        ZplaySpacing.s16,
        ZplaySpacing.s20,
        ZplaySpacing.s12,
      ),
      // Capped and left-anchored, so the field reads as a field rather than as
      // a banner spanning a 960 dp television.
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            width: double.infinity,
            height: 42,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.fromBorderSide(tokens.hairline),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search millions of books & authors...',
                hintStyle: ZplayType.body.toStyle(color: tokens.textDisabled),
                prefixIcon: Icon(Icons.search_rounded, color: tokens.textMuted, size: 19),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: tokens.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s12,
                  vertical: ZplaySpacing.s12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The e-reader's own control banner: the font-engine selector and the
  /// current type size / margin preset, which opens the customisation sheet.
  ///
  /// Every control here is backed by [ReaderSettings] — the same notifier the
  /// reader and its customisation sheet write — so a selection changes the text
  /// the reader actually renders rather than a local display flag.
  ///
  /// It paints no band. The opaque `tokens.surface` box that used to wrap this
  /// row made a strip of selectors read as a toolbar sitting on the page; the
  /// selectors are the shared [TabStrip] now, which paints nothing at rest and
  /// marks the chosen engine with an accent bar under its label, and the single
  /// action beside them is a [PillButton] — the app's one call-to-action shape.
  /// [CardFocusRing] is the only edge either control ever draws.
  Widget _buildReaderControlBanner(bool isMobile) {
    final tokens = context.tokens;
    final television = FormFactorService.of(context) == FormFactor.television;
    final stripHeight = television ? ZplaySpacing.s48 : 44.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s24,
        0,
        ZplaySpacing.s24,
        ZplaySpacing.s12,
      ),
      child: ValueListenableBuilder<ReaderSettingsData>(
        valueListenable: ReaderSettings.settingsNotifier,
        builder: (context, settings, _) {
          final sizeChipLabel = isMobile
              ? '${settings.fontSize.round()} pt · ${_marginLabel(settings.marginPreset)}'
              : 'Font Size: ${settings.fontSize.round()} pt · '
                  'Margins: ${_marginLabel(settings.marginPreset)}';

          return Row(
            children: [
              // The label is a hint, not a control, so it is muted type with no
              // box; on a phone the pills are self-describing and the space is
              // worth more to the selectors.
              if (!isMobile) ...[
                Text(
                  'Font Engine:',
                  style: ZplayType.label
                      .copyWith(weight: FontWeight.w600)
                      .toStyle(color: tokens.textMuted),
                ),
                const SizedBox(width: ZplaySpacing.s12),
              ],
              Expanded(
                child: TabStrip<String>(
                  options: [
                    for (final engine in _fontEngines)
                      TabStripOption<String>(
                        value: engine.family,
                        label: engine.label,
                      ),
                  ],
                  selected: settings.fontFamily,
                  onSelected: ReaderSettings.updateFontFamily,
                  semanticsLabel: 'Reader font engine',
                  height: stripHeight,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              PillButton(
                label: sizeChipLabel,
                variant: PillVariant.secondary,
                icon: Icons.tune_rounded,
                onPressed: () => ReaderCustomizationSheet.show(context),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _marginLabel(MarginPreset preset) => switch (preset) {
    MarginPreset.compact => 'Compact',
    MarginPreset.balanced => 'Standard',
    MarginPreset.wide => 'Wide',
  };

  /// The format filter, as the shared [TabStrip].
  ///
  /// Eight short, data-driven options that do not fit on a phone: the control
  /// TabStrip exists for. It paints no fill and no edge of its own — the accent
  /// bar under the selected label says which format is on, so the shelf no
  /// longer carries a row of filled chips that read as buttons.
  Widget _buildFilters() {
    final television = FormFactorService.of(context) == FormFactor.television;
    final stripHeight = television ? ZplaySpacing.s48 : 44.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s24,
        ZplaySpacing.s4,
        ZplaySpacing.s24,
        ZplaySpacing.s16,
      ),
      child: TabStrip<String?>(
        options: const [
          TabStripOption<String?>(value: null, label: 'All Formats'),
          TabStripOption<String?>(value: 'epub', label: 'EPUB'),
          TabStripOption<String?>(value: 'pdf', label: 'PDF'),
          TabStripOption<String?>(value: 'mobi', label: 'MOBI'),
          TabStripOption<String?>(value: 'azw3', label: 'AZW3'),
          TabStripOption<String?>(value: 'fb2', label: 'FB2'),
          TabStripOption<String?>(value: 'txt', label: 'TXT'),
          TabStripOption<String?>(value: 'cbz', label: 'CBZ'),
        ],
        selected: _selectedFormat,
        onSelected: (format) {
          setState(() => _selectedFormat = format);
          _loadBooks();
        },
        semanticsLabel: 'Book formats',
        height: stripHeight,
      ),
    );
  }
}

/// The shelf's grid geometry, in one place: the live grid and the skeleton are
/// laid out from this, so the placeholder covers land exactly where the real
/// cards do and the page does not shift when the first page arrives.
SliverGridDelegate _booksGridDelegate(bool isMobile) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: isMobile ? 160 : 190,
      mainAxisSpacing: 22,
      crossAxisSpacing: 18,
      childAspectRatio: 0.56,
    );

/// What the shelf looks like while its first page is in flight.
///
/// It replaced a lone [CircularProgressIndicator] centred in an otherwise empty
/// canvas, which on a television is the entire interface for the first seconds
/// and says nothing about what is coming. The shapes are the grid's real ones -
/// a cover box and its caption bars at the geometry the cards will actually
/// arrive at - so nothing moves when they land. Home's `_HomeSkeleton` and
/// Anime's skeleton are the precedent.
class _BooksSkeleton extends StatelessWidget {
  final bool isMobile;

  const _BooksSkeleton({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
      sliver: SliverGrid(
        gridDelegate: _booksGridDelegate(isMobile),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                  ),
                ),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: const SizedBox(height: 12),
              ),
              const SizedBox(height: ZplaySpacing.s4),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.xsAll,
                    ),
                    child: const SizedBox(height: 10),
                  ),
                ),
              ),
            ],
          ),
          childCount: 8,
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final BookResult book;
  final VoidCallback onTap;

  const _BookCard({
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = ContinueReadingService.getProgress(book.md5);
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) {
        return AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          // Lift answers the *pointer*, matching the shared card: a D-pad press
          // must not nudge the cover the user is aiming at, and the ring is what
          // marks focus. The card used to lift on focus too, which contradicted
          // its own note about focus adding exactly one edge.
          transform: Matrix4.translationValues(0, state.hovered ? -3 : 0, 0),
          // The ring is drawn around the whole card, cover *and* caption. One
          // edge, no resting border, no accent glow, and a cover shadow that
          // does not change with focus, so focus adds the ring and moves
          // nothing. The radius is the shared card radius, so a book tile and a
          // film poster round to the same shape.
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.mdAll,
            child: Column(
              // `stretch`, because the ring's stack lays its child out with
              // loosened constraints: without it the card would size to its
              // widest child instead of to the grid cell it was given.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover Artwork
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [ReaderTokens.shadowMd],
                    ),
                    child: ClipRRect(
                      borderRadius: ZplayRadius.mdAll,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: book.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: book.coverUrl,
                                    cacheManager: AppImageCache.manager,
                                    // The cover box is ~190 dp at its widest;
                                    // bound the decode to ~3x so a shelf of
                                    // covers does not hold full-resolution art.
                                    memCacheWidth: 570,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: tokens.surface,
                                      child: Center(
                                        child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: tokens.surface,
                                      child: Center(
                                        child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                      ),
                                    ))
                                : Container(
                                    color: tokens.surface,
                                    child: Center(
                                      child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                    ),
                                  ),
                          ),

                          // Format badge, revealed while focused. The prototype's
                          // card anatomy puts the type badge on the focused card
                          // and leaves a resting card bare; it is `Positioned`, so
                          // appearing moves nothing.
                          if (state.focused)
                            Positioned(
                              top: ZplaySpacing.s8,
                              left: ZplaySpacing.s8,
                              child: CardTypeBadge(
                                label: book.bookFiletype.toUpperCase(),
                              ),
                            ),

                          // Year Tag Bottom-Right if available
                          if (book.year.isNotEmpty)
                            Positioned(
                              bottom: ZplaySpacing.s8,
                              right: ZplaySpacing.s8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s4,
                                  vertical: ZplaySpacing.s2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.bg.withValues(alpha: 0.75),
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                                child: Text(
                                  book.year,
                                  style: ZplayType.caption.toStyle(color: tokens.textEmphasis),
                                ),
                              ),
                            ),

                          // In-Progress Bar directly on Cover Bottom Edge. The
                          // clip rounds it with the cover, so it needs no radius
                          // of its own.
                          if (progress != null && progress.progressPercent > 0.01)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(
                                value: progress.progressPercent,
                                minHeight: ZplaySpacing.s4,
                                backgroundColor: tokens.bg.withValues(alpha: 0.5),
                                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s8),

                // Title
                Text(
                  book.displayTitle,
                  style: ZplayType.bodySmall
                      .copyWith(weight: FontWeight.w600)
                      .toStyle(color: tokens.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: ZplaySpacing.s2),

                // Author, and the prototype's "64% read" reading-progress caption.
                Text(
                  progress != null && progress.progressPercent > 0.01
                      ? '${book.displayAuthor} · ${(progress.progressPercent * 100).round()}% read'
                      : book.displayAuthor,
                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
