import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// Playback speed and sleep timer floating popover menu.
class PlayerSpeedMenu extends StatefulWidget {
  final double currentRate;
  final ValueChanged<double> onRateSelected;
  final VoidCallback onClose;

  const PlayerSpeedMenu({
    super.key,
    required this.currentRate,
    required this.onRateSelected,
    required this.onClose,
  });

  @override
  State<PlayerSpeedMenu> createState() => _PlayerSpeedMenuState();
}

class _PlayerSpeedMenuState extends State<PlayerSpeedMenu> {
  static const List<double> _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  int? _selectedSleepMinutes;

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
                  'PLAYBACK SPEED',
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
                onPressed: widget.onClose,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Speed Preset List
          Column(
            children: _presets.map((rate) {
              final isSelected = (widget.currentRate - rate).abs() < 0.01;
              return FocusableInkWell(
                borderRadius: ZplayRadius.smAll,
                onTap: () {
                  widget.onRateSelected(rate);
                  widget.onClose();
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
                        rate == 1.0
                            ? 'Normal (1.0×)'
                            : '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}×',
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

          const SizedBox(height: 10),
          Divider(color: tokens.borderDefault, height: 1),
          const SizedBox(height: 10),

          // Sleep Timer Section
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s8,
              vertical: ZplaySpacing.s4,
            ),
            child: Text(
              'SLEEP TIMER',
              style: ZplayType.overline
                  .copyWith(size: 10.5, weight: FontWeight.w700)
                  .toStyle(color: PlayerTheme.inkSubtle),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [15, 30, 45, 60].map((min) {
              final active = _selectedSleepMinutes == min;
              return PlayerToggleChip(
                active: active,
                label: '$min min',
                onClick: () {
                  setState(() {
                    _selectedSleepMinutes = active ? null : min;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
