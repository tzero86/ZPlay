import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// Full-screen error view with retry button.
/// [title] names what failed. The view is shared by surfaces that fail over
/// different nouns, so the headline cannot be hardcoded: catalog callers keep
/// the movie wording by default while search passes its own subject.
class ErrorView extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;
  final String title;

  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title = 'Could not load movies',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: tokens.warning,
            ),
            const SizedBox(height: ZplaySpacing.s16),
            Text(
              title,
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s8),
            Text(
              error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: ZplayType.body.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: ZplaySpacing.s20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
