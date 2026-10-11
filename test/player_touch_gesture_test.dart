/// Drives the player's touch contract the way a finger does, and pins what one
/// vertical gesture on the video is taken to mean.
///
/// Reported on an Android phone: "you can only do screen gestures to
/// increase/decrease volume, but no amount of screen tapping or anything is
/// bringing up the player controls, so you are left trapped there". The screen
/// hangs `onTap` and `onVerticalDrag*` off one `GestureDetector`, so a finger
/// that rolls a few pixels gives the gesture to the drag recognizer and the tap
/// is cancelled before `onTap` runs. The drag then flashed the volume readout
/// and moved the level by a fraction of a percent.
///
/// `PlayerScreen` cannot be pumped - it owns a `media_kit` `Player` - so the
/// decision lives in `player_touch_gesture.dart` and is driven here, the same
/// way `player_transport_focus_test.dart` drives `player_remote_keys.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/player/player_touch_gesture.dart';

void main() {
  test('a finger that hardly moves is a tap, not an adjustment', () {
    final touch = PlayerTouchGesture();

    // The way a real tap arrives: a few pixels of roll in each direction,
    // delivered as several updates that never add up to a swipe.
    for (final delta in <double>[2.0, -1.5, 3.0, -2.0]) {
      expect(touch.update(delta), isFalse,
          reason: 'no single update may commit the gesture');
    }

    expect(touch.adjusting, isFalse);
    expect(touch.isTap, isTrue,
        reason: 'the screen toggles the HUD for this gesture, which is the '
            'only way the controls come back on a phone');
  });

  test('a swipe is an adjustment, and stops being a tap', () {
    final touch = PlayerTouchGesture();

    expect(touch.update(30.0), isTrue,
        reason: 'a deliberate swipe commits on its first real movement');
    expect(touch.adjusting, isTrue);
    expect(touch.isTap, isFalse,
        reason: 'the screen must not also toggle the HUD for a swipe');
  });

  test('the slop is what decides, not the direction of travel', () {
    final touch = PlayerTouchGesture(slop: 12.0);

    // Jitter down and up again: the distance travelled is what counts, so a
    // finger that wobbles still commits once it has genuinely moved.
    expect(touch.update(-7.0), isFalse);
    expect(touch.update(7.0), isTrue);
    expect(touch.adjusting, isTrue);
  });

  test('the next gesture starts clean', () {
    final touch = PlayerTouchGesture();

    touch.update(40.0);
    expect(touch.adjusting, isTrue);

    touch.reset();
    expect(touch.adjusting, isFalse);
    expect(touch.isTap, isTrue,
        reason: 'a committed swipe must not make the following tap look like '
            'an adjustment');
    expect(touch.update(3.0), isFalse);
  });
}
