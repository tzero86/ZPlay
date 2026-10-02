import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// The ZPlay mark, drawn rather than loaded.
///
/// Six surfaces showed `assets/icon_small.png` - the rail, the Home app bar,
/// Anime, the player, Addons, and the built-in provider's own icon - and that
/// file is a raster with `#2FD0C0` baked into it. Changing the palette therefore
/// left the app shipping a teal logo on a red app, and nothing would have said
/// so.
///
/// Drawing it means the mark takes its colour from [ZplayTokens.accent] like
/// every other surface, so it follows the theme instead of contradicting it. The
/// shape is unchanged: a full-bleed rounded square with a Z cut into it, which
/// is what the asset always was.
///
/// The cut-out is a [CustomPaint] rather than a `ClipPath` because the glyph has
/// to be transparent - it shows the accent behind it - and a clip would need a
/// second widget doing the same work.
class ZplayLogo extends StatelessWidget {
  const ZplayLogo({super.key, this.size = 24});

  /// The width and height of the mark. Callers pass their own; the internal
  /// geometry is all proportional, so there is one number to get right rather
  /// than a set.
  final double size;

  /// The plate as a fraction of the box it is given. See [build].
  static const double _plateRatio = 0.91;

  /// Corner radius as a fraction of the plate's own side, measured off the
  /// original asset rather than chosen.
  static const double _cornerRatio = 0.20;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.accent;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          // 91% of the box, not all of it. Measured off the original asset: the
          // plate spanned x 13..245 of 256, so it sat inside an 11 px margin on
          // every side. Filling the whole square instead is what made this read
          // as hunched - a rounded square filling its frame looks like it is
          // buckling under the corners, and no amount of radius fixes that.
          width: size * _plateRatio,
          height: size * _plateRatio,
          decoration: BoxDecoration(
            color: accent,
            // 0.20, measured from the asset's own corner profile: the leftmost
            // accent pixel settles at 13 px and the curve is finished by ~62 px.
            // Larger values read as a lozenge rather than a plate.
            borderRadius: BorderRadius.circular(size * _plateRatio * _cornerRatio),
          ),
          child: CustomPaint(
            painter: _ZGlyphPainter(ink: context.tokens.bg),
          ),
        ),
      ),
    );
  }

  /// The Z, as a path in the mark's own coordinates.
  ///
  /// Public and static so a test can read the *shape* rather than a rendered
  /// image. `RenderRepaintBoundary.toImage` never completes under the test
  /// binding, and a golden would have to be regenerated on every tweak - which
  /// is the coupling this whole change exists to remove.
  ///
  /// The thing worth asserting is the diagonal: a Z runs top-right to
  /// bottom-left, and mirrored it is an S. The first version of this file got
  /// that wrong and a test asking only "is a glyph painted" agreed with it.
  static Path glyphPath(Size size) {
    // Proportions read off the original asset rather than drawn freehand: the
    // square's corner radius is 0.22 of its side, and the Z occupies the middle
    // 55% with a stroke a little under half its thickness.
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.155;
    final left = (w - w * 0.55) / 2;
    final right = left + w * 0.55;
    final top = (h - h * 0.55) / 2;
    final bottom = top + h * 0.55;

    return Path()
      ..moveTo(left + stroke / 2, top + stroke / 2)
      ..lineTo(right - stroke / 2, top + stroke / 2)
      ..lineTo(left + stroke / 2, bottom - stroke / 2)
      ..lineTo(right - stroke / 2, bottom - stroke / 2);
  }
 }

class _ZGlyphPainter extends CustomPainter {
  const _ZGlyphPainter({required this.ink});

  /// The colour showing through the cut-out. The mark's background is the
  /// accent, so this is whatever sits behind it - which on a dark shell is the
  /// surface the mark is drawn on.
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      ZplayLogo.glyphPath(size),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.155
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_ZGlyphPainter oldDelegate) => oldDelegate.ink != ink;
}