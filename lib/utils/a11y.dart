import 'package:flutter/material.dart';

/// Shared wording for the app's accessibility labels.
///
/// The rule this file exists to keep in one place:
///
/// * A card is a *button* with one name, not a pile of text nodes. Every poster
///   card says its title (and year) once, so a screen reader announces a
///   destination rather than reading a caption twice.
class A11y {
  const A11y._();

  /// `title, year` when a year is known, otherwise just `title`.
  ///
  /// The comma is what VoiceOver and TalkBack use as a clause break, so this is
  /// one utterance rather than two labels glued together with a space.
  static String cardLabel(String title, {String? year}) {
    final trimmed = year?.trim();
    if (trimmed == null || trimmed.isEmpty) return title;
    return '$title, $trimmed';
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
