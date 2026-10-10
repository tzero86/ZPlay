import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../models/book/book_result.dart';
import '../../models/book/reading_progress.dart';
import '../../services/books/continue_reading_service.dart';
import '../../services/books/reader_settings.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/window/window_service.dart';
import '../../services/discord/discord_rpc_service.dart';

class PdfReaderPage extends StatefulWidget {
  final File file;
  final BookResult book;
  final int initialPage;

  const PdfReaderPage({
    super.key,
    required this.file,
    required this.book,
    this.initialPage = 1,
  });

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  late final PdfViewerController _pdfController;
  int _currentPage = 1;
  int _pageCount = 1;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pdfController = PdfViewerController();
    DiscordRpcService.instance.setReadingBook(
      title: widget.book.title,
      author: widget.book.author,
      coverUrl: widget.book.coverUrl,
      page: _currentPage,
    );
    _startControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startControlsTimer();
    }
  }

  void _saveProgress(int page, int total) {
    if (total <= 0) return;
    final percent = (page / total).clamp(0.0, 1.0);

    final progress = ReadingProgress(
      md5: widget.book.md5,
      title: widget.book.displayTitle,
      author: widget.book.displayAuthor,
      coverUrl: widget.book.coverUrl,
      filePath: widget.file.path,
      fileType: 'pdf',
      chapterIndex: page - 1,
      scrollOffset: page.toDouble(),
      progressPercent: percent,
      totalChapters: total,
      totalPages: total,
      currentPage: page,
      lastReadAt: DateTime.now(),
    );

    ContinueReadingService.saveProgress(progress);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      if (_currentPage < _pageCount) {
        _pdfController.goToPage(pageNumber: _currentPage + 1);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      if (_currentPage > 1) {
        _pdfController.goToPage(pageNumber: _currentPage - 1);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      WindowService.instance.toggleFullscreen();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<ReaderSettingsData>(
      valueListenable: ReaderSettings.settingsNotifier,
      builder: (context, settings, _) {
        return Focus(
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: tokens.bg,
            body: Stack(
              children: [
                // ── PDF Viewer ──
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    child: PdfViewer.file(
                      widget.file.path,
                      controller: _pdfController,
                      initialPageNumber: widget.initialPage,
                      params: PdfViewerParams(
                        backgroundColor: tokens.surfaceRaised,
                        onPageChanged: (pageNumber) {
                          if (pageNumber != null) {
                            setState(() => _currentPage = pageNumber);
                            _saveProgress(pageNumber, _pageCount);
                          }
                        },
                        onViewerReady: (document, controller) {
                          setState(() {
                            _pageCount = document.pages.length;
                          });
                          _saveProgress(_currentPage, document.pages.length);
                        },
                      ),
                    ),
                  ),
                ),

                // ── Top Header Controls Overlay ──
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  top: _showControls ? 0 : -80,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
                    // The shared tinted chrome: the canvas at 0.82 with no
                    // hairline and no drop shadow. The old bar was opaque with a
                    // 1 dp bottom border and an elevation, which is the band the
                    // rest of the app has dropped; 0.82 is the same value Home's
                    // settled chrome uses, and it stays legible over a white PDF
                    // page where a fully transparent strip would not.
                    decoration: BoxDecoration(
                      color: tokens.bg.withValues(alpha: 0.82),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded, color: tokens.textPrimary, size: 20),
                          tooltip: 'Back to Library',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.book.displayTitle,
                                style: ZplayType.body
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: tokens.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.book.displayAuthor,
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.textEmphasis,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.zoom_in_rounded, color: tokens.textPrimary, size: 22),
                          tooltip: 'Zoom In',
                          onPressed: () => _pdfController.zoomUp(),
                        ),
                        IconButton(
                          icon: Icon(Icons.zoom_out_rounded, color: tokens.textPrimary, size: 22),
                          tooltip: 'Zoom Out',
                          onPressed: () => _pdfController.zoomDown(),
                        ),
                        IconButton(
                          icon: Icon(Icons.fullscreen_rounded, color: tokens.textPrimary, size: 24),
                          tooltip: 'Fullscreen (F)',
                          onPressed: () => WindowService.instance.toggleFullscreen(),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom Navigation Controls Overlay ──
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  bottom: _showControls ? 0 : -90,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s20),
                    // Tinted like the top bar, and no hairline: see it for why
                    // 0.82 rather than fully transparent.
                    decoration: BoxDecoration(
                      color: tokens.bg.withValues(alpha: 0.82),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left_rounded, color: tokens.textPrimary, size: 28),
                          tooltip: 'Previous Page',
                          onPressed: _currentPage > 1
                              ? () => _pdfController.goToPage(pageNumber: _currentPage - 1)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Page $_currentPage of $_pageCount',
                                    style: ZplayType.bodySmall
                                        .copyWith(weight: FontWeight.w600)
                                        .toStyle(color: tokens.textEmphasis),
                                  ),
                                  Text(
                                    '${((_currentPage / (_pageCount > 0 ? _pageCount : 1)) * 100).round()}%',
                                    style: ZplayType.bodySmall
                                        .copyWith(weight: FontWeight.w700)
                                        .toStyle(color: tokens.accent),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  activeTrackColor: tokens.accent,
                                  inactiveTrackColor: tokens.borderStrong,
                                  thumbColor: tokens.accent,
                                ),
                                child: Slider(
                                  value: _currentPage.toDouble(),
                                  min: 1,
                                  max: _pageCount > 1 ? _pageCount.toDouble() : 1.0,
                                  divisions: _pageCount > 1 ? _pageCount - 1 : 1,
                                  onChanged: (val) {
                                    final target = val.round();
                                    _pdfController.goToPage(pageNumber: target);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right_rounded, color: tokens.textPrimary, size: 28),
                          tooltip: 'Next Page',
                          onPressed: _currentPage < _pageCount
                              ? () => _pdfController.goToPage(pageNumber: _currentPage + 1)
                              : null,
                        ),
                      ],
                    ),
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
