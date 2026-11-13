import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/movie_detail.dart';
import '../../pages/details/details_page.dart';
import '../../services/layout/form_factor.dart';
import '../../services/metadata/art_quality.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/metadata/trailer_resolver.dart';
import '../../services/metadata/metahub_art.dart';
import '../../services/theme/design_tokens.dart';
import 'trailer_preview.dart';
import '../../l10n/l10n.dart';
import '../../services/home/home_page_settings.dart';
import '../../utils/navigation/route_transitions.dart';
import '../common/card_badges.dart';
import '../common/card_focus_expansion.dart';
import '../common/card_poster_frame.dart';
import '../common/focusable_card.dart';
import '../common/poster_skeleton.dart';
import '../../utils/a11y.dart';

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
  if (poster != null && poster.isNotEmpty) return ArtQuality.upgrade(poster);
  return MetahubArt.isUsableId(movie.id)
      ? MetahubArt.posterUrl(movie.id)
      : null;
}

/// The art this card paints, and whether it is real wide art rather than a 2:3
/// poster cropped into a landscape tile.
///
/// Landscape wants a real wide still, because a 2:3 poster cropped to 16:9
/// keeps only a third of the frame's height - which is what a row of landscape
/// tiles looked like before this fell back to metahub. It takes the catalog's
/// own backdrop first, then the keyless metahub still named by the IMDb id, and
/// only then the poster, cropped with `BoxFit.cover` rather than letterboxed: a
/// 176 x 99 tile is small enough that `contain`'s bars would be as much of the
/// card as the picture. Poster shape always uses the poster, as it always has.
///
/// Both answers come out of one call so the choice of image and the fill
/// alignment cannot drift apart.
({String? url, bool wide}) _artworkFor(Movie movie, CardArtwork artwork) {
  final poster = _posterUrlFor(movie);
  if (artwork != CardArtwork.landscape) return (url: poster, wide: false);
  final backdrop = movie.backdrop;
  if (backdrop != null && backdrop.isNotEmpty) {
    return (
      url: ArtQuality.upgrade(backdrop, kind: ArtKind.backdrop),
      wide: true,
    );
  }
  final metahub = _metahubBackdropFor(movie.id);
  return (url: metahub ?? poster, wide: metahub != null);
}

/// The keyless metahub wide still, when [imdbId] is one metahub can name.
///
/// Never a request: [MetahubArt] only builds the URL. An id metahub does not
/// know 404s there, so anything that is not `tt` plus digits is skipped rather
/// than spent.
String? _metahubBackdropFor(String? imdbId) {
  if (imdbId == null || !MetahubArt.isUsableId(imdbId)) return null;
  return MetahubArt.backdropUrl(imdbId);
}

/// `8.0` stays `8.0`; `8` becomes `8`. A raw catalog string may be either.
String _formatRating(String raw) {
  final parsed = double.tryParse(raw);
  if (parsed == null) return raw;
  // Only an integer-shaped input loses its fraction. A source that already
  // wrote a decimal keeps one digit of it - `8.0` is how IMDb states a whole
  // score, and answering `8` dropped a digit the catalog took the trouble to
  // send.
  return raw.contains('.')
      ? parsed.toStringAsFixed(1)
      : parsed.toInt().toString();
}

/// The card's facts line: rating, year and type, in that order, joined with
/// ` · ` - `8.0 · 2024 · Movie`, `2024 · Series`, or just `Movie`.
///
/// A term the catalog did not supply is dropped rather than blanked, which is
/// what keeps the separators honest: joining the list that exists cannot draw
/// a dot next to nothing. The type always exists - a missing type reads as a
/// film - so the line is never empty.
String _metaLine(Movie movie) => [
  if (movie.imdbRating != null && movie.imdbRating!.isNotEmpty)
    _formatRating(movie.imdbRating!),
  if (movie.year != null && movie.year!.isNotEmpty) movie.year!,
  movie.type == 'series'
      ? 'Series'
      : (movie.type == 'anime' ? 'Anime' : 'Movie'),
].join(' · ');

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
    final openDetails =
        onTap ??
        () {
          Navigator.push(
            context,
            FadeThroughRoute(page: DetailsPage(movie: movie)),
          );
        };

    // Everything the shared frame's slots need, resolved once per build: the
    // picture (and whether it is a real wide still), the type badge's label,
    // and the decode scale for this device.
    final art = _artworkFor(movie, artwork);
    final typeLabel = _typeBadgeLabel(movie.type);
    final decodeScale = (MediaQuery.devicePixelRatioOf(context) * 1.5)
        .clamp(3.0, 4.0)
        .toDouble();

    // The one semantics node for the card's own content. It sits inside the
    // focus detector rather than around it: `CardFocusExpansion` paints the
    // popped copy through an `OverlayPortal`, and a `Semantics` wrapper above
    // the whole card changed the constraints that portal was laid out under.
    return FocusableCard(
      onTap: openDetails,
      builder: (_, state) {
        // Lift and zoom answer the *pointer*, not focus. The prototype lifts a
        // hovered card 3 dp and leaves a focused one exactly where it is: on a
        // television a D-pad press must not nudge the card the user is aiming
        // at, and the hover zoom is a setting of its own.
        //
        // Focus is answered by the `CardFocusRing` below - a crisp 3 dp ring
        // and the type badge - and by `CardFocusExpansion`, which paints this
        // card in the app's `Overlay` as one surface that grows to 1.35x and
        // carries the extra info directly under it: the card grows over its
        // neighbours (and the next rail) while its layout box stays exactly
        // where it is, so nothing in the row re-flows. That is the Netflix pop,
        // and the page never feels it -
        // `test/widgets/movie_card_focus_expansion_test.dart` pins the box.
        //
        // This used to say the poster frame drew the ring, and it does not:
        // that widget owns the inside of the frame only, and adding a border
        // there paints a second one, which
        // `test/widgets/card_anatomy_test.dart` catches at exactly one. A
        // comment that names the wrong widget is why that duplicate ring got
        // written.
        final card = AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          scale: state.pressed
              ? 0.97
              : (state.hovered ? HomePageSettings.cardHoverZoom.value : 1.0),
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
                      // Netflix's ten-foot ring is white: it reads on any
                      // artwork and leaves the brand red to the chrome.
                      color: FormFactorService.hasRemoteInput
                          ? Colors.white
                          : null,
                      radius: ZplayRadius.cardAll,
                      // The shared box; everything that is *this* card lives in
                      // the slots - the type and rating badges, the hover
                      // trailer, and the play disc.
                      child: CardPosterFrame(
                        // The catalog's own wide still when it has one. Null
                        // for most rail items, and the frame falls back to the
                        // keyless metahub still - see [_artworkFor].
                        imageUrl: art.url,
                        // Only a cropped poster is nudged, and only a quarter
                        // of the way up. A poster's face sits above its middle
                        // and its bottom third is credits, so centring the crop
                        // throws away the subject; a poster card keeps the
                        // centre it has always been drawn at, and a real
                        // backdrop needs no nudge because it is already the
                        // shape it is drawn at.
                        alignment: artwork == CardArtwork.landscape && !art.wide
                            ? const Alignment(0, -0.25)
                            : Alignment.center,
                        // Decode at the physical draw size, not at a fixed 3x.
                        // A 3x decode was enough at DPR 2 and soft at DPR 3-4,
                        // and the focused card grows 1.35x again; 1.5x of DPR
                        // covers both without decoding a 4K still for a 200 dp
                        // tile.
                        decode: CardPosterDecode(
                          scale: decodeScale,
                          maxCacheDimension: 2048,
                          heightRatio: artwork.ratio,
                          pinToPoppedCopy: true,
                        ),
                        hovered: state.hovered,
                        // Brightness follows either input, so a D-pad user
                        // still sees which poster they are on; movement and the
                        // accent bloom do not.
                        highlighted: state.hovered || state.focused,
                        focused: state.focused,
                        accentBloomAlpha: 0.35,
                        raisedOnFocus: true,
                        // The Netflix-style hover preview. It sits above the
                        // still and below the vignette and badges, and only
                        // mounts after the pointer rests on the card; a D-pad
                        // never starts one. The catalog names the trailer for
                        // most titles; the rest are asked for on demand.
                        overlay: art.url != null && art.url!.isNotEmpty
                            ? TrailerPreviewGate(
                                hovered: state.hovered,
                                trailerKey: movie.trailerKey,
                                resolveTrailerKey: () =>
                                    TrailerResolver.resolve(movie),
                              )
                            : null,
                        // Type badge (top-left). Built only for a series, and
                        // only in the focused frame, so a resting card - and
                        // every film - carries none.
                        topLeft: state.focused && typeLabel != null
                            ? CardTypeBadge(label: typeLabel)
                            : null,
                        // Rating badge (top-right). Present in every state -
                        // the prototype's resting card already shows the score.
                        topRight:
                            movie.imdbRating != null &&
                                movie.imdbRating!.isNotEmpty
                            ? ValueListenableBuilder<bool>(
                                valueListenable: HomePageSettings.showRating,
                                builder: (context, showRating, _) {
                                  if (!showRating) {
                                    return const SizedBox.shrink();
                                  }
                                  return CardRatingBadge(
                                    rating: _formatRating(movie.imdbRating!),
                                  );
                                },
                              )
                            : null,
                        // Pointer only: a remote's centre button already means
                        // "open", and a disc on every focused card is noise.
                        playDisc: CardPlayDisc(visible: state.hovered),
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
                if (artwork.showsTextBlock)
                  // The caption leaves as the card is selected.
                  //
                  // Focused, the card grows and the details panel under it
                  // prints the name, the year and the type at its own size, so a
                  // caption that stayed would print the same line twice, forty
                  // dp apart, inside one surface - and the second copy is the
                  // one that reads as a mistake. It fades rather than cuts
                  // because the pop is already moving: a caption that vanished
                  // on the frame focus arrived would be the one part of the card
                  // that jumped.
                  //
                  // Only the poster draws this block. A landscape thumbnail
                  // carries its name on the art either way, and its caption
                  // lives in the panel alone.
                  Builder(
                    builder: (context) => AnimatedOpacity(
                      opacity: CardFocusExpansion.isPopped(context) ? 0 : 1,
                      duration: ZplayMotion.fast,
                      curve: ZplayMotion.standard,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: ZplaySpacing.s8),
                          Text(
                            movie.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),

                          const SizedBox(height: ZplaySpacing.s4),
                          // The facts are one string in one Text.
                          //
                          // They used to be a Row of loose Texts with a 4 dp dot
                          // Container between each pair, which spent 16 dp of the
                          // caption's width per separator on decoration and had
                          // to keep every dot's condition in step with the term
                          // beside it. A Row of Texts cannot ellipsise, so a
                          // narrow cell or 200% text scale overflowed it; one
                          // joined Text with `maxLines: 1` either fits or ends in
                          // an ellipsis, and the separators can only exist
                          // between terms that were actually supplied.
                          Text(
                            _metaLine(movie),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.label.toStyle(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        return CardFocusExpansion(
          focused: state.focused,
          // The bottom half the card grows. The card's own data is the name,
          // the year, the type and sometimes a rating; everything else here
          // comes off the addon's info response, which is what makes it worth
          // reading on focus rather than carrying in every rail item.
          //
          // This is the only place the card names itself while it is selected:
          // the card's own caption fades out on focus, so the name is printed
          // once, here, at this panel's size rather than twice inside one
          // surface at two sizes.
          expandedExtra: _CardFocusDetails(movie: movie),
          child: Semantics(
            container: true,
            button: true,
            label: A11y.cardLabel(movie.name, year: movie.year),
            hint: l10nOf(context).a11yOpenDetails,
            excludeSemantics: true,
            onTap: openDetails,
            child: card,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// What a focused card grows into.
//
// The card's own data is the name, the year, the type and - sometimes - a
// rating. The synopsis, the genres and the runtime only exist in the addon's
// info response, which is why this is a widget with a state and a read rather
// than a few more lines in the card's `build`.
//
// It is mounted by [CardFocusExpansion]'s overlay copy, which exists only while
// the pop is up - so it reads for the card the user is on and for no other. A
// rail nobody is pointing at costs nothing, and moving along a row takes the
// previous card's extras with it.
//
// It paints no surface of its own: it is the bottom half of the popped card's
// one surface, and a fill or an edge here would be the second background - and
// the second edge - that made the extra read as another row rather than as the
// selected card growing.
//
// **It has two forms, and the page decides which.** A page that declares a
// [PageContentTop] is saying it has chrome above the surface and, on a grid, a
// card tall enough to spend most of what is left - so there the panel drops the
// genres line and halves its synopsis reserve ([_tightSynopsisReserve]).
// Everywhere else it is exactly the panel it has always been. The declaration
// arrives through the expansion's copy, which is where this widget is mounted;
// see [CardFocusExpansion].
// ─────────────────────────────────────────────────────────────────────────────

/// Reserved height for the synopsis, in logical pixels: four lines of
/// [ZplayType.bodySmall] at its own line height.
///
/// Reserved rather than absent while the read is in flight, because this is
/// painted over the rail below the one the card is in: a box that grew when a
/// response landed would move the popped card's own bottom edge in the middle of
/// the user reading it.
const double _synopsisReserve = 68;

/// The synopsis reserve in the panel's tight form: two lines of
/// [ZplayType.bodySmall] instead of four (12 x 1.40 = 16.8 each, so 34).
///
/// A page that declares a [PageContentTop] is saying it has chrome above the
/// surface, and a grid page means it: on the See All grid the first row's cells
/// are 307.58 dp tall under 136 dp of toolbar, pill row and gap, so the card the
/// copy carries can already spend most of the band and the details have to fit
/// under it in what is left. Two lines of synopsis and no genres line is that
/// panel's share of the answer - and it is deliberately not "clipped by the
/// window's bottom edge", which is what the full panel degrades to there.
///
/// The name and the facts line are not negotiable for the same reason: the name
/// is the one title the user reads while the card is selected (the card's own
/// caption is faded out), and the facts line is the year, the type and the
/// runtime.
const double _tightSynopsisReserve = 34;

class _CardFocusDetails extends StatefulWidget {
  const _CardFocusDetails({required this.movie});

  final Movie movie;

  @override
  State<_CardFocusDetails> createState() => _CardFocusDetailsState();
}

class _CardFocusDetailsState extends State<_CardFocusDetails> {
  MovieDetail? _detail;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = widget.movie.id;
    // Only an IMDb id is worth a request. The info resource is keyed by the
    // addon's own id space, and the rails carry ids that no addon can answer for
    // (`bestsimilar_*`, `torrentio:*`, `anilist:*`) - a read for one of those is
    // a guaranteed miss that spends a round trip to find out, and the card
    // already shows everything it can without it.
    if (!id.startsWith('tt')) return;

    final detail = await MetadataService.fetchMeta(
      baseUrl: widget.movie.addonBaseUrl,
      type: widget.movie.type,
      imdbId: id,
    );
    if (!mounted || detail == null) return;
    setState(() => _detail = detail);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final movie = widget.movie;
    final detail = _detail;
    final runtime = detail?.runtime;

    // What the catalog already knew, plus what the read added. A term that is
    // missing is dropped rather than left as a stranded separator - which is
    // what a bare `join` produces whenever a field is absent.
    final facts = <String>[
      if (movie.year != null && movie.year!.isNotEmpty) movie.year!,
      movie.type == 'series'
          ? 'Series'
          : (movie.type == 'anime' ? 'Anime' : 'Movie'),
      if (runtime != null && runtime.isNotEmpty) runtime,
      if (movie.imdbRating != null && movie.imdbRating!.isNotEmpty)
        '★ ${_formatRating(movie.imdbRating!)}',
    ];
    final genres = detail?.genres ?? const <String>[];
    final synopsis = detail?.description?.trim() ?? '';

    // The tight form, for a page that declared chrome above the surface - see
    // the class docs. Read from this widget's own context: the panel is mounted
    // by the expansion's overlay copy, which carries the page's declaration
    // across the portal, and answers 0 where no page made one.
    final tight = PageContentTop.valueOf(context) > 0;

    return Padding(
      padding: const EdgeInsets.all(ZplaySpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The name is printed unconditionally: the card's own caption is gone
          // by the time this panel is up (it fades as the card is selected), so
          // this is the one title the user reads.
          Text(
            movie.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s4),
          // The facts line is secondary text, not accent.
          //
          // It used to be painted in the ember accent, which is the colour this
          // app reserves for the thing the user can act on - a focused control,
          // a selected filter. A line of metadata in it reads as a link, or as
          // a warning, on every card the user lands on; the year and the runtime
          // are neither.
          Text(
            facts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZplayType.label.toStyle(color: tokens.textSecondary),
          ),
          // The genres line is what the tight form gives up first: it is the
          // only row in this panel the user does not need to identify the card
          // (the poster and the name do that), and on a grid it is a whole line
          // of the band the details have to fit in.
          if (genres.isNotEmpty && !tight) ...[
            const SizedBox(height: ZplaySpacing.s4),
            Text(
              genres.take(3).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZplayType.caption.toStyle(color: tokens.textMuted),
            ),
          ],
          const SizedBox(height: ZplaySpacing.s8),
          SizedBox(
            height: tight ? _tightSynopsisReserve : _synopsisReserve,
            child: synopsis.isEmpty
                ? const PosterSkeleton()
                : Text(
                    synopsis,
                    maxLines: tight ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
