import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';
import '../common/pill_button.dart';
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
      busy: finding,
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
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      // The app's surface language: a solid surface, a hairline, the same
      // modest radius the cards and buttons use - not a glowing slab.
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One quiet line instead of a tinted badge over a caption: the
          // glyph and the category read together.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: tokens.warning,
              ),
              const SizedBox(width: ZplaySpacing.s8),
              Text(
                'PLAYBACK ISSUE',
                style: ZplayType.overline
                    .copyWith(letterSpacing: 1.2)
                    .toStyle(color: tokens.textMuted),
              ),
            ],
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
          const SizedBox(height: ZplaySpacing.s24),
          Wrap(
            spacing: ZplaySpacing.s8,
            runSpacing: ZplaySpacing.s8,
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

/// One of the overlay's actions, as a single focus target.
///
/// The primary and secondary choices are [PillButton]s - the app's own solid
/// white and translucent grey buttons - and the escapes ("Go back", "Copy
/// diagnostic") are quiet text on a [FocusableCard], so a remote still lands
/// on each one and the ring says which.
class _StallAction extends StatelessWidget {
  final FocusNode? focusNode;
  final bool filled;
  final bool quiet;
  final IconData? icon;

  /// The primary is working (the source search is running): its glyph turns
  /// into a small spinner and its label carries the progress.
  final bool busy;
  final String label;
  final VoidCallback onPressed;

  const _StallAction({
    this.focusNode,
    this.filled = false,
    this.quiet = false,
    this.icon,
    this.busy = false,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The two real choices are the app's own buttons - solid white for the
    // primary, the translucent grey plate for the secondary - so the panel
    // reads as part of ZPlay rather than as a Material dialog dropped on top.
    if (!quiet) {
      final button = PillButton(
        focusNode: focusNode,
        label: label,
        icon: busy ? null : icon,
        variant: filled ? PillVariant.primary : PillVariant.secondary,
        onPressed: onPressed,
      );
      if (!busy) return button;
      return Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          button,
          PositionedDirectional(
            start: 18,
            child: IgnorePointer(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.bg,
                ),
              ),
            ),
          ),
        ],
      );
    }
    // The escapes are plain text: present and reachable, never competing with
    // the two choices for attention.
    return FocusableCard(
      focusNode: focusNode,
      onTap: onPressed,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.xsAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s12,
            vertical: ZplaySpacing.s12,
          ),
          child: Text(
            label,
            style: ZplayType.subtitle.toStyle(
              color: state.hovered || state.focused
                  ? tokens.textPrimary
                  : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
