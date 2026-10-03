import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../services/theme/design_tokens.dart';
import '../common/card_badges.dart';
import '../common/poster_skeleton.dart';
import '../common/focusable_card.dart';
import '../../services/storage/app_image_cache.dart';

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

    return FocusableCard(
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
                    radius: ZplayRadius.mdAll,
                    child: _AnimePosterFrame(
                      anime: anime,
                      hovered: state.hovered,
                      focused: state.focused,
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
    );
  }
}

class _AnimePosterFrame extends StatelessWidget {
  final AnimeMedia anime;

  /// Pointer-only: the accent bloom answers a mouse, never focus.
  final bool hovered;

  /// Drives the type badge, and nothing else.
  final bool focused;

  const _AnimePosterFrame({
    required this.anime,
    required this.hovered,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final posterUrl = anime.coverUrl;
    final hasPoster = posterUrl.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.mdAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: hovered ? 0.60 : 0.34),
            blurRadius: hovered ? 32 : 20,
            offset: Offset(0, hovered ? 18 : 10),
          ),
          // The accent bloom is a pointer affordance only: on focus the ring is
          // the single mark.
          if (hovered)
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.28),
              blurRadius: 34,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: ZplayRadius.mdAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tokens.surface),

            // Poster Image (decode bounded to ~3x display width)
            if (hasPoster)
              LayoutBuilder(
                builder: (context, constraints) {
                  final posterWidth = constraints.maxWidth;
                  final cacheWidth = posterWidth.isFinite && posterWidth > 0
                      ? (posterWidth * 3).round().clamp(96, 1280).toInt()
                      : 615;
                  return CachedNetworkImage(
                    imageUrl: posterUrl,
                    cacheManager: AppImageCache.manager,
                    memCacheWidth: cacheWidth,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    placeholder: (context, url) => const PosterSkeleton(),
                    errorWidget: (context, url, error) => const MissingPoster());
                },
              )
            else
              const MissingPoster(),

            // Vignette Gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      tokens.bg.withValues(alpha: 0.20),
                    ],
                  ),
                ),
              ),
            ),

            // Type badge (top-left). Revealed on focus, and only when the title
            // is a series - an anime *film* is a film and carries no badge.
            if (focused && _isSeriesFormat(anime.format))
              const Positioned(
                top: ZplaySpacing.s8,
                left: ZplaySpacing.s8,
                child: CardTypeBadge(label: 'SERIES'),
              ),

            // Rating badge (top-right), present in every state.
            if (anime.averageScore > 0)
              Positioned(
                top: ZplaySpacing.s8,
                right: ZplaySpacing.s8,
                child: CardRatingBadge(rating: anime.formattedScore),
              ),

            // Bottom Overlay with Episode Count
            if (anime.totalEpisodes > 0)
              Positioned(
                bottom: ZplaySpacing.s8,
                left: ZplaySpacing.s8,
                child: Container(
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
                ),
              ),

            // Hover Play Glow Icon
            if (hovered)
              Positioned(
                bottom: ZplaySpacing.s8,
                right: ZplaySpacing.s8,
                child: Container(
                  padding: const EdgeInsets.all(ZplaySpacing.s8),
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: tokens.textPrimary,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
