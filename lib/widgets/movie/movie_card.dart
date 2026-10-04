import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../pages/details/details_page.dart';
import '../../services/metadata/metahub_art.dart';
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
//
// A second shape lives here too. [CardArtwork.landscape] draws the
// Netflix-style rail thumbnail - 16:9, artwork only, no text block - and
// every number below is read through the shape rather than baked into the
// poster's arithmetic, so the poster path still resolves to exactly these
// constants and nothing that renders today moves by a pixel.
// ─────────────────────────────────────────────────────────────────────────────

/// The shape a card is drawn in.
///
/// Not a size budget - that is [MovieCardSizing], which every shape shares.
/// This is what the card *is*, and it decides three things at once: the
/// artwork's ratio, whether the frame is tall or wide, and whether the name
/// gets a block of layout under it. Keeping all three on one value is what
/// stops a landscape thumbnail from being handed a poster's text block - the
/// height arithmetic reads [showsTextBlock] from the same member that chose
/// the ratio, so the two cannot disagree.
enum CardArtwork {
  /// A 2:3 poster with the name and the year/type line under it. What the app
  /// has always drawn, and what every caller gets that does not ask for
  /// something else.
  poster,

  /// A 16:9 rail thumbnail: artwork only, no text block beneath it.
  landscape;

  /// Artwork height as a multiple of width - over 1 for the poster, under 1
  /// for the thumbnail. [AspectRatio] is handed `1 / ratio`, because that
  /// widget speaks width over height.
  double get ratio => switch (this) {
        CardArtwork.poster => MovieCardSizing.posterRatio,
        CardArtwork.landscape => MovieCardSizing.landscapeRatio,
      };

  /// Whether the name and the metadata line are laid out *beneath* the
  /// artwork, and so are charged to `totalHeight`.
  ///
  /// False for the thumbnail, which is what Netflix's rails do and what keeps
  /// a rail one row deep on a 540 dp television. The trade is deliberate and
  /// is paid in identification: the row's own heading names the category, not
  /// the titles, so a thumbnail is identified by its picture alone until it is
  /// focused - and the type badge is what appears then. Callers that need the
  /// name legible without interaction pass [CardArtwork.poster].
  bool get showsTextBlock => this == CardArtwork.poster;
}

class MovieCardSizing {
  final double cardWidth;

  /// Height of the artwork. Kept under its poster name because every caller
  /// and every test already reads it; it is the *poster's* height in
  /// [CardArtwork.poster] and the *thumbnail's* height in
  /// [CardArtwork.landscape].
  final double posterHeight;
  final double totalHeight;
  final double spacing;
  final double sidePadding;

  /// The shape these numbers describe, so a consumer that has to draw
  /// something to match - the loading skeleton, most of all - reads the shape
  /// rather than guessing it back out of [posterHeight] and [totalHeight].
  final CardArtwork artwork;

  MovieCardSizing({
    required this.cardWidth,
    required this.posterHeight,
    required this.totalHeight,
    required this.spacing,
    required this.sidePadding,
    this.artwork = CardArtwork.poster,
  });

  /// Width, artwork shape and text block for a card on a canvas this size.
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
  /// above it is subtracted - caps the artwork. The width band is kept, because
  /// width is what decides how many cards fit across, and the artwork simply
  /// gets shorter: a wide, short poster is a legitimate shape for a card, and
  /// it is the only way to keep the title on the screen.
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
    CardArtwork artwork = CardArtwork.poster,
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

    // Everything past the width band is a function of the shape. For
    // [CardArtwork.poster] each of these resolves to the constant it used to
    // be - 1.48 natural, 0.82 floor, 47.1 of text - so the default argument
    // reproduces the old arithmetic term for term.
    final ratio = artwork.ratio;
    final floorRatio = switch (artwork) {
      CardArtwork.poster => MovieCardSizing.minPosterRatio,
      CardArtwork.landscape => MovieCardSizing.minLandscapeRatio,
    };
    final textBlock = artwork.showsTextBlock
        ? MovieCardSizing.textBlockHeight
        : ZplaySpacing.s0;

    var artworkHeight = cardWidth * ratio;
    if (availableHeight != null && availableHeight.isFinite) {
      // The title is not negotiable - it is what the card is for - so the
      // artwork takes whatever is left, down to a floor that still reads as
      // its shape. A thumbnail spends none of the budget on a text block, so
      // the whole of [availableHeight] is artwork.
      final maxArtwork = availableHeight - textBlock;
      final floor = cardWidth * floorRatio;
      if (maxArtwork < floor) {
        // Not even the floor fits. Shrink the card itself rather than crop it:
        // a narrow, short card shows its whole title, which is what the user
        // needs to identify it.
        cardWidth = maxArtwork / floorRatio;
        artworkHeight = maxArtwork;
      } else if (maxArtwork < artworkHeight) {
        artworkHeight = maxArtwork;
      }
    }

    return MovieCardSizing(
      cardWidth: cardWidth,
      posterHeight: artworkHeight,
      totalHeight: artworkHeight + textBlock,
      spacing: ZplaySpacing.s16,
      sidePadding: ZplaySpacing.s16,
    );
  }

  /// Poster height as a multiple of width. A 2:3 poster is 1.5; 1.48 is the
  /// ratio the app's artwork has always been drawn at, kept because changing it
  /// would re-crop every poster in the library.
  static const double posterRatio = 1.48;

  /// Landscape height as a multiple of width: 16:9, so 9/16. The shape the
  /// rail thumbnails are drawn at. A fraction rather than the decimal 0.5625,
  /// so what the number *means* survives being read.
  static const double landscapeRatio = 9 / 16;

  /// The shortest a poster may become before the card starts losing width
  /// instead. Below this it stops reading as a poster at all.
  static const double minPosterRatio = 0.82;

  /// The floor for [landscapeRatio], and deliberately not [minPosterRatio].
  /// That floor is 0.82 of height against 0.5625 of width, which is 1.46:1 - a
  /// thumbnail that has inflated into a near-square. 0.28 keeps it landscape;
  /// at a 176 dp card width that is 49 dp of artwork, the shortest this shape
  /// is allowed to become.
  static const double minLandscapeRatio = 0.28;

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

/// The movie's own poster, or metahub's keyless one when the catalog supplied
/// none - and a usable IMDb id to ask for. Anything else stays null so the
/// frame shows [MissingPoster].
String? _posterUrlFor(Movie movie) {
  final poster = movie.poster;
  if (poster != null && poster.isNotEmpty) return poster;
  return MetahubArt.isUsableId(movie.id) ? MetahubArt.posterUrl(movie.id) : null;
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

  /// Which shape to draw. Defaults to [CardArtwork.poster], which is the
  /// whole point: every existing caller omits this and gets the card this
  /// widget has always built, at the same size, with the same layout.
  final CardArtwork artwork;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
    this.artwork = CardArtwork.poster,
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
                // ── Artwork ─────────────────────────────────────────────
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
                //
                // The ratio is read from the shape rather than written here, so
                // a thumbnail asks for 16:9 in the same breath as the poster
                // asks for 1:1.48.
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 1 / artwork.ratio,
                    child: CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.mdAll,
                      child: _PosterFrame(
                        posterUrl: _posterUrlFor(movie),
                        // The catalog's own wide still when it has one. Null
                        // for most rail items, and the frame falls back to the
                        // keyless metahub still - see [_PosterFrame._artworkUrl].
                        backdropUrl: movie.backdrop,
                        imdbId: movie.id,
                        hovered: state.hovered,
                        focused: state.focused,
                        contentType: movie.type,
                        imdbRating: movie.imdbRating,
                        artwork: artwork,
                      ),
                    ),
                  ),
                ),

                // ── Title / year / type ────────────────────────────────
                //
                // Only the poster pays for a text block. A landscape thumbnail
                // carries the name on the art instead - see [CardArtwork] - so
                // it charges `totalHeight` nothing and its rail stays one row
                // deep on a television.
                if (artwork.showsTextBlock) ...[
                  const SizedBox(height: ZplaySpacing.s8),
                  Text(
                    movie.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  ),

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
//
// Named for the poster it has always drawn, and now asked to draw a rail
// thumbnail too. The only shape-specific code in here is which image it
// resolves; the overlays, the badges, the ring and the pointer-only lift
// behave identically in both, because a focus treatment that differed
// between shapes would be worse than useless on a D-pad.
// ─────────────────────────────────────────────────────────────────────────────

class _PosterFrame extends StatelessWidget {
  final String? posterUrl;

  /// Wide artwork for [CardArtwork.landscape], used ahead of [posterUrl] when
  /// the catalog supplied it. Null almost everywhere below the hero: the hero
  /// resolver is what fills it in, and it only asks for six slides.
  final String? backdropUrl;

  /// The IMDb id, which is all [MetahubArt] needs to name a real wide still.
  /// Most catalog items carry no `background` of their own, so this is what
  /// stops a landscape tile from having to crop a 2:3 poster into 16:9.
  final String? imdbId;

  final CardArtwork artwork;

  /// Pointer-only. The lift, the accent bloom and the brightening answer a
  /// mouse; a focused card must sit perfectly still.
  final bool hovered;

  /// Drives the type badge, and nothing else.
  final bool focused;

  final String contentType;
  final String? imdbRating;

  const _PosterFrame({
    required this.posterUrl,
    required this.artwork,
    required this.hovered,
    required this.focused,
    required this.contentType,
    this.backdropUrl,
    this.imdbId,
    this.imdbRating,
  });

  /// The art this frame paints, best available.
  ///
  /// Landscape wants a real wide still, because a 2:3 poster cropped to 16:9
  /// keeps only a third of the frame's height - which is what a row of
  /// landscape tiles looked like before this fell back to metahub. It takes the
  /// catalog's own [backdropUrl] first, then the keyless metahub still named by
  /// [imdbId], and only then the poster, cropped with `BoxFit.cover` rather
  /// than letterboxed: a 176 x 99 tile is small enough that `contain`'s bars
  /// would be as much of the card as the picture. Poster shape always uses the
  /// poster, as it always has.
  String? get _artworkUrl {
    if (artwork != CardArtwork.landscape) return posterUrl;
    if (backdropUrl != null && backdropUrl!.isNotEmpty) return backdropUrl;
    return _metahubBackdrop ?? posterUrl;
  }

  /// The keyless metahub wide still, when [imdbId] is one metahub can name.
  ///
  /// Never a request: [MetahubArt] only builds the URL. An id metahub does not
  /// know 404s there, so anything that is not `tt` plus digits is skipped
  /// rather than spent.
  String? get _metahubBackdrop {
    final id = imdbId;
    if (id == null || !MetahubArt.isUsableId(id)) return null;
    return MetahubArt.backdropUrl(id);
  }

  /// True when this frame is painting real wide art rather than a poster
  /// squeezed into a landscape tile. Mirrors [_artworkUrl]'s decision exactly,
  /// so the choice of image and the fill alignment cannot drift apart.
  bool get _usesBackdrop {
    if (artwork != CardArtwork.landscape) return false;
    if (backdropUrl != null && backdropUrl!.isNotEmpty) return true;
    return _metahubBackdrop != null;
  }

  @override
  Widget build(BuildContext context) {
    final artworkUrl = _artworkUrl;
    final hasArtwork = artworkUrl != null && artworkUrl.isNotEmpty;
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

            // Artwork (cached, decode bounded to ~3x display width)
            if (hasArtwork)
              LayoutBuilder(
                builder: (context, constraints) {
                  final artworkWidth = constraints.maxWidth;
                  final cacheWidth = artworkWidth.isFinite && artworkWidth > 0
                      ? (artworkWidth * 3).round().clamp(96, 1280).toInt()
                      : 615;
                  return CachedNetworkImage(
                    imageUrl: artworkUrl,
                    cacheManager: AppImageCache.manager,
                    memCacheWidth: cacheWidth,
                    // `cover` is the crop described on [_artworkUrl]: the
                    // poster fills the 16:9 tile instead of sitting inside it
                    // with bars down either side.
                    fit: BoxFit.cover,
                    // Only a *cropped poster* is nudged, and only a quarter of
                    // the way up. A poster's face sits above its middle and
                    // its bottom third is credits, so centring the crop throws
                    // away the subject; a poster card keeps the centre it has
                    // always been drawn at, and a real backdrop needs no nudge
                    // because it is already the shape it is drawn at.
                    alignment: artwork == CardArtwork.landscape &&
                            !_usesBackdrop
                        ? const Alignment(0, -0.25)
                        : Alignment.center,
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
