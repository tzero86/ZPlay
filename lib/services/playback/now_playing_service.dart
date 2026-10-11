/// The shell's playback seam: the one-way channel between whatever owns playback
/// and the shell's now playing bar.
///
/// **One direction, deliberately.** The surface that owns playback pushes state
/// with [NowPlayingService.publish] and registers a [NowPlayingCommands]
/// implementation with [NowPlayingService.register]. The shell only ever reads
/// [NowPlayingService.current] and calls the delegating statics. Nothing here
/// polls a player, asks a player for its position, or knows what a player is.
///
/// That is what keeps the file importable from a plain widget test and stops it
/// growing a cycle back into the pages that mount the shell, which is why no
/// concrete player is imported here: music goes through
/// `music_now_playing_bridge.dart` and the audiobook screen registers itself
/// while its route is open. Adding a third playback surface later costs one
/// adapter and no changes to this file, because the bar cannot tell the owners
/// apart.
///
/// **Owners are a stack, not a slot.** Two owners coexist in normal use: the
/// music bridge registers at boot and lives as long as the process, while the
/// audiobook player registers and unregisters as its route opens and closes.
/// [NowPlayingService.register] therefore moves an owner to the top of an ordered
/// stack and [NowPlayingService.unregister] removes it wherever it sits, so the
/// transient screen's dispose hands the commands back to the bridge with no
/// cooperation from either owner: neither has to ask whether the other is
/// playing, which is the coupling this seam exists to prevent.
///
/// `material.dart` is the only import, and it is there for [BuildContext]:
/// [ValueNotifier] and [immutable] reach this file through its re-export of
/// `foundation`, so a second import directive would be dead weight.
library;

import 'package:flutter/material.dart';

/// Which kind of media is playing. The bar does not branch on this today beyond
/// picking its fallback artwork, but it is on the snapshot rather than on the bar
/// because a caller that wants to badge the source should not have to widen a
/// type that every owner already publishes.
enum NowPlayingKind { music, audiobook, video }

/// One immutable frame of playback state, flattened to exactly what the bar
/// draws.
///
/// It carries no player, no stream and no callback: the bar resolves nothing at
/// build time, so a snapshot stays usable after the owner that produced it has
/// been disposed.
@immutable
class NowPlayingSnapshot {
  const NowPlayingSnapshot({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.canPrevious = false,
    this.canNext = false,
  });

  final NowPlayingKind kind;

  final String title;

  /// Artist for music, show name and chapter for an audiobook, the item's own
  /// name for video.
  final String subtitle;

  /// Null when the owner has no artwork to offer, which is the common case for a
  /// video route whose poster has not loaded. The bar draws a kind icon instead
  /// of an empty hole.
  final String? artworkUrl;

  final bool isPlaying;

  /// Position at the moment of publishing, not a live value: the owner decides
  /// how often to publish, and the bar never asks for a newer one.
  final Duration position;

  /// Zero when the owner does not have a duration yet, which the bar reads as
  /// "no progress" rather than as a division.
  final Duration duration;

  /// Whether a previous action exists at all. The bar disables rather than hides
  /// the button, so the transport keeps four stable slots as a queue starts and
  /// ends instead of shifting under a D-pad user.
  final bool canPrevious;
  final bool canNext;
}

/// Implemented by whichever surface owns playback, registered with the service.
///
/// The owning surface never hears from the bar directly; it hands over this
/// interface and the bar calls through [NowPlayingService], which is what lets
/// the shell compile without importing a single page.
abstract interface class NowPlayingCommands {
  Future<void> togglePlayPause();

  Future<void> next();

  Future<void> previous();

  Future<void> seek(Duration position);

  /// Stop playback and drop whatever is loaded, so the shell renders no bar.
  ///
  /// The bar has no other way to be dismissed: with a snapshot present it is on
  /// screen, and none of the transport controls remove one. A viewer who played
  /// an album had a strip they could not get rid of.
  Future<void> stop();

  /// Expand to the owning surface at full size.
  void openFullPlayer(BuildContext context);
}

abstract final class NowPlayingService {
  /// Null means nothing is loaded, and the shell renders no bar.
  static final ValueNotifier<NowPlayingSnapshot?> current =
      ValueNotifier<NowPlayingSnapshot?>(null);

  /// Owners in registration order, most recent last. A transient owner sits on
  /// top of a process-wide one and hands the commands back when it leaves.
  static final List<NowPlayingCommands> _ownerStack = <NowPlayingCommands>[];

  /// The owner the bar is talking to: the top of the stack, or null when nothing
  /// is registered and the delegating statics have nowhere to go.
  static NowPlayingCommands? get commands =>
      _ownerStack.isEmpty ? null : _ownerStack.last;

  /// The owner registers on init and unregisters on dispose.
  ///
  /// Registration moves an owner to the top rather than appending a second copy,
  /// so a repeated `initialize()` stays idempotent and a hot reload cannot stack
  /// the music bridge twice. Stacking rather than overwriting is what lets the
  /// audiobook screen register on top of the bridge and leave again without
  /// either owner learning about the other; last-writer-wins would leave the bar
  /// with no commands at all once the transient owner disposed.
  static void register(NowPlayingCommands commands) {
    _ownerStack.removeWhere((owner) => identical(owner, commands));
    _ownerStack.add(commands);
  }

  /// Removes [commands] wherever it sits in the stack, which is the top for a
  /// well behaved owner.
  ///
  /// Identity, not equality: an owner can only ever remove itself, so a dispose
  /// can never tear down a registration it does not own, and unregistering
  /// something that was never registered is a no-op. Removing the top makes the
  /// next owner down the active one again, which is what makes the audiobook
  /// screen's dispose harmless to the music bridge.
  ///
  /// It deliberately leaves [current] alone. Ownership and state are separate, so
  /// a transient owner leaving must not blank the snapshot the restored owner
  /// published.
  static void unregister(NowPlayingCommands commands) {
    _ownerStack.removeWhere((owner) => identical(owner, commands));
  }

  /// The owner pushes state. The shell never polls.
  ///
  /// [snapshot] is null to say "stopped, nothing loaded", which is also the only
  /// way the bar is removed. A separate flag would be a second piece of state for
  /// every owner to keep in sync with the first, and the two would disagree
  /// eventually. It never touches the owner stack either: a snapshot outlives the
  /// owner that published it and vice versa, and the two are set from one owner
  /// on different schedules.
  ///
  /// Known gap, accepted rather than fixed: a restore is silent, because there is
  /// no owner-change notification for a returning owner to react to. If music is
  /// loaded but already paused when an audiobook screen opens and closes, no
  /// `MusicPlayerController` notification follows the restore, so the bar stays
  /// hidden until the next music interaction even though the track is still
  /// loaded. The trigger that would close it is the bridge republishing when it
  /// finds itself the owner again; an owner-change notifier for that is
  /// deliberately out of scope here.
  static void publish(NowPlayingSnapshot? snapshot) {
    current.value = snapshot;
  }

  // The five delegations below are the bar's whole command surface. Each no-ops
  // when nothing is registered rather than asserting: the bar is mounted by the
  // shell unconditionally, so it can be on screen for a frame before an owner
  // mounts, and a tap in that window should do nothing instead of throwing.
  static Future<void> togglePlayPause() async {
    await commands?.togglePlayPause();
  }

  static Future<void> next() async {
    await commands?.next();
  }

  static Future<void> previous() async {
    await commands?.previous();
  }

  static Future<void> seek(Duration position) async {
    await commands?.seek(position);
  }

  static Future<void> stop() async {
    await commands?.stop();
  }

  static void openFullPlayer(BuildContext context) {
    commands?.openFullPlayer(context);
  }
}
