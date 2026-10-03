import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../services/collections/collections_service.dart';
import '../../services/collections/curated_collection.dart';
import '../../services/layout/form_factor.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/poster_skeleton.dart';
import '../../widgets/common/section_header.dart';
import 'collection_grid_page.dart';

/// Browse vertical listing every curated film pack, grouped by kind.
///
/// Nothing on this screen is fetched in its own right: every collection comes
/// from [CollectionsService], whose cards carry a metahub poster URL, so the hub
/// paints in full without a request. That list is the bundled set until a TMDb
/// key is configured, when the 1990s era tiles show their ranked films.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.bg,
      body: ValueListenableBuilder<List<CuratedCollection>>(
        valueListenable: CollectionsService.collections,
        builder: (context, collections, _) {
          final sagas = [
            for (final collection in collections)
              if (collection.kind == CuratedKind.saga) collection,
          ];
          final eras = [
            for (final collection in collections)
              if (collection.kind == CuratedKind.era) collection,
          ];

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _PageHeader()),
              if (sagas.isNotEmpty)
                SliverToBoxAdapter(
                  child: _Group(label: 'Franchises', collections: sagas),
                ),
              if (eras.isNotEmpty)
                SliverToBoxAdapter(
                  child: _Group(label: 'Memory Lane', collections: eras),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Title and one muted line, in the prototype's small heading scale
/// (`h3 { font-size: 15px; font-weight: 700 }` over an 11 px muted note).
///
/// The accent bar this used to draw is gone: the browse switcher above already
/// marks which vertical is showing, and a decorative accent rule is neither
/// state nor content, which is the only thing the accent is for.
class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s24,
        ZplaySpacing.s20,
        ZplaySpacing.s24,
        ZplaySpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Curated Franchises & Eras',
            style: ZplayType.subtitle
                .copyWith(weight: FontWeight.w700)
                .toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s4),
          Text(
            'Hand-picked film packs, in watch order.',
            style: ZplayType.caption.toStyle(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

/// A labelled band of mosaic cards, laid out on the prototype's three-column
/// grid (`grid-template-columns: repeat(3, 1fr)`, one column on a phone).
///
/// Explicit rows of [Expanded] tiles rather than a [Wrap]: the tile width is a
/// division of the band, and a `Wrap` compares the running sum against the
/// constraint, where a floating-point remainder decides whether the third card
/// fits on the row.
class _Group extends StatelessWidget {
  final String label;
  final List<CuratedCollection> collections;

  const _Group({required this.label, required this.collections});

  @override
  Widget build(BuildContext context) {
    final columns =
        FormFactorService.of(context) == FormFactor.compact ? 1 : 3;

    final rows = <List<CuratedCollection>>[
      for (var i = 0; i < collections.length; i += columns)
        collections.sublist(i, math.min(i + columns, collections.length)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ZplaySpacing.s16),
        SectionHeader(title: label, count: collections.length),
        const SizedBox(height: ZplaySpacing.s12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: ZplaySpacing.s16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var j = 0; j < rows[i].length; j++) ...[
                      if (j > 0) const SizedBox(width: ZplaySpacing.s16),
                      Expanded(child: CollectionTile(collection: rows[i][j])),
                      // A short final row keeps the grid's own column width:
                      // the empty cells are `Expanded` too, so the tiles on it
                      // are the same width as every tile above them.
                      for (var k = rows[i].length; k < columns; k++) ...[
                        const SizedBox(width: ZplaySpacing.s16),
                        const Expanded(child: SizedBox.shrink()),
                      ],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One collection in the hub, in the prototype's mosaic anatomy: a fanned
/// three-poster cluster on a card surface, then the title and the collection's
/// own subtitle.
///
/// The text block is a fixed two-line title over a fixed two-line note. A grid
/// row of cards whose copy differs would otherwise end ragged, and the cards in
/// a row are the same height by design.
class CollectionTile extends StatelessWidget {
  final CuratedCollection collection;

  const CollectionTile({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Both blocks are two lines tall, measured through the ambient text scaler:
    // a fixed height derived from the raw type size would clip the copy for a
    // user running a larger text scale.
    final scaler = MediaQuery.textScalerOf(context);
    final titleBlock =
        scaler.scale(ZplayType.subtitle.size) * ZplayType.subtitle.height * 2;
    final metaBlock =
        scaler.scale(ZplayType.caption.size) * ZplayType.caption.height * 2;

    return FocusableCard(
      onTap: () {
        Navigator.push(
          context,
          LiquidRevealRoute(page: CollectionGridPage(collection: collection)),
        );
      },
      builder: (context, state) => AnimatedScale(
        duration: ZplayMotion.base,
        curve: ZplayMotion.standard,
        scale: state.pressed ? 0.98 : (state.highlighted ? 1.02 : 1.0),
        child: CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.mdAll,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.mdAll,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FannedCluster(
                    movies: CollectionsService.moviesFor(collection),
                    highlighted: state.highlighted,
                  ),
                  const SizedBox(height: ZplaySpacing.s12),
                  SizedBox(
                    height: titleBlock,
                    child: Text(
                      collection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.subtitle
                          .copyWith(weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                    ),
                  ),
                  const SizedBox(height: ZplaySpacing.s4),
                  SizedBox(
                    height: metaBlock,
                    child: Text(
                      collection.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three posters in the prototype's fanned cluster: the centre poster
/// upright and lifted, the two flanking posters rotated out and faded, on the
/// page background.
///
/// Every poster sits in a fixed-size box inside a fixed-height cluster, so the
/// fan - and the wider fan a highlighted card draws - changes paint only. The
/// card's own size is identical focused, hovered, selected or idle, which is
/// what keeps a grid row from reflowing as focus moves through it.
class _FannedCluster extends StatelessWidget {
  final List<Movie> movies;
  final bool highlighted;

  const _FannedCluster({required this.movies, required this.highlighted});

  /// `app.css`: `.mosaic-cluster { height: 140px }`, `.mosaic-poster` 80x120.
  static const double _clusterHeight = 140.0;
  static const double _posterHeight = 120.0;
  static const double _posterAspect = 1.48;

  /// `.mosaic-p1` / `.mosaic-p2 { opacity: 0.75 }`. No opacity token covers
  /// artwork, and the scale's two text steps are not this value.
  static const double _sidePosterOpacity = 0.75;

  /// `.mosaic-p1 { left: 20px }`, clamped so a narrow card still shows the fan.
  static const double _sideInset = ZplaySpacing.s20;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final slots = movies.take(3).toList();
    const posterWidth = _posterHeight / _posterAspect;

    return ClipRRect(
      borderRadius: ZplayRadius.smAll,
      child: SizedBox(
        height: _clusterHeight,
        width: double.infinity,
        child: ColoredBox(
          color: tokens.bg,
          child: slots.isEmpty
              ? const MissingPoster()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final inset = math.min(
                      _sideInset,
                      math.max(
                        0.0,
                        (constraints.maxWidth - posterWidth) / 2 -
                            ZplaySpacing.s8,
                      ),
                    );

                    Widget poster(int index) => SizedBox(
                      width: posterWidth,
                      height: _posterHeight,
                      child: _artwork(slots[index]),
                    );

                    Widget flank(int index, bool leading) {
                      // -8deg to +8deg at rest, -12deg to +12deg and 4 px
                      // further out when the card is highlighted.
                      final turns = (highlighted ? 12 : 8) / 360;
                      return Align(
                        alignment: leading
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: leading ? inset : 0,
                            right: leading ? 0 : inset,
                          ),
                          child: AnimatedSlide(
                            duration: ZplayMotion.base,
                            curve: ZplayMotion.standard,
                            offset: Offset(
                              highlighted ? (leading ? -0.05 : 0.05) : 0.0,
                              0.0,
                            ),
                            child: AnimatedRotation(
                              duration: ZplayMotion.base,
                              curve: ZplayMotion.standard,
                              turns: leading ? -turns : turns,
                              child: Opacity(
                                opacity: _sidePosterOpacity,
                                child: Transform.scale(
                                  scale: 0.9,
                                  child: poster(index),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (slots.length > 1) flank(0, true),
                        if (slots.length > 2) flank(2, false),
                        Transform.scale(
                          scale: 1.05,
                          child: poster(slots.length > 1 ? 1 : 0),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _artwork(Movie movie) {
    final poster = movie.poster;
    if (poster == null || poster.isEmpty) return const MissingPoster();

    return CachedNetworkImage(
      imageUrl: poster,
      cacheManager: AppImageCache.manager,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      placeholder: (context, url) => const SizedBox.expand(),
      errorWidget: (context, url, error) => const MissingPoster(),
    );
  }
}
