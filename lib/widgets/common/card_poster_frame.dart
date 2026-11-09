import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';
import 'card_focus_expansion.dart';
import 'poster_skeleton.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Card Poster Frame — the image container every content card draws.
//
// `MovieCard`, `AnimeCard` and `MangaCard` had each grown their own copy of
// this box: the same drop shadow, the same accent bloom on hover, the same
// corner radius and clip, the same bottom vignette, the same decode arithmetic.
// What genuinely differs between the three is what sits *on* the artwork - a
// movie's rating, an anime's episode count, a manga's content-type pill - and
// how each card reads hover versus focus. Those are slots here; the box itself
// is written once.
//
// Focus treatment is deliberately not a parameter. A focus mark that differed
// between cards would be worse than useless on a D-pad: the user has to
// recognise "this is the selected one" on every screen, and the `CardFocusRing`
// drawn over this frame is that mark.
// ─────────────────────────────────────────────────────────────────────────────

/// How [CardPosterFrame] sizes its decode for the box the artwork is painted in.
///
/// The three frames this replaced each ran the same shape of arithmetic and
/// clamped it differently, so the numbers are carried per caller rather than
/// averaged: a poster is decoded at three times the width it is drawn at, and a
/// card that can be popped to 1.35x - the movie card - decodes wider so the
/// popped copy is not re-decoded as it grows.
@immutable
class CardPosterDecode {
  /// Decode width as a multiple of the drawn width.
  final double scale;

  /// Ceiling for both decode dimensions, in physical pixels.
  ///
  /// The movie card asks for a bigger box than the others because its popped
  /// copy is laid out at 1.35x the resting size and pinned to the width it
  /// settles at; a poster decoded at the resting width would go soft the moment
  /// the card grew.
  final int maxCacheDimension;

  /// Decode width used when the frame is laid out with no finite width.
  final int fallbackWidth;

  /// Artwork height as a multiple of its width: 1.48 for a poster, or the
  /// shape's own ratio where the caller draws something else.
  final double heightRatio;

  /// Pin the decode width from [PoppedCopyDecode] when the frame is laid out
  /// inside a popped card copy.
  ///
  /// The copy's card is laid out at a width its own animation is still growing,
  /// so a decode keyed to the layout width would ask for a new one on every
  /// frame of the animation - and every one of those is a fresh decode of the
  /// poster rather than a cache hit. This carries the width the copy *settles*
  /// at, so the image is decoded once, for the size it is finally painted at,
  /// and the frames in between only ever scale it down.
  final bool pinToPoppedCopy;

  const CardPosterDecode({
    this.scale = 3.0,
    this.maxCacheDimension = 1280,
    this.fallbackWidth = 615,
    this.heightRatio = 1.48,
    this.pinToPoppedCopy = false,
  });
}

/// The artwork box of a card: shadow, image, vignette and the overlays that sit
/// on the picture.
///
/// It fills whatever box its caller gives it - the movie and anime cards wrap
/// it in an `AspectRatio`, the manga card in an `Expanded` - so the shape of
/// the tile stays each card's own decision and nothing here assumes one.
///
/// Renders nothing itself beyond that box. A poster with no URL, and an image
/// whose load fails, both land on [MissingPoster] from
/// `widgets/common/poster_skeleton.dart` - the one fallback in the app - so a
/// broken poster reads the same everywhere rather than differently per card.
class CardPosterFrame extends StatelessWidget {
  /// The artwork to draw. Null or empty means "no picture", and the frame
  /// paints [MissingPoster] inside the clipped box instead.
  ///
  /// The caller decides *which* picture - the movie card, for instance, prefers
  /// a real wide still over a poster cropped to 16:9 - because that is library
  /// knowledge, not frame geometry.
  final String? imageUrl;

  /// Pointer state. Drives the accent bloom and nothing else: the bloom is a
  /// pointer affordance, and a focused card has the ring as its one mark.
  final bool hovered;

  /// Brightness state: lifts the drop shadow and fades in the highlight
  /// gradient.
  ///
  /// Separate from [hovered] because the cards answer it differently - the
  /// movie card follows either input, so a D-pad user still sees which poster
  /// they are on, while the anime and manga cards answer the pointer only and
  /// leave focus to the ring.
  final bool highlighted;

  /// Focus state. Only ever raises the card (see [raisedOnFocus]); it moves
  /// nothing.
  final bool focused;

  /// Artwork alignment inside its box, for a picture cropped to a shape it was
  /// not drawn at.
  final Alignment alignment;

  /// Decode sizing for this card's shape.
  final CardPosterDecode decode;

  /// Alpha of the accent bloom painted under a hovered frame, or null for no
  /// bloom at all.
  ///
  /// A number rather than a palette token because the cards measured theirs
  /// separately; the manga card additionally gates it on its ambient-glow
  /// setting and passes null when that is off.
  final double? accentBloomAlpha;

  /// Whether a focused frame paints the second, wider drop that reads as the
  /// card being *raised* rather than merely enlarged.
  ///
  /// A focused card is lifted off the rail by a painted copy - it never moves -
  /// so the extra shadow is what makes the copy read as above the row. Only the
  /// card that pops asks for it.
  final bool raisedOnFocus;

  /// Whether to paint the hover/focus highlight gradient. False for a card
  /// whose own overlays already carry the lift.
  final bool showHighlight;

  /// Painted full-bleed directly over the artwork and under the vignette - the
  /// movie card's hover trailer preview. Nothing else in the frame touches it,
  /// so a card without one pays nothing.
  final Widget? overlay;

  /// Overlays pinned to the frame's corners, inset by [ZplaySpacing.s8]. Each
  /// is a `Positioned`, so revealing one cannot move the artwork.
  final Widget? topLeft;
  final Widget? topRight;
  final Widget? bottomLeft;

  /// Painted full-bleed and pointer-transparent, above the badges and below the
  /// play affordance: the manga card's hover border.
  final Widget? border;

  /// The play affordance, bottom-right. See [CardPlayDisc] and [CardPlayChip]
  /// for the two the cards draw.
  final Widget? playDisc;

  const CardPosterFrame({
    super.key,
    required this.imageUrl,
    required this.hovered,
    required this.highlighted,
    required this.focused,
    this.alignment = Alignment.center,
    this.decode = const CardPosterDecode(),
    this.accentBloomAlpha,
    this.raisedOnFocus = false,
    this.showHighlight = true,
    this.overlay,
    this.topLeft,
    this.topRight,
    this.bottomLeft,
    this.border,
    this.playDisc,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasArtwork = imageUrl != null && imageUrl!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.cardAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: highlighted ? 0.60 : 0.34),
            blurRadius: highlighted ? 32 : 20,
            offset: Offset(0, highlighted ? 18 : 10),
          ),
          // The card is raised by a painted copy, never by moving this box, so
          // the second drop is what carries the height. Focus only - the hover
          // bloom below stays a pointer affordance, and these shadows follow the
          // existing black-drop convention rather than a palette colour.
          if (focused && raisedOnFocus)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 48,
              offset: const Offset(0, 26),
            ),
          // The accent bloom is a pointer affordance only. On focus the ring is
          // the single mark; an accent shadow under a crisp 2 dp border reads as
          // a second, softer edge around it.
          if (hovered && accentBloomAlpha != null)
            BoxShadow(
              color: tokens.accent.withValues(alpha: accentBloomAlpha!),
              blurRadius: 34,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: ZplayRadius.cardAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background fill, so a transparent or still-loading image sits on
            // the card's own surface colour rather than on whatever is behind.
            ColoredBox(color: tokens.surface),

            if (hasArtwork)
              LayoutBuilder(
                builder: (context, constraints) {
                  final artworkWidth = constraints.maxWidth;
                  // A popped copy pins the width it settles at, so growing the
                  // card frame by frame does not decode the poster again on
                  // every frame of the animation (see [PoppedCopyDecode]).
                  // Everywhere else the box the layout handed the image is the
                  // right answer.
                  final cacheWidth =
                      (decode.pinToPoppedCopy
                          ? PoppedCopyDecode.maybeOf(context)
                          : null) ??
                      (artworkWidth.isFinite && artworkWidth > 0
                          ? (artworkWidth * decode.scale)
                                .round()
                                .clamp(96, decode.maxCacheDimension)
                                .toInt()
                          : decode.fallbackWidth);
                  final cacheHeight = (cacheWidth * decode.heightRatio)
                      .round()
                      .clamp(96, decode.maxCacheDimension)
                      .toInt();
                  return CachedNetworkImage(
                    imageUrl: imageUrl!,
                    cacheManager: AppImageCache.manager,
                    memCacheWidth: cacheWidth,
                    memCacheHeight: cacheHeight,
                    // `cover` in every caller: a picture cropped to the shape
                    // its card is drawn at, never letterboxed inside it - a
                    // 176 x 99 tile is small enough that `contain`'s bars would
                    // be as much of the card as the picture.
                    fit: BoxFit.cover,
                    alignment: alignment,
                    filterQuality: FilterQuality.medium,
                    placeholder: (context, url) => const PosterSkeleton(),
                    errorWidget: (context, url, error) =>
                        const MissingPoster(),
                  );
                },
              )
            else
              const MissingPoster(),

            if (overlay != null) Positioned.fill(child: overlay!),

            // Bottom vignette gradient: the lower third of the artwork fades
            // into the card's own background, which is what lets a badge or a
            // caption sit on the picture without a scrim of its own.
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

            // Highlight gradient
            if (showHighlight)
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

            if (topLeft != null)
              Positioned(
                left: ZplaySpacing.s8,
                top: ZplaySpacing.s8,
                child: topLeft!,
              ),

            if (topRight != null)
              Positioned(
                right: ZplaySpacing.s8,
                top: ZplaySpacing.s8,
                child: topRight!,
              ),

            if (bottomLeft != null)
              Positioned(
                left: ZplaySpacing.s8,
                bottom: ZplaySpacing.s8,
                child: bottomLeft!,
              ),

            if (border != null)
              Positioned.fill(child: IgnorePointer(child: border!)),

            if (playDisc != null)
              Positioned(
                right: ZplaySpacing.s8,
                bottom: ZplaySpacing.s8,
                child: playDisc!,
              ),
          ],
        ),
      ),
    );
  }
}

/// The large play disc: a 39 dp light circle in the poster's bottom-right that
/// fades and scales in while the card is highlighted.
///
/// The movie and manga cards drew this identically - it is the pointer's answer
/// to "what happens if I click", so it belongs to the frame's vocabulary rather
/// than to either card.
class CardPlayDisc extends StatelessWidget {
  /// Whether the disc is shown. Each caller passes the state it treats as
  /// active: the highlight union where focus also counts, hover only where the
  /// ring carries focus by itself.
  final bool visible;

  const CardPlayDisc({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: AnimatedScale(
        scale: visible ? 1 : 0.82,
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
    );
  }
}

/// The small accent play chip.
///
/// Deliberately not [CardPlayDisc]: the anime card's frame was measured at a
/// different size - an accent pill 16 dp icon on an 8 dp pad - and it is mounted
/// only while the card is hovered rather than faded in. Two shapes, because the
/// two cards were reviewed as two shapes; merging them would change what one of
/// them draws.
class CardPlayChip extends StatelessWidget {
  const CardPlayChip({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
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
    );
  }
}