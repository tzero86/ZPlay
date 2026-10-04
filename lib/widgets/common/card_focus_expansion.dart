import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// How far a focused card expands over its neighbours. Netflix's pop sits
/// around 1.1-1.2; 1.15 eats 7.5% of the card's width and height into each
/// neighbour at the same time, from the centre.
const double _popScale = 1.15;

/// Paints [child] above its neighbours, scaled up, while [focused] - without
/// letting the scale anywhere near the card's layout box.
///
/// Three jobs, and the split between them is the whole widget:
///
/// 1. **The layout box never moves.** While popped, the in-layout child is a
///    pinned slot the exact size the card occupied before focus arrived (and
///    before that, [child] itself), so neighbours cannot re-flow and the D-pad
///    geometry the page measures stays byte-identical. The RenderBox is never
///    transformed or resized - only paint moves.
/// 2. **The expanded copy paints above everything.** A list paints children in
///    index order, so a card scaled up in place is painted *under* its right
///    neighbour, and the next rail down covers its bottom growth. The copy is
///    therefore painted in the app's [Overlay] via [OverlayPortal], tracked to
///    the card's own position by [CompositedTransformTarget] /
///    [CompositedTransformFollower] - it follows the card through scrolling for
///    free and lands centred on it.
/// 3. **Nothing clips the expansion.** The overlay copy never passes through a
///    scroll view's viewport clip, so a rail that is tighter than the pop
///    cannot shave its top or bottom - and the rail's own horizontal clipping
///    is untouched, because this widget never changes how the rail draws.
///
/// The zoom is an [AnimationController] owned by this state, driving only the
/// overlay copy's [ScaleTransition]: a focus change rebuilds the card once,
/// never its surroundings, and the animation repaints itself alone.
///
/// The overlay copy is `IgnorePointer`ed: hit testing still lands on the card's
/// real (unscaled) hit target, which is what keeps taps and remote activation
/// on the card the user aimed at.
class CardFocusExpansion extends StatefulWidget {
  const CardFocusExpansion({
    super.key,
    required this.focused,
    required this.child,
    this.scale = _popScale,
  });

  /// Whether the card is the one the D-pad (or keyboard) is on. The pop is a
  /// focus treatment; a pointer's hover zoom is a separate affordance and must
  /// not drive this, or hovering a card would paint it over app chrome.
  final bool focused;

  /// The card visual. Reused verbatim as the overlay copy, so what pops is
  /// exactly what sits in the layout - including its own focus ring and
  /// badges.
  final Widget child;

  /// Expansion factor at full focus, centred on the card.
  final double scale;

  @override
  State<CardFocusExpansion> createState() => _CardFocusExpansionState();
}

class _CardFocusExpansionState extends State<CardFocusExpansion>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// 0-1 progress of the pop; [_zoom] maps it to [CardFocusExpansion.scale].
  late final AnimationController _pop;
  late final Animation<double> _zoom;

  /// The card's layout box, frozen when the pop starts. The pinned slot and
  /// the overlay copy are both built at exactly this size, so the copy lands
  /// pixel-on-top of the slot before it scales.
  Size? _box;

  /// Whether the overlay copy is mounted, which is also the only moment the
  /// in-layout child becomes the pinned slot. Kept in lockstep so the card
  /// never shows a gap: the copy goes up and the visual comes out in the same
  /// frame.
  bool _copyMounted = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: ZplayMotion.base,
      reverseDuration: ZplayMotion.fast,
    );
    _zoom = _pop.drive(Tween<double>(begin: 1.0, end: widget.scale));
    _pop.addStatusListener(_onPopStatus);
    if (widget.focused) {
      // Autofocus can land before the first focus transition is observed.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPop());
    }
  }

  @override
  void didUpdateWidget(covariant CardFocusExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) return;
    if (widget.focused) {
      // Measured here, mid-build: the render tree still holds the pre-focus
      // layout, which is the box the pop must keep - and since focus must not
      // move anything, it is also the box from here on.
      _startPop();
    } else {
      _pop.reverse();
      // If the pop never got going (focus lost within the same frame), no
      // status change will come from the controller - retire the copy here.
      WidgetsBinding.instance.addPostFrameCallback((_) => _retireCopy());
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _startPop() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _box = box.size;
    }
    // `OverlayPortalController.show` refuses to run during build, and this is
    // reached from `didUpdateWidget` - mid-build. The copy and the pinned slot
    // also have to land in the same frame or the card blinks out for one, so
    // everything waits for the frame to end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focused) return;
      if (!_portal.isShowing) {
        _portal.show();
      }
      setState(() => _copyMounted = true);
      _pop.forward();
    });
  }

  void _onPopStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    // A status notification can arrive synchronously from `reverse()`, which
    // `didUpdateWidget` calls mid-build - retire after the frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) => _retireCopy());
  }

  /// Takes the copy down and hands the layout back to the real visual - only
  /// once the pop has fully shrunk back to the card's own size, so nothing
  /// blinks.
  void _retireCopy() {
    if (!mounted || widget.focused || !_pop.isDismissed) return;
    if (_portal.isShowing) {
      _portal.hide();
    }
    if (_copyMounted) {
      setState(() => _copyMounted = false);
    }
  }

  /// What stays in the layout while the pop is up: exactly the card's box and
  /// nothing else. The artwork, title, ring and badges are painted by the
  /// overlay copy above - one visual, one ring, however the card is drawn -
  /// and the slot's frozen size is what pins the neighbours in place.
  Widget _pinnedSlot() {
    final box = _box;
    return SizedBox(width: box?.width, height: box?.height);
  }

  /// The overlay copy: [widget.child] at the card's frozen size, centred on
  /// the card's centre and scaled from there, so the growth is split evenly
  /// between the neighbours on each side.
  Widget _overlayCopy(BuildContext context) {
    final box = _box;
    if (box == null) return const SizedBox.shrink();

    // `Center` unwraps `Positioned.fill`'s tight screen constraints before
    // they reach the follower - the copy must size to its own box, not the
    // screen, or it would be laid out at 960x540 and never match the card.
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.center,
            followerAnchor: Alignment.center,
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: ScaleTransition(
                scale: _zoom,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlayCopy,
      child: CompositedTransformTarget(
        link: _link,
        child: _copyMounted ? _pinnedSlot() : widget.child,
      ),
    );
  }
}
