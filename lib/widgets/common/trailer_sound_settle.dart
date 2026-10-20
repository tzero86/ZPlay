/// Waits for a trailer embed to have applied a sound change.
///
/// YouTube applies a mute change asynchronously: the player still reports
/// the old state for a moment after `unMute()` returns. A host that reads
/// the state once, straight after the command, therefore reads the state
/// *before* the change - and the control that is drawn from that answer
/// never moves. That is the bug this waits out.
///
/// The policy is deliberately simple:
///
/// - the state is read again until it agrees with what was asked for;
/// - a read that gives the same answer twice means the embed has settled on
///   a state of its own, and the answer is taken as it is - an embed that
///   refuses to unmute must be reported as refusing, not as unmuting;
/// - the wait is bounded, so a wedged embed cannot hang the control.
library;

/// Reads a trailer embed's sound state until it has settled.
abstract final class TrailerSoundSettle {
  /// How many times the state is read before the answer is taken as it is.
  static const int maxReads = 20;

  /// How long to wait between two reads.
  static const Duration interval = Duration(milliseconds: 50);

  /// Reads the state until it settles.
  ///
  /// [read] returns the state the embed is in, or null when the embed
  /// cannot be asked. [wanted] is the state the change was asking for.
  /// [isCancelled] stops the wait when the surface has gone away.
  ///
  /// Returns the state the embed settled on, or null when there was none.
  static Future<bool?> settle({
    required bool wanted,
    required Future<bool?> Function() read,
    bool Function()? isCancelled,
  }) async {
    bool? previous;
    var repeats = 0;
    for (var attempt = 0; attempt < maxReads; attempt++) {
      final muted = await read();
      if (muted == null) return null;
      if (muted == wanted) return muted;
      if (muted == previous) {
        repeats++;
        // Two reads in a row with the same answer: the state is not moving.
        if (repeats >= 2) return muted;
      } else {
        repeats = 0;
      }
      previous = muted;
      if (isCancelled?.call() ?? false) return null;
      await Future<void>.delayed(interval);
      if (isCancelled?.call() ?? false) return null;
    }
    return previous;
  }
}
