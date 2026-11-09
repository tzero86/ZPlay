import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';
import 'player_glass.dart';

/// What the player paints while a stream is opening, and what it paints instead
/// once that stream has stopped answering.
///
/// Extracted from `PlayerScreen` for the same reason `player_remote_keys.dart`
/// was: the screen owns a `media_kit` `Player`, which no widget test can build,
/// and this overlay is the whole of what a dead source leaves a viewer looking
/// at. As its own widget the controls that get a viewer off that source — and
/// the focus they take on arrival — are shipped code a test can drive.
///
/// The stalled branch is the reason the focus matters. Its actions are the only
/// way out, and the player's own shortcuts own the D-pad whenever nothing else
/// holds focus: the sweep that found this pressed the centre button on the
/// overlay and measured zero accent pixels anywhere on screen. The overlay
/// therefore takes focus itself, and the screen stands its shortcuts down while
/// the overlay holds it.
class PlayerLoadingOverlay extends StatefulWidget {
  final String? backdropUrl;
  final String? logoUrl;

  /// The status line: what is being waited for, or what went wrong.
  final String message;

  /// True when the stream has stopped answering. The artwork gives way to the
  /// warning panel and its actions.
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
  /// own [entryFocusNode], so focus still lands on the primary action and the
  /// overlay's focus contract is unchanged.
  final VoidCallback? onCopyDiagnostic;

  /// What is playing, for the stalled panel's context line - provider, quality
  /// and the addon that supplied it, e.g.
  /// `MovieBoxProviderIN · 1080p · CNCVerse Bridge`. Null hides the line.
  final String? sourceContext;

  /// Searches the ranked alternatives and opens the first one that answers.
  ///
  /// Null is the previous overlay: "Choose another source" is the primary
  /// action and nothing here goes looking for a source on the viewer's behalf.
  /// When it is set the primary action becomes "Find best source", and picking
  /// a source by hand moves to the outlined secondary.
  final VoidCallback? onFindSource;

  /// Stops a search in flight. Wired to the primary action while it runs.
  final VoidCallback? onCancelFindSource;

  /// Whether [onFindSource] is running now.
  final bool findingSource;

  /// The search's own status line (`Testing 4 of 12…`), shown while
  /// [findingSource].
  final String? findSourceProgress;

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
    this.sourceContext,
    this.onFindSource,
    this.onCancelFindSource,
    this.findingSource = false,
    this.findSourceProgress,
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
  /// The stalled branch draws the panel instead, and a stall is the state a
  /// viewer can sit in longest — a repeating ticker behind a panel nobody is
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

  /// Lands the remote on the primary action, the one that keeps the viewer in
  /// the player.
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
            child: CachedNetworkImage(
              imageUrl: widget.backdropUrl!,
              cacheManager: AppImageCache.manager,
              memCacheWidth: 1280,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        if (widget.stalled)
          _buildStalled(context, tokens)
        else
          _buildLoading(tokens),
      ],
    );
  }

  /// While the stream is opening: the artwork, or the app's spinner, and one
  /// status line. Unchanged by the stall restyle.
  Widget _buildLoading(ZplayTokens tokens) {
    return Container(
      color: widget.backdropUrl != null
          ? tokens.bg.withValues(alpha: 0.54)
          : tokens.bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.logoUrl != null)
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
                child: CachedNetworkImage(
                  imageUrl: widget.logoUrl!,
                  cacheManager: AppImageCache.manager,
                  memCacheHeight: 300,
                  height: 100,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      CircularProgressIndicator(color: PlayerTheme.accent),
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
          ],
        ),
      ),
    );
  }

  /// A dead stream: the backdrop under a two-stop scrim, and one panel that
  /// says what stopped and what the viewer can do about it.
  ///
  /// The panel is the whole message. It is a live region because it appears
  /// without the viewer asking, and it is a single node because a screen reader
  /// walking four separate texts across a six-stop traverse reads the state as
  /// four unrelated fragments. The scrim is a gradient rather than the loading
  /// branch's flat fill so the artwork still reads as context behind the card
  /// instead of as a grey rectangle.
  Widget _buildStalled(BuildContext context, ZplayTokens tokens) {
    final bool finding = widget.findingSource;
    final bool canFindSource = widget.onFindSource != null;
    final String? contextLine = widget.sourceContext?.trim();
    // The quiet variant belongs to the search panel. Without a search the
    // overlay keeps the outlined pair it shipped with - the layout its own
    // regression tests pin, and a control a viewer already knows.
    final bool quietEscapes = canFindSource;

    final String primaryLabel = canFindSource
        ? (finding
              ? (widget.findSourceProgress ?? 'Finding a working source…')
              : 'Find best source')
        : 'Choose another source';

    final Widget primary = _StallAction(
      focusNode: widget.entryFocusNode,
      filled: true,
      icon: canFindSource ? Icons.search_rounded : Icons.swap_horiz_rounded,
      leading: finding
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : null,
      label: primaryLabel,
      // While the search runs the same control cancels it: a viewer who
      // changed their mind has to be able to say so without waiting out the
      // budget.
      onPressed: canFindSource
          ? (finding
                ? (widget.onCancelFindSource ?? widget.onFindSource!)
                : widget.onFindSource!)
          : widget.onChooseSource,
    );

    final Widget panel = Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withValues(alpha: 0.94),
        borderRadius: ZplayRadius.lgAll,
        border: Border.all(color: tokens.borderStrong),
        boxShadow: [
          BoxShadow(
            color: tokens.bg.withValues(alpha: 0.55),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.warning.withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 22,
              color: tokens.warning,
            ),
          ),
          const SizedBox(height: ZplaySpacing.s16),
          Text(
            'PLAYBACK ISSUE',
            style: ZplayType.overline
                .copyWith(letterSpacing: 1.4)
                .toStyle(color: tokens.textMuted),
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Text(
            "This source isn't responding",
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Text(
            widget.message,
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
          ),
          if (contextLine != null && contextLine.isNotEmpty) ...[
            const SizedBox(height: ZplaySpacing.s8),
            Text(
              contextLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ZplayType.label.toStyle(color: tokens.textMuted),
            ),
          ],
          const SizedBox(height: ZplaySpacing.s16),
          Wrap(
            spacing: ZplaySpacing.s12,
            runSpacing: ZplaySpacing.s12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              primary,
              if (canFindSource)
                _StallAction(
                  filled: false,
                  label: 'Choose another source',
                  onPressed: widget.onChooseSource,
                ),
              _StallAction(
                quiet: quietEscapes,
                label: 'Go back',
                onPressed: widget.onGoBack,
              ),
              if (widget.onCopyDiagnostic != null)
                _StallAction(
                  quiet: quietEscapes,
                  label: 'Copy diagnostic',
                  onPressed: widget.onCopyDiagnostic!,
                ),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tokens.bg.withValues(alpha: 0.72),
              tokens.bg.withValues(alpha: 0.94),
            ],
          ),
        ),
        child: Center(
          // A phone is 320 dp wide at its narrowest and this panel is four
          // actions on one line at television width; scrolling rather than
          // clipping is what keeps the escape actions reachable there.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            child: panel,
          ),
        ),
      ),
    );
  }
}

/// One of the overlay's escape actions, as a real focus target.
///
/// The Material button stays inside, unmodified, because its fill, shape and
/// ripple are what these controls look like. What it does not keep is its
/// focus: `ExcludeFocus` takes the button's own node out of the order, exactly as
/// the settings rows do for their switches, so this card is the single stop and
/// [CardFocusRing] is the single indicator. Material's focus treatment is a 12%
/// overlay — and nothing at all on the filled variant, which has no themed
/// focused border — where the app's television bar is a 3 dp accent ring; a
/// remote user has to be able to see which action the centre button will take.
///
/// The ring's radius has to match the button's shape or it will not hug it, and
/// every Material 3 button here is a pill.
///
/// Three variants, and they do not wear the same ring:
///
/// * **filled** - the primary action. Its fill is the accent, and the app's ring
///   is the accent, so on that button the line and the shape it is drawn on are
///   the same colour and focus reads as nothing - the state the sweep reported
///   as "nearly invisible: the two read as one shape". The whole app answers
///   that class of defect by moving the fill, as the See All pills did; here the
///   fill is deliberate, so the *ring* moves instead, to the ink Material
///   already prints this button's label in. That colour is chosen against this
///   exact fill, so the ring separates from it by construction.
/// * **outlined** - the secondary. Its fill is the panel's own surface and its
///   ring already reads, so it keeps the accent like every other control in the
///   app.
/// * **quiet** - "Go back" and "Copy diagnostic". A `TextButton`, whose ink is
///   overridden to secondary text: the accent in this app is a fill and an
///   indicator, never body copy, so the label cannot be the default primary
///   colour. It still keeps the accent ring for the same reason as the outlined
///   variant.
class _StallAction extends StatelessWidget {
  final FocusNode? focusNode;
  final bool filled;
  final bool quiet;
  final IconData? icon;

  /// Replaces [icon] when set - the search's spinner takes the icon's slot.
  final Widget? leading;
  final String label;
  final VoidCallback onPressed;

  const _StallAction({
    this.focusNode,
    this.filled = false,
    this.quiet = false,
    this.icon,
    this.leading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Material 3 sizes a button's sides for a dialog, 24 dp each. This row is a
    // `Wrap` inside a 560 dp panel, and with that generosity the primary plus
    // one neighbour already exceed the line - which is not merely a wrapped
    // row: two actions stacked on their left edge have nothing to the right of
    // the first, so the remote's right arrow is a no-op and the second action
    // can only be reached by pressing down. The tighter side padding is the
    // same control at the size of a television action row.
    const EdgeInsets sidePadding = EdgeInsets.symmetric(
      horizontal: ZplaySpacing.s16,
      vertical: ZplaySpacing.s8,
    );

    final Widget button;
    if (quiet) {
      button = TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          padding: sidePadding,
        ),
        child: Text(label),
      );
    } else if (filled) {
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(padding: sidePadding),
        icon: leading ?? Icon(icon, size: 20),
        label: Text(label),
      );
    } else {
      button = OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(padding: sidePadding),
        child: Text(label),
      );
    }

    return FocusableCard(
      focusNode: focusNode,
      onTap: onPressed,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.fullAll,
        // Only the filled variant's fill collides with the ring; the outlined
        // and quiet variants are drawn on the panel's own surface, where the
        // accent already reads.
        color: filled ? Theme.of(context).colorScheme.onPrimary : null,
        child: ExcludeFocus(child: button),
      ),
    );
  }
}
