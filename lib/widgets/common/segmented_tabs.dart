import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// One option in a [SegmentedTabs] control.
@immutable
class SegmentedTabOption<T> {
  const SegmentedTabOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;

  /// Shown under the label. Null hides the number, for callers whose data has
  /// no meaningful count — a wrong number is worse than none.
  final int? count;
}

/// A single-choice control: equal-width segments, and one accent bar that
/// travels to whichever segment is selected.
///
/// Built because the app hand-rolls this pattern repeatedly — `ChoiceChip` rows
/// in IPTV, audiobooks and books, text tabs with per-tab underlines on Home —
/// and every one of those is pointer-sized with no D-pad story.
///
/// **Nothing at rest draws a shape.** The control used to paint a low-alpha
/// track around itself *and* a filled accent block on the selected segment,
/// which is two boxes: the outer one made all seventeen of these read as a
/// widget sitting on the page, and the inner one made the selected option read
/// as a button. Both are gone. Selection is the travelling bar under the label
/// and the label's own brightness — the same two marks `ShellRail` uses for the
/// top bar — and the segments sit on the surface behind them like the
/// destinations there. The equal widths stay, because they are the hit target
/// and the D-pad order, but nothing paints a resting fill or a resting outline.
///
/// **Assumes a dark surface.** The unselected labels are white at
/// [ZplayOpacity.textSecondary], so on a light surface they would be
/// near-invisible. The reader's Light and Sepia themes are exactly that and are
/// not [ZplayTokens], which is why the reader's own margin picker was left as
/// chips rather than converted — flagged by the conversion pass that found it.
/// Making this theme-agnostic means taking those two colours from the ambient
/// [ColorScheme] instead of white.
///
/// **Segments are sized to their content, not by `Expanded`.** That is not a
/// style preference: Home places this control in the app bar's [Row], where the
/// incoming width is unbounded, and a flex child in an unbounded row collapses
/// in release (labels crushed together, bar mis-sized) or throws in debug.
/// Sizing to content gives the control a width of its own, which works in both a
/// bounded parent and an unbounded one. Segments stay equal either way, which is
/// what keeps the bar's arithmetic honest.
class SegmentedTabs<T> extends StatelessWidget {
  final List<SegmentedTabOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Announced by screen readers as the name of the whole control.
  final String? semanticsLabel;

  /// Defaults to the 44px comfortable minimum target.
  final double height;

  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticsLabel,
    this.height = 44,
  }) : assert(options.length > 1, 'a segmented control needs two or more tabs');

  /// The corner radius of a segment, less the [_inset].
  ///
  /// It was named for the track when the track was a painted box drawn at this
  /// radius. There is no track now: the radius belongs to [CardFocusRing],
  /// which is the only edge the control draws on a segment, so the constant
  /// follows the thing that still uses it. The value is unchanged — the ring
  /// hugs the same shape it did before.
  static const double _segmentRadius = 12;
  static const double _inset = 3;

  /// Side padding inside a segment. The first version had none, so adjacent
  /// labels sat against each other.
  static const double _hPad = 16;
  static const double _minSegmentWidth = 78;

  /// Slack for [CardFocusRing]'s 2 dp border, which is painted inside the
  /// segment and so takes width from the label only while the segment is
  /// focused.
  static const double _ringAllowance = 8;

  /// The travelling bar's thickness. Matches the focus ring's 2 dp, so the two
  /// marks the control can draw are the same weight.
  static const double _barThickness = ZplaySpacing.s2;

  /// Where the bar sits: the control's bottom edge, [_inset] up.
  ///
  /// It is decoration over the segments rather than part of them, so it costs
  /// the labels no width — the bar is `Positioned`, and a `Positioned` child
  /// contributes nothing to a [Stack]'s size. The [_inset] is the margin the
  /// segments already have, which is what keeps the bar inside the control's
  /// box: a bar hung past the bottom edge of the box it is anchored to is drawn
  /// outside that box and clipped away, which is how `ShellRail`'s bar once
  /// measured at exactly the right rect and still never appeared.
  static const double _barBottom = _inset;

  /// The narrowest the bar may be drawn, so a segment too small for its own
  /// padding still reports the selection rather than losing it entirely.
  static const double _minBarWidth = ZplaySpacing.s12;

  /// The label style. Measured at the selected weight so the widest case is the
  /// one budgeted for.
  static TextStyle _labelStyle(bool selected) => TextStyle(
        fontSize: 13,
        letterSpacing: 0.1,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      );

  static const TextStyle _countStyle = TextStyle(
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);
    final radius = BorderRadius.circular(_segmentRadius - _inset);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final natural = _contentSegmentWidth() * options.length;
          // Two width sources, and they must not be mixed: a parent that
          // demands an exact width (a SizedBox, an Expanded) wins, and the
          // segments divide whatever that is — the bar is a fraction of the
          // control, so any mismatch shows up as it sitting off-centre. Only
          // when the parent is loose does the control size to its labels, which
          // is the app bar case. Clamped so a tight desktop window cannot push
          // the app bar's row into overflow.
          final tight =
              constraints.minWidth == constraints.maxWidth &&
                  constraints.minWidth.isFinite;
          final trackWidth = tight
              ? constraints.maxWidth
              : math.min(natural, constraints.maxWidth);
          final segmentWidth = trackWidth / options.length;

          return SizedBox(
            height: height,
            width: trackWidth,
            // **The control paints no track.**
            //
            // It used to wrap itself in a 0.05 white fill behind a 0.06 border,
            // which is two concentric edges around a widget that is really just
            // a row of equal hit targets — the resting shape is what made all
            // seventeen of these read as a button sitting on the page. The
            // `SizedBox` is kept because it *reserves* the control's box: that
            // is what keeps the bar's travel and the equal segments in step,
            // and what makes the two states the same size.
            child: Stack(
              children: [
                // The selection mark: a short accent bar that travels between
                // the equal segments, so moving between them reads as one
                // selection moving rather than one mark blinking out and
                // another blinking in.
                //
                // It reuses the geometry the filled indicator had — the same
                // [AnimatedAlign] over the same `FractionallySizedBox` — so
                // there is still exactly one positioning scheme here and the
                // bar is centred on whichever segment shares its index. What
                // changed is the child: a 2 dp bar across the bottom of the
                // segment, as wide as the label it underlines.
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: _duration(context),
                    curve: ZplayMotion.standard,
                    alignment: Alignment(_alignX(selected), 1),
                    child: FractionallySizedBox(
                      widthFactor: 1 / options.length,
                      heightFactor: 1,
                      // The bar is sized to the label's own box rather than
                      // filling the segment: `_barWidth` caps it there, so a
                      // segment that has been widened by a tight parent still
                      // gets a mark under the word and not a bracket around
                      // the cell. Vertical only, so no label loses width.
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: _barBottom),
                          child: SizedBox(
                            height: _barThickness,
                            width: _barWidth(segmentWidth),
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: tokens.accent),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final option in options)
                      SizedBox(
                        width: segmentWidth,
                        child: _Segment(
                          option: option,
                          selected: option.value == selected,
                          radius: radius,
                          onTap: () => onSelected(option.value),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// -1 for the first segment and +1 for the last, matching the segment that
  /// shares its index — the horizontal half of the bar's travel. The vertical
  /// half is fixed at the bottom edge ([_barBottom]), where it sits on every
  /// option alike, so the bar moves along the row and never changes height.
  double _alignX(T value) {
    final index = options.indexWhere((option) => option.value == value);
    if (index < 0) return 0;
    return index * 2 / (options.length - 1) - 1;
  }

  /// Equal segment width, driven by the widest label (or count) plus the space
  /// the segment itself consumes.
  ///
  /// The padding **and** the inset both eat into a segment's text width — the
  /// inset is a margin on the box inside the segment. Budgeting only [_hPad]
  /// left the widest label 2px short, which is why "Movies" rendered as "Movi…"
  /// while the shorter labels were fine.
  ///
  /// [_ringAllowance] is 8, not 4. The 4 dp of slack was not enough for the
  /// focus ring: [CardFocusRing] paints a 2 dp border inside the segment when
  /// it is focused, so the focused label had 4 dp less room than the budgeted
  /// one. "Movies" is the widest of the home filters, so it was exactly the
  /// label that truncated - and only while focused, which reads as the control
  /// shrinking under the remote rather than as a text problem.
  ///
  /// There is deliberately no upper bound. A 136px ceiling was truncating
  /// longer labels — "Compact (Dense Grid)" became "Compact (Dense…" — where
  /// the chips they replaced had shown them in full, and a truncated label is
  /// worse than a wide control. A caller short of room gets the width it
  /// offers instead, and the label ellipsises only as a last resort.
  ///
  /// There is no term for the track's own 1 dp border, because there is no
  /// longer a track to draw one. It was charged here for as long as it was
  /// painted inside the track on both sides, because the budget covers the
  /// label and the segment but not the line between the control and the outside
  /// world: without that 2 dp the two ends of the track came out narrower than
  /// the labels had been sized for, and "Downloads" rendered as "Downloa…" —
  /// a two-tab control is small enough that 2 dp is the difference between a
  /// label that fits and one that does not. Dropping the line drops the charge
  /// with it. Nothing else moved: [CardFocusRing] still paints inside the
  /// segment while it is focused, and that is [_ringAllowance]'s job.
  double _contentSegmentWidth() => math.max(
        _widestLabel() + (_hPad + _inset) * 2 + _ringAllowance,
        _minSegmentWidth,
      );

  /// The widest label or count in the control, measured.
  ///
  /// Shared with [_barWidth], so the bar under a segment can never be drawn
  /// wider than the text it is underlining - the two are the same measurement
  /// rather than two constants that have to be kept in step.
  double _widestLabel() {
    var widest = 0.0;
    for (final option in options) {
      widest = math.max(widest, _textWidth(option.label, _labelStyle(true)));
      final count = option.count;
      if (count != null) {
        widest = math.max(widest, _textWidth('$count', _countStyle));
      }
    }
    return widest;
  }

  /// How wide the bar is drawn, capped to the label's own box.
  ///
  /// A segment is as wide as the *widest* label in the control, so the bar has
  /// to be sized against that rather than against the segment it happens to be
  /// under: on a tight parent the segments divide whatever width they are
  /// offered, which on a television band puts four or five short labels in
  /// cells hundreds of dp wide. A bar filling such a cell is a bracket around
  /// the option rather than a mark under the word, which is the button-look
  /// this control was taken apart to remove.
  ///
  /// Clamped to the segment as well, so a control that has been squeezed — the
  /// case [_contentSegmentWidth]'s budget exists for — gets a bar that narrows
  /// with its labels instead of overflowing the cell it is drawn in — but
  /// floored at [_minBarWidth], so a segment narrower than its own padding
  /// still gets a visible mark. A bar that has been squeezed to nothing stops
  /// reporting the selection at all, which is the one failure this control
  /// cannot have.
  double _barWidth(double segmentWidth) => math.max(
        math.min(
          _widestLabel(),
          segmentWidth - (_hPad + _inset) * 2,
        ),
        math.min(_minBarWidth, segmentWidth),
      );

  /// The bar's travel, collapsed where the platform asks for reduced motion.
  ///
  /// The curve stays and only the duration goes, per [ZplayMotion].
  static Duration _duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : ZplayMotion.base;

  static double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

}

class _Segment<T> extends StatelessWidget {
  final SegmentedTabOption<T> option;
  final bool selected;
  final BorderRadius radius;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: option.count == null
          ? option.label
          : '${option.label}, ${option.count} titles',
      // Own the whole segment: without excluding the descendants a screen
      // reader announces the label and the count as two separate items, with
      // no button or selected state on either. Re-stating the tap action here
      // is part of that — excluding descendants would otherwise drop it.
      onTap: onTap,
      excludeSemantics: true,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) {
          // The label is the second half of the selection mark, and its
          // brightness rather than its weight carries it, the way `ShellRail`'s
          // destinations do. A highlighted-but-unselected segment reads as
          // bright too, so a pointer and a remote can both see what they are
          // on — which matters more now that nothing is filled in under either
          // of them.
          //
          // Tokens rather than `Colors.white.withValues`, which is what the
          // accent fill forced: a label drawn on the accent has to be picked
          // against that accent, and with the fill gone so does the coupling.
          final foreground = selected || state.highlighted
              ? tokens.textPrimary
              : tokens.textSecondary;
          // Supporting text beside the primary label, so it steps down in both
          // states rather than only on the selected one.
          final secondary = selected ? tokens.textSecondary : tokens.textMuted;

          return CardFocusRing(
            focused: state.focused,
            radius: radius,
            child: Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.all(SegmentedTabs._inset),
              padding: const EdgeInsets.symmetric(
                horizontal: SegmentedTabs._hPad,
              ),
              // **A resting segment paints nothing.** Not a fill, not a
              // border: this box used to carry a 0.06 white hover wash, which
              // existed only so it could be suppressed on the selected
              // segment and the accent fill meant exactly one thing. With the
              // fill gone there is nothing left to disambiguate, so the wash
              // went too and a pointed-at segment is marked by its label's
              // brightness — the affordance the control's own selection uses.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    // A narrow segment must ellipsise rather than wrap, or it
                    // would push the control past its fixed height.
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SegmentedTabs._labelStyle(selected)
                        .copyWith(color: foreground),
                  ),
                  if (option.count != null)
                    Text(
                      '${option.count}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: SegmentedTabs._countStyle
                          .copyWith(color: secondary),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
