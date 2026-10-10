import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/audiobook/audiobook_scraper_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/player/player_glass.dart';
import 'audiobook_player_screen.dart';
import 'audiobook_route_transitions.dart';
import '../../services/storage/app_image_cache.dart';

class AudiobookDetailPage extends StatefulWidget {
  final Audiobook audiobook;
  final String? heroTag;

  const AudiobookDetailPage({
    super.key,
    required this.audiobook,
    this.heroTag,
  });

  @override
  State<AudiobookDetailPage> createState() => _AudiobookDetailPageState();
}

class _AudiobookDetailPageState extends State<AudiobookDetailPage> {
  List<AudiobookChapter>? _chapters;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchChapters();
  }

  Future<void> _fetchChapters() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final chapters = await AudiobookScraperService.instance.getChapters(widget.audiobook);
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load chapters: $e';
        });
      }
    }
  }

  void _playChapter(AudiobookChapter chapter) {
    if (_chapters == null || _chapters!.isEmpty) return;
    final initialIndex = _chapters!.indexOf(chapter).clamp(0, _chapters!.length - 1);

    Navigator.push(
      context,
      AudiobookPageRoute(
        page: AudiobookPlayerScreen(
          audiobook: widget.audiobook,
          chapters: _chapters!,
          initialChapterIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.audiobook;
    final hasCover = book.coverImage.isNotEmpty;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 700;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // Background ambient cover blur
          if (hasCover && book.coverImage.trim().isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: CachedNetworkImage(
                  imageUrl: book.coverImage.trim(),
                  cacheManager: AppImageCache.manager,
                  httpHeaders: const {
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),

          // Main Scroll View
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Top Header Bar. A pushed route keeps its own back affordance and
              // its header *is* the top chrome - the shell's nav is not over this
              // route - so it is transparent, filled with nothing, and carries no
              // hairline. The old filled circle was a box whose fill was not its
              // content; the one outline this design draws on a control is the
              // focus ring, and [FocusableInkWell] supplies it.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? ZplaySpacing.s12 : ZplaySpacing.s16,
                    topInset + ZplaySpacing.s8,
                    isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24,
                    ZplaySpacing.s8,
                  ),
                  child: Row(
                    children: [
                      FocusableInkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: ZplayRadius.fullAll,
                        hoverColor: tokens.textPrimary.withValues(
                          alpha: ZplayOpacity.overlayHover,
                        ),
                        child: SizedBox(
                          width: ZplaySpacing.s48,
                          height: ZplaySpacing.s48,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: tokens.textPrimary,
                            size: 20,
                            // Over the blurred cover, which can be bright: the
                            // glyph shadow is what keeps it legible at offset 0,
                            // where there is no tint behind it.
                            shadows: const [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s12),
                      Expanded(
                        child: Text(
                          'Audiobook Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.titleLarge
                              .toStyle(color: tokens.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Hero Cover & Info Section
              SliverToBoxAdapter(
                child: Padding(
                  // One gutter for the whole page: the shared section header
                  // below sits at `s16`, so the cover, the copy and the chapter
                  // rows line up with the heading above them.
                  padding: const EdgeInsets.fromLTRB(
                    ZplaySpacing.s16,
                    ZplaySpacing.s8,
                    ZplaySpacing.s16,
                    ZplaySpacing.s16,
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildCoverImage(book, 180, 260),
                            const SizedBox(height: ZplaySpacing.s20),
                            _buildDetails(book, isMobile),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCoverImage(book, 200, 290),
                            const SizedBox(width: ZplaySpacing.s32),
                            Expanded(child: _buildDetails(book, isMobile)),
                          ],
                        ),
                ),
              ),

              // Section Title. One heading type for every rail and section in the
              // app: the leading glyph was a second mark for a title that already
              // names itself, and spacing plus the title's own weight is the
              // structure. The count is the shared header's muted number rather
              // than another accent badge.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: ZplaySpacing.s16,
                    bottom: ZplaySpacing.s4,
                  ),
                  child: SectionHeader(
                    title: 'Chapters & Audio Files',
                    count: _chapters?.length,
                  ),
                ),
              ),

              // Chapters List
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
                  // The shared failure view, so a chapter fetch that fails looks
                  // like every other fetch that fails and offers the retry the
                  // bare red sentence never did.
                  child: ErrorView(
                    title: 'Could not load chapters',
                    error: _error,
                    onRetry: _fetchChapters,
                  ),
                )
              else if (_chapters == null || _chapters!.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No playable chapters found.',
                      style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    ZplaySpacing.s16,
                    ZplaySpacing.s8,
                    ZplaySpacing.s16,
                    ZplaySpacing.s24 + bottomInset,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chapter = _chapters![index];
                        return _ChapterTile(
                          chapter: chapter,
                          onTap: () => _playChapter(chapter),
                        );
                      },
                      childCount: _chapters!.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(Audiobook book, double width, double height) {
    final tokens = context.tokens;
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: ZplayRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: ZplayRadius.lgAll,
        child: book.coverImage.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: book.coverImage,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: tokens.surfaceRaised),
                errorWidget: (_, __, ___) => Container(
                  color: tokens.surfaceRaised,
                  child: Icon(Icons.headphones_rounded, size: 64, color: tokens.textMuted),
                ))
            : Container(
                color: tokens.surfaceRaised,
                child: Icon(Icons.headphones_rounded, size: 64, color: tokens.textMuted),
              ),
      ),
    );
  }

  Widget _buildDetails(Audiobook book, bool isMobile) {
    final isTorrent = book.source.toLowerCase().contains('audiobookbay');
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s8,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            // No resting border: the fill carries the warning or the accent and
            // the badge is a label, not a control. One rule for both branches,
            // where the torrent case used to wear an 0.8 dp outline the plain
            // source did not.
            color: isTorrent
                ? tokens.warning.withValues(alpha: 0.25)
                : tokens.accentSubtle,
            borderRadius: ZplayRadius.xsAll,
          ),
          child: Text(
            isTorrent ? 'AUDIOBOOKBAY (TORRENT)' : book.source.toUpperCase(),
            style: ZplayType.overline.toStyle(
              color: isTorrent ? tokens.warning : tokens.accent,
            ),
          ),
        ),
        const SizedBox(height: ZplaySpacing.s12),
        Text(
          book.title,
          textAlign: isMobile ? TextAlign.center : TextAlign.start,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: ZplayType.titleLarge
              .copyWith(size: isMobile ? 18 : 24)
              .toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: ZplaySpacing.s16),
        if (_chapters != null && _chapters!.isNotEmpty)
          // The shared pill, so this page's way into the player is the same
          // control as Home's hero and the shelf banner's. It replaced a
          // gradient button that painted its own accent glow - the ring is the
          // one mark this design puts on a control, and a second, softer accent
          // edge under it read as a duplicate focus cue.
          PillButton(
            label: 'Play First Chapter',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _playChapter(_chapters!.first),
          ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final AudiobookChapter chapter;
  final VoidCallback onTap;

  const _ChapterTile({
    required this.chapter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) {
          // Pointer-only movement; focus is answered by the ring below.
          final scale = state.pressed ? 0.98 : (state.hovered ? 1.015 : 1.0);

          // The one focus marker, painted over the row rather than around it, so
          // focus arriving cannot move the tile or its neighbours. It replaced a
          // border that swapped colour and width between states - a 0.5 dp
          // reflow on every focus move, and a second edge where the ring is the
          // only one this design draws.
          return AnimatedScale(
            scale: scale,
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            child: CardFocusRing(
              focused: state.focused,
              radius: ZplayRadius.mdAll,
              child: AnimatedContainer(
                duration: ZplayMotion.fast,
                curve: ZplayMotion.standard,
                decoration: BoxDecoration(
                  // A row that is being pointed at brightens; the fill is the
                  // whole answer, and it is the same answer for a pointer and a
                  // D-pad.
                  color: state.highlighted
                      ? tokens.surfaceOverlay
                      : tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(ZplaySpacing.s16),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: ZplayMotion.fast,
                        curve: ZplayMotion.standard,
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: state.highlighted
                              ? tokens.accent
                              : tokens.accentSubtle,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: state.highlighted
                              ? tokens.onAccent
                              : tokens.accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s16),
                      Expanded(
                        child: Text(
                          chapter.title,
                          style: ZplayType.body
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
