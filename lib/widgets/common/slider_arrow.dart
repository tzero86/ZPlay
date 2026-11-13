import 'dart:ui';
import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// The arrow that sits on the edge of a horizontally scrolling band and steps it
/// one page.
///
/// Home's hero and the anime, manga, music, audiobook, book and IPTV rails each
/// drew this button themselves; this is the one they all draw now.
///
/// **Two finishes, one control.** The app already had both: a frosted disc that
/// picks up whatever slides under it and lifts on hover (every rail, and the
/// anime and audiobook spotlights), and a flat raised-surface circle with an
/// accent ring (home's hero). They are the same control on two different backs -
/// a disc floating over a crowded rail and a button pinned to a full-bleed
/// photograph - and the copies had drifted apart in size as well, 48 and 52. The
/// finish is the caller's, because only the caller knows what its band is made
/// of; the tap, the icon and the hit area are identical either way.
class SliderArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  /// Diameter of the disc, and the size of the glyph inside it.
  ///
  /// The defaults are the rails' 48 dp disc with a 20 dp chevron. Home's hero
  /// passes a larger pair because its band is the whole window rather than a rail
  /// a couple of hundred dp tall, and an arrow sized for the rail reads as debris
  /// on it.
  final double size;
  final double iconSize;

  /// Whether the disc is the frosted one or the flat raised-surface one.
  ///
  /// True (the default) is the disc that belongs to a rail: it blurs what is
  /// behind it, so the cards sliding underneath stay visible through it, and it
  /// lifts and darkens under the pointer. False is chrome pinned on artwork: an
  /// opaque raised surface with an accent border on highlight and no lift, made
  /// of the app's own card primitive - which is also what makes it reachable by
  /// a D-pad, as home's hero controls are.
  final bool frosted;

  const SliderArrow({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.iconSize = 20,
    this.frosted = true,
  });

  @override
  State<SliderArrow> createState() => _SliderArrowState();
}

class _SliderArrowState extends State<SliderArrow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.frosted) return _frosted(context);
    return _surface(context);
  }

  /// Chrome pinned on artwork: opaque raised surfaces and an accent border on
  /// highlight, so the control stays a control against whatever frame is behind
  /// it, and no scale or blur - the band under it is already moving artwork, and
  /// a disc that grows and smears on top of that reads as a rendering fault.
  Widget _surface(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: widget.onTap,
      builder: (_, state) => AnimatedContainer(
        duration: ZplayMotion.base,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state.highlighted
              ? tokens.surfaceRaised
              : tokens.surfaceOverlay,
          border: Border.all(
            color: state.highlighted ? tokens.accent : tokens.borderStrong,
            width: 1.5,
          ),
        ),
        child: Icon(
          widget.icon,
          color: state.highlighted ? tokens.textPrimary : tokens.textEmphasis,
          size: widget.iconSize,
        ),
      ),
    );
  }

  /// The frosted disc a rail uses: blurred backdrop, hover lift, press dip.
  Widget _frosted(BuildContext context) {
    final tokens = context.tokens;

    // Dynamic scale based on interaction state
    final scale = _isPressed ? 0.90 : (_isHovered ? 1.08 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isHovered
                      ? tokens.textPrimary.withValues(
                          alpha: ZplayOpacity.overlayHover,
                        )
                      : tokens.bg.withValues(alpha: 0.5),
                  border: Border.all(
                    color: _isHovered
                        ? tokens.borderStrong
                        : tokens.borderDefault,
                    width: 1.5,
                  ),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  widget.icon,
                  color: tokens.textPrimary.withValues(
                    alpha: _isHovered ? 1.0 : ZplayOpacity.textEmphasis,
                  ),
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
