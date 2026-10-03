import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// The band's metadata line: `Action · Adventure · 2026 · 1h 47m`, read left to
/// right as one sentence.
///
/// Home's hero grew this treatment first, as its own private `_HeroMetaLine`,
/// and the anime, audiobook and music spotlights each reimplemented it by hand
/// before this existed. That is three hand-rolled separators that could drift
/// apart, so the version the other bands use is here. Home still draws its own
/// instance because it also has a certification term and a genre cap the other
/// bands have no field for.
///
/// **One string, not a row of widgets.** The terms and their `·` separators are
/// joined into a single `Text`, so the spacing either side of every interpunct is
/// a property of the font and `Action · Adventure` and `2026 · 1h 47m` carry the
/// same rhythm. A `Row` of separate terms can only be spaced by eye, and a `Wrap`
/// of them would put a second line into a column whose height is the
/// load-bearing part of a hero band.
class HeroMetaLine extends StatelessWidget {
  /// The facts, in the order they should read.
  ///
  /// Already filtered and capped by the caller: each surface knows how many of
  /// its own fields belong on the line and which of them are missing. Empty and
  /// whitespace-only terms are dropped here as well, because catalogs produce
  /// blanks constantly and a line joined from them would show two interpuncts
  /// with nothing between them.
  final List<String> terms;

  /// The score, drawn as a badge in front of the line rather than as a term in
  /// it. `8.6` sitting between two interpuncts reads as a year, and the badge is
  /// what tells it apart.
  final String? leadingRating;

  const HeroMetaLine({super.key, required this.terms, this.leadingRating});

  /// The interpunct and the two spaces either side of it, as one string.
  ///
  /// The reference's separators are tight; the spaces are what keep the line
  /// readable as words rather than as a run of glyphs.
  static const String separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final line = terms
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .join(separator);

    final rating = leadingRating?.trim() ?? '';
    if (line.isEmpty && rating.isEmpty) return const SizedBox.shrink();

    if (rating.isEmpty) return _text(context, line);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RatingBadge(rating),
        if (line.isNotEmpty) ...[
          const SizedBox(width: ZplaySpacing.s8),
          Flexible(child: _text(context, line)),
        ],
      ],
    );
  }

  Widget _text(BuildContext context, String line) {
    final tokens = context.tokens;
    return Text(
      line,
      // One line, always. A hero's content column is bottom-aligned inside a
      // band whose height is fixed, so a metadata line that wrapped would push
      // the title off the top of the band. A long line is truncated instead, and
      // the terms a viewer reads first are the ones at its head.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZplayType.body.toStyle(color: tokens.textEmphasis),
    );
  }
}

/// The score in front of a [HeroMetaLine]: a number with a star, not a word in a
/// sentence.
class _RatingBadge extends StatelessWidget {
  final String rating;

  const _RatingBadge(this.rating);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s8,
        vertical: ZplaySpacing.s4,
      ),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: ZplayOpacity.overlayHover),
        borderRadius: ZplayRadius.smAll,
        border: Border.all(
          color: tokens.warning.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: tokens.warning),
          const SizedBox(width: ZplaySpacing.s4),
          Text(
            rating,
            style: ZplayType.bodyNumeric
                .copyWith(weight: FontWeight.w700)
                .toStyle(color: tokens.warning),
          ),
        ],
      ),
    );
  }
}