import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// How many times wider and taller the popped card is than the resting one.
///
/// Applied as *layout*, not as a paint scale: the copy is laid out at this
/// multiple of the card's box and animates out from the box itself, so the
/// artwork decodes for the size it is painted at (no upscaled blur) and the
/// details panel under it keeps its own type size instead of being doubled
/// along with the card. See [_CardFocusExpansionState._overlayCopy].
const double _popScale = 2.0;

/// Vertical space held back for the details panel when the pop works out how
/// far it is allowed to grow.
///
/// The panel's height is bounded - the synopsis sits in a fixed
/// `_synopsisReserve` box and the name is capped at two lines - so this is a
/// real upper bound, and it means the pop can never grow so large that the
/// details it exists to show would be pushed off the bottom of the screen. On
/// the television's 540 dp canvas it leaves the card about 370 dp: the 2x a rail
/// card asks for, and less than that for a tall poster, which cannot double
/// without losing its own caption.
const double _panelReserve = 150.0;

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

  /// The key on the copy's card half - the popped card itself, above the details
  /// panel and inside the same surface.
  ///
  /// [copyKey] measures the whole copy, which includes the panel; this measures
  /// the card, so a test can state the thing the user asked for - the pop is
  /// twice the resting card - without subtracting the panel's height first.
  static const Key copyCardKey = Key('card-focus-expansion-copy-card');

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

  /// 0-1 progress of the pop. It drives the copy's *size* - from the card's own
  /// box out to [CardFocusExpansion.scale] times that box - and the reveal of
  /// the details panel under it. Nothing is scaled: the copy is laid out at each
  /// size it passes through, so the artwork is never upscaled and the panel's
  /// type never grows with the card.
  late final AnimationController _pop;

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

  /// The last [PageScrollPulse] count this card has seen, or null before it has
  /// looked once - so that a dependency change can tell "the user scrolled the
  /// page" from any other inherited rebuild that reaches this card, and so that
  /// a card mounting *after* a scroll is not dismissed by a pulse it never saw.
  int? _seenPageScroll;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: ZplayMotion.base,
      reverseDuration: ZplayMotion.fast,
    );
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A page that provides a [PageScrollPulse] tells this card when the *user*
    // scrolled it - the one scroll a popped card must not travel over. The
    // first read only records where the count starts, so a card that mounts
    // after a scroll is not dismissed by a pulse it never saw.
    final pulse = PageScrollPulse.valueOf(context);
    final seen = _seenPageScroll;
    if (seen == null) {
      // First look: record where the count starts. A card that mounts after a
      // scroll must not be dismissed by a pulse it never saw.
      _seenPageScroll = pulse;
      return;
    }
    if (pulse == seen) return;
    _seenPageScroll = pulse;
    // Only a copy that is actually *open* is in the way. A card that took focus
    // on this same press has a copy that has only just mounted, at zero height,
    // covering nothing - dismissing that one would take the pop away from the
    // card the user just arrived at, which is the opposite of the point.
    if (!_copyMounted || !_pop.isCompleted) return;
    // After the frame, like [_retireCopy]: the pulse lands during a build, and
    // the portal controller refuses to work mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _dismissForScroll());
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
        // The panel unmounts with the copy, so its height is no longer
        // measurable - the next pop must read it fresh, not trust a stale box.
        _extraHeight = null;
      });
    }
  }

  /// Takes the copy down the instant the user scrolls the page.
  ///
  /// Not the shrink: the copy sits over the row the page is scrolling into view,
  /// and a farewell animation is exactly the overlap being removed. The card
  /// keeps the focus - it is still the one the remote is on - so the slot comes
  /// back to it and the page scrolls as if nothing had been popped at all, until
  /// the focus moves away and comes back, which is a new focus and a new pop.
  void _dismissForScroll() {
    if (!mounted || !_copyMounted) return;
    if (_portal.isShowing) {
      _portal.hide();
    }
    // Rewound with the copy, so the next focus animates out from the card again
    // rather than appearing already open.
    _pop.value = 0;
    setState(() {
      _copyMounted = false;
      _extraHeight = null;
    });
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

  /// The rendered height of whatever [key] anchors, or null while it is not
  /// mounted or has not been laid out.
  double? _heightOf(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.size.height;
  }

  /// [widget.expandedExtra]'s rendered height, read from the render box
  /// [_extraKey] anchors - see [_extraHeight] for why that box holds the full
  /// height on every frame. Null while the extra is not mounted or laid out.
  double? _readExtraHeight() => _heightOf(_extraKey);

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
    // is derived from changed: the centre (the page scrolled under a D-pad key
    // press), the window, or the panel's height. Both measurements first land on
    // this very pass - the frame after the copy mounts - so this is what
    // upgrades the clamp from its first frame, with no setState the loop did not
    // already have.
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

  /// How far the copy is allowed to grow: [CardFocusExpansion.scale], capped so
  /// that the card and the details it carries still fit the window.
  ///
  /// The budget is the window less both margins less the panel's height - and
  /// the panel's height is *known*, not guessed, because the copy measures it
  /// every frame it is up. On the copy's first frame the panel has not been laid
  /// out yet, so [_panelReserve] stands in; from the second frame on the answer
  /// is exact, and it is stable because the panel's height does not depend on how
  /// far the card grew (its synopsis sits in a fixed box). A card that cannot
  /// spend its whole 2x without pushing its own details off the bottom of the
  /// screen grows to what it can and stops - a tall poster, which is most of the
  /// grid - while a rail card, short and wide, spends the lot. Never below 1: the
  /// resting card is the floor.
  double _fitScale(Size box, Size viewport) {
    if (box.height <= 0) return widget.scale;
    final panel = _extraHeight ?? _panelReserve;
    final budget = viewport.height - 2 * _edgeMargin - panel;
    return (budget / box.height).clamp(1.0, widget.scale);
  }

  /// How far the copy has to move to stay inside the overlay, in overlay pixels,
  /// computed on the geometry it settles at.
  ///
  /// The card half is `scale` times the card's box and the panel hangs under it
  /// at its own height, so the painted extent runs from `center - card / 2` down
  /// past the card to the panel's bottom. The clamp brings those edges inside
  /// the window inset by [_edgeMargin]. Bottom first: shift up only as far as
  /// the bottom overflow asks. Then the top: if that shift would put the top
  /// above the margin - the copy is taller than the usable viewport - pin the
  /// top to the margin and accept the bottom overflow. The horizontal axis
  /// clamps the same way, so a card at the right edge of a rail paints past
  /// neither edge.
  ///
  /// The caller applies this multiplied by the pop's progress, so at rest it is
  /// zero - the copy sits exactly on the card's slot, with no jump at focus time
  /// - and it grows to this value as the copy opens. It is recomputed from the
  /// current card centre and the measured heights whenever the copy rebuilds,
  /// which the follow loop drives every frame the card moves.
  Offset _clampShift({
    required Offset center,
    required Size viewport,
    required double cardWidth,
    required double cardHeight,
    required double panelHeight,
  }) {
    final top = center.dy - cardHeight / 2;
    final bottom = top + cardHeight + panelHeight;
    final left = center.dx - cardWidth / 2;
    final right = left + cardWidth;

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
  /// visual with [widget.expandedExtra] under it - laid out at [_fitScale] times
  /// the card's own box.
  ///
  /// One fill, one radius, one clip, no overhang and no second gap. The previous
  /// shape put the extra in its own `Positioned`, 8 dp below the scaled card's
  /// painted bottom and 25% wider on each side, wearing its own background and
  /// its own hairline: from ten feet the eye lands on the panel's edges, and
  /// they belong to nothing the user selected, so the card reads as two objects
  /// - or as the next row appearing - instead of as the selected card growing.
  ///
  /// **Size, not scale.** The copy is the card's own visual laid out wider -
  /// twice as wide at full pop - and grown out from the card's box, so what is
  /// inside it keeps its own proportions: the artwork is drawn at the size it
  /// was decoded for instead of an upscaled bitmap, and the details panel under
  /// it keeps its type size instead of being doubled along with the card, which
  /// is exactly what a 2x paint scale would have done to the panel's text. The
  /// row still cannot re-flow - the copy lives in the Overlay and the in-layout
  /// slot stays the card's frozen box (see the class docs) - and at rest the
  /// copy is laid out at exactly the box the card occupies, which is why it
  /// still lands pixel-on-top of the card it replaces and why the growth starts
  /// from the card itself rather than from somewhere else.
  ///
  /// Laying the artwork out at the width it will be painted at would otherwise
  /// ask for a new decode on every frame of the animation, because the image
  /// bounds its decode by the width it is handed. [PoppedCopyDecode] pins that
  /// decode to the width the copy settles at, so the poster is decoded once and
  /// the frames in between only ever scale it down.
  Widget _overlayCopy(BuildContext context) {
    final box = _box;
    final center = _center;
    if (box == null || center == null) return const SizedBox.shrink();

    final viewport = _viewport;
    final openScale = viewport == null ? widget.scale : _fitScale(box, viewport);
    final panelHeight = _extraHeight ?? 0.0;

    return Positioned(
      left: center.dx - box.width / 2,
      top: center.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: Stack(
          // The copy starts at the card's box and grows past it on both axes, so
          // it has to be allowed to paint outside that box. Everything further
          // out is clipped by the shell, which is the boundary that should be
          // doing the clipping.
          clipBehavior: Clip.none,
          key: CardFocusExpansion.copyKey,
          children: [
            AnimatedBuilder(
              animation: _pop,
              // Rebuilt every frame, but only these wrappers are: `_surface`
              // hands the card's own subtree - and the panel's - straight
              // through, so their elements and state survive the animation.
              builder: (context, _) {
                final size = 1 + (openScale - 1) * _pop.value;
                final cardWidth = box.width * size;
                final cardHeight = box.height * size;
                // The clamp displacement rides the pop's own progress: zero at
                // rest, where the copy must sit exactly on the card's slot with
                // no jump at focus time, and full once it is open. It rides the
                // animation rebuild that already runs every frame, so keeping it
                // live costs no setState of its own.
                final shift = viewport == null
                    ? Offset.zero
                    : _clampShift(
                            center: center,
                            viewport: viewport,
                            // The *settled* geometry, not what the animation is
                            // passing through: the clamp is a statement about
                            // where the copy ends up, so computing it from the
                            // final size keeps it from drifting as the copy grows.
                            cardWidth: box.width * openScale,
                            cardHeight: box.height * openScale,
                            panelHeight: panelHeight,
                          ) *
                          _pop.value;
                return Positioned(
                  // The copy grows about the card's *centre*: the slot's own box
                  // is `box`, so each axis hangs off by half the growth on that
                  // axis. The panel is deliberately not part of this - it hangs
                  // below the card, and recentring on the card plus panel would
                  // drag the card up the screen as the panel unfolds.
                  left: (box.width - cardWidth) / 2 + shift.dx,
                  top: (box.height - cardHeight) / 2 + shift.dy,
                  width: cardWidth,
                  child: PoppedCopyDecode(
                    // What the copy settles at, so the artwork inside is decoded
                    // once, for the size it is finally painted at.
                    cacheWidth: (box.width * openScale * 3)
                        .round()
                        .clamp(96, 1280),
                    child: _surface(context, box, size),
                  ),
                );
              },
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
  /// card's own size: at rest the surface is exactly the card's box - it lands
  /// pixel-on-top of the card it replaces - and its bottom half unfurls from
  /// there, so the growth is the selected card and never a box arriving from
  /// somewhere else.
  ///
  /// [box] is the card's own resting box and [factor] the size the animation is
  /// passing through, so the card is laid out at the box it knows and *painted*
  /// at the size the copy is showing.
  Widget _surface(BuildContext context, Size box, double factor) {
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
            // The card's box at the size the copy is showing, with the card laid
            // out at its resting box inside it and painted up to fill it.
            //
            // Laid out at the resting box on purpose: a card is built to fill
            // whatever box it is handed, so the shape logic inside it - the
            // artwork's aspect, its caption, its badge - is the shape the rail
            // already drew, and `Center` is what hands it those loose
            // constraints. The growth is the paint, and [PoppedCopyDecode] pins
            // the artwork's decode to the size it is painted at, so what the user
            // sees is a sharper card twice the size rather than an upscaled one.
            SizedBox(
              key: CardFocusExpansion.copyCardKey,
              width: box.width * factor,
              height: box.height * factor,
              child: Center(
                child: Transform.scale(
                  scale: factor,
                  child: SizedBox(
                    width: box.width,
                    height: box.height,
                    child: widget.child,
                  ),
                ),
              ),
            ),
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

/// The decode width pinned for artwork laid out inside a popped card copy.
///
/// The copy's card is laid out at a width its own animation is still growing, so
/// a decode keyed to the layout width would ask for a new one on every frame of
/// the animation - and every one of those is a fresh decode of the poster rather
/// than a cache hit, which is the cost the old paint-only pop existed to avoid.
/// This carries the width the copy *settles* at, so the image is decoded once,
/// for the size it is finally painted at, and the frames in between only ever
/// scale it down.
///
/// Read by the card's own artwork frame in `movie_card.dart`; everywhere else
/// the width the layout hands the image is the right answer.
class PoppedCopyDecode extends InheritedWidget {
  const PoppedCopyDecode({
    super.key,
    required this.cacheWidth,
    required super.child,
  });

  /// The decode width for artwork inside this subtree, in physical pixels.
  final int cacheWidth;

  /// The pinned decode width, or null when the artwork is not inside a popped
  /// copy and its own layout should decide.
  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PoppedCopyDecode>()?.cacheWidth;

  @override
  bool updateShouldNotify(PoppedCopyDecode oldWidget) =>
      oldWidget.cacheWidth != cacheWidth;
}

/// A page-level signal that the *user* scrolled the page, so a popped card can
/// get out of the way instead of travelling over the row scrolling into view.
///
/// The distinction it draws is the whole reason it exists: a page scrolls for
/// two reasons - the user asked it to (up or down at the end of the traversal),
/// or a card that just took focus had to be revealed. A popped card must come
/// down for the first and stay up for the second, and the scroll itself cannot
/// tell them apart, because both are an `animateTo` on the same controller. So
/// the page announces the first: it bumps this counter where it handles the key,
/// and every card popped at that moment takes its copy down at once - without
/// the shrink, which is the overlap being removed - rather than animating out
/// over the content arriving underneath it.
///
/// Only [CardFocusExpansion] listens, and a page that never provides one behaves
/// exactly as it did before: the pop is a focus treatment, not a scroll one.
class PageScrollPulse extends InheritedNotifier<ValueNotifier<int>> {
  const PageScrollPulse({
    super.key,
    required ValueNotifier<int> super.notifier,
    required super.child,
  });

  /// The count right now, or 0 where no page is cooperating.
  static int valueOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageScrollPulse>()?.notifier?.value ??
      0;
}
