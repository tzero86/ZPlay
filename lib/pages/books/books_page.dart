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
import '../../widgets/common/focusable_card.dart';
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
                  child: _buildHeader(isMobile),
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

                // Catalog Title
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ZplaySpacing.s24,
                      ZplaySpacing.s8,
                      ZplaySpacing.s24,
                      ZplaySpacing.s16,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _searchController.text.trim().isNotEmpty
                              ? 'Results for "${_searchController.text.trim()}"'
                              : 'Discover Books',
                          style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                        ),
                        const Spacer(),
                        if (!_loading && _books.isNotEmpty)
                          Text(
                            '${_books.length} Books',
                            style: ZplayType.label.toStyle(color: tokens.textMuted),
                          ),
                      ],
                    ),
                  ),
                ),

                // Grid / Loading / Error
                if (_loading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: tokens.accent),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, color: tokens.danger, size: 48),
                          const SizedBox(height: ZplaySpacing.s12),
                          Text(_error!, style: ZplayType.body.toStyle(color: tokens.textEmphasis)),
                          const SizedBox(height: ZplaySpacing.s16),
                          ElevatedButton(
                            onPressed: () => _loadBooks(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
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
                          const SizedBox(height: 14),
                          Text(
                            'No books found',
                            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                          ),
                          const SizedBox(height: 6),
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
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isMobile ? 160 : 190,
                        mainAxisSpacing: 22,
                        crossAxisSpacing: 18,
                        childAspectRatio: 0.56,
                      ),
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
                      padding: const EdgeInsets.symmetric(vertical: 28),
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

  Widget _buildHeader(bool isMobile) {
    final tokens = context.tokens;
    // On a television the shelf does not name itself: Browse's own switcher
    // already says which vertical this is, and a 56 dp title row is 10% of a
    // 540 dp canvas spent repeating it. The search field is the row's real job
    // and keeps the space.
    final television = FormFactorService.of(context) == FormFactor.television;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        television ? ZplaySpacing.s12 : ZplaySpacing.s16,
        ZplaySpacing.s20,
        ZplaySpacing.s12,
      ),
      child: Row(
        children: [
          // Title
          if (!television) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(ZplaySpacing.s8),
                  decoration: BoxDecoration(
                    // The violet identity was the fork's, not the brand's: the
                    // monogram now follows the active palette's accent.
                    color: tokens.accentSubtle,
                    borderRadius: ZplayRadius.smAll,
                    border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.menu_book_rounded, color: tokens.accent, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'Books',
                  style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(width: ZplaySpacing.s20),
          ],

          // Search Bar
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay.withValues(alpha: 0.8),
                borderRadius: ZplayRadius.mdAll,
                border: Border.all(color: tokens.borderStrong),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search millions of books & authors...',
                  hintStyle: ZplayType.label.toStyle(color: tokens.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: tokens.textSecondary, size: 20),
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The e-reader's own control banner, per the prototype's
  /// `.reader-control-banner`: a font-engine selector on the left and the
  /// current type size / margin preset on the right.
  ///
  /// Every control here is backed by [ReaderSettings] — the same notifier the
  /// reader and its customisation sheet write — so a chip changes the text the
  /// reader actually renders rather than a local display flag.
  Widget _buildReaderControlBanner(bool isMobile) {
    final tokens = context.tokens;
    final television = FormFactorService.of(context) == FormFactor.television;
    final chipHeight = television ? ZplaySpacing.s48 : 36.0;

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

          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s12,
              vertical: ZplaySpacing.s8,
            ),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        Text(
                          'Font Engine:',
                          style: ZplayType.label
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(width: ZplaySpacing.s8),
                        for (final engine in _fontEngines) ...[
                          _ReaderChip(
                            label: engine.label,
                            selected: settings.fontFamily == engine.family,
                            height: chipHeight,
                            onTap: () =>
                                ReaderSettings.updateFontFamily(engine.family),
                          ),
                          const SizedBox(width: ZplaySpacing.s4),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s12),
                _ReaderChip(
                  label: sizeChipLabel,
                  selected: false,
                  height: chipHeight,
                  trailingIcon: Icons.expand_more_rounded,
                  onTap: () => ReaderCustomizationSheet.show(context),
                ),
              ],
            ),
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

  Widget _buildFilters() {
    final television = FormFactorService.of(context) == FormFactor.television;
    final chipHeight = television ? ZplaySpacing.s48 : 36.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s24,
        ZplaySpacing.s4,
        ZplaySpacing.s24,
        ZplaySpacing.s20,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // Format Filter Chips
            _buildFormatChip('All Formats', null, height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('EPUB', 'epub', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('PDF', 'pdf', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('MOBI', 'mobi', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('AZW3', 'azw3', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('FB2', 'fb2', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('TXT', 'txt', height: chipHeight),
            const SizedBox(width: ZplaySpacing.s8),
            _buildFormatChip('CBZ', 'cbz', height: chipHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatChip(String label, String? format, {required double height}) {
    return _ReaderChip(
      label: label,
      selected: _selectedFormat == format,
      height: height,
      onTap: () {
        setState(() => _selectedFormat = format);
        _loadBooks();
      },
    );
  }
}

/// A shelf chip: [FocusableCard] for the D-pad story, one accent ring on focus.
///
/// The 2 dp border is reserved in **every** state and painted only when
/// focused, which is what keeps the label from moving a pixel as focus arrives
/// and leaves no resting box around an idle chip. The prototype draws the same
/// thing with `border: 2px solid transparent` on `.atmosphere-chip`.
class _ReaderChip extends StatelessWidget {
  const _ReaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      // Own the chip: without excluding the descendants the label is announced
      // as a plain text item with no button or selected state on it.
      excludeSemantics: true,
      onTap: onTap,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) {
          return AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSubtle : tokens.surfaceRaised,
              borderRadius: ZplayRadius.xsAll,
              border: Border.all(
                color: state.focused ? tokens.accent : Colors.transparent,
                width: ZplaySpacing.s2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: ZplayType.bodySmall
                      .copyWith(weight: selected ? FontWeight.w700 : FontWeight.w500)
                      .toStyle(
                        color: selected
                            ? tokens.accent
                            : state.highlighted
                                ? tokens.textPrimary
                                : tokens.textEmphasis,
                      ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: ZplaySpacing.s4),
                  Icon(
                    trailingIcon,
                    size: ZplaySpacing.s16,
                    color: selected ? tokens.accent : tokens.textSecondary,
                  ),
                ],
              ],
            ),
          );
        },
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
          transform: Matrix4.translationValues(0, state.highlighted ? -4 : 0, 0),
          // The ring is drawn around the whole card, cover *and* caption, which
          // is what the prototype's `.manga-card` does with its permanent 2 dp
          // transparent border. No resting border, no accent glow, and a cover
          // shadow that does not change with focus, so focus adds exactly one
          // edge and moves nothing.
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
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
                      borderRadius: ZplayRadius.smAll,
                      boxShadow: [ReaderTokens.shadowMd],
                    ),
                    child: ClipRRect(
                      borderRadius: ZplayRadius.smAll,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: book.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: book.coverUrl,
                                    cacheManager: AppImageCache.manager,
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
                const SizedBox(height: ReaderTokens.space8),

                // Title
                Text(
                  book.displayTitle,
                  style: ZplayType.bodySmall
                      .copyWith(weight: FontWeight.w600)
                      .toStyle(color: tokens.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),

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
