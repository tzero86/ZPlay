import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';
import 'player_menu_rows.dart';

/// Playback speed floating popover menu.
class PlayerSpeedMenu extends StatelessWidget {
  final double currentRate;
  final ValueChanged<double> onRateSelected;
  final VoidCallback onClose;

  const PlayerSpeedMenu({
    super.key,
    required this.currentRate,
    required this.onRateSelected,
    required this.onClose,
  });

  static const List<double> _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return PlayerGlassCard(
      width: (320.0).clamp(240.0, screenWidth - 32),
      padding: const EdgeInsets.all(ZplaySpacing.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          PlayerMenuHeader(title: 'PLAYBACK SPEED', onClose: onClose),

          const SizedBox(height: 6),

          // Speed Preset List
          Column(
            children: _presets.map((rate) {
              return PlayerMenuOption(
                label: rate == 1.0
                    ? 'Normal (1.0×)'
                    : '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}×',
                selected: (currentRate - rate).abs() < 0.01,
                onTap: () {
                  onRateSelected(rate);
                  onClose();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}