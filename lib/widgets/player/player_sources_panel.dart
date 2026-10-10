import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';
import '../../services/stream/stream_service.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/anime_arabic/anime_arabic_extractor.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';
import 'stream_bitrate_badge.dart';
import '../common/focusable_card.dart';

/// Heading for the "scrape found nothing" state.
///
/// [hasEpisodes] is `showBackToEpisodes`: true for a series, where the
/// back-to-episodes control is rendered, false for a title, where it is not.
String playerEmptyStateHeading({required bool hasEpisodes}) =>
    hasEpisodes ? 'No streams found for this episode' : 'No streams found for this title';

/// Guidance for the "scrape found nothing" state.
///
/// Both branches must name only controls that are actually on screen. The
/// episode branch can point at the back-to-episodes button it renders; the
/// title branch cannot, so it points at the exits that do exist instead.
String playerEmptyStateBody({required bool hasEpisodes}) => hasEpisodes
    ? 'Try going back to episodes and choosing another episode or provider.'
    : 'Try another provider for this title, or close this panel and '
        'check your addons in Settings.';

/// Glassmorphic Sources Side Panel for selecting episode stream sources,
/// with targeted scraping, episode caching, and error recovery banners.
class PlayerSourcesPanel extends StatefulWidget {
  final Video episode;
  final MovieDetail? detail;
  final String currentAddonName;
  final String? errorMessage;
  final List<StreamSource>? cachedSources;
  final Function(List<StreamSource> sources) onSourcesLoaded;
  final Function(StreamSource source, Video episode) onPlaySource;
  final VoidCallback onBackToEpisodes;
  /// When false the panel serves a movie: no back-to-episodes button, and the
  /// empty state talks about the title rather than an episode.
  final bool showBackToEpisodes;
  final VoidCallback onClose;

  const PlayerSourcesPanel({
    super.key,
    required this.episode,
    this.detail,
    required this.currentAddonName,
    this.errorMessage,
    this.cachedSources,
    required this.onSourcesLoaded,
    required this.onPlaySource,
    required this.onBackToEpisodes,
    this.showBackToEpisodes = true,
    required this.onClose,
  });

  @override
  State<PlayerSourcesPanel> createState() => _PlayerSourcesPanelState();
}

class _PlayerSourcesPanelState extends State<PlayerSourcesPanel> {
  final List<StreamSource> _sources = [];
  bool _isLoading = false;
  StreamSubscription<StreamSource>? _streamSub;

  @override
  void initState() {
    super.initState();

    if (widget.cachedSources != null && widget.cachedSources!.isNotEmpty) {
      _sources.addAll(widget.cachedSources!);
      _isLoading = false;
    } else {
      _startScraping();
    }
  }

  @override
  void didUpdateWidget(PlayerSourcesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The provider of the source being played no longer drives the fetch — the
    // panel asks every provider — so choosing another source must not restart
    // the scrape and blank the list the user is reading.
    if (oldWidget.episode.id != widget.episode.id ||
        oldWidget.episode.season != widget.episode.season ||
        oldWidget.episode.episode != widget.episode.episode ||
        oldWidget.detail?.id != widget.detail?.id) {
      _startScraping();
    }
  }

  void _startScraping() {
    setState(() {
      _sources.clear();
      _isLoading = true;
    });

    final detail = widget.detail;
    final ep = widget.episode;
    final type = detail?.type ?? 'tv';
    final id = ep.id.isNotEmpty
        ? ep.id
        : '${detail?.id ?? ""}:${ep.season ?? 1}:${ep.episode ?? 1}';
    final title = detail?.name ?? ep.title;
    final year = int.tryParse(detail?.year ?? '');
    final epNum = ep.episode ?? 1;

    final isArabicAnime = id.startsWith('arabic_anime:') ||
        (detail?.id.startsWith('arabic_anime:') ?? false) ||
        widget.currentAddonName == 'ArabicAnime';

    _streamSub?.cancel();

    if (isArabicAnime) {
      String slug = '';
      if (detail?.id.startsWith('arabic_anime:') == true) {
        slug = detail!.id.replaceFirst('arabic_anime:', '');
      } else if (id.startsWith('arabic_anime:')) {
        final parts = id.split(':');
        if (parts.length >= 2) slug = parts[1];
      }

      () async {
        try {
          if (slug.isEmpty && title.isNotEmpty) {
            final searchResults = await AnimeArabicService.instance.search(title);
            if (searchResults.isNotEmpty) {
              slug = searchResults.first.slug;
            }
          }

          if (slug.isNotEmpty) {
            final arabicDetails = await AnimeArabicService.instance.getDetails(slug);
            final targetEp = arabicDetails.episodes.firstWhere(
              (e) => e.number == epNum,
              orElse: () => ArabicEpisode(
                number: epNum,
                title: 'الحلقة $epNum',
                encodedHref: '',
                watchPath: '/e/$slug-$epNum#tok',
              ),
            );

            final hits = await AnimeArabicExtractor.instance.resolveEpisode(targetEp);
            final sources = AnimeArabicExtractor.toSources(
              hits,
              animeTitle: arabicDetails.title.isNotEmpty ? arabicDetails.title : title,
              episodeNumber: epNum,
            );

            if (mounted) {
              setState(() {
                _sources.addAll(sources);
                _isLoading = false;
              });
              widget.onSourcesLoaded(List.from(_sources));
            }
            return;
          }
        } catch (e) {
          debugPrint('[PlayerSourcesPanel] Arabic anime scrape error: $e');
        }

        if (mounted) {
          setState(() => _isLoading = false);
        }
      }();
      return;
    }

    final isAnime = type == 'anime' ||
        id.startsWith('anilist:') ||
        (detail?.id.startsWith('anilist:') ?? false) ||
        widget.currentAddonName == 'MegaPlay' ||
        widget.currentAddonName == 'AniDB' ||
        widget.currentAddonName == 'WatchHentai' ||
        widget.currentAddonName == 'Hentaini';

    if (isAnime) {
      int? anilistId;
      if (detail?.id.startsWith('anilist:') == true) {
        anilistId = int.tryParse(detail!.id.replaceFirst('anilist:', ''));
      } else if (id.startsWith('anilist:')) {
        final parts = id.split(':');
        if (parts.length >= 2) {
          anilistId = int.tryParse(parts[1]);
        }
      }

      _streamSub = AnimeScraperService.instance
          .scrapeStreamsByDetails(
        title: title,
        anilistId: anilistId,
        episodeNumber: epNum,
      )
          .listen(
        (source) {
          if (!mounted) return;
          setState(() {
            final exists = _sources.any((s) =>
                (source.url != null && s.url == source.url) ||
                (s.name == source.name && s.title == source.title));
            if (!exists) {
              _sources.add(source);
            }
          });
        },
        onError: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onDone: () {
          if (mounted) {
            setState(() => _isLoading = false);
            widget.onSourcesLoaded(List.from(_sources));
          }
        },
      );
      return;
    }

    _streamSub = StreamService.fetchStreamsForTargetAddon(
      targetAddonName: widget.currentAddonName,
      type: type,
      id: id,
      title: title,
      year: year,
      season: ep.season,
      episode: ep.episode,
      genres: detail?.genres,
      // The panel's job is to offer alternatives to the current source, so it
      // fans out to every active provider instead of re-scraping only the
      // playing one; the current source stays represented because its own
      // provider is queried too.
      allProviders: true,
    ).listen(
      (source) {
        if (!mounted) return;
        setState(() {
          // Deduplicate by URL / infoHash / title
          final exists = _sources.any((s) =>
              (source.infoHash != null && s.infoHash == source.infoHash) ||
              (source.url != null && s.url == source.url) ||
              (s.name == source.name && s.title == source.title));
          if (!exists) {
            _sources.add(source);
          }
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isLoading = false);
          widget.onSourcesLoaded(List.from(_sources));
        }
      },
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 680;
    final drawerWidth = isCompact ? screenWidth * 0.94 : 440.0;
    final sNum = widget.episode.season ?? 1;
    final eNum = widget.episode.episode ?? 1;

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: drawerWidth,
        height: MediaQuery.sizeOf(context).height,
        child: Container(
          decoration: BoxDecoration(
          color: tokens.surfaceOverlay.withValues(alpha: 0.95),
          border: Border(
            left: BorderSide(color: tokens.borderStrong, width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.bg.withValues(alpha: 0.85),
              offset: const Offset(-8, 0),
              blurRadius: 36,
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header Bar ──
                _buildHeader(sNum, eNum, isCompact),

                // ── Error Notice Banner (if previous stream failed) ──
                if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty)
                  _buildErrorBanner(widget.errorMessage!, isCompact),

                Divider(height: 1, color: tokens.borderDefault),

                // ── Sources List / Loading / Empty State ──
                Expanded(
                  child: _sources.isEmpty && _isLoading
                      ? _buildLoadingState()
                      : (_sources.isEmpty && !_isLoading
                          ? _buildEmptyState()
                          : _buildSourcesList(isCompact)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildHeader(int sNum, int eNum, bool isCompact) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + ZplaySpacing.s12,
        left: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s16,
        right: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s16,
        bottom: ZplaySpacing.s12,
      ),
      color: tokens.bg.withValues(alpha: 0.4),
      child: Row(
        children: [
          // Back to Episodes Button
          if (widget.showBackToEpisodes)
            PlayerIconButton(
              size: 36,
              iconSize: 20,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Back to Episodes',
              backgroundColor: tokens.textPrimary
                  .withValues(alpha: ZplayOpacity.borderDefault),
              onPressed: widget.onBackToEpisodes,
            ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PlayerTheme.accent.withValues(alpha: 0.25),
                        borderRadius: ZplayRadius.xsAll,
                        border: Border.all(color: PlayerTheme.accent.withValues(alpha: 0.50)),
                      ),
                      child: Text(
                        'S$sNum : E$eNum',
                        style: ZplayType.caption
                            .copyWith(weight: FontWeight.w800, letterSpacing: 0.4)
                            .toStyle(color: tokens.accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.episode.title.isNotEmpty
                            ? widget.episode.title
                            : 'Episode $eNum',
                        style: ZplayType.subtitle
                            .copyWith(weight: FontWeight.w700, letterSpacing: -0.2)
                            .toStyle(color: tokens.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'All providers · watching via ${widget.currentAddonName}',
                  style: ZplayType.bodySmall
                      .copyWith(weight: FontWeight.w500)
                      .toStyle(color: tokens.textSecondary),
                ),
              ],
            ),
          ),

          // Close Drawer Button
          PlayerIconButton(
            size: 36,
            iconSize: 18,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            backgroundColor: tokens.textPrimary
                .withValues(alpha: ZplayOpacity.borderDefault),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message, bool isCompact) {
    final tokens = context.tokens;
    return Container(
      margin: EdgeInsets.all(isCompact ? 10 : 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.danger.withValues(alpha: 0.20),
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: tokens.danger.withValues(alpha: 0.60), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tokens.danger.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: tokens.danger, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: ZplayType.bodySmall
                  .copyWith(weight: FontWeight.w600)
                  .toStyle(color: tokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(PlayerTheme.accent),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s16),
          Text(
            'Searching every provider…',
            style: ZplayType.label
                .copyWith(weight: FontWeight.w600)
                .toStyle(color: tokens.textEmphasis),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: tokens.textDisabled, size: 48),
            const SizedBox(height: ZplaySpacing.s12),
            Text(
              playerEmptyStateHeading(hasEpisodes: widget.showBackToEpisodes),
              style: ZplayType.subtitle
                  .copyWith(weight: FontWeight.w700)
                  .toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              playerEmptyStateBody(hasEpisodes: widget.showBackToEpisodes),
              textAlign: TextAlign.center,
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: ZplaySpacing.s16),
            ElevatedButton.icon(
              onPressed: _startScraping,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Rescrape Sources'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PlayerTheme.accent,
                foregroundColor: tokens.onAccent,
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesList(bool isCompact) {
    final tokens = context.tokens;
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s16,
        vertical: 14,
      ),
      itemCount: _sources.length + (_isLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
      itemBuilder: (context, index) {
        if (index == _sources.length && _isLoading) {
          return Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(PlayerTheme.accent),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Scraping additional sources...',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
              ],
            ),
          );
        }

        final source = _sources[index];

        return _buildSourceCard(source, isCompact);
      },
    );
  }

  Widget _buildSourceCard(
    StreamSource source,
    bool isCompact,
  ) {
    final tokens = context.tokens;
    final title = source.title ?? source.name ?? 'Stream Source';
    final isTorrent = source.infoHash != null && source.infoHash!.isNotEmpty;
    final resolution = _extractResolution(title);
    final runtimeMinutes = int.tryParse(widget.detail?.runtime ?? '');

    return FocusableCard(
      onTap: () => widget.onPlaySource(source, widget.episode),
      builder: (context, state) {
        final isHovered = state.highlighted;
        return AnimatedScale(
          scale: isHovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: ZplayMotion.standard,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHovered
                  ? tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover)
                  : tokens.bg.withValues(alpha: 0.12),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: isHovered
                    ? PlayerTheme.accent.withValues(alpha: 0.80)
                    : tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                width: isHovered ? 1.4 : 1.0,
              ),
              boxShadow: [
                if (isHovered)
                  BoxShadow(
                    color: PlayerTheme.accent.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            padding: EdgeInsets.all(isCompact ? 10 : ZplaySpacing.s12),
            child: Row(
              children: [
                // Icon / Type Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isTorrent
                        ? tokens.warning.withValues(alpha: 0.20)
                        : PlayerTheme.accent.withValues(alpha: 0.2),
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Icon(
                    isTorrent ? Icons.cloud_download_rounded : Icons.play_arrow_rounded,
                    color: isTorrent ? tokens.warning : tokens.accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s12),

                // Source Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges Row (Resolution, Type, Provider)
                      Row(
                        children: [
                          if (resolution.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _getResolutionColor(resolution),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                resolution,
                                style: ZplayType.overline
                                    .copyWith(weight: FontWeight.w800, letterSpacing: 0.4)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                            ),
                          ],

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: tokens.textPrimary
                                  .withValues(alpha: ZplayOpacity.borderMedium),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              isTorrent ? 'P2P' : 'HTTP',
                              style: ZplayType.overline
                                  .copyWith(weight: FontWeight.w700)
                                  .toStyle(color: tokens.textEmphasis),
                            ),
                          ),

                          StreamBitrateBadge(
                            source: source,
                            runtimeMinutes: runtimeMinutes,
                            margin: const EdgeInsets.only(right: 6),
                          ),

                          if (source.name != null && source.name!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                source.name!,
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: ZplaySpacing.s4),

                      // Title
                      Text(
                        title,
                        style: ZplayType.bodySmall
                            .copyWith(weight: FontWeight.w600)
                            .toStyle(color: tokens.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: ZplaySpacing.s8),

                if (source.isMagnet && source.magnetUrl != null) ...[
                  FocusableInkWell(
                    borderRadius: ZplayRadius.mdAll,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: source.magnetUrl!));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, color: tokens.success, size: 18),
                              const SizedBox(width: ZplaySpacing.s8),
                              Text(
                                'Magnet link copied to clipboard',
                                style: ZplayType.label
                                    .copyWith(weight: FontWeight.w600)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                            ],
                          ),
                          backgroundColor: tokens.surfaceOverlay,
                          behavior: SnackBarBehavior.floating,
                          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: tokens.textPrimary
                            .withValues(alpha: ZplayOpacity.borderDefault),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.link_rounded,
                        color: tokens.textEmphasis,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Play Button Icon
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isHovered
                        ? PlayerTheme.accent
                        : tokens.textPrimary.withValues(alpha: ZplayOpacity.borderDefault)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: tokens.textPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _extractResolution(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('4k') || lower.contains('2160p') || lower.contains('uhd')) return '4K';
    if (lower.contains('1080p') || lower.contains('fhd')) return '1080P';
    if (lower.contains('720p') || lower.contains('hd')) return '720P';
    if (lower.contains('480p') || lower.contains('sd')) return '480P';
    return '';
  }

  Color _getResolutionColor(String res) {
    final tokens = context.tokens;
    switch (res) {
      case '4K':
        return tokens.accent;
      case '1080P':
        return tokens.success;
      case '720P':
        return tokens.info;
      default:
        return tokens.textPrimary.withValues(alpha: 0.20);
    }
  }
}
