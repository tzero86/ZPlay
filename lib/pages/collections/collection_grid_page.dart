import 'package:flutter/material.dart';

import '../../services/collections/collections_service.dart';
import '../../services/collections/curated_collection.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/movie/movie_card.dart';

/// Every film in one curated collection, as a poster grid.
///
/// The cards are plain [MovieCard]s, and each one already carries its own tap
/// handler that pushes the details page, so this screen adds only the header and
/// the grid geometry. The list is handed over in memory: no catalog is fetched
/// for it and the collection's own id is never used as a catalog id.
class CollectionGridPage extends StatelessWidget {
  final CuratedCollection collection;

  const CollectionGridPage({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final movies = CollectionsService.moviesFor(collection);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sizing = MovieCardSizing.fromWidth(screenWidth);
    final columns = ((screenWidth - sizing.sidePadding * 2 + sizing.spacing) /
            (sizing.cardWidth + sizing.spacing))
        .floor()
        .clamp(2, 10);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(collection: collection),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  sizing.sidePadding,
                  ZplaySpacing.s16,
                  sizing.sidePadding,
                  ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom,
                ),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  // `mainAxisExtent`, not `childAspectRatio`.
                  //
                  // The ratio form is a width/height *proportion*, so it only
                  // describes the card correctly at exactly `sizing.cardWidth`.
                  // This grid's cells are `columns`-driven and come out wider
                  // than that - 220 dp against a nominal 176 on a television -
                  // so every card rendered 25% too tall: 408 dp instead of
                  // 326.5. An extent fixes the height in dp and leaves the width
                  // to the layout, which is what `manga_page.dart` already does.
                  mainAxisExtent: sizing.totalHeight,
                  crossAxisSpacing: sizing.spacing,
                  mainAxisSpacing: sizing.spacing,
                ),
                itemCount: movies.length,
                itemBuilder: (context, index) => MovieCard(movie: movies[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CuratedCollection collection;

  const _Header({required this.collection});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s8,
        ZplaySpacing.s8,
        ZplaySpacing.s20,
        ZplaySpacing.s8,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary),
          ),
          const SizedBox(width: ZplaySpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                ),
                if (collection.subtitle.isNotEmpty) ...[
                  const SizedBox(height: ZplaySpacing.s4),
                  Text(
                    collection.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
