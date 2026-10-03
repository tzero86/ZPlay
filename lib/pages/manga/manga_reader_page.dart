import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/manga/manga.dart';
import '../../models/manga/manga_chapter.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/manga/manga_service.dart';
import '../../services/manga/manga_settings.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../services/storage/app_image_cache.dart';
import 'widgets/manga_reader_controls.dart';

class MangaReaderPage extends StatefulWidget {
  final Manga manga;
  final List<MangaChapter> chapters;
  final int currentChapterIndex;
  final int resumePageIndex;

  const MangaReaderPage({
    super.key,
    required this.manga,
    required this.chapters,
    required this.currentChapterIndex,
    this.resumePageIndex = 0,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  final MangaService _mangaService = MangaService();
  final FocusNode _focusNode = FocusNode();

  late int _currentChapterIndex;
  late int _currentPageIndex;

  List<String> _pageUrls = [];
  bool _isLoading = true;
  bool _showOverlay = true;
  bool _showDeckDrawer = false;

  late MangaReadingMode _readingMode;

  PageController? _pageController;
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _deckScrollController = ScrollController();
  final TransformationController _transformationController = TransformationController();

  double _currentZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.currentChapterIndex;
    _currentPageIndex = widget.resumePageIndex;
    _readingMode = MangaSettings.defaultReadingMode.value;

    _initPageController();
    _verticalScrollController.addListener(_onVerticalScroll);
    MangaSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    _loadChapter();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _initPageController() {
    _pageController?.dispose();
    _pageController = PageController(initialPage: _currentPageIndex);
  }

  @override
  void dispose() {
    MangaSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _focusNode.dispose();
    _pageController?.dispose();
    _verticalScrollController.dispose();
    _deckScrollController.dispose();
    _transformationController.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  Matrix4 _buildCenterScaleMatrix(double scale, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    return Matrix4.identity()
      ..translate(cx, cy)
      ..scale(scale)
      ..translate(-cx, -cy);
  }

  void _zoomIn() {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _currentZoom = (_currentZoom + 0.25).clamp(0.25, 5.0);
      if ((_currentZoom - 1.0).abs() < 0.05) {
        _currentZoom = 1.0;
        _transformationController.value = Matrix4.identity();
      } else {
        _transformationController.value = _buildCenterScaleMatrix(_currentZoom, size);
      }
    });
  }

  void _zoomOut() {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _currentZoom = (_currentZoom - 0.25).clamp(0.25, 5.0);
      if ((_currentZoom - 1.0).abs() < 0.05) {
        _currentZoom = 1.0;
        _transformationController.value = Matrix4.identity();
      } else {
        _transformationController.value = _buildCenterScaleMatrix(_currentZoom, size);
      }
    });
  }

  void _resetZoom() {
    setState(() {
      _currentZoom = 1.0;
      _transformationController.value = Matrix4.identity();
    });
  }

  Future<void> _loadChapter() async {
    _resetZoom();
    setState(() => _isLoading = true);

    final chapter = widget.chapters[_currentChapterIndex];
    DiscordRpcService.instance.setReadingManga(
      title: widget.manga.title,
      chapter: chapter.name.isNotEmpty ? chapter.name : 'Chapter ${chapter.number}',
      coverUrl: widget.manga.coverNormal.isNotEmpty ? widget.manga.coverNormal : widget.manga.coverSmall,
    );
    final urls = await _mangaService.getChapterImages(chapter.id);

    if (mounted) {
      setState(() {
        _pageUrls = urls;
        _isLoading = false;

        if (urls.isNotEmpty && _currentPageIndex >= urls.length) {
          _currentPageIndex = 0;
        }
      });

      // Keep the chapter warm without decoding every page full-res: the deck
      // needs all thumbs anyway, so precache those (memCacheWidth 140 like the
      // deck). The display widgets below bound pages to 2x screen width, so
      // precache current + adjacent with that same bound — same ResizeImage
      // key, no second decode.
      final pageCacheWidth =
          (MediaQuery.sizeOf(context).width * 2).round().clamp(96, 2048).toInt();
      for (final url in urls) {
        precacheImage(
          ResizeImage.resizeIfNeeded(
            140,
            null,
            CachedNetworkImageProvider(url, cacheManager: AppImageCache.manager),
          ),
          context,
        );
      }
      for (var i = _currentPageIndex - 2; i <= _currentPageIndex + 2; i++) {
        if (i < 0 || i >= urls.length) continue;
        precacheImage(
          ResizeImage.resizeIfNeeded(
            pageCacheWidth,
            null,
            CachedNetworkImageProvider(urls[i], cacheManager: AppImageCache.manager),
          ),
          context,
        );
      }

      if (_pageController?.hasClients ?? false) {
        _pageController!.jumpToPage(_currentPageIndex);
      } else {
        _initPageController();
      }

      _saveProgress();
      _scrollToCurrentPageInDeck();
    }
  }

  void _saveProgress() {
    _mangaService.saveProgress(
      widget.manga,
      _currentChapterIndex,
      _currentPageIndex,
      widget.chapters,
    );
  }

  void _scrollToCurrentPageInDeck() {
    if (!_showDeckDrawer || !_deckScrollController.hasClients || _pageUrls.isEmpty) return;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;
    final isVerySmall = screenW < 420;
    final cardW = (isVerySmall ? 52.0 : (isMobile ? 60.0 : 74.0)) + 8.0;
    final target = (_currentPageIndex * cardW) - (screenW / 2) + (cardW / 2);
    _deckScrollController.animateTo(
      target.clamp(0.0, _deckScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _onVerticalScroll() {
    if (_readingMode != MangaReadingMode.webtoon || _pageUrls.isEmpty) return;

    final offset = _verticalScrollController.offset;
    final estimatedIndex = (offset / 900).floor().clamp(0, _pageUrls.length - 1);

    if (estimatedIndex != _currentPageIndex) {
      setState(() => _currentPageIndex = estimatedIndex);
      _saveProgress();
      _scrollToCurrentPageInDeck();
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPageIndex = index);
    _saveProgress();
    _scrollToCurrentPageInDeck();
  }

  void _jumpToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageUrls.length) return;
    setState(() => _currentPageIndex = pageIndex);

    if (_readingMode == MangaReadingMode.webtoon) {
      if (_verticalScrollController.hasClients) {
        final targetOffset = pageIndex * 900.0;
        _verticalScrollController.animateTo(
          targetOffset.clamp(0.0, _verticalScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    } else {
      if (_pageController?.hasClients ?? false) {
        _pageController!.jumpToPage(pageIndex);
      }
    }
    _saveProgress();
    _scrollToCurrentPageInDeck();
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
      if (!_showOverlay) _showDeckDrawer = false;
    });
  }

  void _toggleDeckDrawer() {
    setState(() {
      _showDeckDrawer = !_showDeckDrawer;
    });
    if (_showDeckDrawer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentPageInDeck();
      });
    }
  }

  void _nextChapter() {
    if (_currentChapterIndex > 0) {
      setState(() {
        _currentChapterIndex--;
        _currentPageIndex = 0;
      });
      _loadChapter();
    }
  }

  void _prevChapter() {
    if (_currentChapterIndex < widget.chapters.length - 1) {
      setState(() {
        _currentChapterIndex++;
        _currentPageIndex = 0;
      });
      _loadChapter();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return;
    }

    if (_readingMode == MangaReadingMode.horizontalLtr) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.space) {
        if (_currentPageIndex < _pageUrls.length - 1) {
          _pageController?.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        } else {
          _nextChapter();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_currentPageIndex > 0) {
          _pageController?.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        } else {
          _prevChapter();
        }
      }
    } else if (_readingMode == MangaReadingMode.horizontalRtl) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.space) {
        if (_currentPageIndex < _pageUrls.length - 1) {
          _pageController?.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        } else {
          _nextChapter();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_currentPageIndex > 0) {
          _pageController?.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        } else {
          _prevChapter();
        }
      }
    }
  }

  void _showReaderCustomizer(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;

    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 490),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: palette.primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Reader Settings & Layout',
                        style: ZplayType.title
                            .copyWith(weight: FontWeight.w700)
                            .toStyle(color: tokens.textPrimary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: tokens.borderDefault),
                  const SizedBox(height: 12),

                  Text('Reading Orientation Mode', style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary)),
                  const SizedBox(height: 8),
                  SegmentedTabs<MangaReadingMode>(
                    semanticsLabel: 'Reading orientation mode',
                    selected: _readingMode,
                    onSelected: (mode) {
                      setState(() => _readingMode = mode);
                      MangaSettings.setDefaultReadingMode(mode);
                      _initPageController();
                    },
                    options: [
                      for (final mode in MangaReadingMode.values)
                        SegmentedTabOption(value: mode, label: mode.label),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Text('Page Reading Width Constraint', style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<MangaReaderMaxWidth>(
                    valueListenable: MangaSettings.readerMaxWidth,
                    builder: (context, width, _) {
                      return SegmentedTabs<MangaReaderMaxWidth>(
                        semanticsLabel: 'Page reading width constraint',
                        selected: width,
                        onSelected: MangaSettings.setReaderMaxWidth,
                        options: [
                          for (final option in MangaReaderMaxWidth.values)
                            SegmentedTabOption(
                              value: option,
                              label: option.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  Text('Reader Background Atmosphere', style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary)),
                  const SizedBox(height: 8),
                  const MangaAtmosphereChips(showLabel: false),

                  const SizedBox(height: 14),

                  ValueListenableBuilder<bool>(
                    valueListenable: MangaSettings.showPageDeck,
                    builder: (context, showDeck, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show Page Deck Previews Drawer', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        value: showDeck,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => MangaSettings.setShowPageDeck(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: MangaSettings.enableNextChapterDeck,
                    builder: (context, showNext, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show Next Chapter Deck Card', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
                        value: showNext,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => MangaSettings.setEnableNextChapterDeck(val),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapterTitle = widget.chapters[_currentChapterIndex].name.isNotEmpty
        ? widget.chapters[_currentChapterIndex].name
        : 'Chapter ${widget.chapters[_currentChapterIndex].number}';

    final tokens = context.tokens;
    final readerBg = MangaSettings.readerBackground.value.color;
    final palette = AppThemeService.currentPalette.value;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: readerBg,
        body: Stack(
          children: [
            // Main Interactive Zoom & Pan Reader Container
            GestureDetector(
              onTap: _toggleOverlay,
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: palette.primaryColor),
                    )
                  : _pageUrls.isEmpty
                      ? Center(
                          child: Text(
                            'No pages found for this chapter.',
                            style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                          ),
                        )
                      : InteractiveViewer(
                          transformationController: _transformationController,
                          minScale: 0.25,
                          maxScale: 5.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          clipBehavior: Clip.none,
                          onInteractionUpdate: (_) {
                            final s = _transformationController.value.getMaxScaleOnAxis();
                            if ((s - _currentZoom).abs() > 0.05) {
                              setState(() => _currentZoom = s);
                            }
                          },
                          child: _readingMode == MangaReadingMode.webtoon
                              ? _buildVerticalWebtoonReader()
                              : _buildHorizontalPageView(),
                        ),
            ),

            // Custom Vertical Scroller for Webtoon Mode (Desktop only, removed for mobile)
            if (_readingMode == MangaReadingMode.webtoon &&
                !_isLoading &&
                _pageUrls.isNotEmpty &&
                MangaSettings.showScrollTrack.value &&
                !(Platform.isAndroid || Platform.isIOS) &&
                MediaQuery.sizeOf(context).width >= 700)
              Positioned(
                right: 20,
                top: 100,
                bottom: 100,
                child: Center(
                  child: CustomScrollTrack(
                    controller: _verticalScrollController,
                    axis: Axis.vertical,
                    length: 320.0,
                  ),
                ),
              ),

            // Top Header Overlay
            if (_showOverlay)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(chapterTitle),
              ),

            // Bottom Navigation & Controls Overlay (Cohesive & Fully Responsive with Page Deck above slider)
            if (_showOverlay)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(),
              ),
          ],
        ),
      ),
    );
  }

  // 1. Horizontal Reading Mode (LTR & RTL)
  Widget _buildHorizontalPageView() {
    final tokens = context.tokens;
    final maxWidth = MangaSettings.readerMaxWidth.value.width;
    final isRtl = _readingMode == MangaReadingMode.horizontalRtl;

    Widget pageView = PageView.builder(
      controller: _pageController,
      reverse: isRtl,
      physics: _currentZoom > 1.05
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      itemCount: _pageUrls.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
            child: CachedNetworkImage(
              imageUrl: _pageUrls[index],
              cacheManager: AppImageCache.manager,
              // Page view keeps one full-res page; 2x screen width stays crisp
              // under the 5x zoom InteractiveViewer while bounding the decode.
              memCacheWidth: (MediaQuery.sizeOf(context).width * 2).round().clamp(96, 2048).toInt(),
              fit: BoxFit.contain,
              placeholder: (context, url) => Center(
                child: CircularProgressIndicator(color: tokens.textDisabled),
              ),
              errorWidget: (context, url, error) => Center(
                child: Icon(Icons.broken_image_rounded, color: tokens.textMuted, size: 48),
              )),
          ),
        );
      },
    );

    return pageView;
  }

  // 2. Vertical Webtoon Continuous Scroll Mode
  Widget _buildVerticalWebtoonReader() {
    final tokens = context.tokens;
    final maxWidth = MangaSettings.readerMaxWidth.value.width;
    final pageGap = MangaSettings.pageGap.value;
    final showNextDeck = MangaSettings.enableNextChapterDeck.value;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: ListView.builder(
          controller: _verticalScrollController,
          physics: _currentZoom > 1.05
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          itemCount: _pageUrls.length + 1,
          itemBuilder: (context, index) {
            if (index == _pageUrls.length) {
              if (!showNextDeck) {
                return const SizedBox(height: 80);
              }
              return _buildNextChapterDeckCard();
            }

            return Container(
              margin: EdgeInsets.only(bottom: pageGap),
              child: CachedNetworkImage(
                imageUrl: _pageUrls[index],
                cacheManager: AppImageCache.manager,
                // Webtoon strip keeps full-res (2x screen, <=2048) for 5x zoom.
                memCacheWidth: (MediaQuery.sizeOf(context).width * 2).round().clamp(96, 2048).toInt(),
                fit: BoxFit.fitWidth,
                placeholder: (context, url) => SizedBox(
                  height: 350,
                  child: Center(
                    child: CircularProgressIndicator(color: tokens.textDisabled),
                  ),
                ),
                errorWidget: (context, url, error) => SizedBox(
                  height: 200,
                  child: Center(
                    child: Icon(Icons.broken_image_rounded, color: tokens.textMuted, size: 48),
                  ),
                )),
            );
          },
        ),
      ),
    );
  }

  // 3. Next Chapter Preview Deck Card (at the end of Webtoon)
  Widget _buildNextChapterDeckCard() {
    final tokens = context.tokens;
    final palette = AppThemeService.currentPalette.value;
    final hasNext = _currentChapterIndex > 0;
    final nextChapter = hasNext ? widget.chapters[_currentChapterIndex - 1] : null;
    final nextTitle = nextChapter != null
        ? (nextChapter.name.isNotEmpty ? nextChapter.name : 'Chapter ${nextChapter.number}')
        : 'You are all caught up!';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withValues(alpha: 0.92),
        borderRadius: ZplayRadius.lgAll,
        border: Border.all(color: tokens.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.primaryColor.withValues(alpha: 0.2),
              borderRadius: ZplayRadius.smAll,
            ),
            child: Text(
              hasNext ? 'UP NEXT' : 'CHAPTER FINISHED',
              style: ZplayType.caption.copyWith(weight: FontWeight.w700).toStyle(color: palette.primaryColor),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            nextTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ZplayType.title.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.manga.title,
            style: ZplayType.label.toStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: 20),
          if (hasNext)
            ElevatedButton.icon(
              onPressed: _nextChapter,
              icon: Icon(Icons.skip_next_rounded, color: tokens.textPrimary, size: 20),
              label: Text(
                'Read Next Chapter',
                style: ZplayType.subtitle.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.check_circle_outline_rounded, color: tokens.success),
              label: Text('Back to Manga Details', style: ZplayType.label.toStyle(color: tokens.textPrimary)),
              style: OutlinedButton.styleFrom(
                side: tokens.hairlineStrong,
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 4. Page Deck Preview Section (Placed DIRECTLY ABOVE the slider)
  Widget _buildPageDeckSection(bool isMobile, bool isVerySmall, AppThemePalette palette) {
    final tokens = context.tokens;
    final cardWidth = isVerySmall ? 54.0 : (isMobile ? 62.0 : 74.0);
    final cardHeight = isVerySmall ? 78.0 : (isMobile ? 88.0 : 104.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withValues(alpha: 0.85),
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_carousel_rounded, color: palette.primaryColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Page Deck Preview',
                      style: ZplayType.caption
                          .copyWith(weight: FontWeight.w700, letterSpacing: 0.5)
                          .toStyle(color: tokens.textEmphasis),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.primaryColor.withValues(alpha: 0.18),
                    borderRadius: ZplayRadius.xsAll,
                    border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Page ${_currentPageIndex + 1} of ${_pageUrls.length}',
                    style: ZplayType.caption.copyWith(weight: FontWeight.w700).toStyle(color: palette.primaryColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: cardHeight,
            child: ListView.builder(
              controller: _deckScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _pageUrls.length,
              itemBuilder: (context, index) {
                final isCurrent = index == _currentPageIndex;
                return FocusableCard(
                  onTap: () => _jumpToPage(index),
                  builder: (context, _) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: isCurrent ? palette.primaryColor : tokens.borderStrong,
                        width: isCurrent ? 2.2 : 1.0,
                      ),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: palette.primaryColor.withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: ZplayRadius.smAll,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: _pageUrls[index],
                            cacheManager: AppImageCache.manager,
                            fit: BoxFit.cover,
                            memCacheWidth: 140,
                            placeholder: (_, __) => Container(color: tokens.surface),
                            errorWidget: (_, __, ___) => Center(
                              child: Icon(Icons.broken_image_rounded, color: tokens.textDisabled, size: 18),
                            )),
                          // Bottom gradient overlay
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 26,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.85),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Page number indicator badge
                          Positioned(
                            bottom: 3,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isCurrent ? palette.primaryColor : Colors.black.withValues(alpha: 0.7),
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: ZplayType.overline.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                                ),
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
        ],
      ),
    );
  }

  // Top Glass Bar
  Widget _buildTopBar(String title) {
    final tokens = context.tokens;
    final palette = AppThemeService.currentPalette.value;
    final topInset = MediaQuery.paddingOf(context).top;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Container(
          padding: EdgeInsets.only(top: 12 + topInset, bottom: 12, left: 16, right: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            border: Border(bottom: tokens.hairlineStrong),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.manga.title,
                      style: ZplayType.subtitle
                          .copyWith(weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      title,
                      style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reader Customization',
                icon: Icon(Icons.tune_rounded, color: palette.primaryColor, size: 22),
                onPressed: () => _showReaderCustomizer(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom Glass Control Bar with Integrated Page Deck (above slider), Navigation & Zoom
  Widget _buildBottomBar() {
    final tokens = context.tokens;
    final palette = AppThemeService.currentPalette.value;
    final showScrubber = MangaSettings.showPageScrubber.value;
    final showDeckToggle = MangaSettings.showPageDeck.value;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;
    final isVerySmall = screenW < 420;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 24,
            12,
            isMobile ? 12 : 24,
            12 + bottomInset,
          ),
          decoration: BoxDecoration(
            color: tokens.bg.withValues(alpha: 0.90),
            border: Border(top: tokens.hairlineStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Page Deck Thumbnail Strip (DIRECTLY ABOVE THE SLIDER) ──
              if (_showDeckDrawer && _pageUrls.isNotEmpty)
                _buildPageDeckSection(isMobile, isVerySmall, palette),

              // ── 2. Page Scrubber Slider ──
              if (showScrubber && _pageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                      thumbColor: palette.primaryColor,
                      overlayColor: palette.primaryColor.withValues(alpha: 0.2),
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                    ),
                    child: Slider(
                      value: _currentPageIndex.toDouble().clamp(0.0, (_pageUrls.length - 1).toDouble()),
                      min: 0.0,
                      max: (_pageUrls.length - 1).toDouble(),
                      divisions: _pageUrls.length > 1 ? _pageUrls.length - 1 : 1,
                      onChanged: (val) {
                        _jumpToPage(val.round());
                      },
                    ),
                  ),
                ),

              // ── 3. Bottom Actions & Responsive Navigation Row ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Prev Chapter Button
                  IconButton(
                    icon: Icon(Icons.skip_previous_rounded, color: tokens.textPrimary),
                    onPressed: _currentChapterIndex < widget.chapters.length - 1 ? _prevChapter : null,
                    tooltip: 'Previous Chapter',
                    splashRadius: 20,
                  ),

                  // Center Cluster: Zoom Controls + Page Badge
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive Zoom Control Cluster (Desktop / Tablet / Standard)
                        if (!isVerySmall)
                          Container(
                            decoration: BoxDecoration(
                              color: tokens.borderDefault,
                              borderRadius: ZplayRadius.lgAll,
                              border: Border.all(color: tokens.borderStrong),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.zoom_out_rounded, color: tokens.textPrimary, size: 18),
                                  onPressed: _currentZoom > 0.26 ? _zoomOut : null,
                                  tooltip: 'Zoom Out (-)',
                                  padding: const EdgeInsets.all(5),
                                  constraints: const BoxConstraints(),
                                ),
                                InkWell(
                                  onTap: _resetZoom,
                                  borderRadius: ZplayRadius.smAll,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    child: Text(
                                      '${(_currentZoom * 100).round()}%',
                                      style: ZplayType.caption
                                          .copyWith(weight: FontWeight.w700)
                                          .toStyle(
                                            color: (_currentZoom - 1.0).abs() > 0.03
                                                ? palette.primaryColor
                                                : tokens.textEmphasis,
                                          ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.zoom_in_rounded, color: tokens.textPrimary, size: 18),
                                  onPressed: _currentZoom < 4.9 ? _zoomIn : null,
                                  tooltip: 'Zoom In (+)',
                                  padding: const EdgeInsets.all(5),
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),

                        if (!isVerySmall) const SizedBox(width: 8),

                        // Page Counter Badge
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 8 : 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.borderStrong,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Text(
                            'Page ${_currentPageIndex + 1} / ${_pageUrls.isNotEmpty ? _pageUrls.length : "?"}',
                            style: ZplayType.caption
                                .copyWith(size: isVerySmall ? 11 : 12.5, weight: FontWeight.w700)
                                .toStyle(color: tokens.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right Cluster: Deck Toggle + Next Chapter Button
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDeckToggle)
                        IconButton(
                          tooltip: 'Toggle Page Deck',
                          icon: Icon(
                            Icons.view_carousel_rounded,
                            color: _showDeckDrawer ? palette.primaryColor : tokens.textEmphasis,
                            size: 20,
                          ),
                          onPressed: _toggleDeckDrawer,
                          splashRadius: 20,
                        ),

                      IconButton(
                        icon: Icon(Icons.skip_next_rounded, color: tokens.textPrimary),
                        onPressed: _currentChapterIndex > 0 ? _nextChapter : null,
                        tooltip: 'Next Chapter',
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
