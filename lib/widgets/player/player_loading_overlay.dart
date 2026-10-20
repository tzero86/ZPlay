import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';
import 'player_glass.dart';

/// What the player paints while a stream is opening, and what it paints instead
/// once that stream has stopped answering.
///
/// Extracted from `PlayerScreen` for the same reason `player_remote_keys.dart`
/// was: the screen owns a `media_kit` `Player`, which no widget test can build,
/// and this overlay is the whole of what a dead source leaves a viewer looking
/// at. As its own widget the two controls that get a viewer off that source —
/// and the focus they take on arrival — are shipped code a test can drive.
///
/// The stalled branch is the reason the focus matters. Its two actions are the
/// only way out, and the player's own shortcuts own the D-pad whenever nothing
/// else holds focus: the sweep that found this pressed the centre button on the
/// overlay and measured zero accent pixels anywhere on screen. The overlay
/// therefore takes focus itself, and the screen stands its shortcuts down while
/// the overlay holds it.
class PlayerLoadingOverlay extends StatefulWidget {
  final String? backdropUrl;
  final String? logoUrl;

  /// The status line: what is being waited for, or what went wrong.
  final String message;

  /// True when the stream has stopped answering. The artwork gives way to the
  /// warning and the escape actions appear under the message.
  final bool stalled;

  /// The node the first action focuses through.
  ///
  /// Owned by the screen rather than by this widget, because the screen needs
  /// the same node for two other questions: whether the overlay holds focus (its
  /// shortcuts must stand down while it does), and where focus has to go back to
  /// when the overlay is taken away.
  final FocusNode? entryFocusNode;

  final VoidCallback onChooseSource;
  final VoidCallback onGoBack;

  /// Optional third escape: copy the redacted diagnostic report.
  ///
  /// A dead source is the other surface where a user has to tell us what
  /// happened, and it is local-only like the Settings page's copy. It sits
  /// after the two escape actions in traversal order and deliberately does not
  /// own [entryFocusNode], so focus still lands on "Choose another source" and
  /// the overlay's focus contract is unchanged.
  final VoidCallback? onCopyDiagnostic;

  const PlayerLoadingOverlay({
    super.key,
    this.backdropUrl,
    this.logoUrl,
    required this.message,
    this.stalled = false,
    this.entryFocusNode,
    required this.onChooseSource,
    required this.onGoBack,
    this.onCopyDiagnostic,
  });

  @override
  State<PlayerLoadingOverlay> createState() => _PlayerLoadingOverlayState();
}

class _PlayerLoadingOverlayState extends State<PlayerLoadingOverlay>
    with SingleTickerProviderStateMixin {
  /// The pulse on the title art while the stream is opening. It belongs to the
  /// overlay rather than to the screen: it exists only while this is on screen,
  /// and it was the last thing keeping the screen a `TickerProvider`.
  late final AnimationController _logoAnimController;

  @override
  void initState() {
    super.initState();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _syncArtworkPulse();
    if (widget.stalled) _focusFirstAction();
  }

  @override
  void didUpdateWidget(PlayerLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncArtworkPulse();
    // The overlay is already mounted when it is a stall rather than a load: the
    // screen raises it the moment a source opens and turns its actions on later,
    // so this is the transition that matters.
    if (!oldWidget.stalled && widget.stalled) _focusFirstAction();
  }

  /// Runs the artwork pulse only while the artwork is what is on screen.
  ///
  /// The stalled branch draws the warning instead, and a stall is the state a
  /// viewer can sit in longest — a repeating ticker behind an icon nobody is
  /// looking at is work for nothing, and it is also what would make the state
  /// un-pumpable to a test.
  void _syncArtworkPulse() {
    final bool pulses = !widget.stalled && widget.logoUrl != null;
    if (pulses) {
      if (!_logoAnimController.isAnimating) {
        _logoAnimController.repeat(reverse: true);
      }
    } else if (_logoAnimController.isAnimating) {
      _logoAnimController.stop();
    }
  }

  @override
  void dispose() {
    _logoAnimController.dispose();
    super.dispose();
  }

  /// Lands the remote on "Choose another source", the action that keeps the
  /// viewer in the player.
  ///
  /// A no-op on a pointer device: there the buttons are reachable by the mouse
  /// alone and a ring is not the affordance.
  ///
  /// The node is attached by the row that carries it, one frame after this call
  /// — and a request made before then rides the node's reparent, so there is
  /// nothing to wait for. See `player_remote_keys.dart` for the state this
  /// avoids: a node no widget owns defers its request forever.
  void _focusFirstAction() {
    if (!FormFactorService.hasRemoteInput) return;
    widget.entryFocusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.backdropUrl != null)
          Opacity(
            opacity: 0.4,
            child: Image.network(
              widget.backdropUrl!,
              cacheWidth: 1280,
              fit: BoxFit.cover,
            ),
          ),
        Container(
          color: widget.backdropUrl != null
              ? tokens.bg.withValues(alpha: 0.54)
              : tokens.bg,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.stalled)
                  Icon(
                    Icons.error_outline_rounded,
                    color: tokens.textEmphasis,
                    size: 56,
                  )
                else if (widget.logoUrl != null)
                  AnimatedBuilder(
                    animation: _logoAnimController,
                    builder: (context, child) {
                      final val = _logoAnimController.value;
                      return Opacity(
                        opacity: 0.3 + (val * 0.7),
                        child: Transform.scale(
                          scale: 0.95 + (val * 0.1),
                          child: child,
                        ),
                      );
                    },
                    child: Image.network(
                      widget.logoUrl!,
                      cacheHeight: 300,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  )
                else
                  CircularProgressIndicator(color: PlayerTheme.accent),
                const SizedBox(height: ZplaySpacing.s32),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: ZplayType.body
                      .copyWith(letterSpacing: 1.2)
                      .toStyle(color: tokens.textEmphasis),
                ),
                if (widget.stalled) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _StallAction(
                        focusNode: widget.entryFocusNode,
                        filled: true,
                        icon: Icons.swap_horiz_rounded,
                        label: 'Choose another source',
                        onPressed: widget.onChooseSource,
                      ),
                      _StallAction(
                        filled: false,
                        label: 'Go back',
                        onPressed: widget.onGoBack,
                      ),
                      if (widget.onCopyDiagnostic != null)
                        _StallAction(
                          filled: false,
                          label: 'Copy diagnostic',
                          onPressed: widget.onCopyDiagnostic!,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the overlay's two escape actions, as a real focus target.
///
/// The Material button stays inside, unmodified, because its fill, shape and
/// ripple are what these two controls look like. What it does not keep is its
/// focus: `ExcludeFocus` takes the button's own node out of the order, exactly as
/// the settings rows do for their switches, so this card is the single stop and
/// [CardFocusRing] is the single indicator. Material's focus treatment is a 12%
/// overlay — and nothing at all on the filled variant, which has no themed
/// focused border — where the app's television bar is a 3 dp accent ring; a
/// remote user has to be able to see which of the two actions the centre button
/// will take.
///
/// The ring's radius has to match the button's shape or it will not hug it, and
/// both buttons are Material 3 pills.
///
/// **The two actions do not wear the same ring.** The filled one's fill is the
/// accent, and the app's ring is the accent, so on that button the line and the
/// shape it is drawn on are the same colour and focus reads as nothing - the
/// state the sweep reported as "nearly invisible: the two read as one shape".
/// The whole app answers that class of defect by moving the fill, as the See All
/// pills did; here the fill is deliberate (it is what makes this the primary
/// action of the two) so the *ring* moves instead, to the ink Material already
/// prints this button's label in. That colour is chosen against this exact fill,
/// so the ring separates from it by construction, and the outlined neighbour -
/// whose fill is the overlay's own scrim and whose ring already reads - keeps the
/// accent like every other control in the app.
class _StallAction extends StatelessWidget {
  final FocusNode? focusNode;
  final bool filled;
  final IconData? icon;
  final String label;
  final VoidCallback onPressed;

  const _StallAction({
    this.focusNode,
    required this.filled,
    this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: focusNode,
      onTap: onPressed,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.fullAll,
        // The filled variant's own fill is the accent, and the app's ring is the
        // accent too: on that button the two are one shape and the ring says
        // nothing. The fill is not the thing to move here - it is the whole
        // identity of the primary action on a dead stream - so the ring is, and
        // it takes the ink Material already prints that button's own label in,
        // which is chosen against that exact fill. The outlined neighbour beside
        // it keeps the accent: there the fill is the overlay's own scrim, and the
        // ring already reads on it.
        color: filled ? Theme.of(context).colorScheme.onPrimary : null,
        child: ExcludeFocus(
          child: filled
              ? FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                )
              : OutlinedButton(onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}
