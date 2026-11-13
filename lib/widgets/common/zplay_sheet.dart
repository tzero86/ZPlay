import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';

/// The one shell every bottom sheet and drawer uses.
///
/// Each sheet was hand-rolling the same structure with different numbers:
/// `0xFF16161E` with a 28px top radius in one, `0xFF0F121C` with 24 in another,
/// drag handles 44x4.5 and 40x4. That inconsistency is most of why the app reads
/// as several apps stitched together — and [ZplayRadius.sheetTop] already existed
/// for exactly this role and was used by nothing.
///
/// The order is: drag handle, optional context header, hairline, body. The
/// header states what you are acting on before the list does, which a bare list
/// of source names never did.
class ZplaySheet extends StatelessWidget {
  final String? title;
  final String? subtitle;

  /// Shown at the end of the header row — a spinner, a count, a close button.
  final Widget? status;

  /// Shown before the title. For a sheet whose subject has a mark, e.g. a repo
  /// icon.
  final Widget? leading;

  /// Sheet body. Make it scrollable if it can exceed [maxHeightFactor].
  final Widget child;

  /// Fraction of the screen height the sheet may occupy. The sheet is only as
  /// tall as its content beneath this ceiling.
  final double maxHeightFactor;

  /// Sets a *definite* height as a fraction of the screen, for sheets that fill
  /// their frame and scroll their body with an [Expanded]. Mutually exclusive
  /// with [maxHeightFactor] in effect: a definite height wins.
  final double? heightFactor;

  const ZplaySheet({
    super.key,
    this.title,
    this.subtitle,
    this.status,
    this.leading,
    required this.child,
    this.maxHeightFactor = 0.88,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: heightFactor == null ? null : screenHeight * heightFactor!,
      constraints: BoxConstraints(maxHeight: screenHeight * maxHeightFactor),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: ZplayRadius.sheetTop,
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 32,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DragHandle(),
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZplaySpacing.s20,
                0,
                ZplaySpacing.s20,
                ZplaySpacing.s12,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: ZplaySpacing.s12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.title.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.bodySmall.toStyle(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (status != null) status!,
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          ],
          child,
        ],
      ),
    );
  }
}

/// The grab affordance. One size everywhere; it was two.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(
        top: ZplaySpacing.s12,
        bottom: ZplaySpacing.s8,
      ),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// One row in a sheet.
///
/// Selection is an inset accent bar plus a tick rather than a full-width fill. A
/// filled row reads as "the action", which is wrong where the row is one choice
/// among several; and on a remote, fill and focus then look identical. Focus is
/// the app's single ring, and the row is a comfortable target.
class ZplaySheetItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  const ZplaySheetItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
  });

  /// Minimum row height. Matches the comfortable target, and gives the two-line
  /// row the same rhythm as the one-line row.
  static const double minHeight = 56;

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);
    const radius = ZplayRadius.smAll;

    return FocusableCard(
      onTap: onTap,
      enabled: onTap != null,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: radius,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          constraints: const BoxConstraints(minHeight: minHeight),
          margin: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s8,
            vertical: ZplaySpacing.s2,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: state.highlighted && !selected
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              // Inset accent bar marks the current choice without filling the
              // row. Width is constant so the text does not shift when it
              // appears.
              Container(
                width: 3,
                height: selected ? 24 : 0,
                margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (leading != null) ...[
                leading!,
                const SizedBox(width: ZplaySpacing.s12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.subtitle.toStyle(
                        color: selected ? tokens.accent : tokens.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: ZplaySpacing.s2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.caption.toStyle(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (selected)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s12,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
