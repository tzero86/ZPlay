import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/stream/stream_model.dart';
import '../../services/anime_arabic/anime_arabic_extractor.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/zplay_sheet.dart';
import '../player/player_screen.dart';
import '../../services/storage/app_image_cache.dart';

class AnimeArabicStreamSheet extends StatefulWidget {
  final ArabicAnimeDetails details;
  final ArabicEpisode episode;
  final bool autoPlay;

  const AnimeArabicStreamSheet({
    super.key,
    required this.details,
    required this.episode,
    this.autoPlay = false,
  });

  @override
  State<AnimeArabicStreamSheet> createState() => _AnimeArabicStreamSheetState();
}

class _AnimeArabicStreamSheetState extends State<AnimeArabicStreamSheet> {
  final AnimeArabicExtractor _extractor = AnimeArabicExtractor.instance;
  final AnimeArabicService _service = AnimeArabicService.instance;

  final List<StreamSource> _allSources = [];
  bool _isScraping = true;
  String? _error;
  String _statusLine = 'Resolving servers…';

  @override
  void initState() {
    super.initState();
    _startScraping();
  }

  void _startScraping() async {
    setState(() {
      _allSources.clear();
      _isScraping = true;
      _error = null;
      _statusLine = 'Cracking Arabic server map…';
    });

    try {
      final hits = await _extractor.resolveEpisode(
        widget.episode,
        onProgress: (phase, detail) {
          if (mounted) {
            setState(() {
              _statusLine = detail;
            });
          }
        },
      );

      if (!mounted) return;

      if (hits.isEmpty) {
        setState(() {
          _isScraping = false;
          _error = 'No playable Arabic streams found for Episode ${widget.episode.number}.';
        });
        return;
      }

      final sources = AnimeArabicExtractor.toSources(
        hits,
        animeTitle: widget.details.title,
        episodeNumber: widget.episode.number,
      );

      setState(() {
        _allSources.addAll(sources);
        _isScraping = false;
      });

      if (widget.autoPlay && _allSources.isNotEmpty) {
        _playSource(_allSources.first);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScraping = false;
          _error = 'Failed to load Arabic streams: $e';
        });
      }
    }
  }

  void _playSource(StreamSource source) {
    _service.recordWatch(
      anime: widget.details.toCard(),
      episodeNumber: widget.episode.number,
      totalEpisodes: widget.details.episodes.isNotEmpty
          ? widget.details.episodes.length
          : widget.episode.number,
    );

    final movieDetail = widget.details.toMovieDetail();
    final video = movieDetail.videos.firstWhere(
      (v) => v.episode == widget.episode.number,
      orElse: () => movieDetail.videos.first,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: source,
          title: '${widget.details.title} - Episode ${widget.episode.number}',
          backdropUrl: widget.details.displayBanner,
          detail: movieDetail,
          episode: video,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    // The shared sheet shell: one drag handle, one surface, one header shape.
    // The hand-rolled container, drag bar, hairline border and black drop
    // shadow this used to draw were the third variant of a sheet in the app.
    return ZplaySheet(
      title: widget.details.title,
      subtitle: _isScraping ? 'جاري فحص السيرفرات...' : null,
      leading: ClipRRect(
        borderRadius: ZplayRadius.smAll,
        child: CachedNetworkImage(
          imageUrl: widget.details.displayCover,
          cacheManager: AppImageCache.manager,
          memCacheWidth: 132,
          width: 44,
          height: 60,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(
            width: 44,
            height: 60,
            color: tokens.surfaceRaised,
            child: Icon(Icons.movie_rounded, color: tokens.textMuted),
          ),
        ),
      ),
      status: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'السيرفرات',
            count: _allSources.isEmpty ? null : _allSources.length,
          ),

          // Sources list.
          if (_isScraping && _allSources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  CircularProgressIndicator(color: tokens.accent),
                  const SizedBox(height: ZplaySpacing.s16),
                  Text(
                    _statusLine,
                    textAlign: TextAlign.center,
                    style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                  ),
                ],
              ),
            )
          else if (_error != null && _allSources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s24),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: tokens.warning,
                    size: 36,
                  ),
                  const SizedBox(height: ZplaySpacing.s12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  PillButton(
                    label: 'إعادة المحاولة',
                    icon: Icons.refresh_rounded,
                    onPressed: _startScraping,
                  ),
                ],
              ),
            )
          else
            // `Flexible` against the sheet's own ceiling: [ZplaySheet] bounds
            // the body it is handed (`maxHeightFactor`), so the
            // shrink-wrapping list inside this takes the space that is left and
            // scrolls once it runs out. Restating that ceiling as the sheet's
            // frame minus a hand-measured height of the chrome above would
            // duplicate the shell's own number, and go stale with it.
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
                itemCount: _allSources.length,
                itemBuilder: (context, idx) => _buildSourceTile(_allSources[idx]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(StreamSource source) {
    final tokens = ZplayTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: 5,
      ),
      child: FocusableCard(
        onTap: () => _playSource(source),
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: ZplaySpacing.s12,
            ),
            decoration: BoxDecoration(
              // A fill and the app's one ring; the row draws no border box of
              // its own and nothing glows.
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.accentSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: tokens.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name ?? 'سيرفر تشغيل',
                        style: ZplayType.body
                            .copyWith(weight: FontWeight.w700)
                            .toStyle(color: tokens.textPrimary),
                      ),
                      const SizedBox(height: ZplaySpacing.s2),
                      Text(
                        source.description ?? 'تشغيل مباشر • جودة عالية',
                        style: ZplayType.caption.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: tokens.textDisabled,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
