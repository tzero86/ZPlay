import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'horizontal_edge_fade.dart';
import 'focusable_card.dart';

/// One option in a [TabStrip].
@immutable
class TabStripOption<T> {
  const TabStripOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;

  /// Drawn before the label. Null leaves the pill text-only.
  final IconData? icon;
}

/// A horizontally scrolling row of content-sized pills, for an unbounded number
/// of short options.
///
/// **The strip paints nothing.** It used to fill the selected pill with the
/// accent and the resting ones with a raised surface, which made a strip of
/// labels read as a row of buttons sitting on the page. These are an overlay
/// on the content beneath them, like the shell's own destinations: a pill at
/// rest is nothing but its label, the selected one carries a short accent bar
/// underneath it, and [CardFocusRing] is the only edge any pill ever draws.
///
/// **Why this is not [SegmentedTabs].** `SegmentedTabs` is structurally an
/// equal-width control: it clamps its track to the available width and divides it
/// into equal segments (`trackWidth / options.length`), so seven vertical labels
/// on a 390 px phone get about 56 px each against a `_minSegmentWidth` of 78 and
/// the labels crush, while its sliding indicator is a fraction of the track,
/// which stops meaning anything the moment the row is allowed to scroll. Making
/// it scroll would mean discarding both of the things it is good at. This control
/// is the opposite trade: pills as wide as their own text, a scroll position
/// instead of an indicator, and no assumption that the options fit. It stays a
/// single-select control with a 44 px target, the same keyboard and D-pad story
/// as [SegmentedTabs] because both are built on [FocusableCard], and the same
/// token vocabulary, so the two look like siblings even though they behave
/// differently.
///
/// Use [SegmentedTabs] when the labels fit and the choice is a mode switch; use
/// this when the count is data-driven.
class TabStrip<T> extends StatefulWidget {
  const TabStrip({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticsLabel,
    this.height = 44,
  });

  final List<TabStripOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Announced by screen readers as the name of the whole control.
  final String? semanticsLabel;

  /// Defaults to the 44 px comfortable minimum target. A caller that wants the
  /// ten-foot target passes its own.
  final double height;

  @override
  State<TabStrip<T>> createState() => _TabStripState<T>();
}

class _TabStripState<T> extends State<TabStrip<T>> {
  final ScrollController _scroll = ScrollController();

  /// One key per pill, so the selected one can be located in the viewport and
  /// asked to reveal itself. Index-aligned with [TabStrip.options].
  late List<GlobalKey> _pillKeys;


  /// Read here rather than inside the callbacks: the reveal and the pill
  /// transitions run outside build, and the tokens' own guidance is to collapse
  /// the duration and keep the curve when the platform asks for less motion.
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void initState() {
    super.initState();
    _pillKeys = _keysFor(widget.options.length);
    // The edge fade tracks this controller itself, so this only has to worry
    // about the reveal.
    // Metrics do not exist until the first layout, so the initial reveal and the
    // initial fade state both have to wait for it. The reveal is unanimated: the
    // strip is entering already on its selection, not moving to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelected(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant TabStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      // Only the keys change: the fade re-reads its own edges on the metrics
      // notification that the new layout raises.
      _pillKeys = _keysFor(widget.options.length);
    }
    if (oldWidget.selected != widget.selected) {
      _revealSelected(animate: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static List<GlobalKey> _keysFor(int count) =>
      List<GlobalKey>.generate(count, (_) => GlobalKey());

  /// Brings the selected pill into view, centred. Centring rather than "scroll
  /// only if off screen" is deliberate: it is what Flutter's own tab bar does, it
  /// keeps the selected pill away from the fading edge, and it makes the
  /// selection change visible even when the pill was already on screen.
  ///
  /// A live selection change is deferred by one frame. That is not a style
  /// choice: the change arrives through [didUpdateWidget], which runs inside the
  /// parent's build, and a scroll activity started at that point does not
  /// animate at all (measured: the position stays exactly where it was, so the
  /// strip never follows the selection). Deferring costs one frame of the
  /// animation, which starts as the new selection paints, and is invisible.
  void _revealSelected({required bool animate}) {
    final index =
        widget.options.indexWhere((option) => option.value == widget.selected);
    // `indexWhere` returns -1 for a selection that is not among the options, and
    // an empty strip has no key at any index.
    if (index < 0 || index >= _pillKeys.length) return;
    final pillContext = _pillKeys[index].currentContext;
    if (pillContext == null) return;

    if (!animate) {
      // The first layout path, already inside a post-frame callback: a jump has
      // no activity to lose, so it can run now.
      _scrollIntoView(pillContext, animate: false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !pillContext.mounted) return;
      _scrollIntoView(pillContext, animate: true);
    });
  }

  void _scrollIntoView(BuildContext pillContext, {required bool animate}) {
    Scrollable.ensureVisible(
      pillContext,
      alignment: 0.5,
      duration: animate ? _motionDuration : Duration.zero,
      curve: ZplayMotion.standard,
    );
  }

  Duration get _motionDuration =>
      _reduceMotion ? Duration.zero : ZplayMotion.base;


  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final duration = _motionDuration;

    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: SizedBox(
        height: widget.height,
        child: HorizontalEdgeFade(
          scrollController: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // **The row needs a bounded height.** A `SingleChildScrollView`
            // gives its child an unbounded cross axis, so the `Row` measured
            // each pill by its *content* rather than by the height asked for,
            // and the pill's own `Container(height:)` was then overruled by the
            // text inside it. The request is authoritative - the row's geometry
            // is the app's chrome, and a caller that reserves 28 dp cannot be
            // handed 26.
            child: SizedBox(
              height: widget.height,
              child: Row(
                spacing: ZplaySpacing.s8,
                children: [
                  for (var i = 0; i < widget.options.length; i++)
                    KeyedSubtree(
                      key: _pillKeys[i],
                      child: _Pill<T>(
                        option: widget.options[i],
                        selected: widget.options[i].value == widget.selected,
                        height: widget.height,
                        duration: duration,
                        tokens: tokens,
                        onSelected: () =>
                            widget.onSelected(widget.options[i].value),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// One pill: label, optional icon, and the whole hit target.
///
/// The pill is an overlay on the page rather than a control drawn on it, so it
/// paints no fill at rest and none when selected either: the accent bar under
/// the label ([_underline]) and the label's own brightness are what say which
/// option is chosen, and [CardFocusRing] is the only edge it ever draws.
class _Pill<T> extends StatelessWidget {
  const _Pill({
    required this.option,
    required this.selected,
    required this.height,
    required this.duration,
    required this.tokens,
    required this.onSelected,
  });

  final TabStripOption<T> option;
  final bool selected;
  final double height;
  final Duration duration;
  final ZplayTokens tokens;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      // Own the pill: without excluding the descendants the label and the icon
      // are announced as separate items with no button or selected state on
      // either, and the tap action would be dropped along with them.
      excludeSemantics: true,
      onTap: onSelected,
      child: FocusableCard(
        onTap: onSelected,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.fullAll,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
            decoration: _surface,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon != null) ...[
                  Icon(option.icon,
                      size: ZplaySpacing.s16, color: _iconColor(state)),
                  const SizedBox(width: ZplaySpacing.s8),
                ],
                // The label and its bar, in a `Stack` that holds nothing but
                // `Positioned` children. The bar is anchored to the *label's*
                // box rather than to the pill's, so it needs a parent with a
                // box of its own: the label carries the bar, not the pill, which
                // is what lets the selected pill keep exactly the resting pill's
                // box and leaves the glyph where it was.
                Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    // The label, with room below it for the bar. The padding is
                    // what gives the bar somewhere to sit *inside* the stack: a
                    // `Positioned` child never contributes to a `Stack`'s size,
                    // so a bar hung below a text-only stack is drawn outside it
                    // and clipped away. That is why the bar measured at exactly
                    // the right rect and still never appeared.
                    Padding(
                      padding: const EdgeInsets.only(bottom: ZplaySpacing.s4),
                      child: Text(
                        option.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.label.toStyle(
                          color: _labelColor(state),
                        ),
                      ),
                    ),
                    _underline(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The pill's own surface: **nothing is painted, in either state.**
  ///
  /// One object, shared by every pill in every state, because nothing about it
  /// depends on the selection - which is the point. The unselected pill was a
  /// raised chip so it would stay legible on a page background that is not the
  /// canvas, and the selected one was a block of accent; between them a strip of
  /// verticals was the most button-like control in the app. The labels carry
  /// that contrast on their own against the page, so the surface has nothing
  /// to contribute and says nothing.
  ///
  /// The border is **reserved and never painted.** Flutter reserves a border's
  /// width whether or not the border is painted, so a pill that dropped this
  /// would be 2 dp narrower than one that keeps it - and every pill after it in
  /// the row would slide sideways the moment its neighbour was selected.
  ///
  /// Drawing that width was also what made the switcher read as a row of
  /// buttons: the prototype's own switcher pill is a filled chip with no
  /// `border` rule at all, so a line here is a second edge the control never
  /// needed. Transparent reserves the space and paints nothing, leaving
  /// [CardFocusRing] the only line a pill draws; a border beside it is the ghost
  /// border inside the shape.
  static final BoxDecoration _surface = BoxDecoration(
    color: Colors.transparent,
    borderRadius: ZplayRadius.fullAll,
    border: Border.all(color: Colors.transparent),
  );

  /// The selection mark: a short accent bar under the label.
  ///
  /// `Positioned`, so it is decoration over the label rather than part of it.
  /// It cannot widen the label, push it off centre or move the glyph, which is
  /// why it can exist on the selected pill without that pill changing shape. It
  /// is full-bleed across the label's width - `bottom` is the only inset that
  /// is not a zero - so a label that has been ellipsised brings its shorter bar
  /// with it.
  ///
  /// [ZplayMotion] drives the change. Losing selection collapses the bar to
  /// nothing and gaining it grows one out of the label's centre, so the accent
  /// travels between pills instead of blinking out of one and back into
  /// another. [duration] arrives already collapsed when the platform asks for
  /// reduced motion, which keeps the curve and drops the wait.
  Widget _underline() => Positioned(
        left: ZplaySpacing.s0,
        right: ZplaySpacing.s0,
        bottom: ZplaySpacing.s0,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: duration,
          curve: ZplayMotion.emphasized,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(
              scaleX: t,
              alignment: Alignment.center,
              child: child,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: tokens.accent),
            child: const SizedBox(height: ZplaySpacing.s2),
          ),
        ),
      );

  /// The glyph is neutral in every state.
  ///
  /// It used to take [ZplayTokens.onAccent] on the selected pill, which needed
  /// the accent fill underneath to be legible at all and marked the same pill
  /// twice. The bar under the label is the mark now. A pill the pointer or the
  /// remote is on still brightens, so both input families can see what they are
  /// pointing at.
  Color _iconColor(CardInteraction state) =>
      state.highlighted ? tokens.textPrimary : tokens.textSecondary;

  /// The label is the brightest thing on the selected pill and the dimmest on a
  /// resting one: the accent says which option, the brightness says which words.
  /// A pointed-at label reads like the selected one, for the same reason the
  /// glyph does.
  ///
  /// **One weight in every state.** The selected label used to be w600 against
  /// the resting w500, and the two have different advance widths, so the
  /// selected pill is a fraction wider and every pill after it shifts by that
  /// fraction when the selection moves. Selection is the bar and the brightness
  /// now, and neither of those is a width.
  Color _labelColor(CardInteraction state) =>
      selected || state.highlighted ? tokens.textPrimary : tokens.textSecondary;
}
