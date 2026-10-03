import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import '../movie/movie_card.dart';

/// A rail's worth of card-shaped placeholders.
///
/// The app shows a bare `CircularProgressIndicator` while content loads — 87
/// call sites across 46 files (docs/UX_FINDINGS.md). A spinner says nothing
/// about what is coming, and on a TV it is often the only thing on the screen.
///
/// The reason the geometry is passed in rather than guessed is layout jump: a
/// placeholder that is the wrong size moves everything when the real cards
/// land, which is worse than showing nothing at all.
class RailSkeleton extends StatefulWidget {
  final MovieCardSizing sizing;
  final int count;

  /// Draws a title bar above the row, for rails whose header is known already.
  final bool showHeader;

  const RailSkeleton({
    super.key,
    required this.sizing,
    this.count = 6,
    this.showHeader = false,
  });

  @override
  State<RailSkeleton> createState() => _RailSkeletonState();
}

class _RailSkeletonState extends State<RailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.28, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    // One controller and one FadeTransition for the whole rail rather than one
    // per block: the blocks then breathe together, and a six-card rail costs a
    // single animation instead of eighteen.
    return FadeTransition(
      opacity: _pulse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: _block(tokens, width: 168, height: 20),
            ),
          SizedBox(
            height: widget.sizing.totalHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding:
                  EdgeInsets.symmetric(horizontal: widget.sizing.sidePadding),
              itemCount: widget.count,
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(right: widget.sizing.spacing),
                child: _card(tokens),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(ZplayTokens tokens) {
    final sizing = widget.sizing;

    // A landscape thumbnail has no title block under it - the row already has
    // a heading - so drawing one here would flash a text bar that never
    // appears once the real cards land. Gated on the shape rather than on a
    // separate skeleton, because the height it draws from is the shape's.
    if (!sizing.artwork.showsTextBlock) {
      return _block(
        tokens,
        width: sizing.cardWidth,
        height: sizing.posterHeight,
        radius: 10,
      );
    }

    return SizedBox(
      width: sizing.cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block(
            tokens,
            width: sizing.cardWidth,
            height: sizing.posterHeight,
            radius: 14,
          ),
          const SizedBox(height: 9),
          _block(tokens, width: sizing.cardWidth * 0.74, height: 12),
          const SizedBox(height: 6),
          _block(tokens, width: sizing.cardWidth * 0.44, height: 10),
        ],
      ),
    );
  }

  Widget _block(
    ZplayTokens tokens, {
    required double width,
    required double height,
    double radius = 6,
  }) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
