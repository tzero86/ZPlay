import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';
import 'slider_arrow.dart';

/// Default distance from the rail's edge a revealed arrow rests at; a caller
/// can override it through `arrowInset`.
const double _arrowInset = 10;

/// Where a hidden arrow parks. Negative, so it sits outside the rail and cannot
/// catch a pointer on its way in or out.
const double _arrowParked = -60;

/// Which chrome the rail draws on each scrollable edge.
enum RailArrowStyle {
  /// Hover-only arrows ([SliderArrow]): they appear while a pointer is over the
  /// rail and are unreachable without one, because nothing there is focusable.
  pointer(Duration(milliseconds: 250)),

  /// Arrows built on [FocusableCard], so a D-pad can land on them and a remote
  /// can press them. A rail whose cards are focusable needs this one: a
  /// hover-only arrow beside focusable cards is a dead end for the only input
  /// a television has.
  focusable(Duration(milliseconds: 300));

  const RailArrowStyle(this.revealDuration);

  /// How long the arrow takes to slide in from beside the rail.
  ///
  /// The shipped surfaces disagreed here - 250 ms against 300 ms - and that
  /// difference is kept rather than picked, because retiming either one is a
  /// visual change nobody asked for.
  final Duration revealDuration;
}

/// A horizontal card rail with edge arrows: the one implementation the card
/// rows share.
///
/// What was copied three times verbatim - the controller, the can-scroll flags,
/// the hover state, the arrow slid in from `-60` to `10`, and a press moving
/// 80% of the viewport over 650 ms of `easeOutCubic` - lives here once. Each
/// field documents the one thing that genuinely differed between the callers.
class HoverScrollRail extends StatefulWidget {
  const HoverScrollRail({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
    this.spacing = ZplaySpacing.s16,
    this.edgeTolerance = exactEdgeTolerance,
    this.arrowInset = _arrowInset,
    this.arrowStyle = RailArrowStyle.pointer,
    this.showArrows,
  });

  /// Exact can-scroll test: the flags flip the instant the rail leaves its
  /// start or its end.
  static const double exactEdgeTolerance = 0;

  /// Can-scroll test with 10 px of slop: the flags do not flip until the rail is
  /// more than 10 px away from an end. The anime and continue-watching rails
  /// have always used this value; the movie row has always used
  /// [exactEdgeTolerance].
  static const double slopEdgeTolerance = 10;

  /// How many cards the row holds. Passed straight to the list.
  final int itemCount;

  /// Builds one card. Index is the card's position, so a caller can key an
  /// entrance animation to it without the rail knowing about animation.
  final IndexedWidgetBuilder itemBuilder;

  /// Vertical space the row occupies; the card is expected to fit it.
  final double height;

  /// Leading and trailing inset of the row, so the first card lines up with the
  /// heading above it instead of being clipped by the edge of the screen.
  final EdgeInsetsGeometry padding;

  /// Gap between cards.
  final double spacing;

  /// Slop in the can-scroll test; see [exactEdgeTolerance] and
  /// [slopEdgeTolerance].
  final double edgeTolerance;

  /// Where a revealed arrow comes to rest, measured in from the rail's edge.
  ///
  /// 10 dp is what the movie, anime and continue-watching rows have always
  /// used. Music parked its arrows 8 dp in, and that row keeps its own number
  /// rather than inheriting a 2 dp shift from this consolidation.
  final double arrowInset;

  /// Which arrow chrome this rail draws; see [RailArrowStyle].
  final RailArrowStyle arrowStyle;

  /// Whether the edge arrows exist at all, or null to decide from the platform.
  ///
  /// Null applies the desktop rule the rails already carried: web, Windows,
  /// macOS and Linux have a pointer that can raise a hover, everything else
  /// gets its arrows revealed by focus instead and so has none here. A caller
  /// that already exports its own pointer test - `continueWatchingHasPointer()`
  /// is the one that exists today - passes it in, so the rail cannot answer
  /// that question differently from the surface around it.
  final bool? showArrows;

  @override
  State<HoverScrollRail> createState() => _HoverScrollRailState();
}

class _HoverScrollRailState extends State<HoverScrollRail> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHoveringRail = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollButtons);

    // Defer the initial check until after first frame so maxScrollExtent is
    // calculated.
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

    final position = _scrollController.position;
    final tolerance = widget.edgeTolerance;
    final canLeft = position.pixels > tolerance;
    final canRight = position.pixels < position.maxScrollExtent - tolerance;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // Scroll by 80% of the viewport width to leave some context.
    final scrollAmount = position.viewportDimension * 0.8 * directionMultiplier;

    final target = (position.pixels + scrollAmount).clamp(
      0.0,
      position.maxScrollExtent,
    );

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  /// The platform test the rails carried before this widget existed: web,
  /// Windows, macOS and Linux all have a pointer that can raise a hover.
  static bool _hasPointer() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return switch (widget.arrowStyle) {
      RailArrowStyle.pointer => SliderArrow(icon: icon, onTap: onTap),
      RailArrowStyle.focusable => _FocusableRailArrow(icon: icon, onTap: onTap),
    };
  }

  @override
  Widget build(BuildContext context) {
    final showArrows = widget.showArrows ?? _hasPointer();
    final revealDuration = widget.arrowStyle.revealDuration;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringRail = true),
      onExit: (_) => setState(() => _isHoveringRail = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ListView.separated(
              clipBehavior: Clip.none,
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: widget.padding,
              itemCount: widget.itemCount,
              separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
              itemBuilder: widget.itemBuilder,
            ),

            if (showArrows) ...[
              // Left arrow.
              AnimatedPositioned(
                duration: revealDuration,
                curve: Curves.easeOutCubic,
                left: _canScrollLeft && _isHoveringRail
                    ? widget.arrowInset
                    : _arrowParked,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _arrow(
                    Icons.arrow_back_ios_new_rounded,
                    () => _scroll(-1),
                  ),
                ),
              ),
              // Right arrow.
              AnimatedPositioned(
                duration: revealDuration,
                curve: Curves.easeOutCubic,
                right: _canScrollRight && _isHoveringRail
                    ? widget.arrowInset
                    : _arrowParked,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _arrow(
                    Icons.arrow_forward_ios_rounded,
                    () => _scroll(1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Arrow a D-pad can reach, for a rail whose cards are focusable too.
///
/// Same 48 dp sphere, blur and hover colours as [SliderArrow]; the difference
/// is the state it reacts to. [FocusableCard] reports `hovered || focused` as
/// highlighted, so a remote lands on this arrow and sees the same lit ring a
/// pointer gets.
class _FocusableRailArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FocusableRailArrow({required this.icon, required this.onTap});

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
