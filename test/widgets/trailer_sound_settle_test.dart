/// Guards the wait that lets a trailer embed apply a sound change.
///
/// YouTube applies a mute change asynchronously, so a host that reads the
/// state once, straight after the command, reads the state from *before*
/// the change. The control drawn from that answer never moves, and the
/// user is left with a button that does nothing - the failure that
/// shipped.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/trailer_sound_settle.dart';

void main() {
  test('it waits for the state to agree with what was asked for', () async {
    // The embed answers "still muted" twice and then "unmuted": the change
    // landed on the third read.
    final answers = <bool>[true, true, false];
    var reads = 0;
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async => answers[reads++ < answers.length ? reads - 1 : 2],
    );
    expect(settled, isFalse);
    expect(reads, greaterThan(1), reason: 'the state must be read again');
  });

  test('it gives up on an embed that refuses to change', () async {
    // An embed that will not make noise must be reported as refusing. A
    // host that reported the *wanted* state would draw a speaker over a
    // silent video.
    var reads = 0;
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async {
        reads++;
        return true;
      },
    );
    expect(settled, isTrue, reason: 'the embed refused, and must be reported');
    expect(
      reads,
      3,
      reason: 'two agreeing reads are enough to call it settled',
    );
  });

  test('it stops when the surface has gone away', () async {
    var reads = 0;
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async {
        reads++;
        return true;
      },
      isCancelled: () => true,
    );
    expect(settled, isNull);
    expect(reads, 1, reason: 'a cancelled wait must not keep reading');
  });

  test('it stops when the embed cannot be asked', () async {
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async => null,
    );
    expect(settled, isNull);
  });

  test('it does not read forever', () async {
    // A wedged embed must not hang the control: the wait is bounded.
    var reads = 0;
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async {
        reads++;
        // An answer that keeps flipping never settles.
        return reads.isEven;
      },
    );
    expect(settled, isNotNull);
    expect(reads, lessThanOrEqualTo(TrailerSoundSettle.maxReads));
  });

  test('a state that already agrees is taken at once', () async {
    var reads = 0;
    final settled = await TrailerSoundSettle.settle(
      wanted: false,
      read: () async {
        reads++;
        return false;
      },
    );
    expect(settled, isFalse);
    expect(reads, 1, reason: 'there is nothing to wait for');
  });
}
