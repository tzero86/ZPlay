import 'package:flutter/material.dart';

import '../../models/manga/manga.dart';
import '../../pages/manga/manga_details_page.dart';
import '../../services/theme/design_tokens.dart';
import '../../l10n/l10n.dart';
import '../../services/manga/manga_settings.dart';
import '../../utils/a11y.dart';
import '../../utils/navigation/route_transitions.dart';
import '../common/card_poster_frame.dart';
import '../common/focusable_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Card sizing — responsive breakpoints that scale with MangaCardDensity.
// ─────────────────────────────────────────────────────────────────────────────

class MangaCardSizing {
  final double cardWidth;
  final double posterHeight;
  final double totalHeight;
  final double spacing;
  final double sidePadding;

  MangaCardSizing({
    required this.cardWidth,
    required this.posterHeight,
    required this.totalHeight,
    required this.spacing,
    required this.sidePadding,
  });

  factory MangaCardSizing.fromWidth(
    double screenWidth, {
    MangaCardDensity density = MangaCardDensity.standard,
  }) {
    double baseWidth;

    if (screenWidth < 360) {
      baseWidth = 138;
    } else if (screenWidth < 430) {
      baseWidth = 152;
    } else if (screenWidth < 700) {
      baseWidth = 162;
    } else if (screenWidth < 1000) {
      baseWidth = 176;
    } else if (screenWidth < 1400) {
      baseWidth = 190;
    } else {
      baseWidth = 205;
    }

    // Apply density scaling only when not standard (compact shrinks, cinematic grows)
    if (density == MangaCardDensity.compact) {
      baseWidth *= 0.85;
    } else if (density == MangaCardDensity.spacious) {
      baseWidth *= 1.20;
    }

    final cardWidth = baseWidth;
    final posterHeight = cardWidth * 1.48;
    final totalHeight = posterHeight + 66;

    return MangaCardSizing(
      cardWidth: cardWidth,
      posterHeight: posterHeight,
      totalHeight: totalHeight,
      spacing: ZplaySpacing.s16,
      sidePadding: ZplaySpacing.s16,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manga Card
// ─────────────────────────────────────────────────────────────────────────────

class MangaCard extends StatelessWidget {
  final Manga manga;
  final VoidCallback? onTap;

  const MangaCard({super.key, required this.manga, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final showYear = MangaSettings.showMangaYear.value;
    final showBadge = MangaSettings.showContentTypeBadge.value;
    final ambientGlow = MangaSettings.ambientCardGlow.value;

    final genreText = manga.tags.isNotEmpty
        ? manga.tags.first
        : (manga.type.isNotEmpty ? manga.type : '');
    final metaText = [
      if (showYear && manga.year.isNotEmpty) manga.year,
      if (genreText.isNotEmpty) genreText,
    ].join(' • ');

    // One node for the whole card - title and year spoken once, the caption
    // excluded - and the tap action mirrored because that subtree is excluded
    // with it.
    final openDetails =
        onTap ??
        () {
          Navigator.push(
            context,
            FadeThroughRoute(
              page: MangaDetailsPage(manga: manga),
            ),
          );
        };

    return Semantics(
      container: true,
      button: true,
      label: A11y.cardLabel(manga.title, year: manga.year),
      hint: l10nOf(context).a11yOpenDetails,
      excludeSemantics: true,
      onTap: openDetails,
      child: FocusableCard(
        onTap: openDetails,
        // The lift, the zoom and the poster's own hover treatment answer the
        // pointer, never focus - `MovieCard`/`CardArtwork` is the reference and it
        // does exactly this. On a television the `CardFocusRing` drawn over the
        // poster is the one mark that says where the remote is; a card that also
        // swelled, lifted and lit its own accent border on focus was wearing three
        // indicators for one state.
        builder: (context, state) => AnimatedScale(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          scale: state.pressed ? 0.97 : (state.hovered ? 1.045 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, state.hovered ? -6 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Poster ──────────────────────────────────────────────
                Expanded(
                  child: CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.cardAll,
                    child: CardPosterFrame(
                      imageUrl: manga.coverNormal.isNotEmpty
                          ? manga.coverNormal
                          : manga.coverSmall,
                      hovered: state.hovered,
                      // Pointer only: on a television the ring drawn over the
                      // poster is the one mark that says where the remote is,
                      // and this card never brightened its shadow for focus.
                      highlighted: state.hovered,
                      focused: state.focused,
                      // The ambient glow is the user's setting; without it a
                      // hovered card keeps the plain drop the others have.
                      accentBloomAlpha: state.hovered && ambientGlow
                          ? 0.30
                          : null,
                      // Content type badge (top-left), faded in on hover.
                      topLeft: showBadge
                          ? AnimatedOpacity(
                              opacity: state.hovered ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 170),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s8,
                                  vertical: ZplaySpacing.s4,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accent.withValues(alpha: 0.88),
                                  borderRadius: ZplayRadius.smAll,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.40,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  (manga.type.isNotEmpty
                                          ? manga.type
                                          : 'MANGA')
                                      .toUpperCase(),
                                  style: ZplayType.overline.toStyle(
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            )
                          : null,
                      // Border glow on hover, over the badges and under the
                      // play disc, exactly where this card always drew it.
                      border: AnimatedContainer(
                        duration: const Duration(milliseconds: 170),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.cardAll,
                          border: Border.all(
                            color: state.hovered
                                ? tokens.accent
                                : tokens.borderDefault,
                            width: state.hovered ? 1.4 : 1,
                          ),
                        ),
                      ),
                      playDisc: CardPlayDisc(visible: state.hovered),
                    ),
                  ),
                ),

                // ── Title & Info ─────────────────────────────────────────
                const SizedBox(height: ZplaySpacing.s8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 170),
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  child: Text(
                    manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (metaText.isNotEmpty || showYear) ...[
                  const SizedBox(height: ZplaySpacing.s4),
                  Text(
                    metaText.isNotEmpty ? metaText : 'Unknown Year',
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
        ),
      ),
    );
  }
}


