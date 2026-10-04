import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// How far a focused card expands over its neighbours. Netflix's pop sits
/// around 1.1-1.2; 1.15 eats 7.5% of the card's width and height into each
/// neighbour at the same time, from the centre.
const double _popScale = 1.15;

/// The gap between the card and the panel it grows into.
const double _extraGap = ZplaySpacing.s8;

/// How far the grown panel overhangs the card on each side, as a fraction of the
/// card's width.
///
/// A rail's thumbnails are ~176 dp wide, which is fine for a picture and too
/// narrow for a synopsis: at the card's own width the text wraps to four short
/// lines and reads as a column of words. A quarter on each side buys 50% more
/// line without the panel running into anything it would be confused with - the
/// neighbour it overlaps is the point, not an accident.
const double _extraOverhang = 0.25;

/// Paints [child] above its neighbours, scaled up, while [focused] - and, when
/// [expandedExtra] is given, grows a panel under it - without letting either near
/// the card's layout box.
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
/// The zoom is an [AnimationController] owned by this state, driving only the
/// overlay copy's [ScaleTransition]: a focus change rebuilds the card once,
/// never its surroundings.
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

  /// Painted under the card, inside the same overlay copy, while the pop is up.
  ///
  /// The slot exists so a card can grow into something with a caption without
  /// the caption touching the layout: it is a sibling of the scaled copy inside
  /// the overlay entry, so the page's own box is still the card's - the pinned
  /// slot, the neighbours and the row's arithmetic are all unchanged, and the
  /// panel simply paints over whatever is below.
  ///
  /// Only mounted while the pop is up, which is the same thing as "only while
  /// this card is the one the user is on" - so a panel that loads something is
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
      setState(() {
        _copyMounted = true;
        _center = _readCenter();
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
      setState(() => _copyMounted = false);
    }
  }

  /// The card's centre, in the coordinates the overlay entry is laid out in.
  ///
  /// Read from the card's own render box rather than from a cached layer
  /// transform - see the class docs. Null when the card is detached or has not
  /// been laid out, in which case the previous answer stands.
  Offset? _readCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;
    return box.localToGlobal(box.size.center(Offset.zero), ancestor: overlayBox);
  }

  /// Re-reads the card's position once per frame while the copy is up.
  ///
  /// A post-frame callback rather than a `Ticker`, because the pop already owns
  /// this state's single ticker. It costs one render-box read and one `setState`
  /// on the frames where the card actually moved - the card is inside a
  /// scroll view, so "did not move" is the common case and rebuilds nothing.
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
    final next = _readCenter();
    if (next != null && next != _center) {
      setState(() => _center = next);
    }
    WidgetsBinding.instance.addPostFrameCallback(_followFrame);
  }

  /// What stays in the layout while the pop is up: exactly the card's box and
  /// nothing else. The artwork, title, ring and badges are painted by the
  /// overlay copy above - one visual, one ring, however the card is drawn - and
  /// the slot's frozen size is what pins the neighbours in place.
  Widget _pinnedSlot() {
    final box = _box;
    return SizedBox(width: box?.width, height: box?.height);
  }

  /// The overlay copy: [widget.child] at the card's frozen size, centred on the
  /// card's live centre and scaled from there, so the growth is split evenly
  /// between the neighbours on each side - plus [widget.expandedExtra] under it.
  Widget _overlayCopy(BuildContext context) {
    final box = _box;
    final center = _center;
    if (box == null || center == null) return const SizedBox.shrink();
    final extra = widget.expandedExtra;

    return Positioned(
      left: center.dx - box.width / 2,
      top: center.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: Stack(
          // The grown panel hangs below the card's box, and the Stack's own box
          // is that of the card - so the panel has to be allowed to paint past
          // it. Everything above is clipped by the shell, which is the boundary
          // that should be doing the clipping.
          clipBehavior: Clip.none,
          key: CardFocusExpansion.copyKey,
          children: [
            ScaleTransition(scale: _zoom, child: widget.child),
            if (extra != null)
              Positioned(
                // Measured from the *scaled* card's bottom edge, not the box's:
                // the copy grows by `scale` around the card's centre, so its
                // painted bottom is `h * (1 + scale) / 2` below the box's top -
                // half the growth on each side. A gap measured from the unscaled
                // box would tuck the panel's top edge under the grown card and
                // cover its bottom 15 dp.
                top: box.height * (1 + widget.scale) / 2 + _extraGap,
                left: -box.width * _extraOverhang,
                right: -box.width * _extraOverhang,
                child: extra,
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
