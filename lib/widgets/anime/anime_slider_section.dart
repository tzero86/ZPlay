import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../widgets/common/hover_scroll_rail.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/movie/movie_card.dart';
import 'anime_card.dart';

class AnimeSliderSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<AnimeMedia> animeList;
  final Function(AnimeMedia) onAnimeTap;
  final VoidCallback? onSeeAll;

  const AnimeSliderSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.animeList,
    required this.onAnimeTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (animeList.isEmpty) return const SizedBox.shrink();

    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header matching Home Page exactly
          SectionHeader(
            title: title,
            count: animeList.length,
            subtitle: subtitle,
            onSeeAll: onSeeAll,
          ),
          const SizedBox(height: 12),

          // 10 px of slop in the can-scroll test, the value this rail has
          // always used for its arrows.
          HoverScrollRail(
            height: sizing.totalHeight,
            padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
            spacing: sizing.spacing,
            edgeTolerance: HoverScrollRail.slopEdgeTolerance,
            itemCount: animeList.length,
            itemBuilder: (context, index) {
              final anime = animeList[index];
              return SizedBox(
                width: sizing.cardWidth,
                child: AnimeCard(
                  anime: anime,
                  width: sizing.cardWidth,
                  onTap: () => onAnimeTap(anime),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}