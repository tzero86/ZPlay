import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// Fades the edges of a horizontally scrolling row into its surroundings, and
/// only on the sides that have somewhere left to scroll.
///
/// A row that simply stops at the viewport edge gives a user on a sofa no way to
/// know there is more: the chip is cut in half, which reads as a layout mistake
/// rather than as an invitation. A fade reads as "this continues", and
/// disappearing entirely at the ends means it is a real, trustworthy signal
/// rather than decoration.
///
/// A [ShaderMask] with [BlendMode.dstIn] is what lets the fade reach the content
/// itself rather than a rectangle behind it, which is the whole point: it dims
/// the pill that runs off the edge instead of washing out a background that may
/// not even be there.
///
/// Used by [TabStrip] and the Browse catalog row, so both horizontal rows in the
/// app signal overflow the same way.
class HorizontalEdgeFade extends StatefulWidget {
  const HorizontalEdgeFade({
    super.key,
    required this.child,
    required this.scrollController,
    this.extent = ZplaySpacing.s16,
  });

  final Widget child;

  /// The controller driving the horizontal scroll this fade tracks. Must be the
  /// same controller the scrolling viewport uses, or the fades never move.
  final ScrollController scrollController;

  /// How far into the row the fade reaches, in logical pixels, before it is
  /// clamped to [maxExtent] of the row's width.
  final double extent;

  /// Each fade is capped below half the row so the two can never meet in the
  /// middle of a very narrow strip.
  static const double maxExtent = 0.45;

  /// Scroll offsets land on fractions of a pixel, so an exact comparison leaves
  /// a fade on at the very end of the row.
  static const double edgeTolerance = ZplaySpacing.s2;

  @override
  State<HorizontalEdgeFade> createState() => _HorizontalEdgeFadeState();
}

class _HorizontalEdgeFadeState extends State<HorizontalEdgeFade> {
  /// Tracked rather than read on demand because the fade has to repaint the
  /// moment the row reaches an end, including when it gets there from a metrics
  /// change with no scroll event at all.
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncEdges);
  }

  @override
  void didUpdateWidget(HorizontalEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.scrollController, widget.scrollController)) return;
    oldWidget.scrollController.removeListener(_syncEdges);
    widget.scrollController.addListener(_syncEdges);
    _syncEdges();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncEdges);
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final atStart = position.pixels <= HorizontalEdgeFade.edgeTolerance;
    final atEnd =
        position.pixels >=
        position.maxScrollExtent - HorizontalEdgeFade.edgeTolerance;
    if (atStart == _atStart && atEnd == _atEnd) return;
    setState(() {
      _atStart = atStart;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _maybeFade(
        NotificationListener<ScrollMetricsNotification>(
          // Re-checked after metrics change, because a window resize can make a
          // row scrollable without any scroll event at all.
          onNotification: (notification) {
            _syncEdges();
            return false;
          },
          child: widget.child,
        ),
        constraints.maxWidth,
      ),
    );
  }

  Widget _maybeFade(Widget child, double width) {
    final leading = !_atStart;
    final trailing = !_atEnd;
    // An unbounded width means the row is inside a parent that sizes to content,
    // and a gradient over an infinite extent is meaningless.
    if ((!leading && !trailing) || !width.isFinite || width <= 0) return child;

    final fade = (widget.extent / width).clamp(0.0, HorizontalEdgeFade.maxExtent);
    final colors = <Color>[];
    final stops = <double>[];
    if (leading) {
      colors.addAll(const [Colors.transparent, Colors.white]);
      stops.addAll([0, fade]);
    }
    if (trailing) {
      // A one-sided fade still needs an opaque anchor at its near end, or the
      // gradient would interpolate from the first stop onwards.
      if (!leading) {
        colors.add(Colors.white);
        stops.add(0);
      }
      colors.addAll(const [Colors.white, Colors.transparent]);
      stops.addAll([1 - fade, 1]);
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) =>
          LinearGradient(colors: colors, stops: stops).createShader(rect),
      child: child,
    );
  }
}
