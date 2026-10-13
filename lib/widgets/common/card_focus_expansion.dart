import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';

/// How many times wider and taller the popped card is than the resting one.
///
/// Deliberately modest. A rail card that doubles covers the row below it and
/// the next rail along, and once it has done that the eye stops reading it as
/// the card the user is on and starts reading it as a window opened over the
/// page - the reported "it just opens on top". A third larger says *this one*
/// without the card losing the neighbours it grew out of.
///
/// Applied as *layout*, not as a paint scale: the copy is laid out at this
/// multiple of the card's box and animates out from the box itself, so the
/// artwork decodes for the size it is painted at (no upscaled blur) and the
/// details panel under it keeps its own type size instead of being doubled
/// along with the card. See [_CardFocusExpansionState._overlayCopy].
const double _popScale = 1.35;

/// Alpha of the television's backdrop scrim at full pop, before it is
/// multiplied by the expansion's progress.
///
/// Enough to put everything the user is *not* on a stop down and leave the
/// popped card the brightest thing on screen, which is the whole reason the
/// scrim exists; short of the point where the rail the user came from stops
/// being legible, which is what a blackout would cost.
const double _scrimAlpha = 0.55;

/// How far the details rise into place as they fade in, in dp.
///
/// Small on purpose: this is the panel settling under the card, not the panel
/// travelling. Anything larger reads as a second thing arriving, which is the
/// two-objects look the one-surface shape exists to remove.
const double _revealRise = 8.0;

/// Vertical space held back for the details panel when the pop works out how
/// far it is allowed to grow.
///
/// The panel's height is bounded - the synopsis sits in a fixed
/// `_synopsisReserve` box and the name is capped at two lines - so this is a
/// real upper bound, and it means the pop can never grow so large that the
/// details it exists to show would be pushed off the bottom of the screen. On
/// the television's 540 dp canvas it leaves the card about 370 dp - more than
/// the 1.35x a rail card asks for, and short of what a tall poster would need to
/// grow that far, which is the case the cap is really there for: a poster that
/// grew its full third would lose its own caption to the details underneath it.
const double _panelReserve = 150.0;

/// How far the popped surface stays inside the overlay's edges once it is open.
///
/// The clamp that uses it is paint-only and progress-multiplied - see
/// [_CardFocusExpansionState._clampShift] - so it never moves a layout box, and
/// tests must pin "inside the window", not this number.
///
/// A page that declares a [PageContentTop] gets the same margin between the copy
/// and the bottom of the page's chrome, so a pop that had to come down past a
/// toolbar stops the same distance short of the filter row under it as it would
/// from the window's own edge.
const double _edgeMargin = 12.0;

/// Paints [child] above its neighbours, grown, while [focused] - and, when
/// [expandedExtra] is given, into one taller surface carrying it - without
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
/// The growth is an [AnimationController] owned by this state, read through a
/// curve for the size and a later one for the details' reveal. It drives the
/// surface's own size and its bottom half, and nothing else: a focus change
/// rebuilds the card once, never its surroundings.
///
/// **It paints inside the band the page leaves it.** A page whose content starts
/// below its own chrome says so with [PageContentTop], and both the growth and
/// the clamp read that declaration: the fit spends the band, and the copy may
/// not rise above it. Without one the band is the whole window, which is the
/// behaviour every rail had before the signal existed.
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
  /// [_popScale] times the resting card - without subtracting the panel's height
  /// first.
  static const Key copyCardKey = Key('card-focus-expansion-copy-card');

  /// The key on the scrim the pop dims the page with, behind the copy.
  ///
  /// Built only where the form factor has remote input
  /// ([FormFactorService.hasRemoteInput]): a test reads it to state that a
  /// television dims for the D-pad and a pointer device does not.
  static const Key scrimKey = Key('card-focus-expansion-scrim');

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
  ///
  /// Read through [_growth] for everything the animation *draws* - the copy's
  /// size, the clamp displacement that rides it, the details' fade and rise -
  /// and directly where the raw progress is the statement itself: the panel's
  /// `SizeTransition` clips by it, `isCompleted` is what "a copy is open" asks,
  /// and the dismissal rewinds it.
  late final AnimationController _pop;

  /// The growth's curve: the same controller, read through
  /// [ZplayMotion.emphasizedDecelerate].
  ///
  /// The size and the clamp ride this, not the raw progress, so a card growing
  /// by a third arrives with weight and settles rather than snapping open - a
  /// large surface transition, which is what an emphasised curve is for.
  ///
  /// `drive` rather than [CurvedAnimation]: it adds no listener of its own, so
  /// there is nothing here to dispose alongside the controller, and the
  /// details' reveal needs only the forward curve.
  late final Animation<double> _growth;

  /// The details' own reveal: a fade plus [_revealRise] of rise, driven from
  /// [Interval] 0.3 so the panel starts arriving only once the card's own growth
  /// is under way.
  ///
  /// Later than the growth on purpose. Fading in with the card's first frame
  /// makes the panel something the card is *seen to have had all along*; letting
  /// the card open first and then settling the panel under it is what makes the
  /// panel read as the card's own bottom half arriving.
  late final Animation<double> _reveal;

  /// The card's layout box, frozen when the pop starts. The pinned slot and the
  /// overlay copy are both built at exactly this size, so the copy lands
  /// pixel-on-top of the slot before it grows.
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

  /// The y the page says its own content starts at, in the window's
  /// coordinates, or 0 where the page declares nothing - see [PageContentTop].
  ///
  /// Read here rather than in `_overlayCopy` because it has to be: the copy is
  /// painted in the app's [Overlay], which is not a descendant of the page that
  /// declared the chrome, and this state - which *is* - is the one place the
  /// declaration is reachable. The copy carries it back down to the details
  /// panel for the same reason (see [_surface]).
  ///
  /// It is read as a dependency, so a page that declared its chrome and later
  /// changed it (a filter row appearing, say) moves the pop's bounds with it.
  double _contentTop = 0;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      // Slower than the 200 ms this used to run at. The card has a third of the
      // distance to travel now, so the same duration would read as a snap; the
      // reverse stays fast, because a card the user has already left should be
      // gone.
      duration: ZplayMotion.slow,
      reverseDuration: ZplayMotion.fast,
    );
    _growth = _pop.drive(
      CurveTween(curve: ZplayMotion.emphasizedDecelerate),
    );
    _reveal = _pop.drive(
      CurveTween(
        curve: const Interval(0.3, 1.0, curve: ZplayMotion.decelerate),
      ),
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
    // Where the page's own chrome ends. Assigned, not `setState`: this runs
    // during a build that is already rebuilding this subtree, so the field lands
    // before the copy reads it. A page that declares nothing answers 0, and 0 is
    // the window's own top edge - which is the arithmetic this widget did before
    // [PageContentTop] existed.
    _contentTop = PageContentTop.valueOf(context);
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
  /// that the card and the details it carries still fit the band the page left
  /// it.
  ///
  /// The budget is that band less the panel's height - and the panel's height is
  /// *known*, not guessed, because the copy measures it every frame it is up. On
  /// the copy's first frame the panel has not been laid out yet, so
  /// [_panelReserve] stands in; from the second frame on the answer is exact, and
  /// it is stable because the panel's height does not depend on how far the card
  /// grew (its synopsis sits in a fixed box). A card that cannot spend its whole
  /// [CardFocusExpansion.scale] without pushing its own details off the bottom of
  /// the screen grows to what it can and stops - a tall poster, which is most of
  /// the grid - while a rail card, short and wide, spends the lot. Never below 1:
  /// the resting card is the floor.
  ///
  /// **The band, not the window.** A page whose content starts below its own
  /// chrome - a toolbar, a filter row, a tab row - declares that with
  /// [PageContentTop], and the copy may not use the strip above it however much
  /// room it has: on a grid page the focused cell is the *first* row, so the
  /// window's own top is inside the chrome. The band is what is left of the
  /// window below that declaration, less an [_edgeMargin] at each end, and a
  /// page with chrome above it therefore lets the card grow less. A page that
  /// declares nothing answers 0 and the band is the window.
  double _fitScale(Size box, Size viewport) {
    if (box.height <= 0) return widget.scale;
    final panel = _extraHeight ?? _panelReserve;
    final budget = viewport.height - _contentTop - 2 * _edgeMargin - panel;
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
  /// above the bound - the copy is taller than the band - pin the top to the
  /// bound and accept the bottom overflow. The horizontal axis clamps the same
  /// way, so a card at the right edge of a rail paints past neither edge.
  ///
  /// **The top bound is the page's content top, not the window's.** A page that
  /// declares a [PageContentTop] is saying everything above that line is its own
  /// chrome, so the copy may not be pinned to the window's edge and paint over a
  /// toolbar and the row of filters under it: the bound is the declaration plus
  /// one [_edgeMargin], and it never goes above the window's own margin (a page
  /// declaring a content top smaller than the margin changes nothing). A page
  /// that declares nothing answers 0, which is the window's edge - the
  /// arithmetic this clamp has always done.
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

    // The window's own margin, or the page's chrome plus it - whichever is
    // lower. The margin is what keeps the copy off the first pixel of the band:
    // a pop touching the filter row it just cleared reads as a clip, not a gap.
    final topBound = math.max(_edgeMargin, _contentTop + _edgeMargin);

    var shiftY = 0.0;
    if (bottom > viewport.height - _edgeMargin) {
      shiftY = viewport.height - _edgeMargin - bottom;
    }
    if (top + shiftY < topBound) {
      shiftY = topBound - top;
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
  /// shape put the extra in its own `Positioned`, 8 dp below the card's painted
  /// bottom and 25% wider on each side, wearing its own background and
  /// its own hairline: from ten feet the eye lands on the panel's edges, and
  /// they belong to nothing the user selected, so the card reads as two objects
  /// - or as the next row appearing - instead of as the selected card growing.
  ///
  /// **Size, not scale.** The copy is the card's own visual laid out wider -
  /// [_popScale] times as wide at full pop - and grown out from the card's box,
  /// so what is inside it keeps its own metrics: the artwork is drawn at the
  /// size it was decoded for instead of an upscaled bitmap, and the card's own
  /// ring, caption and badge are drawn at the sizes they were designed at
  /// instead of being multiplied along with the card, which is exactly what a
  /// paint scale would have done to them. The
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

    return Positioned.fill(
      child: Stack(
        // `none`, matching the copy's own stack: the clamp is what keeps the
        // copy inside the window, and this wrapper is not the boundary that
        // should be cutting it off.
        clipBehavior: Clip.none,
        children: [
          // The dimming, television only, painted under the copy. On a
          // remote-driven screen the scrim is the focus treatment: everything
          // the user is *not* on goes down a stop, and the card that grew is the
          // only thing at full brightness. On a pointer device focus follows a
          // click, and dimming the whole app for the card under the cursor would
          // be wrong - so there the scrim is not built at all, rather than built
          // invisible.
          if (FormFactorService.hasRemoteInput)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pop,
                  builder: (context, _) => ColoredBox(
                    key: CardFocusExpansion.scrimKey,
                    // Rides the raw progress, so the dim arrives and leaves with
                    // the card instead of lagging a curve behind the growth.
                    color: Colors.black.withValues(
                      alpha: _scrimAlpha * _pop.value,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: center.dx - box.width / 2,
            top: center.dy - box.height / 2,
            width: box.width,
            height: box.height,
            child: IgnorePointer(
              child: Stack(
                // The copy starts at the card's box and grows past it on
                // both axes, so it has to be allowed to paint outside that
                // box. Everything further out is clipped by the shell, which
                // is the boundary that should be doing the clipping.
                clipBehavior: Clip.none,
                key: CardFocusExpansion.copyKey,
                children: [
                  AnimatedBuilder(
                    animation: _growth,
                    // Rebuilt every frame, but only these wrappers are:
                    // `_surface` hands the card's own subtree - and the
                    // panel's - straight through, so their elements and
                    // state survive the animation.
                    builder: (context, _) {
                      final size = 1 + (openScale - 1) * _growth.value;
                      final cardWidth = box.width * size;
                      final cardHeight = box.height * size;
                      // The clamp displacement rides the same curve as the
                      // size it is keeping inside the window: zero at rest,
                      // where the copy must sit exactly on the card's slot
                      // with no jump at focus time, and full once it is
                      // open. Riding one curve keeps the card on its slot
                      // for the whole growth instead of letting the shift
                      // run ahead of the size, and it rides the animation
                      // rebuild that already runs every frame, so keeping
                      // it live costs no setState of its own.
                      final shift = viewport == null
                          ? Offset.zero
                          : _clampShift(
                                  center: center,
                                  viewport: viewport,
                                  // The *settled* geometry, not what the
                                  // animation is passing through: the clamp
                                  // is a statement about where the copy
                                  // ends up, so computing it from the final
                                  // size keeps it from drifting as the copy
                                  // grows.
                                  cardWidth: box.width * openScale,
                                  cardHeight: box.height * openScale,
                                  panelHeight: panelHeight,
                                ) *
                                _growth.value;
                      return Positioned(
                        // The copy grows about the card's *centre*: the
                        // slot's own box is `box`, so each axis hangs off by
                        // half the growth on that axis. The panel is
                        // deliberately not part of this - it hangs below the
                        // card, and recentring on the card plus panel would
                        // drag the card up the screen as the panel unfolds.
                        left: (box.width - cardWidth) / 2 + shift.dx,
                        top: (box.height - cardHeight) / 2 + shift.dy,
                        width: cardWidth,
                        child: PoppedCopyDecode(
                          // What the copy settles at, so the artwork inside
                          // is decoded once, for the size it is finally
                          // painted at.
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
          ),
        ],
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
  /// somewhere else. The unfurling content carries [_reveal] as well: it fades
  /// and rises [_revealRise] into place, starting only once the growth is under
  /// way, so the panel settles under the card rather than appearing already
  /// finished while the card grows over it.
  ///
  /// [box] is the card's own resting box and [factor] the size the animation is
  /// passing through, so the card is laid out directly at the box the copy is
  /// showing.
  Widget _surface(BuildContext context, Size box, double factor) {
    final extra = widget.expandedExtra;
    final tokens = context.tokens;
    // [SlideTransition] measures its offset as a fraction of the child's own
    // size, and the panel's height is known - it is measured every frame it is up
    // (see [_extraHeight]), and the keyed subtree the slide sits inside is what
    // makes it the same height - so dividing the rise by it moves the panel by
    // exactly [_revealRise] whatever the panel's content turns out to measure.
    // [_panelReserve] stands in before the measurement lands, and for a panel
    // that measured zero height, where the fraction would be infinite and the
    // panel is transparent anyway.
    final measured = _extraHeight;
    final panelHeight = measured == null || measured <= 0
        ? _panelReserve
        : measured;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        // The one lift the popped card carries, and a small one. It is the
        // shadow the detached panel used to wear, moved onto the surface the
        // panel is now part of - a shadow belongs to the thing that is raised,
        // and two of them draw the seam this shape exists to remove - but a wide,
        // dark shadow reads as a window floating over the page, which is the look
        // the pop is supposed to avoid. Just enough to sit the card off the rail.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
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
            // The card itself, laid out at the size the copy is showing.
            //
            // This used to be a card laid out at its resting box and blown up
            // with `Transform.scale`, and that is a *paint* scale: it multiplies
            // every stroke and every glyph with it, so the card's 3 dp
            // [CardFocusRing] drew 6 dp, its caption grew and its badge grew -
            // the chunky, wrong edge of the pop. Laid out at the popped size
            // instead, the ring, the caption and the badge are drawn at the
            // metrics they were designed at, and what grows is the card.
            //
            // It leans on the card being built to fill whatever box it is handed,
            // which is how the rail already uses it: the artwork is `Flexible`
            // and the caption is fixed, so the extra height goes to the artwork
            // and the caption keeps its own size - which is why the artwork grows
            // slightly more than the card does, and why a caption that scaled
            // with it would be the wrong answer. The artwork's decode is still
            // pinned to the settled width by [PoppedCopyDecode], so the frames in
            // between never ask for a new decode.
            SizedBox(
              key: CardFocusExpansion.copyCardKey,
              width: box.width * factor,
              height: box.height * factor,
              child: widget.child,
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
                child: KeyedSubtree(
                  key: _extraKey,
                  // The panel asks the page whether it declared chrome above the
                  // surface (see `_CardFocusDetails`'s tight form), and this copy
                  // is painted in the app's [Overlay] - which is *not* a
                  // descendant of the page that declared it. The expansion's own
                  // context is inside that page, so it carries the answer across
                  // the portal. A page that declared nothing hands down 0, and the
                  // panel is the full one it has always been.
                  child: PageContentTop(
                    value: _contentTop,
                    child: FadeTransition(
                      opacity: _reveal,
                      child: SlideTransition(
                        position: _reveal.drive(
                          Tween<Offset>(
                            begin: Offset(0, _revealRise / panelHeight),
                            end: Offset.zero,
                          ),
                        ),
                        child: extra,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if ((notification is ScrollStartNotification ||
                notification is ScrollUpdateNotification) &&
            _copyMounted &&
            _pop.isCompleted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _dismissForScroll(),
          );
        }
        return false;
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _overlayCopy,
        child: _copyMounted ? _pinnedSlot() : widget.child,
      ),
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

/// A page-level declaration of where its own chrome ends and its content
/// starts, so a popped card knows which band of the window it may paint in.
///
/// The pop grows about the card the user is on and rises as it grows, and the
/// clamp that keeps it on screen has only ever known the window - so a card in
/// the first grid row, whose cell starts under a toolbar and a row of filters or
/// tabs, was pinned to the window's own edge and painted over all of it: on the
/// See All grid the genre pills were left half-visible beside the pop, which
/// reads as broken rather than as layering. Only the page knows how tall that
/// chrome is, so it says so here, and the pop treats the band below the
/// declaration as the space it has - see [_CardFocusExpansionState._fitScale]
/// for the growth and [_CardFocusExpansionState._clampShift] for the bound the
/// copy may not rise above.
///
/// The value is a y in the window's coordinates - the bottom of the page's own
/// chrome, i.e. where its scrollable content starts - because that is the space
/// the clamp works in, which is the app's [Overlay]. A page that provides
/// nothing behaves exactly as it did before: [valueOf] answers 0, which is the
/// window's own top edge.
///
/// One consequence worth knowing when reading a page that provides it: the
/// declaration is read by the card *in layout* and handed back down to the copy
/// through the portal, because the overlay the copy is painted in is not a
/// descendant of the page that declared it.
class PageContentTop extends InheritedWidget {
  const PageContentTop({
    super.key,
    required this.value,
    required super.child,
  });

  /// The y, in the window's coordinates, where the page's own content starts.
  final double value;

  /// The declared content top, or 0 where no page is cooperating.
  static double valueOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageContentTop>()?.value ?? 0;

  @override
  bool updateShouldNotify(PageContentTop oldWidget) => oldWidget.value != value;
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
