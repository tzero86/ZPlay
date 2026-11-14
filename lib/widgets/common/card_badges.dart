import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// The two poster badges of the prototype's card anatomy.
///
/// `app.css` draws them as absolutely positioned overlays on `.card-poster-wrap`
/// (`.card-badge-type`, `.card-badge-rating`), so they take no part in the
/// poster's own size. In Flutter they are `Positioned` children of a poster
/// `Stack` for exactly the same reason: a badge that claimed vertical space
/// would push the title down and make `MovieCardSizing.totalHeight` a lie, which
/// is the grid overflow that sizing exists to prevent. Overlay them, and the
/// measured 47.1 dp text block stays the only thing under the poster.

/// The type badge: an accent pill in the poster's top-left corner, revealed
/// **only while the card is focused** (brief rule 5: "Type Badge appears ONLY on
/// focus").
///
/// Callers build it only for serialized content, and only in the focused frame,
/// so a resting card carries no badge and a film never carries one. It is
/// `Positioned` by the caller, so appearing cannot move anything.
class CardTypeBadge extends StatelessWidget {
  const CardTypeBadge({super.key, required this.label});

  /// Already uppercase, e.g. `SERIES`, `ANIME`.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: ZplayRadius.xsAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s4,
            vertical: ZplaySpacing.s2,
          ),
          child: Text(
            label,
            style: ZplayType.overline.toStyle(color: tokens.onAccent),
          ),
        ),
      ),
    );
  }
}

/// The rating badge: a star and a score on a dark scrim, poster's top-right.
///
/// Present in every state - the prototype's *resting* card already shows
/// `★ 8.8` - so it is not focus-gated; only the score changes.
class CardRatingBadge extends StatelessWidget {
  const CardRatingBadge({super.key, required this.rating});

  /// Pre-formatted, e.g. `8.6`.
  final String rating;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.bg.withValues(alpha: 0.85),
          borderRadius: ZplayRadius.xsAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s4,
            vertical: ZplaySpacing.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 12, color: tokens.warning),
              const SizedBox(width: ZplaySpacing.s2),
              Text(
                rating,
                style: ZplayType.caption.toStyle(color: tokens.warning),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The status tag: a small red label sitting on the poster's bottom edge -
/// "New season", "New episode", "New release". Read from the catalog's own
/// dates (see `CardFreshness`), so only a genuinely recent title carries one.
class CardStatusTag extends StatelessWidget {
  const CardStatusTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZplaySpacing.s4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s8,
            vertical: 3,
          ),
          child: Text(
            label,
            maxLines: 1,
            style: ZplayType.overline
                .toStyle(color: tokens.onAccent)
                .copyWith(letterSpacing: 0.2),
          ),
        ),
      ),
    );
  }
}

/// The Top 10 rank: a red block in the poster's top-left corner reading
/// `TOP` over the number.
class CardRankBadge extends StatelessWidget {
  const CardRankBadge({super.key, required this.rank});

  /// 1-based.
  final int rank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(ZplaySpacing.s4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TOP',
                style: TextStyle(
                  color: tokens.onAccent,
                  fontSize: 8,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '$rank',
                style: TextStyle(
                  color: tokens.onAccent,
                  fontSize: 15,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
