import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/manga/manga.dart';
import '../../pages/manga/manga_details_page.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/manga/manga_settings.dart';
import '../../utils/navigation/route_transitions.dart';
import '../common/poster_skeleton.dart';
import '../common/focusable_card.dart';
import '../../services/storage/app_image_cache.dart';

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

  factory MangaCardSizing.fromWidth(double screenWidth, {MangaCardDensity density = MangaCardDensity.standard}) {
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

  const MangaCard({
    super.key,
    required this.manga,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final showYear = MangaSettings.showMangaYear.value;
    final showBadge = MangaSettings.showContentTypeBadge.value;
    final ambientGlow = MangaSettings.ambientCardGlow.value;

    final genreText = manga.tags.isNotEmpty ? manga.tags.first : (manga.type.isNotEmpty ? manga.type : '');
    final metaText = [
      if (showYear && manga.year.isNotEmpty) manga.year,
      if (genreText.isNotEmpty) genreText,
    ].join(' • ');

    return FocusableCard(
      onTap: onTap ??
          () {
            Navigator.push(
              context,
              LiquidRevealRoute(
                page: MangaDetailsPage(manga: manga),
                tapPosition: null,
              ),
            );
          },
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
                  radius: ZplayRadius.mdAll,
                  child: _PosterFrame(
                    posterUrl: manga.coverNormal.isNotEmpty ? manga.coverNormal : manga.coverSmall,
                    hovered: state.hovered,
                    contentType: manga.type.isNotEmpty ? manga.type : 'MANGA',
                    showBadge: showBadge,
                    ambientGlow: ambientGlow,
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
    );
  }
}

class _PosterFrame extends StatelessWidget {
  final String? posterUrl;
  final bool hovered;
  final String contentType;
  final bool showBadge;
  final bool ambientGlow;

  const _PosterFrame({
    required this.posterUrl,
    required this.hovered,
    required this.contentType,
    required this.showBadge,
    required this.ambientGlow,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;

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
          if (hovered && ambientGlow)
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.30),
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
            // Background fill
            ColoredBox(
              color: tokens.surface,
            ),

            // Poster image (cached, decode bounded to ~3x display width)
            if (hasPoster)
              LayoutBuilder(
                builder: (context, constraints) {
                  final posterWidth = constraints.maxWidth;
                  final cacheWidth = posterWidth.isFinite && posterWidth > 0
                      ? (posterWidth * 3).round().clamp(96, 1280).toInt()
                      : 615;
                  return CachedNetworkImage(
                    imageUrl: posterUrl!,
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

            // Bottom vignette gradient
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

            // Hover highlight gradient
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: hovered ? 1 : 0,
                duration: const Duration(milliseconds: 170),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.textPrimary.withValues(alpha: 0.11),
                        Colors.transparent,
                        tokens.bg.withValues(alpha: 0.40),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Content type badge (top-left)
            if (showBadge)
              Positioned(
                left: ZplaySpacing.s8,
                top: ZplaySpacing.s8,
                child: AnimatedOpacity(
                  opacity: hovered ? 1.0 : 0.0,
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
                          color: Colors.black.withValues(alpha: 0.40),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      contentType.toUpperCase(),
                      style: ZplayType.overline.toStyle(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),

            // Border glow on hover
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  decoration: BoxDecoration(
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.all(
                      color: hovered
                          ? tokens.accent
                          : tokens.borderDefault,
                      width: hovered ? 1.4 : 1,
                    ),
                  ),
                ),
              ),
            ),

            // Play button (bottom-right, hover reveal)
            Positioned(
              right: ZplaySpacing.s8,
              bottom: ZplaySpacing.s8,
              child: AnimatedOpacity(
                opacity: hovered ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: AnimatedScale(
                  scale: hovered ? 1 : 0.82,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.textPrimary.withValues(alpha: 0.95),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.40),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: tokens.bg,
                      size: 29,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MissingPoster extends StatelessWidget {
  const MissingPoster({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      color: tokens.surface,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: tokens.textDisabled,
          size: 40,
        ),
      ),
    );
  }
}
