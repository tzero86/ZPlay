/// ZPlay form-factor classification: the one place the app decides whether it is
/// on a phone, a tablet, a desktop or a television.
///
/// Everything downstream reads this instead of branching on width. The charter
/// (`docs/REDESIGN_DIRECTION.md`, "Form-factor matrix") measured 58 files
/// branching on width across 11 distinct breakpoint numbers, with `shortestSide`
/// used nowhere; one classifier the shell owns is what retires that drift.
///
/// **Television comes from the platform, not from `MediaQuery`.** This file
/// used to claim `MediaQuery.navigationModeOf` reported the D-pad "for free,
/// with no platform channel and no plugin", and that was simply false: the
/// Android engine sends no navigation mode in its six `SettingsChannel` keys and
/// `common/settings.h` has no such field, so the value is permanently
/// `traditional` and a real television silently received the pointer-device
/// chrome. [DeviceProfile] asks `UiModeManager` instead, once, before the first
/// frame; see that file for the full argument. The `MediaQuery` claim looked
/// plausible because the field exists, the enum has the right name, and the
/// framework documents it in terms of televisions.
///
/// **Bands run on `shortestSide`, not on width.** `shortestSide` does not change
/// when a device rotates, so turning one does not reclassify it: a 390 by 844
/// phone stays [FormFactor.compact] in landscape, and a 1024 by 768 tablet stays
/// [FormFactor.medium] in both orientations. Width would promote every phone in
/// landscape to a tablet and every tablet in landscape to a desktop, so the
/// chrome would jump mid-rotation.
///
/// Nothing here renders, holds state or builds a widget: every member is a pure
/// function over its inputs, so the classification is testable through
/// [FormFactorService.resolve] without pumping a tree.
library;

import 'package:flutter/widgets.dart';

import 'device_profile.dart';

/// Re-exported so shell code reads one import for "what am I running on".
export 'device_profile.dart' show DeviceProfile;

/// The four chrome layouts the shell can be in. Ordered narrowest to widest,
/// with [television] last because its input, not its width, is what defines it.
///
/// To ask "does this form factor get a side rail rather than the bottom bar",
/// test `of(context) != FormFactor.compact`. Do not ask for
/// [FormFactor.expanded] or [FormFactor.medium] and assume television is
/// included: it shares the rail with desktop but not the keyboard map or the
/// hover affordances, so it is deliberately its own value.
enum FormFactor {
  /// Phone. Bottom bar, five slots, 44 px targets. `shortestSide` below
  /// [FormFactorService.mediumMin].
  compact,

  /// Tablet and small windows. Left rail, 88 px, 48 px targets. `shortestSide`
  /// from [FormFactorService.mediumMin] up to [FormFactorService.expandedMin].
  medium,

  /// Desktop. Left rail, 88 px, 44 px targets, keyboard map. `shortestSide` at or
  /// above [FormFactorService.expandedMin].
  expanded,

  /// Ten-foot. Expanded rail, 236 px, 56 to 64 px targets, focus ring. Reported
  /// by the platform rather than measured, so it wins at any window size.
  television,
}

abstract final class FormFactorService {
  /// The breakpoints the charter pins: 600 and 1024 on `shortestSide`.
  static const double mediumMin = 600;
  static const double expandedMin = 1024;

  /// True when the platform says this is a television.
  ///
  /// Read from [DeviceProfile], which asks `UiModeManager` once at startup.
  /// This is deliberately not `MediaQuery.navigationModeOf`: that value is
  /// [NavigationMode.traditional] on every Android device, television or not,
  /// because nothing populates it, so the old implementation could never return
  /// `true` on the one platform that matters. It looked right because the field
  /// exists, the enum has the right name, and the framework documents it in
  /// terms of televisions.
  static bool get hasRemoteInput => DeviceProfile.isTelevision;

  /// Television wins over the size bands: a TV is wide but its input is the
  /// reason it needs a different layout, not its width.
  static FormFactor of(BuildContext context) => resolve(
    shortestSide: MediaQuery.sizeOf(context).shortestSide,
    remoteInput: hasRemoteInput,
  );

  /// Pure function form, for tests and for code without a BuildContext.
  ///
  /// Bands are half open, so a window exactly on a breakpoint takes the larger
  /// one: 600 is [FormFactor.medium] and 1024 is [FormFactor.expanded]. That
  /// direction matters for a desktop window dragged to its minimum width, which
  /// would otherwise flicker between the rail and the bottom bar at the boundary.
  static FormFactor resolve({
    required double shortestSide,
    required bool remoteInput,
  }) {
    // Remote input is tested first, so a television is classified by what drives
    // it and never by its window: a TV surface can be narrow enough to fall in
    // the compact band and still needs the ten-foot chrome.
    if (remoteInput) return FormFactor.television;
    if (shortestSide < mediumMin) return FormFactor.compact;
    if (shortestSide < expandedMin) return FormFactor.medium;
    return FormFactor.expanded;
  }
}
