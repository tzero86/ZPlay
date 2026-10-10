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
import '../../../widgets/common/section_header.dart';
import '../../../widgets/common/slider_arrow.dart';
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
    final isDesktop = _isDesktop();

    return ValueListenableBuilder<List<ReadingProgress>>(
      valueListenable: ContinueReadingService.activeItems,
      builder: (context, items, _) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header. The shared rail header - one semibold title and a muted
              // tabular count - with its baked 16 dp inset offset by 8 so the
              // heading lands on the shelf's 24 dp gutter, the same line the
              // covers below start on. The accent bar the row used to carry was
              // decoration on a title, and this app keeps its one accent for
              // state.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                child: SectionHeader(title: widget.title, count: items.length),
              ),

              const SizedBox(height: ZplaySpacing.s12),

              // Slider
              MouseRegion(
                onEnter: (_) => setState(() => _isHoveringSlider = true),
                onExit: (_) => setState(() => _isHoveringSlider = false),
                child: SizedBox(
                  height: 240,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ListView.builder(
                        clipBehavior: Clip.none,
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s24,
                          vertical: ZplaySpacing.s8,
                        ),
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

                      // Desktop scroll arrows: the shared [SliderArrow], shown
                      // while the pointer is over the rail and slid clear of the
                      // edge when it is not. The local circular button they
                      // replaced carried its own fill, hairline and shadow, and
                      // its reveal was gated on a focus flag that could never be
                      // true - a `Focus(canRequestFocus: false)` never reports
                      // focus, so the arrows were already hover-only and the flag
                      // was dead weight.
                      if (isDesktop) ...[
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          left: _canScrollLeft && _isHoveringSlider ? 10 : -60,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: SliderArrow(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => _scroll(-1),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          right: _canScrollRight && _isHoveringSlider ? 10 : -60,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: SliderArrow(
                              icon: Icons.arrow_forward_ios_rounded,
                              onTap: () => _scroll(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
          // Lift answers the pointer only, matching the shelf card and the
          // shared card: the ring is what marks focus, and a D-pad press must
          // not nudge the cover being aimed at.
          transform: Matrix4.translationValues(0, state.hovered ? -3 : 0, 0),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.mdAll,
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
                        borderRadius: ZplayRadius.mdAll,
                        boxShadow: [ReaderTokens.shadowMd],
                      ),
                      child: ClipRRect(
                        borderRadius: ZplayRadius.mdAll,
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