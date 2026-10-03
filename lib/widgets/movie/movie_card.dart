import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../pages/details/details_page.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/home/home_page_settings.dart';
import '../../utils/navigation/route_transitions.dart';
import '../common/card_badges.dart';
import '../common/focusable_card.dart';
import '../common/poster_skeleton.dart';
import '../../services/storage/app_image_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Card sizing — responsive breakpoints that mimic Stremio poster sizes.
//
//   Mobile  : ~138-162 px wide
//   Tablet  : ~176 px
//   Desktop : ~190-205 px
//
// Aspect ratio 1:1.48  (width × 1.48 = poster height).
// Total card height = poster + the measured text block (47.1 dp).
// ─────────────────────────────────────────────────────────────────────────────

class MovieCardSizing {
  final double cardWidth;
  final double posterHeight;
  final double totalHeight;
  final double spacing;
  final double sidePadding;

  MovieCardSizing({
    required this.cardWidth,
    required this.posterHeight,
    required this.totalHeight,
    required this.spacing,
    required this.sidePadding,
  });

  /// Width, poster shape and text block for a card on a canvas this size.
  ///
  /// **Height is an input, not an afterthought.** The original version was a
  /// function of width alone, which is why nothing on the television fitted: a
  /// card was always 326.5 dp (176 wide, poster 260.5, plus 66 for text), and a
  /// 540 dp canvas with a hero above it has about 200 dp left. The card was
  /// never going to fit, and because it could not be made to fit it was simply
  /// cropped, which is how a title ends up cut in half at the bottom of the
  /// screen.
  ///
  /// So [availableHeight] - the space a rail actually has, once the chrome
  /// above it is subtracted - caps the poster. The width band is kept, because
  /// width is what decides how many cards fit across, and the poster simply
  /// gets shorter: a wide, short poster is a legitimate shape for a card, and it
  /// is the only way to keep the title on the screen.
  ///
  /// The text block is charged its **measured** height, not a rounded guess.
  /// `ZplayType.subtitle` is 15 px at 1.30 line height and `ZplayType.label` is
  /// 13 px at 1.20, so 8 + 19.5 + 4 + 15.6 = 47.1 dp. The old constant was 66,
  /// which over-charged every card on every screen by nearly 19 dp.
  factory MovieCardSizing.fromWidth(
    double screenWidth, {
    /// Vertical space a card may occupy. Null means "as tall as the shape wants",
    /// which is the pointer behaviour and the reason nothing here is a
    /// regression for it.
    double? availableHeight,
  }) {
    double cardWidth;

    if (screenWidth < 360) {
      cardWidth = 138;
    } else if (screenWidth < 430) {
      cardWidth = 152;
    } else if (screenWidth < 700) {
      cardWidth = 162;
    } else if (screenWidth < 1000) {
      cardWidth = 176;
    } else if (screenWidth < 1400) {
      cardWidth = 190;
    } else {
      cardWidth = 205;
    }

    final density = HomePageSettings.cardDensity.value;
    if (density == CardDensity.compact) {
      cardWidth *= 0.85;
    } else if (density == CardDensity.cinematic) {
      cardWidth *= 1.20;
    }

    var posterHeight = cardWidth * MovieCardSizing.posterRatio;
    if (availableHeight != null && availableHeight.isFinite) {
      // The title is not negotiable - it is what the card is for - so the poster
      // takes whatever is left, down to a floor that still reads as a poster.
      final maxPoster = availableHeight - MovieCardSizing.textBlockHeight;
      final floor = cardWidth * MovieCardSizing.minPosterRatio;
      if (maxPoster < floor) {
        // Not even the floor fits. Shrink the card itself rather than crop it:
        // a narrow, short card shows its whole title, which is what the user
        // needs to identify it.
        cardWidth = maxPoster / MovieCardSizing.minPosterRatio;
        posterHeight = maxPoster;
      } else if (maxPoster < posterHeight) {
        posterHeight = maxPoster;
      }
    }

    return MovieCardSizing(
      cardWidth: cardWidth,
      posterHeight: posterHeight,
      totalHeight: posterHeight + MovieCardSizing.textBlockHeight,
      spacing: ZplaySpacing.s16,
      sidePadding: ZplaySpacing.s16,
    );
  }

  /// Poster height as a multiple of width. A 2:3 poster is 1.5; 1.48 is the
  /// ratio the app's artwork has always been drawn at, kept because changing it
  /// would re-crop every poster in the library.
  static const double posterRatio = 1.48;

  /// The shortest a poster may become before the card starts losing width
  /// instead. Below this it stops reading as a poster at all.
  static const double minPosterRatio = 0.82;

  /// Height of the block under the poster: 8 gap + `subtitle` 15 px x 1.30 +
  /// 4 gap + `label` 13 px x 1.20. Measured, not rounded up to a round number.
  static const double textBlockHeight = 47.1;
}

/// The type badge's text for a catalog `type`, or null when the item is a film
/// and must carry no badge at all.
///
/// The prototype reveals a *type* badge on focus; the brief narrows it to
/// serialized content, so a movie - identified by its poster - gets nothing.
String? _typeBadgeLabel(String type) {
  switch (type.toLowerCase()) {
    case 'series':
      return 'SERIES';
    case 'anime':
      return 'ANIME';
    default:
      return null;
  }
}

/// `8.0` stays `8.0`; `8` becomes `8`. A raw catalog string may be either.
String _formatRating(String raw) {
  final parsed = double.tryParse(raw);
  if (parsed == null) return raw;
  return parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toStringAsFixed(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Movie Card
// ─────────────────────────────────────────────────────────────────────────────

class MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap ??
          () {
            Navigator.push(
              context,
              LiquidRevealRoute(
                page: DetailsPage(movie: movie),
                tapPosition: null, // Let it center if tapPosition not easily available
              ),
            );
          },
      builder: (_, state) {
        // Lift and zoom answer the *pointer*, not focus. The prototype lifts a
        // hovered card 3 dp and leaves a focused one exactly where it is: on a
        // television a D-pad press must not nudge the card the user is aiming
        // at. Focus is answered by the `CardFocusRing` below - a crisp 2 dp ring
        // and the type badge, and nothing that moves.
        //
        // This used to say `_PosterFrame` drew the ring, and it does not: that
        // widget owns the inside of the frame only, and adding a border there
        // paints a second one, which `test/widgets/card_anatomy_test.dart`
        // catches at exactly one. A comment that names the wrong widget is why
        // that duplicate ring got written.
        return AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          scale: state.pressed ? 0.97 : (state.hovered ? HomePageSettings.cardHoverZoom.value : 1.0),
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            transform: Matrix4.translationValues(0, state.hovered ? -3 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Poster ──────────────────────────────────────────────
                //
                // `Flexible` + `AspectRatio`, and the order matters.
                //
                // A bare `Expanded` gave the poster whatever height the parent
                // offered: a grid cell 44 dp wider than the card's nominal width
                // produced a poster 25% taller than the artwork is drawn, and the
                // Browse grid looked like four enormous posters.
                //
                // `AspectRatio` on its own is not the fix either. It *asks* for
                // width x 1.48 and overflows when the parent cannot afford that -
                // measured at 109 px. `Flexible` gives the ratio a ceiling it can
                // yield, so the poster is as tall as the artwork wants and as
                // short as the parent insists, and the title below - the thing
                // that identifies the card - is never what gets cut.
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 1 / MovieCardSizing.posterRatio,
                    child: CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.mdAll,
                      child: _PosterFrame(
                        posterUrl: movie.poster,
                        hovered: state.hovered,
                        focused: state.focused,
                        contentType: movie.type,
                        imdbRating: movie.imdbRating,
                      ),
                    ),
                  ),
                ),

                // ── Title ───────────────────────────────────────────────
                const SizedBox(height: ZplaySpacing.s8),
                Text(
                  movie.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),

                // ── Year / type ─────────────────────────────────────────
                const SizedBox(height: ZplaySpacing.s4),
                Row(
                  children: [
                    if (movie.year != null && movie.year!.isNotEmpty)
                      Text(
                        movie.year!,
                        style: ZplayType.label.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                    if (movie.year != null && movie.year!.isNotEmpty)
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
                    Text(
                      movie.type == 'series' ? 'Series' : (movie.type == 'anime' ? 'Anime' : 'Movie'),
                      style: ZplayType.label.toStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Poster Frame — the image container with overlays, shadows, and hover FX.
// ─────────────────────────────────────────────────────────────────────────────

class _PosterFrame extends StatelessWidget {
  final String? posterUrl;

  /// Pointer-only. The lift, the accent bloom and the brightening answer a
  /// mouse; a focused card must sit perfectly still.
  final bool hovered;

  /// Drives the type badge, and nothing else.
  final bool focused;

  final String contentType;
  final String? imdbRating;

  const _PosterFrame({
    required this.posterUrl,
    required this.hovered,
    required this.focused,
    required this.contentType,
    this.imdbRating,
  });

  @override
  Widget build(BuildContext context) {
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    final tokens = context.tokens;
    // Brightness follows either input, so a D-pad user still sees which poster
    // they are on; movement and the accent bloom do not.
    final highlighted = hovered || focused;
    final typeLabel = _typeBadgeLabel(contentType);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.mdAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: highlighted ? 0.60 : 0.34),
            blurRadius: highlighted ? 32 : 20,
            offset: Offset(0, highlighted ? 18 : 10),
          ),
          // The accent bloom is a pointer affordance only. On focus the ring is
          // the single mark; an accent shadow under a crisp 2 dp border reads as
          // a second, softer edge around it.
          if (hovered)
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.35),
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
                opacity: highlighted ? 1 : 0,
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

            // Type badge (top-left). Built only for a series, and only in the
            // focused frame, so a resting card - and every film - carries none.
            // `Positioned`, so revealing it cannot move the poster or the title.
            if (focused && typeLabel != null)
              Positioned(
                left: ZplaySpacing.s8,
                top: ZplaySpacing.s8,
                child: CardTypeBadge(label: typeLabel),
              ),

            // Rating badge (top-right). Present in every state - the prototype's
            // resting card already shows the score.
            if (imdbRating != null && imdbRating!.isNotEmpty)
              ValueListenableBuilder<bool>(
                valueListenable: HomePageSettings.showRating,
                builder: (context, showRating, _) {
                  if (!showRating) return const SizedBox.shrink();
                  return Positioned(
                    right: ZplaySpacing.s8,
                    top: ZplaySpacing.s8,
                    child: CardRatingBadge(rating: _formatRating(imdbRating!)),
                  );
                },
              ),

            // Play button (bottom-right, hover reveal)
            Positioned(
              right: ZplaySpacing.s8,
              bottom: ZplaySpacing.s8,
              child: AnimatedOpacity(
                opacity: highlighted ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: AnimatedScale(
                  scale: highlighted ? 1 : 0.82,
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
