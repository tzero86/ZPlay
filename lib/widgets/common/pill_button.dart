import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// Which of the two reference treatments a pill carries.
///
/// The reference app's hero pairs a solid light fill with a translucent one over
/// the artwork, and nothing in between: a pill is either the affirmative or the
/// qualifier beside it. Splitting this into two values rather than a colour and a
/// border is what keeps a caller from inventing a third look.
enum PillVariant {
  /// Solid light fill, dark glyph and label.
  ///
  /// Not `tokens.accent`. The reference's primary CTA is white on any
  /// artwork - the accent red is the app's *selection* colour, used for the
  /// focus ring, the progress bar and the active filter pill, so putting it
  /// behind a hero label would spend the one signal that tells a D-pad user
  /// where they are on something that is only ever a button.
  primary,

  /// Translucent dark fill - a scrim over whatever is behind it - with a light
  /// glyph and label.
  secondary,
}

/// The app's pill-shaped call to action.
///
/// Material's buttons are rounded rectangles: `RoundedRectangleBorder` with a
/// 14 dp radius, and a focus treatment that swaps the *border* from transparent
/// to a 2 dp line. Both are wrong for this shape. A 14 dp radius on a 44 dp-tall
/// control is not a pill, and a border whose width changes between states is a
/// 2 dp reflow every time focus arrives - which on a television is the thing a
/// D-pad user sees on every single focus move, and it moves the label with it.
///
/// So: the ring is a separate overlay drawn *over* the pill (the same
/// [CardFocusRing] the cards use), the pill's own box is identical in every
/// state, and the shape is `BorderRadius.circular` past its own half-height so
/// both ends are genuinely round.
///
/// Reachability comes from [FocusableCard], which is what makes this a
/// `Focus` node a remote can land on - the same answer the rest of the app gives
/// for "a control a D-pad has to reach".
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.variant = PillVariant.primary,
    this.icon,
    this.onPressed,
    this.autofocus = false,
    this.expand = false,
  });

  /// The control's text. Kept as a plain string rather than a [Widget] so every
  /// pill in the app is one label type and cannot drift into its own font.
  final String label;

  final PillVariant variant;

  /// Optional leading glyph. Sized here rather than by the caller: a 20 dp
  /// glyph beside a 15 dp label is the proportion the reference uses, and a
  /// caller who wants a different one needs a different control.
  final IconData? icon;

  final VoidCallback? onPressed;

  /// Home's hero autofocuses its primary action so a remote arriving at the
  /// page has somewhere to be. Deliberate, and deliberately not the default:
  /// two autofocuses on one screen contend, so only the page's own primary
  /// action should ask for it.
  final bool autofocus;

  /// Whether the pill fills the width it is given instead of hugging its label.
  /// The details page's primary CTA is the case: it is the only way into the
  /// app's main function and its column is sized by it.
  final bool expand;

  /// The height a pill presents.
  ///
  /// 44 dp is the pointer floor. A television is aimed at from across a room
  /// with a five-way pad, so it gets 48 dp - the same ten-foot rule
  /// `FocusMetrics` states for every other control in the app, and the reason a
  /// card in a rail is 48 rather than 44.
  ///
  /// A height, not a minimum: the pill is laid out to exactly this value, so a
  /// longer label cannot make it grow and push the layout around it. The hero's
  /// height budget and the details page's poster column are both measured
  /// against a fixed button height for that reason, which is why they ask this
  /// method rather than writing the number themselves.
  static double heightFor(BuildContext context) =>
      FormFactorService.of(context) == FormFactor.television ? 48.0 : 44.0;

  /// The secondary fill: a dark scrim, not a colour of its own.
  ///
  /// This is a wash over the artwork behind it, not a surface, so it is drawn
  /// in [ZplayOpacity.overlayControl] rather than the 0.15 hover step. The
  /// hover step is for washing a flat surface and has no edge over a
  /// photograph: at 0.15 the hero's secondary action receded into the still
  /// entirely and read as a naked text link. Dark rather than white, so the
  /// artwork underneath keeps its own colour instead of being lifted.
  static Color scrim(ZplayTokens tokens) =>
      tokens.bg.withValues(alpha: ZplayOpacity.overlayControl);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isPrimary = variant == PillVariant.primary;
    final foreground = isPrimary ? tokens.bg : tokens.textPrimary;

    // **A `MainAxisSize.min` row, not a flexible one.** `Flexible` inside a
    // shrink-wrapped row makes the row's width a function of the *constraint* it
    // is handed rather than of its content, so a pill near the right edge of the
    // hero's 680 dp column would lay itself out against whatever was left over
    // and its label would then be ellipsised by a width the pill chose for
    // itself. A button's width is its label's width; the only case that may
    // flex is [expand], where the caller asked for the width explicitly.
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: ZplaySpacing.s8),
        ],
        if (expand)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZplayType.subtitle.toStyle(color: foreground),
            ),
          )
        else
          Text(
            label,
            maxLines: 1,
            style: ZplayType.subtitle.toStyle(color: foreground),
          ),
      ],
    );

    return FocusableCard(
      onTap: onPressed,
      enabled: onPressed != null,
      autofocus: autofocus,
      cursor: onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, state) {
        // The pill's own box is identical in every state. It does not lift, does
        // not swell and does not change border width, so focus arriving cannot
        // move it or its neighbours - on the hero that would shift the metadata
        // line above it, which is the "focus arrives and the layout jumps"
        // failure the ring exists to prevent.
        final pill = SizedBox(
          // [heightFor] outright rather than a minimum: see its doc for why the
          // height is a property of the control rather than of its label.
          height: heightFor(context),
          width: expand ? double.infinity : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // A pill, not a rounded rectangle: a radius past half the height
              // makes both ends semicircles whatever the label's width.
              color: isPrimary ? tokens.textPrimary : scrim(tokens),
              // The secondary carries an edge as well as a fill. Over a dark
              // still the fill has nothing to separate itself from and the
              // button reads as loose text, so the hairline is what draws its
              // shape; over a bright still the fill does that job. The primary
              // is already white on dark and needs neither. Painted inside the
              // box, so the pill's measured size is unchanged - see the
              // comment above [build] about why that is load-bearing.
              border: isPrimary
                  ? null
                  : Border.all(color: tokens.borderStrong),
              borderRadius: ZplayRadius.fullAll,
            ),
            // The label is inset by the padding, so the pill is as wide as its
            // content plus 48 dp and exactly as tall as [heightFor].
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s24,
              ),
              child: content,
            ),
          ),
        );

        // The app's one focus indicator, drawn over the pill rather than around
        // it, so the ring costs the pill zero size. This is the same
        // [CardFocusRing] the rails use - a focused control that invented its
        // own ring would be the second indicator in the app.
        return CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.fullAll,
          child: pill,
        );
      },
    );
  }
}