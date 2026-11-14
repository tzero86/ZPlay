import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A [LinearGradient] that fills its box, painted from a small strip image the
/// gradient is rendered into once, instead of as a live gradient shader.
///
/// **Why.** On Linux with the Impeller OpenGL backend, a full-window gradient
/// fill is pathologically expensive once the surface is large: a maximized
/// window on a 4K monitor at fractional scaling is ~14 megapixels, and there
/// the hero's two scrims alone made the first scrolled frame take ~3 seconds to
/// rasterize while briefly allocating ~6 GB, so scrolling froze the app.
/// Measured with each scrim switched off in turn: either one alone was enough.
/// A stretched texture is a plain blit at any size, and a gradient sampled
/// bilinearly from 256 steps is indistinguishable from the shader.
///
/// Only top-to-bottom and left-to-right gradients are supported - the two the
/// full-bleed scrims use - and [gradient]'s own `begin`/`end` are ignored in
/// favour of [axis].
class BakedGradient extends StatefulWidget {
  const BakedGradient({super.key, required this.gradient, required this.axis});

  final LinearGradient gradient;

  /// [Axis.vertical] runs the colours top to bottom, [Axis.horizontal] left to
  /// right.
  final Axis axis;

  @override
  State<BakedGradient> createState() => _BakedGradientState();
}

class _BakedGradientState extends State<BakedGradient> {
  /// Steps along the gradient. Bilinear sampling interpolates between them, so
  /// this only has to resolve the stops, not the pixels it is stretched over.
  static const int _steps = 256;

  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _bake();
  }

  @override
  void didUpdateWidget(BakedGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gradient != widget.gradient ||
        oldWidget.axis != widget.axis) {
      _bake();
    }
  }

  void _bake() {
    final vertical = widget.axis == Axis.vertical;
    final width = vertical ? 1 : _steps;
    final height = vertical ? _steps : 1;
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final gradient = LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: widget.gradient.colors,
      stops: widget.gradient.stops,
    );
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(rect, Paint()..shader = gradient.createShader(rect));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    _image?.dispose();
    _image = image;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RawImage(
        image: _image,
        fit: BoxFit.fill,
        // Bilinear: the steps blend into a continuous ramp when stretched.
        filterQuality: FilterQuality.low,
      ),
    );
  }
}
