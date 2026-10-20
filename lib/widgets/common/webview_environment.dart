import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// The one WebView2 environment, configured once per process.
///
/// **The environment is process-wide and reference-counted.** WebView2 will
/// not reconfigure it while a controller is alive: `initializeEnvironment`
/// fails with `environment_already_initialized` when one exists, and only
/// releases it when the last controller is disposed. The trailer modal and
/// the hover preview both need it, and either can be first - the modal when
/// the user opens a trailer, the preview when the pointer rests on a card -
/// so configuring it from each of them was a race: the second one threw and
/// the embed failed.
///
/// This is that one configuration, shared. The autoplay switch is what makes
/// the difference between a trailer that plays and a trailer that shows
/// YouTube's play button: Chromium refuses to start an unmuted video without
/// a user gesture, and a resting pointer is not one. The argument is applied
/// to the environment, so it has to be set before the first controller exists
/// - which is exactly what this does.
///
/// A runtime that refuses the configuration is still a runtime that can play
/// the trailer once something is pressed, so a failure here degrades to
/// YouTube's own control rather than to a failed embed.
abstract final class WebviewEnvironment {
  static bool _requested = false;

  /// Chromium's own switch, passed through to the browser process by WebView2.
  static const String autoplayArgument =
      '--autoplay-policy=no-user-gesture-required';

  /// Configures the environment, at most once per process.
  ///
  /// Never throws. A machine without the WebView2 runtime, a platform whose
  /// plugin is missing, or an environment that is already configured: one
  /// answer for all of them, and the answer is a log line rather than an
  /// exception on the way to the embed.
  static Future<void> ensureAutoplayPolicy() async {
    if (_requested) return;
    _requested = true;
    if (!kIsWeb && !Platform.isWindows) return;
    try {
      await WebviewController.initializeEnvironment(
        additionalArguments: autoplayArgument,
      );
    } catch (error) {
      debugPrint('[WebviewEnvironment] autoplay policy not applied: $error');
    }
  }

  /// Forgets that the environment was configured.
  ///
  /// Test-only: the environment outlives a test case, and a test that wants
  /// the configuration attempted again needs the attempt to be possible.
  @visibleForTesting
  static void resetForTesting() => _requested = false;
}
