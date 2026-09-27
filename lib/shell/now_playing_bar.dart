import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/layout/form_factor.dart';
import '../services/playback/now_playing_service.dart';
import '../services/storage/app_image_cache.dart';
import '../services/theme/design_tokens.dart';
import '../widgets/common/focusable_card.dart';

/// The shell's single transport strip: whatever is playing, on every form factor.
///
/// The shell mounts this unconditionally in the slot the prototype pins for the
/// current form factor, so the idle case is the bar's problem, not the shell's:
/// with no snapshot the widget collapses to zero height and the surrounding
/// column stays correct, which is why the null branch returns a [SizedBox.shrink]
/// rather than the shell conditionally omitting the child.
///
/// It reads only [NowPlayingService], so it never learns which surface is
/// playing. Tap-to-expand, previous, play or pause and next are the entire
/// contract it needs from an owner.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  /// Pinned shell metrics, shared with the rail's target sizes so the two chrome
  /// pieces agree under a finger.
  ///
  /// They are deliberately not [ZplaySpacing] steps: each of these moves with the
  /// form factor, and naming them as generic gaps would hide that.
  static const double _artwork = 40.0;
  static const double _artworkTelevision = 56.0;
  static const double _target = 44.0;
  static const double _targetTelevision = 56.0;

  /// The accent progress line's thickness.
  static const double _progressThickness = 2.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NowPlayingSnapshot?>(
      valueListenable: NowPlayingService.current,
      builder: (context, snapshot, _) {
        if (snapshot == null) return const SizedBox.shrink();
        return _NowPlayingContents(snapshot: snapshot);
      },
    );
  }
}

/// The loaded state of the bar.
///
/// Split from [NowPlayingBar] because the two states share nothing: idle is a
/// zero-size placeholder, this is a Material strip with its own form-factor and
/// token reads. One `build` would put the null check in front of a layout that
/// only runs when it is not null.
class _NowPlayingContents extends StatelessWidget {
  const _NowPlayingContents({required this.snapshot});

  final NowPlayingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isTelevision = FormFactorService.of(context) == FormFactor.television;
    final artworkSize = isTelevision
        ? NowPlayingBar._artworkTelevision
        : NowPlayingBar._artwork;
    final targetSize = isTelevision
        ? NowPlayingBar._targetTelevision
        : NowPlayingBar._target;

    return Material(
      color: tokens.surfaceRaised,
      child: DecoratedBox(
        // The hairline is what separates the bar from the slot page's own
        // content above it, since the shell deliberately gives the bar no
        // elevation of its own.
        decoration: BoxDecoration(border: Border(top: tokens.hairline)),
        child: Semantics(
          button: true,
          label: 'Now playing, ${snapshot.title}, ${snapshot.subtitle}',
          hint: 'Open the full player',
          child: FocusableCard(
            onTap: () => NowPlayingService.openFullPlayer(context),
            // The bar was the last piece of shell chrome still built on a raw
            // `InkWell`. That is a `Focus` widget only incidentally and draws no
            // indicator of its own, so on a TV the bar could hold focus with
            // nothing on screen saying so. The rail and the tab strip both went
            // through `FocusableCard` for exactly this reason.
            builder: (context, state) => CardFocusRing(
              focused: state.focused,
              // Zero, because the bar is the full width of the content column
              // with square corners: the ring has to sit on the strip's own edge
              // rather than round the corners the strip does not have.
              radius: BorderRadius.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProgressLine(
                    position: snapshot.position,
                    duration: snapshot.duration,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s12,
                      vertical: ZplaySpacing.s8,
                    ),
                    child: Row(
                      children: [
                        _Artwork(
                          url: snapshot.artworkUrl,
                          kind: snapshot.kind,
                          size: artworkSize,
                        ),
                        const SizedBox(width: ZplaySpacing.s12),
                        Expanded(child: _TrackInfo(snapshot: snapshot)),
                        const SizedBox(width: ZplaySpacing.s8),
                        _TransportButton(
                          icon: Icons.skip_previous_rounded,
                          label: 'Previous',
                          size: targetSize,
                          onPressed: snapshot.canPrevious
                              ? NowPlayingService.previous
                              : null,
                        ),
                        _TransportButton(
                          icon: snapshot.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: snapshot.isPlaying ? 'Pause' : 'Play',
                          size: targetSize,
                          onPressed: NowPlayingService.togglePlayPause,
                        ),
                        _TransportButton(
                          icon: Icons.skip_next_rounded,
                          label: 'Next',
                          size: targetSize,
                          onPressed: snapshot.canNext
                              ? NowPlayingService.next
                              : null,
                        ),
                      ],
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

/// Title, subtitle and the two tabular time readouts.
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.snapshot});

  final NowPlayingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final remaining = snapshot.duration - snapshot.position;
    final timeStyle = ZplayType.labelNumeric.toStyle(color: tokens.textMuted);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.title,
          style: ZplayType.label.toStyle(color: tokens.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ZplaySpacing.s2),
        Text(
          snapshot.subtitle,
          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ZplaySpacing.s2),
        Row(
          children: [
            Text(_formatClock(snapshot.position), style: timeStyle),
            const SizedBox(width: ZplaySpacing.s8),
            // Remaining is signed, the way every player states it, and clamped
            // because a live broadcast reports a position past whatever duration
            // it last published.
            Text(
              '-${_formatClock(remaining.isNegative ? Duration.zero : remaining)}',
              style: timeStyle,
            ),
          ],
        ),
      ],
    );
  }
}

/// The 2 px track: accent fill over the faintest border colour, clamped to the
/// full width.
///
/// The track is [ZplayTokens.borderSubtle] because that is the faintest border
/// colour the token set actually ships: `ZplayOpacity.borderFaint` exists as an
/// alpha step, but no `tokens.borderFaint` is derived from it, and deriving one
/// here would put a second white alpha in circulation.
///
/// The clamp matters because a position can pass the duration the owner last
/// reported, and a [FractionallySizedBox] above 1.0 overflows its box rather
/// than saturating.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final double fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      height: NowPlayingBar._progressThickness,
      child: ColoredBox(
        color: tokens.borderSubtle,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: ColoredBox(color: tokens.accent),
        ),
      ),
    );
  }
}

/// Square artwork, with the kind's icon standing in when the owner has no URL.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.kind, required this.size});

  final String? url;
  final NowPlayingKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = ColoredBox(
      color: tokens.surface,
      child: Icon(
        _iconFor(kind),
        size: size * 0.5,
        color: tokens.textMuted,
      ),
    );

    final artworkUrl = url;
    return ClipRRect(
      borderRadius: ZplayRadius.smAll,
      child: SizedBox.square(
        dimension: size,
        child: artworkUrl == null || artworkUrl.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: artworkUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                // Decode at the size the bar actually paints, so a 40 px slot
                // does not hold a full-resolution cover in the image cache.
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }

  static IconData _iconFor(NowPlayingKind kind) => switch (kind) {
    NowPlayingKind.music => Icons.music_note_rounded,
    NowPlayingKind.audiobook => Icons.menu_book_rounded,
    NowPlayingKind.video => Icons.movie_rounded,
  };
}

/// One transport control.
///
/// The disabled state is an opacity change over a live hit target rather than a
/// null-out: the button keeps its slot so the row's rhythm and the D-pad focus
/// order are the same whether or not a queue has a next item.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final glyph = Center(
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : ZplayOpacity.textDisabled,
        duration: ZplayMotion.fast,
        child: AnimatedSwitcher(
          // Only the play or pause icon ever changes, and cross-fading it at the
          // shared tap-feedback duration is the whole animation the bar needs;
          // the other two buttons swap nothing.
          duration: ZplayMotion.fast,
          child: Icon(
            icon,
            key: ValueKey(icon),
            size: size * 0.55,
            color: context.tokens.textPrimary,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox.square(
        dimension: size,
        // Enabled and disabled are different widgets rather than one card with
        // a null callback: a disabled `FocusableCard` is still focusable on a
        // D-pad (the framework keeps the node live in directional navigation
        // mode regardless of `enabled`), so a remote would come to rest on a
        // skip that does not exist and the centre key would do nothing.
        child: enabled
            ? FocusableCard(
                onTap: onPressed,
                // Matches the `CircleBorder` the `InkWell` used to carry, so
                // the ring closes on the same shape as the button it replaces.
                builder: (context, state) => CardFocusRing(
                  focused: state.focused,
                  radius: ZplayRadius.fullAll,
                  child: glyph,
                ),
              )
            : GestureDetector(
                // A disabled control still swallows its own tap. With no
                // recogniser of its own the tap reaches the bar's tap-to-expand
                // behind it, so pressing a skip that does not exist would open
                // the full player instead of doing nothing. `excludeFromSemantics`
                // keeps the swallow invisible: screen readers still see
                // `enabled: false` and no tap action.
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                child: glyph,
              ),
      ),
    );
  }
}

/// `m:ss` under an hour and `h:mm:ss` above it.
///
/// Hand-rolled rather than `intl`: the players already read this way, and a
/// locale-aware formatter would render this one-line strip differently per
/// locale while adding a dependency for two divisions.
String _formatClock(Duration value) {
  final total = value.inSeconds;
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = (total ~/ 60) % 60;
  final hours = total ~/ 3600;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
