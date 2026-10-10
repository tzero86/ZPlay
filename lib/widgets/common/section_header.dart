import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// Quiet rail header: one small semibold title, optional muted count,
/// optional subtitle, optional See All. One row height across rails so
/// title baselines align whether or not a rail offers See All.
///
/// The count is a muted, tabular number rather than a badge. Accent is a signal
/// for state — what you are on, what is live — and a rail title is neither, so
/// three rails wearing no number and a fourth wearing an accent pill was both
/// inconsistent and decorative. Tabular figures keep the header from shifting
/// as the number changes.
///
/// "See All" is a [FocusableCard], so it is reachable with a remote and carries
/// the app's single focus ring. It was a [TextButton] with
/// `minimumSize: Size.zero` and `tapTargetSize: shrinkWrap`, which left a target
/// roughly 28px tall — well under the comfortable minimum, on the control most
/// likely to be wanted from across a room.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// How many items the section holds. Hidden when null: a rail that does not
  /// know its count should show nothing rather than guess.
  final int? count;

  final VoidCallback? onSeeAll;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.count,
    this.onSeeAll,
    this.trailing,
  });

  static const BorderRadius _actionRadius = ZplayRadius.smAll;

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s16,
        ZplaySpacing.s8,
        ZplaySpacing.s16,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.title.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: ZplaySpacing.s8),
                          Text(
                            '$count',
                            style: ZplayType.labelNumeric.toStyle(
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: ZplaySpacing.s2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.label.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            if (onSeeAll != null) const SizedBox(width: ZplaySpacing.s8),
          ],
          if (onSeeAll != null)
            FocusableCard(
              onTap: onSeeAll,
              builder: (context, state) => CardFocusRing(
                focused: state.focused,
                radius: _actionRadius,
                child: AnimatedContainer(
                  duration: ZplayMotion.fast,
                  curve: ZplayMotion.standard,
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
                  decoration: BoxDecoration(
                    borderRadius: _actionRadius,
                    color: state.highlighted
                        ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
                        : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See All',
                        style: ZplayType.label.toStyle(
                          color: state.highlighted
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: state.highlighted
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
