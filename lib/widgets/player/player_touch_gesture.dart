/// The player's touch contract: what one vertical finger gesture on the video
/// is asking for.
///
/// Extracted from `player_screen.dart` for the same reason
/// [`player_remote_keys`] was: `PlayerScreen` owns a `media_kit` `Player` and no
/// widget test can build it, so a rule left inside it can only be checked by a
/// stand-in that agrees with it by hand.
///
/// The report this exists for, from an Android phone: "you can only do screen
/// gestures to increase/decrease volume, but no amount of screen tapping or
/// anything is bringing up the player controls, so you are left trapped there".
/// The screen hangs `onTap` and `onVerticalDrag*` off one `GestureDetector`. A
/// finger that rolls a few pixels on its way down hands the gesture to the drag
/// recognizer, which cancels the tap before `onTap` ever fires; the drag then
/// painted the volume readout and moved the level by a fraction of a percent.
/// Every tap therefore looked like a volume gesture and the transport never came
/// back.
///
/// So a gesture is not an adjustment until the finger has travelled [slop].
/// Under that, the gesture is a tap, and the screen answers it exactly as it
/// answers a clean one: the HUD toggles.
library;

/// Tracks one vertical gesture and answers the only question the screen has
/// about it: is this a tap, or is this an adjustment?
class PlayerTouchGesture {
  PlayerTouchGesture({this.slop = defaultSlop});

  /// How far a finger may travel and still be tapping, in logical pixels.
  ///
  /// Owned here rather than by the screen so a test can drive the same number
  /// the screen does, and tuned to the platform's own tap slop: a deliberate
  /// volume or brightness swipe travels tens of pixels, a tap rolls a handful.
  static const double defaultSlop = 12.0;

  final double slop;

  double _travelled = 0;
  bool _adjusting = false;

  /// Whether the gesture has travelled far enough to be an adjustment. Until it
  /// has, the screen changes nothing and shows no readout.
  bool get adjusting => _adjusting;

  /// Whether the gesture that just ended was a tap, and must toggle the HUD.
  bool get isTap => !_adjusting;

  /// Feeds one vertical delta and reports whether the gesture is now an
  /// adjustment.
  ///
  /// The distance is accumulated rather than taken from the endpoint, so a
  /// finger that jitters up and down still commits once it has genuinely moved.
  bool update(double dy) {
    _travelled += dy.abs();
    if (!_adjusting && _travelled >= slop) _adjusting = true;
    return _adjusting;
  }

  /// Ready for the next gesture.
  void reset() {
    _travelled = 0;
    _adjusting = false;
  }
}
