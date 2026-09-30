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

/// A single-choice control: one track, equal-width segments, and one accent
/// indicator that slides to whichever segment is selected.
///
/// Built because the app hand-rolls this pattern repeatedly — `ChoiceChip` rows
/// in IPTV, audiobooks and books, text tabs with per-tab underlines on Home —
/// and every one of those is pointer-sized with no D-pad story.
///
/// **Assumes a dark surface.** The track and the unselected labels are white at
/// low alpha, so on a light surface the control would be near-invisible. The
/// reader's Light and Sepia themes are exactly that and are not [ZplayTokens],
/// which is why the reader's own margin picker was left as chips rather than
/// converted — flagged by the conversion pass that found it. Making this
/// theme-agnostic means taking those two colours from the ambient [ColorScheme]
/// instead of white.
///
/// **Segments are sized to their content, not by `Expanded`.** That is not a
/// style preference: Home places this control in the app bar's [Row], where the
/// incoming width is unbounded, and a flex child in an unbounded row collapses
/// in release (labels crushed together, indicator mis-sized) or throws in debug.
/// Sizing to content gives the control a width of its own, which works in both a
/// bounded parent and an unbounded one. Segments stay equal either way, which is
/// what keeps the sliding indicator's arithmetic honest.
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

  static const double _trackRadius = 12;
  static const double _inset = 3;

  /// Side padding inside a segment. The first version had none, so adjacent
  /// labels sat against each other.
  static const double _hPad = 16;
  static const double _minSegmentWidth = 78;

  /// Slack for [CardFocusRing]'s 2 dp border, which is painted inside the
  /// segment and so takes width from the label only while the segment is
  /// focused.
  static const double _ringAllowance = 8;

  /// The track's own 1 dp border, painted inside it on both sides.
  ///
  /// The budget in [_contentSegmentWidth] covers the label, the segment's own
  /// padding and the focus ring, but not the border between the track and the
  /// outside world. So the two ends of the track were 1 dp narrower than the
  /// labels had been sized for, which is why "Downloads" rendered as
  /// "Downloa...": a two-tab control is small enough that 2 dp is the
  /// difference between a label that fits and one that does not. Border is
  /// painted inside the box, exactly as [CardFocusRing]'s is, so it is charged
  /// to the width the same way.
  static const double _trackBorder = 1;

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
    final radius = BorderRadius.circular(_trackRadius - _inset);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final natural = _contentSegmentWidth() * options.length;
          // Two width sources, and they must not be mixed: a parent that
          // demands an exact width (a SizedBox, an Expanded) wins, and the
          // segments divide whatever that is — the indicator is a fraction of
          // the track, so any mismatch shows up as it sitting off-centre. Only
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(_trackRadius),
                // Width from the constant, not the default, because the
                // budget in [_contentSegmentWidth] charges this border to the
                // track's width. Two literals for one border is how the 2 dp
                // that truncated "Downloads" got left out of the arithmetic.
                border: Border.all(
                  color: tokens.borderSubtle,
                  width: _trackBorder,
                ),
              ),
              child: Stack(
                children: [
                  // One indicator that slides between the equal segments, so
                  // moving between them reads as a single selection travelling.
                  Positioned.fill(
                    child: AnimatedAlign(
                      duration: ZplayMotion.base,
                      curve: ZplayMotion.standard,
                      alignment: Alignment(_alignX(selected), 0),
                      child: FractionallySizedBox(
                        widthFactor: 1 / options.length,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(_inset),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.accent,
                              borderRadius: BorderRadius.circular(
                                _trackRadius - _inset,
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
            ),
          );
        },
      ),
    );
  }

  /// -1 for the first segment and +1 for the last, matching the segment that
  /// shares its index.
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
  /// There is deliberately no upper bound. A 136px ceiling was truncating longer
  /// labels — "Compact (Dense Grid)" became "Compact (Dense…" — where the chips
  /// they replaced had shown them in full, and a truncated label is worse than a
  /// wide control. A caller short of room gets the width it offers instead, and
  /// the label ellipsises only as a last resort.
  double _contentSegmentWidth() {
    var widest = 0.0;
    for (final option in options) {
      widest = math.max(widest, _textWidth(option.label, _labelStyle(true)));
      final count = option.count;
      if (count != null) {
        widest = math.max(widest, _textWidth('$count', _countStyle));
      }
    }
    return math.max(
      // 8, not 4. The 4 dp of slack was not enough for the focus ring:
      // [CardFocusRing] paints a 2 dp border inside the segment when it is
      // focused, so the focused label had 4 dp less room than the budgeted one.
      // "Movies" is the widest of the home filters, so it was exactly the label
      // that truncated - and only while focused, which reads as the control
      // shrinking under the remote rather than as a text problem. Budgeting the
      // ring keeps every label whole in both states.
      widest + (_hPad + _inset) * 2 + _ringAllowance + _trackBorder,
      _minSegmentWidth,
    );
  }

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
    final tokens = ZplayTokens.of(context);
    final foreground =
        selected ? tokens.onAccent : Colors.white.withValues(alpha: 0.62);
    final secondary = selected
        ? tokens.onAccent.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.38);

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
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: radius,
          child: Container(
            alignment: Alignment.center,
            margin: const EdgeInsets.all(SegmentedTabs._inset),
            padding: const EdgeInsets.symmetric(
              horizontal: SegmentedTabs._hPad,
            ),
            decoration: BoxDecoration(
              // Hover is suppressed on the selected segment so the accent fill
              // goes on meaning exactly one thing: the option you are on.
              color: selected || !state.highlighted
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: radius,
            ),
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
                    style: SegmentedTabs._countStyle.copyWith(color: secondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
