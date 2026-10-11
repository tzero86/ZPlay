import 'package:flutter/material.dart';

import '../../shell/app_shell_scope.dart';
import '../music/music_player_controller.dart';
import 'now_playing_service.dart';

/// Adapts the process wide [MusicPlayerController] to the shell's playback seam.
///
/// Neither side can depend on the other: the controller is owned by the music
/// feature and the service deliberately imports no player, so the two meet here
/// instead. One adapter is also what keeps the shell, the bar and the audiobook
/// screen ignorant of how music happens to be played today.
abstract final class MusicNowPlayingBridge {
  /// Listens to [MusicPlayerController] and publishes to [NowPlayingService].
  /// Called once from main.dart. Idempotent.
  static void initialize() {
    // Hot reload re-runs the boot code that calls this, and a second listener
    // would publish every position tick twice.
    if (_initialized) return;
    _initialized = true;

    _controller.addListener(_publish);
    NowPlayingService.register(_commands);
    _publish();
  }

  /// Asks the music slot to open its own full size player.
  ///
  /// The bar cannot reach `_MusicPageState`'s expansion flag and must not import
  /// the page, so the bar's expand tap arrives here and the page listens while it
  /// is mounted. A counter rather than a bool, so two taps in a row are both
  /// delivered instead of collapsing into one state change.
  static final ValueNotifier<int> expandRequests = ValueNotifier<int>(0);

  static bool _initialized = false;

  static final MusicPlayerController _controller = MusicPlayerController.instance;

  static final _MusicNowPlayingCommands _commands = _MusicNowPlayingCommands(_controller);

  /// Publishes the controller's current frame.
  ///
  /// Runs on every controller notification, which includes the position stream,
  /// so the bar's progress line advances at the rate the player reports rather
  /// than the page having to poll it.
  static void _publish() {
    final track = _controller.currentTrack;

    // Null is the service's "nothing loaded" and the only way the bar is removed,
    // so an empty queue publishes it rather than a snapshot with empty strings.
    if (track == null) {
      NowPlayingService.publish(null);
      return;
    }

    final artist = track.artist.trim();
    final album = track.album.trim();

    NowPlayingService.publish(
      NowPlayingSnapshot(
        kind: NowPlayingKind.music,
        title: track.title,
        // Either half of the credit can be missing on a user added track, and a
        // stray separator reads worse than a subtitle that is just the other half.
        subtitle: artist.isEmpty ? album : (album.isEmpty ? artist : '$artist · $album'),
        artworkUrl: track.coverUrl.trim().isEmpty ? null : track.coverUrl,
        isPlaying: _controller.isPlaying,
        position: _controller.position,
        duration: _controller.duration,
        // Previous follows the controller's own answer: it is also true a few
        // seconds into a track, because pressing it there restarts the track,
        // which is what playPrevious does. Next cannot use the matching getter,
        // which also answers true on the last track of a repeat one queue where
        // playNext does nothing.
        canPrevious: _controller.hasPrevious,
        canNext: _controller.currentIndex < _controller.playlist.length - 1 ||
            _controller.repeatMode == MusicRepeatMode.all,
      ),
    );
  }
}

/// The bar's five commands, mapped onto the controller's own methods.
///
/// Only the transport the bar draws is exposed: lyrics, the queue, shuffle and
/// repeat stay on the music page's own surface.
class _MusicNowPlayingCommands implements NowPlayingCommands {
  const _MusicNowPlayingCommands(this._controller);

  final MusicPlayerController _controller;

  @override
  Future<void> togglePlayPause() => _controller.togglePlayPause();

  @override
  Future<void> next() => _controller.playNext();

  @override
  Future<void> previous() => _controller.playPrevious();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  /// Stops the controller and drops the loaded track.
  ///
  /// `clearQueue` empties the playlist but leaves `_currentTrack` set, and the
  /// bridge publishes from that field - so the bar would survive the very press
  /// meant to remove it. Publishing null is the service's "nothing loaded" and
  /// the only way the bar goes away, so this does that explicitly rather than
  /// hoping a listener re-reads an empty queue.
  @override
  Future<void> stop() async {
    await _controller.togglePlayPause();
    _controller.clearQueue();
    NowPlayingService.publish(null);
  }

  /// Brings the music slot forward and asks it to expand, because the full size
  /// player is a state of the page rather than a route the bar could push.
  @override
  void openFullPlayer(BuildContext context) {
    AppShellScope.of(context)?.go(ShellSlot.browse);
    MusicNowPlayingBridge.expandRequests.value++;
  }
}
