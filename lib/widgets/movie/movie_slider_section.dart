import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie_section.dart';
import '../../pages/calendar/tv_calendar_page.dart';
import '../../pages/catalog/catalog_page.dart';
import '../../services/theme/design_tokens.dart';
import '../../utils/navigation/route_transitions.dart';
import './movie_card.dart';
import '../common/focusable_card.dart';
import '../common/section_header.dart';

class MovieSliderSection extends StatefulWidget {
  final MovieSection section;
  final bool showCalendarButton;

  /// See All opens the section's own catalog page, which only exists for addon
  /// catalogs. Curated rails carry a synthetic `curated_*` catalog id, so they
  /// hide the control instead of pushing a catalog that would 404.
  final bool showSeeAll;

  /// Vertical space this rail may occupy, chrome above it already subtracted.
  ///
  /// Null means "size to the card's natural shape", which is what a pointer
  /// device wants: there the window is tall and the card fits. On a television
  /// the card did not fit - a 326.5 dp rail starting at 328 dp in a 540 dp
  /// window overflows by 114 dp, and the overflow is a movie title cut in half
  /// at the bottom of the screen. A caller that knows its own chrome passes the
  /// remainder and the card shrinks to fit instead of being cropped.
  final double? maxHeight;

  /// The shape the row's thumbnails are drawn in.
  ///
  /// Poster by default, so every existing caller is unchanged. A rail that
  /// opts in gets Netflix's landscape thumbnail, which carries no title block -
  /// the row already has a heading above it, and a name under every thumbnail
  /// in a seven-wide row is unreadable at television distance anyway.
  final CardArtwork artwork;

  const MovieSliderSection({
    super.key,
    required this.section,
    this.showCalendarButton = false,
    this.showSeeAll = true,
    this.maxHeight,
    this.artwork = CardArtwork.poster,
  });

  @override
  State<MovieSliderSection> createState() => _MovieSliderSectionState();
}

class _MovieSliderSectionState extends State<MovieSliderSection>
    with SingleTickerProviderStateMixin {
  Offset? _tapPosition;
  late final ScrollController _scrollController;

  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHoveringSlider = false;

  /// Cards that take part in the entry stagger.
  ///
  /// The rail mounts every card at once, so a row used to arrive in one hard
  /// cut. Only the first few animate, and only once on mount: animating a list
  /// that scrolls is the quickest way to lose frames, and the perf notes already
  /// call this screen heavy.
  static const int _staggeredCards = 6;
  static const double _staggerStep = 0.08;

  late final AnimationController _entry;
  final List<Animation<double>> _entryFades = [];
  final List<Animation<Offset>> _entrySlides = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollButtons);

    // Built once rather than per build, so a scroll does not allocate.
    _entry = AnimationController(vsync: this, duration: ZplayMotion.slow);
    for (var i = 0; i < _staggeredCards; i++) {
      final fade = _entry.drive(
        CurveTween(
          curve: Interval(
            i * _staggerStep,
            0.45 + i * _staggerStep,
            curve: ZplayMotion.standard,
          ),
        ),
      );
      _entryFades.add(fade);
      _entrySlides.add(
        fade.drive(
          Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ),
        ),
      );
    }
    _entry.forward();

    // Defer the initial check until after first frame so maxScrollExtent is calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  /// Wraps a card in its share of the entry animation. Cards past the stagger
  /// window are returned untouched.
  Widget _enter(int index, Widget child) {
    if (index >= _staggeredCards) return child;

    return FadeTransition(
      opacity: _entryFades[index],
      child: SlideTransition(position: _entrySlides[index], child: child),
    );
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;

    final canLeft = _scrollController.position.pixels > 0;
    final canRight =
        _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent;

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
    // Scroll by 80% of the viewport width to leave some context
    final scrollAmount = viewportWidth * 0.8 * directionMultiplier;

    final target = (_scrollController.position.pixels + scrollAmount).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sizing = MovieCardSizing.fromWidth(
      MediaQuery.sizeOf(context).width,
      availableHeight: widget.maxHeight,
      artwork: widget.artwork,
    );
    final isDesktop = _isDesktop();

    return Padding(
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Listener(
            onPointerDown: (event) => _tapPosition = event.position,
            child: SectionHeader(
              title: widget.section.title,
              count: widget.section.movies.length,
              subtitle: widget.section.subtitle,
              trailing: widget.showCalendarButton
                  ? InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TvCalendarPage(),
                          ),
                        );
                      },
                      borderRadius: ZplayRadius.smAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s12,
                          vertical: ZplaySpacing.s4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.textPrimary.withValues(alpha: 0.08),
                          borderRadius: ZplayRadius.smAll,
                          border: Border.all(color: tokens.borderStrong),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              size: 14,
                              color: tokens.accent,
                            ),
                            const SizedBox(width: ZplaySpacing.s4),
                            Text(
                              'Calendar',
                              style: ZplayType.label.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
              onSeeAll: widget.showSeeAll
                  ? () {
                      Navigator.push(
                        context,
                        LiquidRevealRoute(
                          page: CatalogPage(section: widget.section),
                          tapPosition: _tapPosition,
                        ),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: ZplaySpacing.s12),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringSlider = true),
            onExit: (_) => setState(() => _isHoveringSlider = false),
            child: SizedBox(
              height: sizing.totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ListView.separated(
                    clipBehavior: Clip.none,
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: sizing.sidePadding,
                    ),
                    itemCount: widget.section.movies.length,
                    separatorBuilder: (context, index) {
                      return SizedBox(width: sizing.spacing);
                    },
                    itemBuilder: (context, index) {
                      return _enter(
                        index,
                        SizedBox(
                          width: sizing.cardWidth,
                          child: MovieCard(
                            movie: widget.section.movies[index],
                            artwork: widget.artwork,
                          ),
                        ),
                      );
                    },
                  ),

                  // Desktop Scroll Arrows
                  if (isDesktop) ...[
                    // Left Arrow
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: _canScrollLeft && _isHoveringSlider ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _SliderArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scroll(-1),
                        ),
                      ),
                    ),
                    // Right Arrow
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      right: _canScrollRight && _isHoveringSlider ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _SliderArrow(
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
  }
}

class _SliderArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SliderArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => AnimatedScale(
        // Dynamic scale based on interaction state
        scale: state.pressed ? 0.90 : (state.highlighted ? 1.08 : 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.highlighted
                    ? tokens.textPrimary.withValues(
                        alpha: ZplayOpacity.overlayHover,
                      )
                    : tokens.bg.withValues(alpha: 0.5),
                border: Border.all(
                  color: state.highlighted
                      ? tokens.borderStrong
                      : tokens.borderDefault,
                  width: 1.5,
                ),
                boxShadow: state.highlighted
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                icon,
                color: tokens.textPrimary.withValues(
                  alpha: state.highlighted ? 1.0 : ZplayOpacity.textEmphasis,
                ),
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
