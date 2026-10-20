import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// The button that turns the trailer's sound on and off.
///
/// A preview is muted by default - a trailer that starts talking under the
/// pointer is a trailer the user did not ask for - but a user who has
/// deliberately rested on the hero may well want to hear it, and a control
/// that cannot be undone is not a control.
///
/// **It belongs in the surface's own control row.** The first attempt drew it
/// as a floating button over the picture, and the hero's own layer - the
/// scrims, the content column, the action row - is painted above the
/// preview, so the button rendered *under* the surface that was supposed to
/// be over it and the click never reached it. A control that renders and
/// does nothing is worse than no control, so the button is now a pill
/// beside the hero's other actions, at the same level as everything else the
/// user can press.
///
/// It is a **speaker glyph and nothing else**: a word beside it would have
/// to say "Unmute" in one state and "Mute" in the other, and the label is
/// the part that goes wrong - the icon is the part a user reads at a glance,
/// and a speaker with a slash is the same mark in every language.
///
/// It is a [FocusableCard], like every other control in the app, so a remote
/// can reach it and the pointer's press is handled the same way as the
/// hero's own pills.
///
/// The state is the app's own, not the embed's: the embed may refuse to
/// unmute, and an icon that says "sound on" over a silent video is a lie.
/// The host asks the embed and the embed answers, and this draws the answer.
class TrailerMuteButton extends StatelessWidget {
  const TrailerMuteButton({
    super.key,
    required this.muted,
    required this.onPressed,
  });

  /// Whether the trailer is silent right now.
  final bool muted;

  /// Asked for when the user presses the button. The new state is *not*
  /// passed in: the button asks the embed and the embed's answer is what
  /// comes back.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      toggled: !muted,
      label: muted ? 'Unmute trailer' : 'Mute trailer',
      excludeSemantics: true,
      child: FocusableCard(
        onTap: onPressed,
        builder: (context, state) => SizedBox(
          // The same height as the hero's pills, so the control sits in
          // the row as one of them rather than beside them.
          height: 44,
          width: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // The secondary fill the hero's own pills use: a wash over the
              // artwork, not a surface of its own.
              color: tokens.bg.withValues(alpha: ZplayOpacity.overlayControl),
              borderRadius: ZplayRadius.cardAll,
            ),
            child: Center(
              child: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 20,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
