import 'package:flutter/material.dart';

import '../../models/movie/movie_section.dart';
import '../../pages/calendar/tv_calendar_page.dart';
import '../../pages/catalog/catalog_page.dart';
import '../../services/theme/design_tokens.dart';
import '../../utils/navigation/route_transitions.dart';
import './movie_card.dart';
import '../common/hover_scroll_rail.dart';
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
  }

  @override
  void dispose() {
    _entry.dispose();
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sizing = MovieCardSizing.fromWidth(
      MediaQuery.sizeOf(context).width,
      availableHeight: widget.maxHeight,
      artwork: widget.artwork,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
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
                      FadeThroughRoute(
                        page: CatalogPage(section: widget.section),
                      ),
                    );
                  }
                : null,
          ),
          const SizedBox(height: ZplaySpacing.s12),

          // The entrance stagger stays here rather than inside the rail: it is
          // this surface's arrival, not rail machinery, and wrapping the child
          // is all the rail needs to let it happen.
          HoverScrollRail(
            height: sizing.totalHeight,
            padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
            spacing: sizing.spacing,
            edgeTolerance: HoverScrollRail.exactEdgeTolerance,
            arrowStyle: RailArrowStyle.focusable,
            itemCount: widget.section.movies.length,
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
        ],
      ),
    );
  }
}
