import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../services/theme/design_tokens.dart';
import '../../l10n/l10n.dart';
import '../../utils/a11y.dart';
import '../common/card_badges.dart';
import '../common/card_poster_frame.dart';
import '../common/focusable_card.dart';

/// True for AniList's episodic formats. `MOVIE` is a film, so it gets no badge.
bool _isSeriesFormat(String format) {
  switch (format.toUpperCase()) {
    case 'TV':
    case 'TV_SHORT':
    case 'OVA':
    case 'ONA':
    case 'SPECIAL':
      return true;
    default:
      return false;
  }
}

class AnimeCard extends StatelessWidget {
  final AnimeMedia anime;
  final VoidCallback onTap;
  final double? width;

  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // One node for the whole card - title and year spoken once, the caption
    // excluded - and the tap action mirrored because that subtree is excluded
    // with it.
    return Semantics(
      container: true,
      button: true,
      label: A11y.cardLabel(
        anime.displayTitle,
        year: anime.seasonYear > 0 ? '${anime.seasonYear}' : null,
      ),
      hint: l10nOf(context).a11yOpenDetails,
      excludeSemantics: true,
      onTap: onTap,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) => AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          scale: state.pressed ? 0.97 : (state.hovered ? 1.045 : 1.0),
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            transform: Matrix4.translationValues(0, state.hovered ? -3 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster Frame.
                //
                // `AspectRatio` *outside*, not an `Expanded` around it: an
                // `Expanded` hands its child a tight height that an `AspectRatio`
                // cannot win, and the poster absorbs whatever the parent offered.
                // Same defect and same fix as `MovieCard` - see the arithmetic
                // there.
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 1 / 1.48,
                    child: CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.cardAll,
                      child: CardPosterFrame(
                        imageUrl: anime.coverUrl,
                        // The anime card answers the pointer only: on a
                        // television the ring over the poster is the one mark,
                        // so the shadow never brightens on focus.
                        hovered: state.hovered,
                        highlighted: state.hovered,
                        focused: state.focused,
                        // This frame never drew the highlight gradient; its
                        // badges and the episode chip are the overlays it
                        // carries.
                        showHighlight: false,
                        accentBloomAlpha: 0.28,
                        // Type badge (top-left). Revealed on focus, and only
                        // when the title is a series - an anime *film* is a film
                        // and carries no badge.
                        topLeft: state.focused && _isSeriesFormat(anime.format)
                            ? const CardTypeBadge(label: 'SERIES')
                            : null,
                        // Rating badge (top-right), present in every state.
                        topRight: anime.averageScore > 0
                            ? CardRatingBadge(rating: anime.formattedScore)
                            : null,
                        // Episode count, bottom-left, in every state.
                        bottomLeft: anime.totalEpisodes > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s8,
                                  vertical: ZplaySpacing.s4,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.bg.withValues(alpha: 0.72),
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                                child: Text(
                                  '${anime.totalEpisodes} EPS',
                                  style: ZplayType.overline.toStyle(
                                    color: tokens.textEmphasis,
                                  ),
                                ),
                              )
                            : null,
                        playDisc: state.hovered ? const CardPlayChip() : null,
                      ),
                    ),
                  ),
                ),

                // Title
                const SizedBox(height: ZplaySpacing.s8),
                Text(
                  anime.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),

                // Year / Format / Genre
                const SizedBox(height: ZplaySpacing.s4),
                Row(
                  children: [
                    if (anime.seasonYear > 0) ...[
                      Text(
                        '${anime.seasonYear}',
                        style: ZplayType.label.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s8,
                        ),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: tokens.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        anime.genres.isNotEmpty
                            ? anime.genres.first
                            : anime.formattedFormat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZplayType.label.toStyle(color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
