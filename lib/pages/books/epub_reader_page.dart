import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/book/book_result.dart';
import '../../models/book/reading_progress.dart';
import '../../services/books/continue_reading_service.dart';
import '../../services/books/epub_parser_service.dart';
import '../../services/books/reader_settings.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/window/window_service.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../widgets/common/custom_scroll_track.dart';
import 'widgets/comic_reader_view.dart';
import 'widgets/epub_content_view.dart';
import 'widgets/focus_mode_view.dart';
import 'widgets/reader_customization_sheet.dart';
import 'widgets/reader_design_tokens.dart';

class EpubReaderPage extends StatefulWidget {
  final File file;
  final BookResult book;
  final int initialChapterIndex;
  final double initialScrollOffset;

  const EpubReaderPage({
    super.key,
    required this.file,
    required this.book,
    this.initialChapterIndex = 0,
    this.initialScrollOffset = 0.0,
  });

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _readerFocusNode = FocusNode();

  EpubBookData? _bookData;
  bool _loading = true;
  String? _error;

  int _currentChapterIndex = 0;
  bool _showChrome = false; // Zero chrome by default
  bool _isHoveringControls = false;
  Timer? _chromeTimer;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _scrollController.addListener(_onScrollChanged);
    _loadBook();
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _readerFocusNode.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onScrollChanged() {
    _saveProgress();
  }

  Future<void> _loadBook() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    DiscordRpcService.instance.setReadingBook(
      title: widget.book.title,
      author: widget.book.author,
      coverUrl: widget.book.coverUrl,
    );

    try {
      final parsed = await EpubParserService.instance.parseBook(
        widget.file,
        widget.book.bookFiletype,
      );

      if (!mounted) return;
      setState(() {
        _bookData = parsed;
        _loading = false;
        if (_currentChapterIndex >= parsed.totalChapters) {
          _currentChapterIndex = 0;
        }
      });

      DiscordRpcService.instance.setReadingBook(
        title: widget.book.title,
        author: widget.book.author,
        coverUrl: widget.book.coverUrl,
        page: _currentChapterIndex + 1,
        totalPages: parsed.totalChapters,
      );

      if (widget.initialScrollOffset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(widget.initialScrollOffset);
          }
        });
      }

      _saveProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to open "${widget.book.displayTitle}": $e';
        _loading = false;
      });
    }
  }

  void _onUserActivity() {
    if (!_showChrome) {
      setState(() => _showChrome = true);
    }
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showChrome && !_isHoveringControls) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() {
      _showChrome = !_showChrome;
    });

    _chromeTimer?.cancel();
    if (_showChrome) {
      _chromeTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showChrome && !_isHoveringControls) {
          setState(() => _showChrome = false);
        }
      });
    }
  }

  void _goToChapter(int target) {
    if (_bookData == null) return;
    if (target < 0 || target >= _bookData!.totalChapters) return;

    HapticFeedback.selectionClick();

    setState(() {
      _currentChapterIndex = target;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _saveProgress();
  }

  void _saveProgress() {
    if (_bookData == null) return;
    final total = _bookData!.totalChapters;
    final percent = total > 0 ? ((_currentChapterIndex + 1) / total).clamp(0.0, 1.0) : 0.0;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    final progress = ReadingProgress(
      md5: widget.book.md5,
      title: widget.book.displayTitle,
      author: widget.book.displayAuthor,
      coverUrl: widget.book.coverUrl,
      filePath: widget.file.path,
      fileType: widget.book.bookFiletype.isNotEmpty ? widget.book.bookFiletype : 'epub',
      chapterIndex: _currentChapterIndex,
      scrollOffset: offset,
      progressPercent: percent,
      totalChapters: total,
      totalPages: total,
      currentPage: _currentChapterIndex + 1,
      lastReadAt: DateTime.now(),
    );

    ContinueReadingService.saveProgress(progress);
  }

  Uint8List? _getComicPageImage() {
    if (_bookData == null || _currentChapterIndex >= _bookData!.chapters.length) return null;
    final ch = _bookData!.chapters[_currentChapterIndex];

    final key = 'page_$_currentChapterIndex.jpg';
    if (_bookData!.images.containsKey(key)) return _bookData!.images[key];

    final chImg = _bookData!.resolveImage(ch.href, ch.href);
    if (chImg != null) return chImg;

    final imgMatch = RegExp(r'<img[^>]+(?:src|href)="([^"]+)"', caseSensitive: false).firstMatch(ch.htmlContent);
    if (imgMatch != null) {
      final src = imgMatch.group(1)!;
      final resolved = _bookData!.resolveImage(src, ch.href);
      if (resolved != null) return resolved;
    }

    if (widget.book.isComic && _bookData!.images.isNotEmpty) {
      if (_currentChapterIndex < _bookData!.images.length) {
        return _bookData!.images.values.elementAt(_currentChapterIndex);
      }
    }

    return null;
  }

  String _getSamplePreviewText() {
    if (_bookData == null || _currentChapterIndex >= _bookData!.chapters.length) return '';
    final ch = _bookData!.chapters[_currentChapterIndex];
    final plain = ch.htmlContent.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.length > 200) {
      return '${plain.substring(0, 195)}...';
    }
    return plain;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _goToChapter(_currentChapterIndex + 1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _goToChapter(_currentChapterIndex - 1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (ReaderSettings.current.focusModeActive) {
        ReaderSettings.exitFocusMode();
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      WindowService.instance.toggleFullscreen();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _scaffoldKey.currentState?.openDrawer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return ValueListenableBuilder<ReaderSettingsData>(
      valueListenable: ReaderSettings.settingsNotifier,
      builder: (context, settings, _) {
        final comicImage = _getComicPageImage();
        final isComicMode = comicImage != null &&
            (widget.book.isComic ||
                _bookData!.chapters[_currentChapterIndex].wordCount == 0 ||
                _bookData!.chapters[_currentChapterIndex].htmlContent.contains('<img'));

        // If Focus Mode is active on text books
        if (settings.focusModeActive && !isComicMode && _bookData != null && _bookData!.chapters.isNotEmpty) {
          return FocusModeView(
            book: _bookData!,
            chapter: _bookData!.chapters[_currentChapterIndex],
            settings: settings,
            onExit: () => ReaderSettings.exitFocusMode(),
            onNextChapter: _currentChapterIndex < _bookData!.chapters.length - 1
                ? () => _goToChapter(_currentChapterIndex + 1)
                : null,
            onPrevChapter: _currentChapterIndex > 0
                ? () => _goToChapter(_currentChapterIndex - 1)
                : null,
          );
        }

        final total = _bookData?.totalChapters ?? 1;
        final current = _currentChapterIndex + 1;
        final overallProgress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

        return Focus(
          focusNode: _readerFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: isComicMode ? ReaderTokens.bg : settings.backgroundColor,
            drawer: _buildTocDrawer(),
            body: MouseRegion(
              onHover: (_) => _onUserActivity(),
              onEnter: (_) => _onUserActivity(),
              child: Stack(
                children: [
                  // ── Reader Content Canvas ──
                  Positioned.fill(
                    child: _loading
                        ? _buildSkeletonLoading(settings)
                        : _error != null
                            ? _buildErrorState(settings)
                            : _bookData == null || _bookData!.chapters.isEmpty
                                ? _buildEmptyState(settings)
                                : isComicMode
                                    ? ComicReaderView(
                                        imageBytes: comicImage,
                                        pageTitle: _bookData!.chapters[_currentChapterIndex].title,
                                        onNextPage: _currentChapterIndex < _bookData!.chapters.length - 1
                                            ? () => _goToChapter(_currentChapterIndex + 1)
                                            : null,
                                        onPrevPage: _currentChapterIndex > 0
                                            ? () => _goToChapter(_currentChapterIndex - 1)
                                            : null,
                                        onToggleControls: _toggleChrome,
                                        showControls: _showChrome,
                                      )
                                    : GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: _toggleChrome,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 780),
                                            child: SingleChildScrollView(
                                              controller: _scrollController,
                                              physics: const BouncingScrollPhysics(),
                                              padding: const EdgeInsets.only(
                                                top: 76,
                                                bottom: 96,
                                              ),
                                              child: EpubContentView(
                                                book: _bookData!,
                                                chapter: _bookData!.chapters[_currentChapterIndex],
                                                settings: settings,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                  ),

                  // ── In-App Brightness Dimmer Layer ──
                  if (settings.brightness < 0.99)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: ReaderTokens.bg.withValues(
                            alpha: 1.0 - settings.brightness,
                          ),
                        ),
                      ),
                    ),

                  // ── Top Bar Chrome with Gradient Scrim ──
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      offset: _showChrome ? Offset.zero : const Offset(0, -0.2),
                      duration: reduceMotion ? Duration.zero : ReaderTokens.motionChrome,
                      curve: ReaderTokens.curveChrome,
                      child: AnimatedOpacity(
                        opacity: _showChrome ? 1.0 : 0.0,
                        duration: reduceMotion ? Duration.zero : ReaderTokens.motionChrome,
                        curve: ReaderTokens.curveChrome,
                        child: IgnorePointer(
                          ignoring: !_showChrome,
                          child: MouseRegion(
                            onEnter: (_) {
                              _isHoveringControls = true;
                              _chromeTimer?.cancel();
                            },
                            onExit: (_) {
                              _isHoveringControls = false;
                              _onUserActivity();
                            },
                            child: _buildTopChrome(settings, isComicMode),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom Bar Chrome with Gradient Scrim ──
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      offset: _showChrome ? Offset.zero : const Offset(0, 0.2),
                      duration: reduceMotion ? Duration.zero : ReaderTokens.motionChrome,
                      curve: ReaderTokens.curveChrome,
                      child: AnimatedOpacity(
                        opacity: _showChrome ? 1.0 : 0.0,
                        duration: reduceMotion ? Duration.zero : ReaderTokens.motionChrome,
                        curve: ReaderTokens.curveChrome,
                        child: IgnorePointer(
                          ignoring: !_showChrome,
                          child: MouseRegion(
                            onEnter: (_) {
                              _isHoveringControls = true;
                              _chromeTimer?.cancel();
                            },
                            onExit: (_) {
                              _isHoveringControls = false;
                              _onUserActivity();
                            },
                            child: _buildBottomChrome(),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Custom Scroll Track (Desktop Only) ──
                  if (!isComicMode && !_loading && _error == null && _bookData != null && MediaQuery.sizeOf(context).width > 800)
                    Positioned(
                      right: 24,
                      bottom: 40,
                      child: CustomScrollTrack(controller: _scrollController),
                    ),

                // ── Hairline Progress Bar Pinned to Absolute Bottom (Always Visible) ──
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Stack(
                    children: [
                      // 2px track in 12% opacity
                      Container(
                        height: 2.0,
                        color: settings.textColor.withValues(alpha: 0.12),
                      ),
                      // 2px active indicator
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: overallProgress,
                        child: Container(
                          height: 2.0,
                          color: settings.accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  // ──────────────────────────────────────────────────────────────────────────
  // TOP CHROME (56px Height + 24px Gradient Scrim)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTopChrome(ReaderSettingsData settings, bool isComicMode) {
    final chapterTitle = _bookData != null && _currentChapterIndex < _bookData!.chapters.length
        ? _bookData!.chapters[_currentChapterIndex].title
        : widget.book.displayTitle;

    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ReaderTokens.bg.withValues(alpha: 0.94),
            ReaderTokens.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: ReaderTokens.space16),
        // **No band and no hairline.** The bar used to be an opaque
        // `surfaceRaised` strip with a bottom hairline under it, which is the
        // one chrome treatment the rest of the app has dropped: the reader's
        // chrome is now transparent over its page, and the gradient scrim above
        // (`ReaderTokens.bg`, 0.94 to 0) is what keeps the controls legible
        // without drawing a frame around them.
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: ReaderTokens.textPrimary,
                size: 18,
              ),
              tooltip: 'Back to Library',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: ReaderTokens.space4),
            IconButton(
              icon: Icon(
                Icons.menu_book_rounded,
                color: ReaderTokens.textPrimary,
                size: 20,
              ),
              tooltip: 'Table of Contents (T)',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const SizedBox(width: ReaderTokens.space12),

            // Book Title & Chapter Subtitle
            Expanded(
              child: Text(
                '${widget.book.displayTitle} · $chapterTitle',
                style: ZplayType.label
                    .copyWith(weight: FontWeight.w600)
                    .toStyle(color: ReaderTokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Text-Specific Controls
            if (!isComicMode) ...[
              IconButton(
                icon: Icon(
                  Icons.center_focus_strong_rounded,
                  color: settings.focusModeActive
                      ? ReaderTokens.accent
                      : ReaderTokens.textPrimary,
                  size: 20,
                ),
                tooltip: 'Focus Mode (Line-by-Line)',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ReaderSettings.toggleFocusMode();
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  color: ReaderTokens.textPrimary,
                  size: 20,
                ),
                tooltip: 'Appearance & Customization',
                onPressed: () => ReaderCustomizationSheet.show(
                  context,
                  realBookSampleText: _getSamplePreviewText(),
                ),
              ),
            ],

            IconButton(
              icon: Icon(
                Icons.fullscreen_rounded,
                color: ReaderTokens.textPrimary,
                size: 22,
              ),
              tooltip: 'Toggle Fullscreen (F)',
              onPressed: () => WindowService.instance.toggleFullscreen(),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BOTTOM CHROME (64px Height + 24px Gradient Scrim)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBottomChrome() {
    if (_bookData == null || _bookData!.totalChapters == 0) return const SizedBox.shrink();

    final total = _bookData!.totalChapters;
    final current = _currentChapterIndex + 1;
    final percent = ((current / total) * 100).round();

    final currentCh = _bookData!.chapters[_currentChapterIndex];
    final words = currentCh.wordCount;
    final minsLeft = words > 0 ? (words / 200).ceil() : 1;

    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            ReaderTokens.bg.withValues(alpha: 0.94),
            ReaderTokens.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: ReaderTokens.space16),
        // Transparent, like the top bar: the page shows through and the
        // gradient scrim below it carries the legibility. No hairline, no band.
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                color: ReaderTokens.textPrimary,
                size: 26,
              ),
              tooltip: 'Previous Chapter (Left Arrow)',
              onPressed: _currentChapterIndex > 0 ? () => _goToChapter(_currentChapterIndex - 1) : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ReaderTokens.space8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ch. $current of $total',
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w600)
                          .toStyle(color: ReaderTokens.textPrimary),
                    ),
                    Text(
                      '$percent% · ~$minsLeft min left',
                      style: ZplayType.bodySmall.toStyle(
                        color: ReaderTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right_rounded,
                color: ReaderTokens.textPrimary,
                size: 26,
              ),
              tooltip: 'Next Chapter (Right Arrow)',
              onPressed: _currentChapterIndex < total - 1 ? () => _goToChapter(_currentChapterIndex + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STATES: SKELETON LOADING, ERROR, EMPTY
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSkeletonLoading(ReaderSettingsData settings) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 28,
                width: 220,
                decoration: BoxDecoration(
                  color: settings.textColor.withValues(alpha: ZplayOpacity.borderDefault),
                  borderRadius: ReaderTokens.rounded8,
                ),
              ),
              const SizedBox(height: ReaderTokens.space32),
              for (int i = 0; i < 6; i++) ...[
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: settings.textColor.withValues(alpha: ZplayOpacity.borderSubtle),
                    borderRadius: ReaderTokens.rounded4,
                  ),
                ),
                const SizedBox(height: ReaderTokens.space12),
              ],
              Container(
                height: 16,
                width: 180,
                decoration: BoxDecoration(
                  color: settings.textColor.withValues(alpha: ZplayOpacity.borderSubtle),
                  borderRadius: ReaderTokens.rounded4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(ReaderSettingsData settings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ReaderTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, color: ReaderTokens.danger, size: 48),
            const SizedBox(height: ReaderTokens.space16),
            Text(
              _error ?? 'Unable to open book',
              style: ZplayType.body.toStyle(color: settings.textColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ReaderTokens.space24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Library'),
                ),
                const SizedBox(width: ReaderTokens.space12),
                FilledButton(
                  onPressed: _loadBook,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ReaderSettingsData settings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ReaderTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_books_rounded, color: settings.secondaryTextColor, size: 48),
            const SizedBox(height: ReaderTokens.space16),
            Text(
              'No readable chapters found.',
              style: ZplayType.body.toStyle(
                color: settings.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TABLE OF CONTENTS DRAWER
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTocDrawer() {
    final toc = _bookData?.tableOfContents ?? [];

    return Drawer(
      backgroundColor: ReaderTokens.surfaceOverlay,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The drawer's title row, with no rule under it: the drawer's own
            // scrim separates it from the list, and the list's first row starts
            // the content.
            Padding(
              padding: const EdgeInsets.all(ReaderTokens.space24),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    color: ReaderTokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: ReaderTokens.space12),
                  Text(
                    'Table of Contents',
                    style: ZplayType.title.toStyle(
                      color: ReaderTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: toc.isEmpty
                  ? Center(
                      child: Text(
                        'No table of contents available',
                        style: ZplayType.bodySmall.toStyle(
                          color: ReaderTokens.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: toc.length,
                      itemBuilder: (context, idx) {
                        final item = toc[idx];
                        final isSelected = item.chapterIndex == _currentChapterIndex;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: ReaderTokens.space24,
                            vertical: ReaderTokens.space4,
                          ),
                          leading: Text(
                            '${idx + 1}',
                            style: ZplayType.caption
                                .copyWith(
                                  weight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                )
                                .toStyle(
                                  color: isSelected
                                      ? ReaderTokens.accent
                                      : ReaderTokens.textSecondary,
                                ),
                          ),
                          title: Text(
                            item.title,
                            style: ZplayType.label
                                .copyWith(
                                  weight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                )
                                .toStyle(
                                  color: isSelected
                                      ? ReaderTokens.accent
                                      : ReaderTokens.textPrimary,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: ReaderTokens.accent,
                                  size: 18,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(context).pop();
                            _goToChapter(item.chapterIndex);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
