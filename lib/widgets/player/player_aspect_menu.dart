import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

class AspectOption {
  final String id;
  final String label;
  final BoxFit fit;

  const AspectOption({required this.id, required this.label, required this.fit});
}

const List<AspectOption> aspectOptions = [
  AspectOption(id: 'fit', label: 'Fit to screen (Contain)', fit: BoxFit.contain),
  AspectOption(id: 'cover', label: 'Fill screen (Crop/Zoom)', fit: BoxFit.cover),
  AspectOption(id: 'fill', label: 'Stretch to fill', fit: BoxFit.fill),
];

/// Aspect ratio and picture popover menu.
class PlayerAspectMenu extends StatelessWidget {
  final BoxFit currentFit;
  final double subtitleScale;
  final ValueChanged<BoxFit> onFitSelected;
  final ValueChanged<double> onSubtitleScaleChanged;
  final VoidCallback onClose;

  const PlayerAspectMenu({
    super.key,
    required this.currentFit,
    required this.subtitleScale,
    required this.onFitSelected,
    required this.onSubtitleScaleChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tokens = context.tokens;

    return PlayerGlassCard(
      width: (320.0).clamp(240.0, screenWidth - 32),
      padding: const EdgeInsets.all(ZplaySpacing.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s8,
                  vertical: ZplaySpacing.s4,
                ),
                child: Text(
                  'ASPECT RATIO',
                  style: ZplayType.overline
                      .copyWith(size: 10.5, weight: FontWeight.w700)
                      .toStyle(color: PlayerTheme.inkSubtle),
                ),
              ),
              PlayerIconButton(
                size: 28,
                iconSize: 14,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                onPressed: onClose,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Aspect Options List
          Column(
            children: aspectOptions.map((opt) {
              final isSelected = currentFit == opt.fit;
              return FocusableInkWell(
                borderRadius: ZplayRadius.smAll,
                onTap: () {
                  onFitSelected(opt.fit);
                  onClose();
                },
                child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
                    decoration: BoxDecoration(
                      color: isSelected ? PlayerTheme.raised : Colors.transparent,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: isSelected ? PlayerTheme.edge : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          opt.label,
                          style: ZplayType.label
                              .copyWith(
                                size: 13.5,
                                weight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              )
                              .toStyle(
                                color: isSelected
                                    ? PlayerTheme.ink
                                    : PlayerTheme.inkMuted,
                              ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: PlayerTheme.accent,
                          ),
                      ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: ZplaySpacing.s12),
          Divider(color: tokens.borderDefault, height: 1),
          const SizedBox(height: ZplaySpacing.s12),

          // Subtitle Size Scaling Slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtitle Size Scale',
                  style: ZplayType.bodySmall
                      .copyWith(size: 12.5, weight: FontWeight.w500)
                      .toStyle(color: PlayerTheme.inkMuted),
                ),
                Text(
                  '${subtitleScale.toStringAsFixed(1)}×',
                  style: ZplayType.bodySmall
                      .copyWith(size: 12.5, weight: FontWeight.w700)
                      .toStyle(color: PlayerTheme.ink, tabular: true),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: PlayerTheme.accent,
              inactiveTrackColor: tokens.textPrimary.withValues(alpha: 0.15),
              thumbColor: tokens.textPrimary,
              overlayColor: PlayerTheme.accent.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: subtitleScale,
              min: 0.5,
              max: 2.5,
              divisions: 20,
              onChanged: onSubtitleScaleChanged,
            ),
          ),
        ],
      ),
    );
  }
}
