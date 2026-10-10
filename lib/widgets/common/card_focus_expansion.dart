import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// How far a focused card expands over its neighbours. Netflix's pop sits
/// around 1.1-1.2; 1.15 eats 7.5% of the card's width and height into each
/// neighbour at the same time, from the centre.
const double _popScale = 1.15;

/// How far the popped surface stays inside the overlay's edges once it is open.
///
/// The clamp that uses it is paint-only and progress-multiplied - see
/// [_CardFocusExpansionState._clampShift] - so it never moves a layout box, and
/// tests must pin "inside the window", not this number.
const double _edgeMargin = 12.0;

/// Paints [child] above its neighbours, scaled up, while [focused] - and, when
/// [expandedExtra] is given, grown into one taller surface carrying it - without
/// letting the growth near the card's layout box.
///
/// Three jobs, and the split between them is the whole widget:
///
/// 1. **The layout box never moves.** While popped, the in-layout slot is a
///    pinned box the exact size the card occupied before focus arrived, so
///    neighbours cannot re-flow and the D-pad geometry the page measures stays
///    byte-identical. Only paint moves.
/// 2. **The copy paints above everything.** A list paints children in index
///    order, so a card scaled up in place is painted *under* its right
///    neighbour, and the next rail down covers its bottom growth. The copy is
///    therefore painted in the app's [Overlay] via [OverlayPortal].
/// 3. **Its position is read, not cached.** The copy used to be tracked with
///    `CompositedTransformTarget`/`Follower`, which positions the follower from
///    the transform the leader recorded when it last *painted*. A card inside a
///    scroll view sits inside a repaint boundary the list inserts for it, and
///    scrolling moves that boundary's layer without repainting the card - so the
///    recorded transform goes stale by exactly the distance scrolled, and the pop
///    lands where the card used to be. That is the reported "the expand box
///    renders like three rows above the movie selected": three rows is one page
///    scroll. The copy now asks the card's own render box where it is, every
///    frame it is visible, and the answer cannot be stale because it is not a
///    cache.
///
/// The zoom is an [AnimationController] owned by this state. It drives the
/// surface's scale and the reveal of its bottom half, and nothing else: a focus
/// change rebuilds the card once, never its surroundings.
///
/// The overlay copy is `IgnorePointer`ed: hit testing still lands on the card's
/// real (unscaled) hit target, which is what keeps taps and remote activation
/// on the card the user aimed at.
class CardFocusExpansion extends StatefulWidget {
  const CardFocusExpansion({
    super.key,
    required this.focused,
    required this.child,
    this.expandedExtra,
    this.scale = _popScale,
  });

  /// The key on the overlay copy, so a test can measure what the user sees
  /// rather than reconstructing it from the paint internals.
  static const Key copyKey = Key('card-focus-expansion-copy');

  /// Whether the card is the one the D-pad (or keyboard) is on. The pop is a
  /// focus treatment; a pointer's hover zoom is a separate affordance and must
  /// not drive this, or hovering a card would paint it over app chrome.
  final bool focused;

  /// The card visual. Reused verbatim as the overlay copy, so what pops is
  /// exactly what sits in the layout - including its own focus ring and
  /// badges.
  final Widget child;

  /// Painted under the card's own visual, inside the same surface, while the pop
  /// is up: the card grows a bottom half rather than growing a second box under
  /// itself.
  ///
  /// The slot exists so a card can grow into something with a caption without
  /// the caption touching the layout: it is laid out inside the surface in the
  /// overlay entry, so the page's own box is still the card's - the pinned slot,
  /// the neighbours and the row's arithmetic are all unchanged, and the surface
  /// simply paints over whatever is below.
  ///
  /// Only mounted while the pop is up, which is the same thing as "only while
  /// this card is the one the user is on" - so the extra that loads something is
  /// not loading it for a rail nobody is pointing at.
  final Widget? expandedExtra;

  /// Expansion factor at full focus, centred on the card.
  final double scale;

  @override
  State<CardFocusExpansion> createState() => _CardFocusExpansionState();
}

class _CardFocusExpansionState extends State<CardFocusExpansion>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();

  /// 0-1 progress of the pop; [_zoom] maps it to [CardFocusExpansion.scale].
  late final AnimationController _pop;
  late final Animation<double> _zoom;

  /// The card's layout box, frozen when the pop starts. The pinned slot and the
  /// overlay copy are both built at exactly this size, so the copy lands
  /// pixel-on-top of the slot before it scales.
  Size? _box;

  /// The card's centre in the overlay's coordinates, re-read every frame the
  /// copy is up. Null until the first read, which is why the copy is not built
  /// on the frame the pop starts.
  Offset? _center;

  /// The overlay's own size, read in the same pass as [_center] - it is the
  /// area the popped surface has to fit inside.
  Size? _viewport;

  /// [widget.expandedExtra]'s rendered height while the copy is up, re-read
  /// every follow frame from the extra's own render box.
  ///
  /// The extra is laid out once, inside the copy, and its render box holds the
  /// extra's *full* height on every frame: `SizeTransition` reveals it by
  /// clipping (its `Align` lays the child out loose), so the box never shrinks
  /// with the animation. That makes the fully-open surface height - this widget
  /// [_box]'s height plus this - measurable from the first frame the extra
  /// exists, not only once the pop has finished opening.
  double? _extraHeight;

  /// Anchors [widget.expandedExtra] so its render box can be read for
  /// [_extraHeight]: a [GlobalKey] is what turns a key back into a context.
  final GlobalKey _extraKey = GlobalKey();

  /// Whether the per-frame follow loop is running, so it is started once and
  /// cannot stack.
  bool _following = false;

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
      final placement = _readPlacement();
      setState(() {
        _copyMounted = true;
        _center = placement?.center;
        _viewport = placement?.viewport;
      });
      _follow();
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
      setState(() {
        _copyMounted = false;
        // The extra unmounts with the copy, so its height is no longer
        // measurable - the next pop must read it fresh, not trust a stale box.
        _extraHeight = null;
      });
    }
  }

  /// The card's centre in the overlay entry's coordinates, and the overlay's
  /// own size - one pass, because both come off the same overlay render box and
  /// the clamp needs both.
  ///
  /// The centre is read from the card's own render box rather than from a
  /// cached layer transform - see the class docs. Null when the card is
  /// detached or has not been laid out, in which case the previous answer
  /// stands.
  ({Offset center, Size viewport})? _readPlacement() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;
    return (
      center: box.localToGlobal(
        box.size.center(Offset.zero),
        ancestor: overlayBox,
      ),
      viewport: overlayBox.size,
    );
  }

  /// [widget.expandedExtra]'s rendered height, read from the render box
  /// [_extraKey] anchors - see [_extraHeight] for why that box holds the full
  /// height on every frame. Null while the extra is not mounted or laid out.
  double? _readExtraHeight() {
    final extraContext = _extraKey.currentContext;
    if (extraContext == null) return null;
    final box = extraContext.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.size.height;
  }

  /// Re-reads what the clamp is computed from once per frame while the copy is
  /// up: the card's placement and the extra's height.
  ///
  /// A post-frame callback rather than a `Ticker`, because the pop already owns
  /// this state's single ticker. It costs two render-box reads and one
  /// `setState` only on the frames where one of them actually changed - the
  /// card is inside a scroll view, so "did not move" is the common case and
  /// rebuilds nothing.
  void _follow() {
    if (_following) return;
    _following = true;
    WidgetsBinding.instance.addPostFrameCallback(_followFrame);
  }

  void _followFrame(Duration _) {
    if (!mounted || !_copyMounted) {
      _following = false;
      return;
    }
    final next = _readPlacement();
    final nextExtraHeight = _readExtraHeight();
    // The follow loop's one setState, widened to fire when anything the clamp
    // is derived from changed: the centre (the page scrolled under a D-pad
    // key press), the window, or the extra's height. The extra first measures
    // on this very pass - the frame after the copy mounts - so this is what
    // upgrades the clamp from its no-extra first frame, with no setState the
    // loop did not already have.
    if ((next != null &&
            (next.center != _center || next.viewport != _viewport)) ||
        nextExtraHeight != _extraHeight) {
      setState(() {
        if (next != null) {
          _center = next.center;
          _viewport = next.viewport;
        }
        _extraHeight = nextExtraHeight;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(_followFrame);
  }

  /// How far the painted surface has to move to stay inside the overlay, in
  /// overlay pixels, computed at the final (max) zoom.
  ///
  /// At full zoom the surface paints from `center - scale * box / 2` down and
  /// out to `scale * surfaceHeight`; the clamp brings those edges inside the
  /// window inset by [_edgeMargin]. Bottom first: shift up only as far as the
  /// bottom overflow asks. Then the top: if that shift would put the top above
  /// the margin - the surface is taller than the usable viewport - pin the top
  /// to the margin instead and accept the bottom overflow. The horizontal axis
  /// clamps the same way, so a card at the right edge of a rail paints past
  /// neither edge.
  ///
  /// The caller applies this multiplied by the pop's progress, so at rest it
  /// is zero - the copy sits exactly on the card's slot, with no jump at focus
  /// time - and it grows to this value as the surface opens. It is recomputed
  /// from the current card centre whenever the copy rebuilds, which the follow
  /// loop drives every frame the card moves.
  Offset _clampShift({
    required Size box,
    required Offset center,
    required Size viewport,
    required double surfaceHeight,
  }) {
    final scale = widget.scale;
    final top = center.dy - scale * box.height / 2;
    final bottom = top + scale * surfaceHeight;
    final left = center.dx - scale * box.width / 2;
    final right = left + scale * box.width;

    var shiftY = 0.0;
    if (bottom > viewport.height - _edgeMargin) {
      shiftY = viewport.height - _edgeMargin - bottom;
    }
    if (top + shiftY < _edgeMargin) {
      shiftY = _edgeMargin - top;
    }

    var shiftX = 0.0;
    if (right > viewport.width - _edgeMargin) {
      shiftX = viewport.width - _edgeMargin - right;
    }
    if (left + shiftX < _edgeMargin) {
      shiftX = _edgeMargin - left;
    }
    return Offset(shiftX, shiftY);
  }

  /// What stays in the layout while the pop is up: exactly the card's box and
  /// nothing else. The artwork, title, ring and badges are painted by the
  /// overlay copy above - one visual, one ring, however the card is drawn - and
  /// the slot's frozen size is what pins the neighbours in place.
  Widget _pinnedSlot() {
    final box = _box;
    return SizedBox(width: box?.width, height: box?.height);
  }

  /// The overlay copy: the popped card as **one surface** - the card's own
  /// visual with [widget.expandedExtra] under it - laid out at the card's own
  /// box and scaled about the card's centre.
  ///
  /// One fill, one radius, one clip, no overhang and no second gap. The previous
  /// shape put the extra in its own `Positioned`, 8 dp below the scaled card's
  /// painted bottom and 25% wider on each side, wearing its own background and
  /// its own hairline: from ten feet the eye lands on the panel's edges, and
  /// they belong to nothing the user selected, so the card reads as two objects
  /// - or as the next row appearing - instead of as the selected card growing.
  ///
  /// Scale, never size. The card's *box* stays whatever the layout gave it and
  /// only the paint scales: the row must not re-flow (see the class docs), and
  /// the artwork bounds its decode by the width it is handed - laying it out 15%
  /// wider would ask for a different decode every animation frame.
  Widget _overlayCopy(BuildContext context) {
    final box = _box;
    final center = _center;
    if (box == null || center == null) return const SizedBox.shrink();

    // Where the fully-open surface would paint - the card's box plus the
    // extra's own full height, at the final zoom - and therefore how far it
    // must move to stay inside the window (see _clampShift). On the copy's
    // first frame the extra has not been measured yet; the pop is at 0 then,
    // and zero progress zeroes the clamp, so the follow loop's read - which
    // lands before any progress can show - is in time.
    final viewport = _viewport;
    final clamp = viewport == null
        ? Offset.zero
        : _clampShift(
            box: box,
            center: center,
            viewport: viewport,
            surfaceHeight: box.height + (_extraHeight ?? 0.0),
          );

    return Positioned(
      left: center.dx - box.width / 2,
      top: center.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: Stack(
          // The surface is laid out at the card's box and grows downward with
          // the extra, so it has to be allowed to paint past that box.
          // Everything outside it is clipped by the shell, which is the boundary
          // that should be doing the clipping.
          clipBehavior: Clip.none,
          key: CardFocusExpansion.copyKey,
          children: [
            Positioned(
              // The surface's own origin is the card's top-left corner: the
              // point the extra is measured from, and the point the transform
              // below scales about.
              left: 0,
              top: 0,
              width: box.width,
              child: AnimatedBuilder(
                animation: _zoom,
                // Scaled about the *card's* centre, which is not the surface's:
                // the surface is the card plus whatever the extra has revealed
                // under it, so its own centre walks downward as the panel grows,
                // and scaling about that would drag the card up the screen with
                // every frame of the animation.
                builder: (context, child) {
                  // The clamp displacement rides the pop's own progress: zero
                  // at rest, where the surface must sit exactly on the card's
                  // slot with no jump at focus time, full once the surface is
                  // open. It rides the animation rebuild that already runs every
                  // frame for the zoom, so keeping it live costs no setState of
                  // its own - the shift is only recomputed when the follow loop
                  // rebuilds the copy with new input.
                  final shift = clamp * _pop.value;
                  return Transform.translate(
                    offset: shift,
                    child: Transform(
                      transform: Matrix4.diagonal3Values(
                        _zoom.value,
                        _zoom.value,
                        1,
                      ),
                      origin: Offset(box.width / 2, box.height / 2),
                      child: child,
                    ),
                  );
                },
                // Built once, not per frame: the transforms above are the only
                // things the animation moves.
                child: _surface(context, box),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The popped card itself: [widget.child] with [widget.expandedExtra] directly
  /// under it, inside one fill, one radius and one clip.
  ///
  /// The fill is the colour the artwork frame already paints inside its own
  /// rounded corners, so the artwork's corners sit on their own colour and the
  /// two are one surface rather than a picture on a panel.
  ///
  /// The extra is revealed by [SizeTransition] on the same controller as the
  /// scale: at rest the surface is exactly the card's box - it lands
  /// pixel-on-top of the card it replaces - and its bottom half unfurls from
  /// there, so the growth is the selected card and never a box arriving from
  /// somewhere else.
  Widget _surface(BuildContext context, Size box) {
    final extra = widget.expandedExtra;
    final tokens = context.tokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        // The one lift the popped card carries. It is the shadow the detached
        // panel used to wear, moved onto the surface the panel is now part of: a
        // shadow belongs to the thing that is raised, and two of them draw the
        // seam this shape exists to remove.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        // One clip for the whole card, so nothing inside it - the artwork's own
        // drop shadow above all - paints past the surface's rounded corners.
        borderRadius: ZplayRadius.mdAll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The card's visual at exactly the box the layout gave it. The
            // scale above is paint-only, so this is still the resting card.
            SizedBox(width: box.width, height: box.height, child: widget.child),
            if (extra != null)
              SizeTransition(
                sizeFactor: _pop,
                // Grows downward from the card's bottom edge. The extra's own
                // top padding is all the space there is between the card and its
                // text: a second gap reads as a seam, which is what the user
                // reported seeing.
                alignment: AlignmentDirectional.topStart,
                // The key is how the clamp reads this extra's full height from
                // its render box (see [_extraHeight]); a keyed subtree lays it
                // out exactly once, right here, exactly as before.
                child: KeyedSubtree(key: _extraKey, child: extra),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlayCopy,
      child: _copyMounted ? _pinnedSlot() : widget.child,
    );
  }
}
