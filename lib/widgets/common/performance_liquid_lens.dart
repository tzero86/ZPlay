import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../services/theme/design_tokens.dart';
import '../../services/theme/glass_settings.dart';

/// Reusable styles keep the package render object from receiving a new
/// style identity and repainting when an unrelated parent rebuilds.
abstract final class PerformanceGlassStyles {
  static LiquidGlassStyle get dock => GlassSettings.createDockGlassStyle();
  static LiquidGlassStyle get sheet => GlassSettings.createSheetGlassStyle();
  static LiquidGlassStyle get menuButton =>
      GlassSettings.createButtonGlassStyle();
  static LiquidGlassStyle get menu => GlassSettings.createSheetGlassStyle();
}

/// A deliberately constrained use of the package's real lens.
class PerformanceLiquidLens extends StatelessWidget {
  final LiquidGlassStyle? style;
  final Widget child;
  final bool visible;

  const PerformanceLiquidLens({
    super.key,
    this.style,
    required this.child,
    this.visible = true,
  });

  /// The lens is chrome, so its fallback is two semantic surfaces rather than
  /// the fork's near-blacks. The 0.94 keeps the panel reading as glass — the page
  /// behind it still shows through, which is what the real lens does.
  static const double _fallbackAlpha = 0.94;

  BoxDecoration _fallbackDecoration(ZplayTokens tokens) => BoxDecoration(
    borderRadius: ZplayRadius.lgAll,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tokens.surfaceOverlay.withValues(alpha: _fallbackAlpha),
        tokens.surface.withValues(alpha: _fallbackAlpha),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      child: child,
      builder: (context, enabled, cachedChild) {
        if (!enabled) {
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: _fallbackDecoration(tokens),
            child: cachedChild,
          );
        }

        return ValueListenableBuilder<int>(
          valueListenable: GlassSettings.styleRevision,
          builder: (context, _, __) {
            final effectiveStyle = style ?? PerformanceGlassStyles.dock;
            return RepaintBoundary(
              child: LiquidGlassLens(
                style: effectiveStyle,
                visibility: visible,
                useImpellerBackdrop: true,
                child: cachedChild,
              ),
            );
          },
        );
      },
    );
  }
}
