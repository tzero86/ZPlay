import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/theme/design_tokens.dart';

/// Full-screen error view with retry button.
/// [title] names what failed. The view is shared by surfaces that fail over
/// different nouns, so the headline cannot be hardcoded: catalog callers keep
/// the movie wording by default while search passes its own subject.
class ErrorView extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;

  /// What failed, in the caller's own words. Null uses the bundle's generic
  /// "could not load" line, so catalog callers keep the movie wording without
  /// this widget hardcoding a sentence it cannot translate.
  final String? title;

  /// Optional second action, drawn beside the retry button.
  ///
  /// A failure surface is exactly where a user needs to hand us the state that
  /// produced the failure, so the caller that knows what to do with a report
  /// passes it here. Both members are paired: a label with no callback (or the
  /// reverse) draws nothing, so existing callers are unchanged.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = l10nOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: tokens.warning),
            const SizedBox(height: ZplaySpacing.s16),
            Text(
              title ?? l10n.errorLoadFailed,
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s8),
            Text(
              error ?? l10n.errorUnknown,
              textAlign: TextAlign.center,
              style: ZplayType.body.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: ZplaySpacing.s20),
            Wrap(
              spacing: ZplaySpacing.s12,
              runSpacing: ZplaySpacing.s8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.actionTryAgain),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.onAccent,
                  ),
                ),
                if (secondaryActionLabel != null && onSecondaryAction != null)
                  OutlinedButton.icon(
                    onPressed: onSecondaryAction,
                    icon: const Icon(Icons.copy_all_rounded),
                    label: Text(secondaryActionLabel!),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.textPrimary,
                      side: BorderSide(color: tokens.borderStrong),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
