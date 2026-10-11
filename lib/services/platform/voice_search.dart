/// Voice search, handed to the platform's own recognition UI.
///
/// Typing is the one thing a television remote cannot do. The field is a
/// `TextField` and that is right on a phone, but on a leanback device the user
/// walks an on-screen keyboard one key at a time, so spelling a title costs a
/// minute and the search is abandoned before it is finished. The answer, and
/// the one Stremio ships, is to let the platform own the listening: the user
/// presses a microphone, Android shows whatever recognizer the device carries -
/// Google's, the OEM's, the television's own - and the field only ever sees the
/// finished sentence.
///
/// Nothing about the recognizer can be assumed from here. A device may have one,
/// may have none, and may refuse the microphone permission; the activity may
/// cancel when the user backs out without saying anything. So the whole surface
/// is two calls - "can you?" and "listen" - and every failure has one answer:
/// [available] folds a missing channel, a platform error and a plain "no" into
/// `false`, because a microphone that does nothing is a worse control than no
/// microphone at all.
///
/// The channel name is the other half of `VoiceSearchBridge.METHOD_CHANNEL` in
/// `MainActivity`'s package, kept here so the pairing is grep-able from either
/// side, exactly as `DeviceProfile.channel` is kept next to its native half.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The platform's speech recognizer, behind a two-call Dart surface.
abstract final class VoiceSearch {
  /// The channel `VoiceSearchBridge` answers on.
  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('io.github.tzero86.zplay/voice_search');

  /// The one probe, shared by every caller.
  ///
  /// A cached future rather than a resolved/answer flag pair: two builds in one
  /// frame both ask, and a flag set before the await would hand the second one
  /// the default `false` - a microphone missing because a second question was
  /// asked before the first had answered.
  static Future<bool>? _probeOnce;

  /// Whether the platform can actually run a recognition activity.
  ///
  /// Resolved once and remembered: the answer cannot change while the process
  /// lives, a recognizer is not installed mid-session, and the field must never
  /// wait on a channel round trip to build. Read it after the first frame and
  /// show the microphone only when it is true.
  ///
  /// Every failure folds into `false` rather than throwing. A desktop or web
  /// build has no native half and the channel answers `MissingPluginException`;
  /// an Android device with no recognizer answers `false`. Neither is an error
  /// the caller can act on, and neither should put a broken control on screen.
  static Future<bool> available() => _probeOnce ??= _probe();

  /// The one round trip, with every failure folded into `false`.
  static Future<bool> _probe() async {
    try {
      return await channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[VoiceSearch] availability probe failed: ${e.message}');
      return false;
    } on MissingPluginException {
      // A build without the native half - Windows, web - has no recognizer.
      return false;
    } catch (e) {
      debugPrint('[VoiceSearch] availability probe failed: $e');
      return false;
    }
  }

  /// Hand the query to the platform's recognizer and await the transcript.
  ///
  /// Completes with the words the user spoke, or `null` when they cancelled or
  /// backed out without speaking. A cancellation is not an empty query: it must
  /// leave the field exactly as it was rather than clearing it.
  ///
  /// Throws `PlatformException` with `denied` when the microphone permission
  /// was refused, and `unavailable` when there is no recognizer to show. The
  /// caller decides whether that is a message to the user or the end of the
  /// control; anything else the platform reports is a refusal of one attempt,
  /// not of the feature.
  static Future<String?> listen() async {
    return await channel.invokeMethod<String>('listen');
  }

  /// Test seam: forget the resolved answer so the next [available] asks again.
  ///
  /// The answer is process-wide, so a test that mocked the channel would leak
  /// its own into the next one without this.
  @visibleForTesting
  static void debugReset() {
    _probeOnce = null;
  }
}
