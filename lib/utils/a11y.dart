import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Shared wording and platform plumbing for the app's accessibility labels.
///
/// The rules this file exists to keep in one place:
///
/// * A card is a *button* with one name, not a pile of text nodes. Every poster
///   card says its title (and year) once and hints "Open details", so a screen
///   reader announces a destination rather than reading a caption twice.
/// * A resumable card says what it resumes and how far in, because "Resume
///   Dune" alone does not tell a person whether they are starting over.
/// * An announcement must never crash a widget test or a headless host that has
///   no binding yet. [announce] is a no-op there rather than an assertion.
class A11y {
  const A11y._();

  /// The hint carried by every card that opens a details page.
  static const String openDetailsHint = 'Open details';

  /// `title, year` when a year is known, otherwise just `title`.
  ///
  /// The comma is what VoiceOver and TalkBack use as a clause break, so this is
  /// one utterance rather than two labels glued together with a space.
  static String cardLabel(String title, {String? year}) {
    final trimmed = year?.trim();
    if (trimmed == null || trimmed.isEmpty) return title;
    return '$title, $trimmed';
  }

  /// `Resume <title>, 42% watched` - the state of a Continue Watching card.
  ///
  /// The percentage is clamped and rounded once, here, so the label and any
  /// visual readout agree on the same number.
  static String resumeLabel(String title, double progress) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    return 'Resume $title, $pct% watched';
  }

  /// A spoken name for an icon-only control.
  ///
  /// Prefers the icon's own `semanticLabel`, then a small map of the icons the
  /// player actually uses, and only then [fallback]. The player's icon buttons
  /// mostly carry a `tooltip`; this covers the menu rows and overlays that do
  /// not, where an unnamed button is otherwise announced as "button".
  static String iconLabel(Widget icon, {String fallback = 'Button'}) {
    if (icon is! Icon) return fallback;
    final explicit = icon.semanticLabel;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final data = icon.icon;
    if (data == null) return fallback;
    return _labelFor(data) ?? fallback;
  }

  /// Sends a screen-reader announcement, if there is a binding and a view to
  /// send it to.
  ///
  /// A headless host (a widget test that has not initialized a binding, a
  /// background isolate) has neither, and announcing there used to be an
  /// assertion, so this is deliberately silent instead.
  static void announce(
    String message, {
    TextDirection textDirection = TextDirection.ltr,
    BuildContext? context,
  }) {
    if (!_hasBinding) return;
    final FlutterView? view = context != null
        ? View.of(context)
        : WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    unawaited(SemanticsService.sendAnnouncement(view, message, textDirection));
  }

  /// True once a `WidgetsBinding` exists.
  ///
  /// `WidgetsBinding.instance` throws a `FlutterError` before initialization
  /// rather than returning null, so this asks and catches rather than reading a
  /// nullable that does not exist.
  static bool get _hasBinding {
    try {
      WidgetsBinding.instance;
      return true;
    } on FlutterError {
      return false;
    }
  }

  /// The icons whose button has no tooltip, named the way a person would say
  /// them. Deliberately small: anything not here falls back to its caller's
  /// label instead of growing an icon dictionary.
  ///
  /// A switch rather than a map because `IconData` overrides `==` and can
  /// therefore not be a const map key.
  static String? _labelFor(IconData data) {
    switch (data) {
      case Icons.close_rounded:
        return 'Close';
      case Icons.arrow_back_ios_new_rounded:
      case Icons.chevron_left_rounded:
        return 'Back';
      case Icons.chevron_right_rounded:
        return 'Next';
      case Icons.play_arrow_rounded:
        return 'Play';
      case Icons.pause_rounded:
        return 'Pause';
      case Icons.replay_10_rounded:
        return 'Seek back 10 seconds';
      case Icons.forward_10_rounded:
        return 'Seek forward 10 seconds';
      case Icons.replay_rounded:
        return 'Restart';
      case Icons.undo_rounded:
        return 'Undo';
      case Icons.skip_previous_rounded:
        return 'Previous';
      case Icons.skip_next_rounded:
        return 'Next';
      case Icons.volume_off_rounded:
        return 'Mute';
      case Icons.volume_down_rounded:
        return 'Lower volume';
      case Icons.volume_up_rounded:
        return 'Raise volume';
      case Icons.video_library_rounded:
        return 'Episodes';
      case Icons.aspect_ratio_rounded:
        return 'Aspect ratio';
      case Icons.speed_rounded:
        return 'Playback speed';
      case Icons.audiotrack_rounded:
        return 'Audio tracks';
      case Icons.subtitles_rounded:
        return 'Subtitles';
      case Icons.tune_rounded:
        return 'Settings';
      case Icons.timer_outlined:
        return 'Timing';
      case Icons.text_fields_rounded:
        return 'Text size';
      case Icons.format_list_bulleted_rounded:
        return 'Chapters';
      case Icons.fullscreen_rounded:
        return 'Fullscreen';
      case Icons.fullscreen_exit_rounded:
        return 'Exit fullscreen';
      case Icons.link_rounded:
        return 'Copy link';
      case Icons.camera_alt_outlined:
        return 'Screenshot';
      case Icons.lock_outline_rounded:
        return 'Lock screen';
      case Icons.cast_rounded:
        return 'Cast';
      case Icons.download_rounded:
        return 'Download';
      case Icons.refresh_rounded:
        return 'Refresh';
      case Icons.search_rounded:
        return 'Search';
      default:
        return null;
    }
  }
}
