import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// The title row every floating player menu opens with: an overline caption and
/// the close button a remote can reach first.
class PlayerMenuHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const PlayerMenuHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s8,
            vertical: ZplaySpacing.s4,
          ),
          child: Text(
            title,
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
    );
  }
}

/// A 38 dp option row: raised fill and edge when [selected], plus the check mark
/// that tells a viewer on a remote which option is live.
class PlayerMenuOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const PlayerMenuOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableInkWell(
      borderRadius: ZplayRadius.smAll,
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
        decoration: BoxDecoration(
          color: selected ? PlayerTheme.raised : Colors.transparent,
          borderRadius: ZplayRadius.smAll,
          border: Border.all(
            color: selected ? PlayerTheme.edge : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: ZplayType.label
                  .copyWith(
                    size: 13.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                  )
                  .toStyle(
                    color: selected ? PlayerTheme.ink : PlayerTheme.inkMuted,
                  ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 16,
                color: PlayerTheme.accent,
              ),
          ],
        ),
      ),
    );
  }
}