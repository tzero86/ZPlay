import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/book/book_result.dart';
import '../../../models/book/reading_progress.dart';
import '../../../services/books/continue_reading_service.dart';
import '../../../services/layout/form_factor.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../widgets/common/card_badges.dart';
import '../../../widgets/common/focusable_card.dart';
import 'reader_design_tokens.dart';
import '../epub_reader_page.dart';
import '../pdf_reader_page.dart';
import '../../../services/storage/app_image_cache.dart';

class ContinueReadingSlider extends StatefulWidget {
  final String title;

  const ContinueReadingSlider({
    super.key,
    this.title = 'Continue Reading',
  });

  @override
  State<ContinueReadingSlider> createState() => _ContinueReadingSliderState();
}

class _ContinueReadingSliderState extends State<ContinueReadingSlider> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHoveringSlider = false;

  /// Whether a scroll arrow holds focus.
  ///
  /// The arrows are revealed by the pointer; a keyboard user tabbing onto one
  /// used to land on a fully transparent button, which is a focus target with
  /// no indicator at all. Focus reveals them on the same terms hover does.
  bool _leftArrowFocused = false;
  bool _rightArrowFocused = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollButtons);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;
    final canLeft = _scrollController.position.pixels > 10;
    final canRight =
        _scrollController.position.pixels < _scrollController.position.maxScrollExtent - 10;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;
    final viewportWidth = _scrollController.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.8 * directionMultiplier;
    final target = (_scrollController.position.pixels + scrollAmount)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  void _openReader(BuildContext context, ReadingProgress item) {
    final file = File(item.filePath);
    final book = BookResult(
      title: item.title,
      author: item.author,
      md5: item.md5,
      link: '',
      bookImage: item.coverUrl,
      bookFiletype: item.fileType,
    );

    if (item.fileType == 'pdf') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PdfReaderPage(
            file: file,
            book: book,
            initialPage: item.currentPage,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => EpubReaderPage(
            file: file,
            book: book,
            initialChapterIndex: item.chapterIndex,
            initialScrollOffset: item.scrollOffset,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDesktop = _isDesktop();

    return ValueListenableBuilder<List<ReadingProgress>>(
      valueListenable: ContinueReadingService.activeItems,
      builder: (context, items, _) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                      widget.title,
                      style: ZplayType.titleLarge.toStyle(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length} ${items.length == 1 ? 'Book' : 'Books'}',
                      style: ZplayType.label.toStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),

              // Slider
              MouseRegion(
                onEnter: (_) => setState(() => _isHoveringSlider = true),
                onExit: (_) => setState(() => _isHoveringSlider = false),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ContinueReadingCard(
                            item: item,
                            onTap: () => _openReader(context, item),
                            onRemove: () => ContinueReadingService.removeProgress(item.md5),
                          );
                        },
                      ),
                    ),

                    // Left Arrow
                    if (isDesktop && _canScrollLeft)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Focus(
                            canRequestFocus: false,
                            onFocusChange: (hasFocus) {
                              if (_leftArrowFocused != hasFocus) {
                                setState(() => _leftArrowFocused = hasFocus);
                              }
                            },
                            child: AnimatedOpacity(
                              opacity:
                                  _isHoveringSlider || _leftArrowFocused ? 1.0 : 0.0,
                              duration: ZplayMotion.base,
                              child: _buildArrowButton(
                                Icons.chevron_left_rounded,
                                () => _scroll(-1),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Right Arrow
                    if (isDesktop && _canScrollRight)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Focus(
                            canRequestFocus: false,
                            onFocusChange: (hasFocus) {
                              if (_rightArrowFocused != hasFocus) {
                                setState(() => _rightArrowFocused = hasFocus);
                              }
                            },
                            child: AnimatedOpacity(
                              opacity:
                                  _isHoveringSlider || _rightArrowFocused ? 1.0 : 0.0,
                              duration: ZplayMotion.base,
                              child: _buildArrowButton(
                                Icons.chevron_right_rounded,
                                () => _scroll(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArrowButton(IconData icon, VoidCallback onPressed) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: tokens.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: tokens.textPrimary, size: 26),
        onPressed: onPressed,
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  final ReadingProgress item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ContinueReadingCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final television = FormFactorService.of(context) == FormFactor.television;
    final percent = (item.progressPercent * 100).round();
    final author = item.author.trim();
    // The prototype's shelf caption: "Frank Herbert · 64% read". When the
    // service never captured an author, the reader's own position stands in —
    // the card keeps saying where in the book the reader is either way.
    final positionLabel = item.fileType == 'pdf'
        ? 'Page ${item.currentPage}'
        : 'Ch. ${item.chapterIndex + 1}';
    final caption = author.isNotEmpty
        ? '$author · $percent% read'
        : '$positionLabel · $percent% read';

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) {
        return AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          width: 140,
          margin: const EdgeInsets.only(right: 18),
          transform: Matrix4.translationValues(0, state.highlighted ? -4 : 0, 0),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover with progress bar. One edge: the ring is on the whole
                // card, the cover keeps a resting shadow that focus does not
                // change, and the cover itself carries no border.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 180,
                      width: 140,
                      decoration: const BoxDecoration(
                        borderRadius: ZplayRadius.smAll,
                        boxShadow: [ReaderTokens.shadowMd],
                      ),
                      child: ClipRRect(
                        borderRadius: ZplayRadius.smAll,
                        child: item.coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.coverUrl,
                                cacheManager: AppImageCache.manager,
                                // Cover box is fixed 140 wide; bound to ~3x.
                                memCacheWidth: 420,
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
                    ),

                  // Format tag, revealed on focus, on the same terms as the
                  // catalogue cards. Positioned, so it costs no layout.
                  if (state.focused)
                    Positioned(
                      top: ZplaySpacing.s8,
                      left: ZplaySpacing.s8,
                      child: CardTypeBadge(label: item.fileType.toUpperCase()),
                    ),

                  // Remove Button Top-Right (always on mobile, hover-only on desktop)
                  if (state.highlighted || !(defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux))
                    Positioned(
                      top: -ZplaySpacing.s8,
                      right: -ZplaySpacing.s8,
                      // A 48 dp target on a television, per the ten-foot rule.
                      // The glyph stays small and the ring hugs the glyph, so the
                      // extra area is invisible but reachable.
                      child: SizedBox(
                        width: television ? ZplaySpacing.s48 : ZplaySpacing.s32,
                        height: television ? ZplaySpacing.s48 : ZplaySpacing.s32,
                        child: FocusableCard(
                          onTap: onRemove,
                          builder: (context, closeState) => Center(
                            child: CardFocusRing(
                              focused: closeState.focused,
                              radius: ZplayRadius.fullAll,
                              child: Container(
                                padding: const EdgeInsets.all(ZplaySpacing.s4),
                                decoration: BoxDecoration(
                                  color: closeState.highlighted
                                      ? tokens.danger
                                      : tokens.surfaceOverlay,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: tokens.textPrimary,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Progress Bar at Bottom of Cover
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: ZplaySpacing.s4,
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.5),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(ZplayRadius.sm),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: item.progressPercent.clamp(0.02, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(ZplayRadius.sm),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s8),

              // Title
              Text(
                item.title,
                style: ZplayType.bodySmall
                    .copyWith(weight: FontWeight.w600)
                    .toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Reading progress caption
              Text(
                caption,
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