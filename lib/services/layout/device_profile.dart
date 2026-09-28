/// One-shot television detection, read before the first frame.
///
/// **The framework does not do this, and no amount of `MediaQuery` will.**
/// `MediaQueryData.navigationMode` exists, defaults to
/// [NavigationMode.traditional] (`media_query.dart:233`) and is only ever
/// filled from `platformData` (`media_query.dart:333`). Nothing supplies
/// `platformData` on Android: the engine's `SettingsChannel` sends exactly six
/// keys — `textScaleFactor`, `nativeSpellCheckServiceDefined`,
/// `brieflyShowPassword`, `alwaysUse24HourFormat`, `platformBrightness` and
/// `configurationId` — and `common/settings.h` has no navigation field at all.
/// The only `platformData` the framework accepts is an ancestor `MediaQuery`
/// handing its own data down. So on a television `navigationModeOf` is
/// permanently `traditional`, and every ten-foot decision keyed on it is
/// silently off.
///
/// That is why this exists rather than a plugin. It is a single boolean read
/// once at startup, the answer cannot change while the process lives, and
/// `MainActivity` already hosts a channel, so a second dependency would buy
/// nothing.
///
/// **Leanback, not "has a D-pad".** A phone with a Bluetooth keyboard or a
/// tablet with a gamepad also reports a directional pad, and a Fire TV stick
/// and a Chromecast with an Android TV receiver both report leanback while
/// having no directional pad worth naming. `UiModeManager.getCurrentModeType`
/// is the platform's own "this is a television" answer, and the manifest
/// already declares `android.software.leanback` for the launcher, so the two
/// are asking the same question. Both are ANDed: a leanback box with a
/// touchscreen reports leanback and is still driven by touch, and a leanback
/// box that somehow reports a touch pad is a device whose D-pad the user is
/// not using.
///
/// Read eagerly rather than on demand because the first frame's layout depends
/// on it. A first-frame race here is not a flicker: the shell builds its
/// chrome, the rail sets its target sizes and the autofocus decision is made
/// once, so a late answer would leave a phone layout on a television with no
/// rebuild to correct it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Startup-time form-factor facts that only the platform can answer.
abstract final class DeviceProfile {
  /// The channel `MainActivity` answers on. Kept next to the Dart name so the
  /// two halves of the pairing are grep-able from either side.
  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('io.github.tzero86.zplay/device');

  static bool _television = false;
  static bool _resolved = false;

  /// Whether this device is a television. Safe to read synchronously from any
  /// build; on every non-Android platform it is `false`, which is correct
  /// because the only television platform this app ships to is Android TV.
  static bool get isTelevision => _television;

  /// Ask the platform once, before the first frame.
  ///
  /// Never throws: a missing channel, a detached engine in a unit test, or a
  /// platform with no such API must all resolve to `false` and leave the app on
  /// its pointer-device layout, which is the safe answer. A television wrongly
  /// classified as a phone is a usable app; a phone wrongly classified as a
  /// television is a broken one.
  static Future<void> resolve() async {
    if (_resolved) return;
    // Set before the await so a re-entrant call cannot issue a second query,
    // and so a failed read still counts as resolved rather than retrying on
    // every frame that asks.
    _resolved = true;
    _television = Platform.isAndroid && await probe();
  }

  /// The one round trip, with every failure folded into `false`.
  ///
  /// Split out from [resolve] so the channel call stays reachable from a test
  /// on any host. Gating the probe on `Platform.isAndroid` inside the same
  /// method meant a Windows or CI runner skipped the channel entirely, which is
  /// exactly where this class was wrong and nobody could see it.
  @visibleForTesting
  static Future<bool> probe() async {
    try {
      return await channel.invokeMethod<bool>('isTelevision') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[DeviceProfile] television probe failed: ${e.message}');
      return false;
    } on MissingPluginException {
      // A build without the native half, or a test. Not a television.
      return false;
    }
  }

  /// Test seam: forces the answer and marks it resolved.
  @visibleForTesting
  static void debugSetTelevision({required bool value}) {
    _television = value;
    _resolved = true;
  }
}
