import 'package:flutter/widgets.dart';

/// Measures the panel a video is actually being shown in.
///
/// The upscaling advisory needs the size of the video area, not the size of the
/// window: `MediaQuery` reports the whole surface, letterbox bars included, so
/// using it would compare a 1920x800 film against a full-height panel and
/// understate the upscale factor. `BoxConstraints` from a `LayoutBuilder`
/// wrapped tightly around the video widget is the honest number, because it is
/// the box the decoder's output is fitted into.
///
/// A single key is shared by both players. Only one is ever mounted at a time —
/// the mainline player and the IPTV player are separate routes — so one key is
/// correct and avoids a global registry that would outlive its widget.
class VideoPanelMetrics {
  const VideoPanelMetrics._();

  static final GlobalKey _panelKey = GlobalKey(debugLabel: 'videoPanel');

  /// The key to attach around the video widget.
  static Key get panelKey => _panelKey;

  /// The current panel size in logical pixels, or null before first layout.
  static Size? get size {
    final box = _panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.size;
  }

  /// The current panel width in logical pixels, or 0 before first layout.
  static double get width => size?.width ?? 0;

  /// The current panel height in logical pixels, or 0 before first layout.
  static double get height => size?.height ?? 0;
}
