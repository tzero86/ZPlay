import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/anime/anime_media.dart';
import '../../models/continue_watching/continue_watching_item.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';
import '../../pages/anime/anime_stream_sheet.dart';
import '../../pages/anime_arabic/anime_arabic_details_page.dart';
import '../../pages/player/player_screen.dart';
import '../../pages/player/watch_screen.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/anime_arabic/anime_arabic_extractor.dart';
import '../../services/stream/stream_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../addon/addon_manager.dart';
import '../anime/anime_library_service.dart';
import '../debrid/debrid_rejection_store.dart';
import '../stream/stream_health_checker.dart';
import '../diagnostics/crash_breadcrumbs.dart';
import '../metadata/metadata_service.dart';
import '../trakt/trakt_service.dart';
import '../trakt/trakt_continue_watching_service.dart';
import '../simkl/simkl_service.dart';
import '../simkl/simkl_continue_watching_service.dart';

class ContinueWatchingService {
  static const _storageKey = 'continue_watching_sessions_v1';

  /// Maximum number of top-scoring rescraped candidates probed for liveness when
  /// resuming. Probes run concurrently, so added latency stays bounded by a single probe.
  static const int _resumeProbeLimit = 8;

  /// How long the resume rescrape waits for sources before it gives up on the
  /// rest of them. The scrapers themselves give up at 8 seconds, so a shorter
  /// window here truncates the candidate pool to whichever providers happened to
  /// answer first, and the sources that were still being fetched never get probed
  /// or offered. A source that strongly matches the saved session ends the wait
  /// immediately, so this only extends the slow, otherwise-empty case.
  static const Duration _resumeScrapeWindow = Duration(seconds: 12);

  /// How long the resume metadata fetch gets before the session's own detail is
  /// used instead. Shorter than the rescrape window above, so the fetch has
  /// always answered by the time that window closes, and the same give-up the
  /// scrapers use: an answer later than this is worth nothing to the resume.
  static const Duration _resumeMetaWindow = Duration(seconds: 8);


  static final ValueNotifier<List<ContinueWatchingItem>> activeItems =
      ValueNotifier<List<ContinueWatchingItem>>([]);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final list = jsonDecode(rawJson) as List<dynamic>;
        final rawItems = list
            .whereType<Map<String, dynamic>>()
            .map((j) => ContinueWatchingItem.fromJson(j))
            .where((item) => !item.isCompleted && item.positionSeconds > 10)
            .toList();

        // Sort by most recent
        rawItems.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));

        // Deduplicate by show/movie ID (keep only the latest episode per show)
        final deduped = <String, ContinueWatchingItem>{};
        for (final item in rawItems) {
          final existing = deduped[item.sessionKey];
          if (existing == null) {
            deduped[item.sessionKey] = item;
          } else if (item.episodeIndex > existing.episodeIndex) {
            deduped[item.sessionKey] = item;
          }
        }

        final items = deduped.values.toList();
        items.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
        activeItems.value = items;
      }
    } catch (e) {
      debugPrint('[ContinueWatchingService] Failed to load sessions: $e');
    }

    // Sync cloud items in background
    syncCloudSessions();
  }

  /// Syncs continue watching entries from Trakt and Simkl
  static Future<void> syncCloudSessions() async {
    try {
      final cloudItems = <ContinueWatchingItem>[];

      // 1. Trakt Continue Watching
      if (await TraktService.instance.isAuthenticated()) {
        try {
          final traktMovies = await TraktContinueWatchingService.instance.fetchMovies();
          for (final tm in traktMovies) {
            final progress = (tm.progress ?? 0) / 100.0;
            final durationSeconds = (tm.runtime != null && tm.runtime! > 0) ? tm.runtime! * 60 : 7200;
            final posSec = (progress * durationSeconds).toInt();
            cloudItems.add(ContinueWatchingItem(
              id: tm.id,
              title: tm.title,
              type: 'movie',
              posterUrl: tm.posterUrl,
              backdropUrl: tm.meta.background,
              year: tm.year,
              positionSeconds: posSec > 0 ? posSec : 1,
              totalDurationSeconds: durationSeconds,
              lastWatchedAt: tm.pausedAtMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(tm.pausedAtMs!)
                  : DateTime.now(),
              isTorrent: false,
            ));
          }

          final traktShows = await TraktContinueWatchingService.instance.fetchShows();
          for (final ts in traktShows) {
            final progress = (ts.progress ?? 0) / 100.0;
            final durationSeconds = (ts.runtime != null && ts.runtime! > 0) ? ts.runtime! * 60 : 2700;
            final posSec = (progress * durationSeconds).toInt();
            cloudItems.add(ContinueWatchingItem(
              id: ts.id,
              title: ts.title,
              type: 'series',
              posterUrl: ts.posterUrl,
              backdropUrl: ts.meta.background,
              year: ts.year,
              season: ts.season,
              episode: ts.episode,
              positionSeconds: posSec > 0 ? posSec : 1,
              totalDurationSeconds: durationSeconds,
              lastWatchedAt: ts.pausedAtMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(ts.pausedAtMs!)
                  : DateTime.now(),
              isTorrent: false,
            ));
          }
        } catch (e) {
          debugPrint('[ContinueWatchingService] Trakt sync error: $e');
        }
      }

      // 2. Simkl Continue Watching
      if (await SimklService.instance.isAuthenticated()) {
        try {
          final simklRes = await SimklContinueWatchingService.instance.fetchItems();
          if (simklRes != null) {
            for (final sm in simklRes.movies) {
              final progress = (sm.progress ?? 0) / 100.0;
              const durationSeconds = 7200;
              final posSec = (progress * durationSeconds).toInt();
              cloudItems.add(ContinueWatchingItem(
                id: sm.id,
                title: sm.meta.name,
                type: 'movie',
                posterUrl: sm.meta.poster,
                backdropUrl: sm.meta.background,
                year: sm.meta.year,
                positionSeconds: posSec > 0 ? posSec : 1,
                totalDurationSeconds: durationSeconds,
                lastWatchedAt: sm.pausedAtMs != null
                    ? DateTime.fromMillisecondsSinceEpoch(sm.pausedAtMs!)
                    : DateTime.now(),
                isTorrent: false,
              ));
            }

            for (final ss in simklRes.shows) {
              final progress = (ss.progress ?? 0) / 100.0;
              const durationSeconds = 2700;
              final posSec = (progress * durationSeconds).toInt();
              cloudItems.add(ContinueWatchingItem(
                id: ss.id,
                title: ss.meta.name,
                type: 'series',
                posterUrl: ss.meta.poster,
                backdropUrl: ss.meta.background,
                year: ss.meta.year,
                season: ss.season,
                episode: ss.episode,
                positionSeconds: posSec > 0 ? posSec : 1,
                totalDurationSeconds: durationSeconds,
                lastWatchedAt: ss.pausedAtMs != null
                    ? DateTime.fromMillisecondsSinceEpoch(ss.pausedAtMs!)
                    : DateTime.now(),
                isTorrent: false,
              ));
            }
          }
        } catch (e) {
          debugPrint('[ContinueWatchingService] Simkl sync error: $e');
        }
      }

      if (cloudItems.isEmpty) return;

      // Merge with local active items
      final existingMap = {for (final item in activeItems.value) item.sessionKey: item};
      for (final cloudItem in cloudItems) {
        final local = existingMap[cloudItem.sessionKey];
        if (local == null) {
          existingMap[cloudItem.sessionKey] = cloudItem;
        } else {
          // If cloud is newer and higher episode, advance to the new episode
          if (cloudItem.episodeIndex > local.episodeIndex ||
              (cloudItem.episodeIndex == local.episodeIndex &&
                  cloudItem.lastWatchedAt.isAfter(local.lastWatchedAt))) {
            // Cloud services carry no maturity metadata, so keep whatever the
            // local session already knew about the content.
            existingMap[cloudItem.sessionKey] =
                cloudItem.copyWith(isAdult: cloudItem.isAdult || local.isAdult);
          }
        }
      }

      final merged = existingMap.values.where((i) => !i.isCompleted).toList();
      merged.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        activeItems.value = merged;
      });
    } catch (e) {
      debugPrint('[ContinueWatchingService] Cloud sync error: $e');
    }
  }

  /// Whether a session is known to originate from adult content.
  ///
  /// Reads in-memory state only — installed addons, the extractors that serve
  /// NSFW anime, and the AniList adult flag the anime library persisted — so it
  /// can also classify sessions saved before [ContinueWatchingItem.isAdult]
  /// existed. Anything it cannot classify counts as non-adult.
  static bool isAdultSession({
    required String id,
    required String type,
    String? addonName,
    List<String> genres = const [],
    Set<String>? nsfwAddonKeys,
  }) {
    final name = (addonName ?? '').trim().toLowerCase();
    if (name == 'watchhentai' || name == 'hentaini') return true;

    // Batch callers pass a hoisted set so the addon list is scanned once per
    // batch; single calls keep the original direct scan (no set allocation).
    if (nsfwAddonKeys != null) {
      if (nsfwAddonKeys.contains(name)) return true;
    } else {
      for (final addon in AddonManager.instance.addons) {
        if (!addon.isNsfwOnly) continue;
        if (name == addon.manifest.name.toLowerCase() ||
            name == addon.manifest.id.toLowerCase()) {
          return true;
        }
      }
    }

    if (type != 'anime' && !id.startsWith('anilist:')) return false;
    if (genres.any(_isAdultGenre)) return true;

    final anilistId = int.tryParse(id.replaceFirst('anilist:', ''));
    if (anilistId == null) return false;
    return AnimeLibraryService.instance.getProgress(anilistId)?.anime.isAdult == true ||
        AnimeLibraryService.instance.getWatchlistItem(anilistId)?.anime.isAdult == true;
  }

  /// AniList's adult genres — the same signal the scraper uses to route a title
  /// to the hentai extractors.
  static bool _isAdultGenre(String genre) {
    final value = genre.toLowerCase();
    return value.contains('hentai') || value.contains('erotica');
  }

  /// Lowercased names/ids of NSFW-only addons (+ hardcoded hentai sources),
  /// built once so batch callers don't re-scan the addon list per item.
  static Set<String> buildNsfwAddonKeys() {
    final keys = <String>{'watchhentai', 'hentaini'};
    for (final addon in AddonManager.instance.addons) {
      if (!addon.isNsfwOnly) continue;
      keys.add(addon.manifest.name.toLowerCase());
      keys.add(addon.manifest.id.toLowerCase());
    }
    return keys;
  }

  /// Saves or updates the playback progress for a session.
  /// Automatically purges finished media (>= 90% watched).
  /// Enforces only 1 single card per show, tracking the latest episode.
  static Future<void> saveProgress({
    required MovieDetail detail,
    Video? episode,
    required StreamSource source,
    required int positionSeconds,
    required int totalDurationSeconds,
  }) async {
    if (positionSeconds < 5 || totalDurationSeconds <= 0) return;

    final progress = positionSeconds / totalDurationSeconds;
    final isFinished = progress >= 0.90;

    final isTorrent = (source.infoHash != null && source.infoHash!.isNotEmpty) ||
        (source.url != null && source.url!.startsWith('magnet:'));

    String? magnetUrl;
    if (isTorrent) {
      if (source.url != null && source.url!.startsWith('magnet:')) {
        magnetUrl = source.url;
      } else if (source.infoHash != null && source.infoHash!.isNotEmpty) {
        magnetUrl = 'magnet:?xt=urn:btih:${source.infoHash}';
        if (source.sources != null) {
          for (final tr in source.sources!) {
            if (tr.startsWith('tracker:')) {
              final tracker = tr.replaceFirst('tracker:', '');
              magnetUrl = '$magnetUrl&tr=${Uri.encodeComponent(tracker)}';
            }
          }
        }
      }
    }

    final newItem = ContinueWatchingItem(
      id: detail.id,
      title: detail.name,
      type: detail.type,
      posterUrl: detail.poster,
      backdropUrl: detail.background,
      year: detail.year,
      season: episode?.season,
      episode: episode?.episode,
      episodeTitle: episode?.title,
      episodeId: episode?.id,
      streamName: source.name,
      streamTitle: (source.title != null && source.title!.isNotEmpty)
          ? source.title!
          : source.displayTitle,
      streamDescription: source.description,
      addonName: source.addonName,
      quality: source.quality,
      isTorrent: isTorrent,
      rawUrl: source.url,
      infoHash: source.infoHash,
      fileIdx: source.fileIdx,
      positionSeconds: positionSeconds,
      totalDurationSeconds: totalDurationSeconds,
      lastWatchedAt: DateTime.now(),
      isAdult: isAdultSession(
        id: detail.id,
        type: detail.type,
        addonName: source.addonName,
        genres: detail.genres,
      ),
    );

    // Read current list
    final current = List<ContinueWatchingItem>.from(activeItems.value);

    // Remove any existing entry for this show/movie
    current.removeWhere((i) => i.sessionKey == newItem.sessionKey);

    // Only insert if not finished (>= 90% watched)
    if (!isFinished) {
      current.insert(0, newItem);
    }

    // Sort newest first
    current.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));

    // Limit to max 50 stored sessions
    final trimmed = current.take(50).toList();

    // Schedule notification safely after current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      activeItems.value = trimmed;
    });

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = trimmed.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[ContinueWatchingService] Failed to persist session: $e');
    }

    // Push cloud scrobble / history to Trakt and Simkl
    _syncCloudPlayback(
      detail: detail,
      episode: episode,
      progressPercent: (progress * 100.0).clamp(0.0, 100.0),
      isFinished: isFinished,
    );
  }

  static DateTime? _lastCloudScrobbleTime;
  static String? _lastCloudScrobbleKey;

  static void _syncCloudPlayback({
    required MovieDetail detail,
    Video? episode,
    required double progressPercent,
    required bool isFinished,
  }) async {
    final imdbId = detail.id.startsWith('tt') ? detail.id : '';
    final targetId = imdbId.isNotEmpty ? imdbId : (detail.tmdbId ?? detail.id);
    if (targetId.isEmpty) return;

    final season = episode?.season;
    final epNum = episode?.episode;
    final type = detail.type;

    // Rate limit periodic scrobbles to once every 20s unless finished
    final currentKey = '$targetId:$season:$epNum';
    final now = DateTime.now();
    if (!isFinished &&
        _lastCloudScrobbleKey == currentKey &&
        _lastCloudScrobbleTime != null &&
        now.difference(_lastCloudScrobbleTime!) < const Duration(seconds: 20)) {
      return;
    }
    _lastCloudScrobbleTime = now;
    _lastCloudScrobbleKey = currentKey;

    // 1. Trakt Playback Scrobble / History
    if (await TraktService.instance.isAuthenticated()) {
      try {
        if (isFinished) {
          await TraktService.instance.scrobbleStop(
            targetId,
            100.0,
            season: season,
            episode: epNum,
          );
          await TraktService.instance.addToHistory(targetId, type);
        } else {
          await TraktService.instance.scrobblePause(
            targetId,
            progressPercent,
            season: season,
            episode: epNum,
          );
        }
      } catch (e) {
        debugPrint('[ContinueWatchingService] Trakt cloud scrobble error: $e');
      }
    }

    // 2. Simkl Playback Scrobble / History
    if (await SimklService.instance.isAuthenticated()) {
      try {
        if (isFinished) {
          await SimklService.instance.scrobbleStop(
            targetId,
            100.0,
            season: season,
            episode: epNum,
          );
          if (type == 'series' && season != null && epNum != null) {
            await SimklService.instance.markEpisodeWatched(targetId, season, epNum);
          } else {
            await SimklService.instance.markWatched(targetId, type);
          }
        } else {
          await SimklService.instance.scrobblePause(
            targetId,
            progressPercent,
            season: season,
            episode: epNum,
          );
        }
      } catch (e) {
        debugPrint('[ContinueWatchingService] Simkl cloud scrobble error: $e');
      }
    }
  }

  /// Removes an item completely from continue watching locally and removes
  /// its playback session & tracking state from Trakt and Simkl in the background.
  static Future<void> removeItem(ContinueWatchingItem item) async {
    final current = List<ContinueWatchingItem>.from(activeItems.value);
    current.removeWhere((i) => i.sessionKey == item.sessionKey);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      activeItems.value = current;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = current.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[ContinueWatchingService] Failed to remove session: $e');
    }

    // Cloud Removal (Trakt & Simkl)
    _removeCloudSession(item);
  }

  static void _removeCloudSession(ContinueWatchingItem item) async {
    final rawId = item.id;
    if (rawId.startsWith('anilist:')) return;

    final baseId = rawId.contains(':') ? rawId.split(':').first : rawId;
    if (baseId.isEmpty) return;

    final type = item.type;
    final isSeries = type == 'series' || type == 'show' || type == 'shows';

    // 1. Trakt Cloud Removal
    try {
      if (await TraktService.instance.isAuthenticated()) {
        await TraktService.instance.deletePlaybackForImdb(baseId, type: type);
        if (isSeries) {
          await TraktService.instance.removeFromHistory(baseId, 'series');
        }
        debugPrint('[ContinueWatchingService] Removed $baseId ($type) from Trakt continue watching');
      }
    } catch (e) {
      debugPrint('[ContinueWatchingService] Trakt cloud removal error for $baseId: $e');
    }

    // 2. Simkl Cloud Removal
    try {
      if (await SimklService.instance.isAuthenticated()) {
        await SimklService.instance.deletePlaybackForImdb(baseId);
        if (isSeries) {
          await SimklService.instance.addToList(baseId, 'series', 'hold');
        }
        debugPrint('[ContinueWatchingService] Removed $baseId ($type) from Simkl continue watching');
      }
    } catch (e) {
      debugPrint('[ContinueWatchingService] Simkl cloud removal error for $baseId: $e');
    }
  }

  /// Resumes playback when a continue-watching card is clicked:
  /// - For First Launch from Trakt/Simkl: Opens WatchScreen to let user manually pick source, then auto-seeks.
  /// - For Anime: Rescrapes streams with AnimeScraperService and auto-seeks.
  /// - For Torrents: launches directly using saved magnet and fileIdx (no rescraping).
  /// - For ZPlayHTTP & Addons: rescrapes and selects the best matching healthy stream.
  /// - Fallback: opens WatchScreen or AnimeStreamSheet if source died.
  static Future<void> resumePlayback(
    BuildContext context,
    ContinueWatchingItem item,
  ) async {
    final movieDetail = MovieDetail(
      id: item.id,
      name: item.title,
      type: item.type,
      poster: item.posterUrl,
      background: item.backdropUrl,
      year: item.year,
    );

    // A session only stores the id, title and art it was saved with, so the
    // player would otherwise get no logo and the rescrape behind it no genres.
    // Started here, before any branch waits on a scraped source, so the request
    // overlaps that wait instead of sitting in front of it. Null means the
    // fetch failed or the id is not one Cinemeta indexes (anime sessions carry
    // anilist: ids), and then the session's own detail above is what ships.
    final metaFuture = _fetchResumeMeta(item);

    Video? video;
    if (item.season != null && item.episode != null) {
      video = Video(
        id: item.episodeId ?? '${item.id}:${item.season}:${item.episode}',
        title: item.episodeTitle ?? 'Episode ${item.episode}',
        season: item.season ?? 1,
        episode: item.episode ?? 1,
        thumbnail: item.backdropUrl,
      );
    }

    // 0. First-Launch Trakt/Simkl Cloud Session:
    // If no saved local stream source or magnet exists, open WatchScreen
    // so the user can choose their preferred provider manually, then auto-seek!
    final isFirstLaunchCloudItem = item.addonName == null &&
        (item.magnetUrl == null || item.magnetUrl!.isEmpty) &&
        (item.rawUrl == null || item.rawUrl!.isEmpty);

    if (isFirstLaunchCloudItem) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WatchScreen(
            detail: movieDetail,
            selectedEpisode: video,
            type: item.type,
            initialPosition: Duration(seconds: item.positionSeconds),
          ),
        ),
      );
      return;
    }

    // 1. Arabic Anime Specialized Resume Path
    if (item.id.startsWith('arabic_anime:') || item.addonName == 'ArabicAnime') {
      final slug = item.id.replaceAll('arabic_anime:', '');
      final episodeNum = item.episode ?? 1;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF12151E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppThemeService.currentPalette.value.primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'استئناف ${item.title} الحلقة $episodeNum...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      try {
        final details = await AnimeArabicService.instance.getDetails(slug);
        final ep = details.episodes.firstWhere(
          (e) => e.number == episodeNum,
          orElse: () => details.episodes.isNotEmpty
              ? details.episodes.first
              : ArabicEpisode(
                  number: episodeNum,
                  title: 'الحلقة $episodeNum',
                  encodedHref: '',
                  watchPath: '/e/$slug-$episodeNum#tok',
                ),
        );

        final rawStreams = await AnimeArabicExtractor.instance.resolveEpisode(ep);

        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        if (rawStreams.isNotEmpty) {
          final sources = AnimeArabicExtractor.toSources(
            rawStreams,
            animeTitle: details.title,
            episodeNumber: episodeNum,
          );

          StreamSource targetSource = sources.first;
          if (item.streamName != null) {
            final matched = sources.where((s) => s.name == item.streamName || s.title == item.streamTitle);
            if (matched.isNotEmpty) targetSource = matched.first;
          }

          final movieDetail = details.toMovieDetail();
          final video = movieDetail.videos.firstWhere(
            (v) => v.episode == episodeNum,
            orElse: () => movieDetail.videos.first,
          );

          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                source: targetSource,
                title: '${details.title} - الحلقة $episodeNum',
                backdropUrl: details.displayBanner,
                logoUrl: movieDetail.logo,
                detail: movieDetail,
                episode: video,
                initialPosition: Duration(seconds: item.positionSeconds),
                // The extractor's own ranking, so a source that dies on open is
                // replaced automatically instead of dropping the user into the
                // picker after a resume. A torrent the provider already refused
                // is left out, since ranking it again only wastes an attempt.
                alternatives: _excludingRejected(sources),
              ),
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('[ContinueWatching] Arabic resume error: $e');
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }

      if (!context.mounted) return;
      final card = ArabicAnimeCard(
        slug: slug,
        title: item.title,
        cover: item.posterUrl ?? item.backdropUrl,
      );
      Navigator.push(
        context,
        CinematicSlideRoute(
          page: AnimeArabicDetailsPage(
            anime: card,
            initialEpisodeNumber: episodeNum,
          ),
        ),
      );
      return;
    }

    // 2. General Anime Specialized Resume Path
    if (item.type == 'anime' || item.id.startsWith('anilist:')) {
      final anilistId = int.tryParse(item.id.replaceAll('anilist:', '')) ?? 0;
      final anime = AnimeMedia(
        id: anilistId,
        titleEnglish: item.title,
        titleRomaji: item.title,
        titleNative: '',
        titleUserPreferred: item.title,
        coverImageLarge: item.posterUrl ?? '',
        coverImageExtraLarge: item.posterUrl ?? '',
        bannerImage: item.backdropUrl ?? '',
        description: '',
        seasonYear: int.tryParse(item.year ?? '') ?? 0,
        averageScore: 0,
        genres: const [],
        format: 'TV',
        status: 'RELEASING',
        totalEpisodes: 0,
      );

      final episodeNum = item.episode ?? 1;

      // Show rescrape loader for Anime HTTP streams
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF12151E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppThemeService.currentPalette.value.primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Resuming ${item.title} Ep $episodeNum...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final animeSources = <StreamSource>[];
      StreamSubscription<StreamSource>? sub;

      try {
        final stream = AnimeScraperService.instance.scrapeStreamsStream(
          anime: anime,
          episodeNumber: episodeNum,
        );

        final completer = Completer<void>();

        sub = stream.listen(
          (source) {
            animeSources.add(source);
            final matchScore = calculateSourceMatchScore(source, item);
            if (matchScore >= 950.0) {
              if (!completer.isCompleted) completer.complete();
            }
          },
          onError: (_) {},
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );

        await completer.future.timeout(_resumeScrapeWindow, onTimeout: () {});
      } catch (_) {} finally {
        sub?.cancel();
      }

      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (!context.mounted) return;

      StreamSource? selectedSource;
      if (animeSources.isNotEmpty) {
        animeSources.sort((a, b) {
          final scoreA = calculateSourceMatchScore(a, item);
          final scoreB = calculateSourceMatchScore(b, item);
          return scoreB.compareTo(scoreA);
        });
        selectedSource = animeSources.first;
      }

      if (selectedSource != null) {
        final detail = AnimeScraperService.toMovieDetail(anime);
        final video = AnimeScraperService.toVideo(anime, episodeNum);

        final finalSource = selectedSource;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              source: finalSource,
              title: finalSource.displayTitle,
              backdropUrl: item.backdropUrl,
              logoUrl: detail.logo,
              detail: detail,
              episode: video,
              initialPosition: Duration(seconds: item.positionSeconds),
              // Ranked scraped candidates, so the player can walk them if the
              // selected one delivers nothing, minus the torrents the provider
              // has already refused.
              alternatives: _excludingRejected(animeSources),
            ),
          ),
        );
      } else {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => AnimeStreamSheet(
            anime: anime,
            episodeNumber: episodeNum,
            autoPlay: false,
          ),
        );
      }
      return;
    }

    // 2. Fast-Path Torrent Resume:
    // If we have the saved magnet or infoHash + fileIdx, launch immediately!
    if (item.isTorrent &&
        ((item.magnetUrl != null && item.magnetUrl!.isNotEmpty) ||
         (item.infoHash != null && item.infoHash!.isNotEmpty))) {
      final source = item.toStreamSource();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            source: source,
            title: item.streamTitle ?? item.title,
            backdropUrl: item.backdropUrl,
            // This path launches from the saved magnet without waiting on
            // anything, so the only detail in scope is the session's own.
            logoUrl: movieDetail.logo,
            detail: movieDetail,
            episode: video,
            initialPosition: Duration(seconds: item.positionSeconds),
          ),
        ),
      );
      return;
    }

    // 3. HTTP / Dynamic Stream Rescrape Path
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF12151E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppThemeService.currentPalette.value.primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Resuming ${item.title}...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final streamId = item.episodeId ?? (item.type == 'series' && item.season != null && item.episode != null
        ? '${item.id}:${item.season}:${item.episode}'
        : item.id);

    final candidateSources = <StreamSource>[];
    StreamSubscription<StreamSource>? sub;

    try {
      final stream = StreamService.fetchStreams(
        type: item.type,
        id: streamId,
        title: item.title,
        year: int.tryParse(item.year ?? ''),
        season: item.season,
        episode: item.episode,
        // The fetch runs alongside this rescrape rather than in front of it, so
        // the fetched genres are not in hand yet and this first pass starts on
        // the session's; they reach the detail the player opens with below.
        genres: movieDetail.genres,
      );

      final completer = Completer<void>();

      sub = stream.listen(
        (source) {
          candidateSources.add(source);
          // If we found an exceptionally strong match (matching release tags, exact title/description, or exact hash), we can finish promptly
          final matchScore = calculateSourceMatchScore(source, item);
          if (matchScore >= 950.0) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (_) {},
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // The metadata fetch started with this resume, so it works against the
      // same window as the rescrape: waiting for both here keeps the request
      // from adding a round trip in front of the sources, and the fetch's own
      // cap below this window means a slow answer cannot stretch the wait past
      // what this path already allows itself.
      await Future.wait<Object?>(
        [completer.future, metaFuture],
      ).timeout(_resumeScrapeWindow, onTimeout: () => const <Object?>[]);
    } catch (_) {} finally {
      sub?.cancel();
    }

    // Close loading dialog
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // The fetch above has had the whole rescrape window to answer, so this read
    // is a microtask; a null answer keeps the session's own detail.
    final detail = _mergeResumeDetail(await metaFuture, movieDetail, item);

    if (!context.mounted) return;

    // Rank all rescraped candidate sources using our semantic matcher
    candidateSources.sort((a, b) {
      final scoreA = calculateSourceMatchScore(a, item);
      final scoreB = calculateSourceMatchScore(b, item);
      return scoreB.compareTo(scoreA);
    });

    StreamSource? selectedSource;
    // What the player walks when the chosen source delivers nothing. The probe
    // verdict leads that order, so the automatic source search spends its
    // attempts on sources known to serve media rather than on ones already
    // known to be dead. Stays the plain ranking unless the probe below reorders
    // it, which keeps a resume without candidates on its old path. Torrents the
    // provider has already refused are dropped: one of them can never play, so
    // ranking it would only spend one of the player's attempts.
    var handoverCandidates = _excludingRejected(candidateSources);
    if (candidateSources.isNotEmpty) {
      // Probe the highest-scoring candidates for liveness, concurrently, so the
      // selection prefers a source that actually serves media. Probes are wrapped
      // in a timeout so a hung URL can never stall the resume.
      final probeCandidates = candidateSources.take(_resumeProbeLimit).toList();
      final liveness = await Future.wait(
        probeCandidates.map(
          (s) => StreamHealthChecker.isAlive(s)
              .timeout(const Duration(seconds: 8), onTimeout: () => false)
              .catchError((_) => false),
        ),
      );

      final aliveCount = liveness.where((alive) => alive).length;
      final firstAliveIndex = liveness.indexOf(true);

      // The probe above is a new async gap that can last seconds, and the
      // Navigator.push calls below use this BuildContext - re-check before that.
      if (!context.mounted) return;

      // First alive candidate in score order; if none passed the probe, fall back
      // to the best textual match. The probe can yield false negatives (providers
      // that block range requests but stream fine over HLS), so it must only ever
      // reorder preference toward a verified source, never reduce reach.
      final StreamSource chosen = firstAliveIndex >= 0
          ? probeCandidates[firstAliveIndex]
          : candidateSources.first;
      selectedSource = chosen;

      // Attempt order for the player: the candidates the probe accepted, in
      // rank order, then the ones it rejected, also in rank order. Only the
      // first _resumeProbeLimit candidates were probed at all, so the unchecked
      // tail rides behind the verified ones instead of claiming a verification
      // it never got. Nothing leaves the list: a rejected probe is a false
      // negative often enough that reach must not depend on it, and the player
      // opening this source genuinely needs the alternatives behind it.
      final verified = <StreamSource>[];
      final unverified = <StreamSource>[];
      for (var i = 0; i < candidateSources.length; i++) {
        if (i < liveness.length && liveness[i]) {
          verified.add(candidateSources[i]);
        } else {
          unverified.add(candidateSources[i]);
        }
      }
      handoverCandidates =
          _excludingRejected(<StreamSource>[...verified, ...unverified]);

      final bestScore = calculateSourceMatchScore(chosen, item);
      debugPrint('[ContinueWatchingService] Probed ${probeCandidates.length} source(s), $aliveCount alive; selected source match: "${chosen.addonName} - ${chosen.displayTitle}" (Match Score: $bestScore)');

      // The probe verdict decides whether the player is handed a source that is
      // already known to be dead. Without this trail a resume that lands on a
      // stalled stream looks identical to a source that died after verification.
      CrashBreadcrumbs.stream(
        aliveCount > 0 ? 'resume.selected.verified' : 'resume.selected.unverified',
        title: item.title,
        addon: '${chosen.addonName} $aliveCount/${probeCandidates.length} alive of ${candidateSources.length}',
      );
    }

    if (selectedSource != null) {
      final finalSource = selectedSource;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            source: finalSource,
            title: finalSource.displayTitle,
            backdropUrl: item.backdropUrl,
            logoUrl: detail.logo,
            detail: detail,
            episode: video,
            initialPosition: Duration(seconds: item.positionSeconds),
            // The whole ranking, probe verdict first: the player walks this in
            // order, and the liveness probe above is only a heuristic, so it
            // needs the alternatives to fall back on when the chosen source
            // turns out to be dead anyway. Already free of refused torrents.
            alternatives: handoverCandidates,
          ),
        ),
      );
    } else {
      // Fallback to WatchScreen so the user can choose from all available sources
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WatchScreen(
            detail: detail,
            selectedEpisode: video,
            type: item.type,
            initialPosition: Duration(seconds: item.positionSeconds),
          ),
        ),
      );
    }
  }

  /// Full metadata for a resumed session, so the player gets the title's logo
  /// and the rescrape behind it the genres a bare session detail cannot carry.
  ///
  /// Cinemeta indexes imdb ids only, so anime sessions (anilist: ids) and
  /// Arabic anime (a slug) skip the request entirely. Nothing here is allowed to
  /// fail the resume: a rejected request, a timeout or a body Cinemeta does not
  /// have all return null, and the caller keeps the session's own detail.
  static Future<MovieDetail?> _fetchResumeMeta(ContinueWatchingItem item) async {
    final imdbId = item.id.split(':').first;
    if (!imdbId.startsWith('tt')) return null;

    try {
      return await MetadataService.fetchMeta(
        // An empty base url resolves to Cinemeta inside fetchMeta.
        baseUrl: '',
        type: item.type == 'series' ? 'series' : 'movie',
        imdbId: imdbId,
      ).timeout(_resumeMetaWindow, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  /// The candidates a Debrid provider has not already refused.
  ///
  /// A refusal is permanent for that torrent, so handing it to the player as a
  /// fallback would only spend one of the attempts on a source that cannot
  /// play. A null hash reports as usable: a direct link has nothing to refuse,
  /// and the store ignores a null hash anyway.
  static List<StreamSource> _excludingRejected(
    List<StreamSource> candidates,
  ) {
    final store = DebridRejectionStore.instance;
    return candidates.where((s) => !store.isRejected(s.infoHash)).toList();
  }

  /// The fetched metadata with the session's own artwork filled in wherever
  /// Cinemeta had none, so a resume still looks like the card the user tapped.
  static MovieDetail _mergeResumeDetail(
    MovieDetail? fetched,
    MovieDetail session,
    ContinueWatchingItem item,
  ) {
    if (fetched == null) return session;
    return fetched.copyWith(
      poster: fetched.poster ?? item.posterUrl,
      background: fetched.background ?? item.backdropUrl,
      year: fetched.year ?? item.year,
    );
  }

  /// Calculates a comprehensive relevance/match score between a rescraped [candidate] stream
  /// and the saved [target] continue-watching session.
  ///
  /// Matches on:
  /// 1. Exact infoHash / magnet / URL fingerprint (+1000 pts)
  /// 2. Addon Provider (+150 pts)
  /// 3. Stream / Scraper Name match (+80 pts)
  /// 4. Video filename, description & release group tags (FLUX, PSA, GalaxyRG, YTS, EZTV, WEB-DL, BluRay, etc.) (+35 pts per tag)
  /// 5. Resolution / Quality match (+80 pts)
  /// 6. Audio / Video Codec / HDR tags match (+30 pts)
  /// 7. Text Token Overlap (Jaccard / Dice similarity on words) (+120 pts)
  /// 8. Stream Type (Torrent / Debrid / Direct HTTP) consistency (+40 pts)
  static double calculateSourceMatchScore(
    StreamSource candidate,
    ContinueWatchingItem target,
  ) {
    double score = 0.0;

    // 1. Exact Unique Fingerprints
    if (target.infoHash != null &&
        target.infoHash!.isNotEmpty &&
        candidate.infoHash != null &&
        candidate.infoHash!.toLowerCase() == target.infoHash!.toLowerCase()) {
      score += 1000.0;
      if (target.fileIdx != null && candidate.fileIdx == target.fileIdx) {
        score += 200.0;
      }
    }

    if (target.rawUrl != null &&
        target.rawUrl!.isNotEmpty &&
        candidate.url != null &&
        candidate.url == target.rawUrl) {
      score += 1000.0;
    }

    // 2. Source Card Line 2: Exact Title & Scraper Prefix Match
    // e.g. "FSOnline · FileSuN · 1080p"
    final targetTitle = (target.streamTitle ?? '').trim();
    final candidateTitle = (candidate.title ?? candidate.displayTitle).trim();
    if (targetTitle.isNotEmpty && candidateTitle.isNotEmpty) {
      final cleanTarget = _normalizeForComparison(targetTitle);
      final cleanCand = _normalizeForComparison(candidateTitle);

      if (cleanTarget == cleanCand) {
        score += 700.0; // Exact normalized title match!
      } else {
        // Match scraper name / server prefix (e.g. "fsonline", "vidrock", "lookmovie", "cinesu", etc.)
        final targetPrefix = cleanTarget.split(' ').firstOrNull ?? '';
        final candPrefix = cleanCand.split(' ').firstOrNull ?? '';
        if (targetPrefix.isNotEmpty && targetPrefix == candPrefix) {
          score += 350.0; // Same scraper / provider prefix!
        } else if (cleanTarget.contains(cleanCand) || cleanCand.contains(cleanTarget)) {
          score += 200.0;
        }
      }
    }

    // 3. Source Card Line 3: Description / Comments Match ("these comments under it")
    // e.g. "FSOnline HLS Stream"
    final targetDesc = (target.streamDescription ?? '').trim();
    final candidateDesc = (candidate.description ?? '').trim();
    if (targetDesc.isNotEmpty && candidateDesc.isNotEmpty) {
      final cleanTargetDesc = _normalizeForComparison(targetDesc);
      final cleanCandDesc = _normalizeForComparison(candidateDesc);

      if (cleanTargetDesc == cleanCandDesc) {
        score += 500.0; // Exact normalized description match!
      } else if (cleanCandDesc.contains(cleanTargetDesc) || cleanTargetDesc.contains(cleanCandDesc)) {
        score += 250.0; // Substring description match!
      }
    }

    // 4. Source Card Line 1: Addon Provider Match (e.g. "ZPlayHTTP")
    final targetAddon = (target.addonName ?? '').trim().toLowerCase();
    final candidateAddon = candidate.addonName.trim().toLowerCase();
    if (targetAddon.isNotEmpty && targetAddon == candidateAddon) {
      score += 150.0;
    }

    // Stream Scraper / Server Name Match
    final targetName = (target.streamName ?? '').trim().toLowerCase();
    final candidateName = (candidate.name ?? '').trim().toLowerCase();
    if (targetName.isNotEmpty && candidateName.isNotEmpty) {
      if (targetName == candidateName) {
        score += 80.0;
      } else if (candidateName.contains(targetName) || targetName.contains(candidateName)) {
        score += 40.0;
      }
    }

    // 5. Resolution / Quality Match
    final targetQuality = (target.quality ?? '').trim().toUpperCase();
    final candidateQuality = (candidate.quality ?? '').trim().toUpperCase();
    if (targetQuality.isNotEmpty && candidateQuality.isNotEmpty) {
      if (targetQuality == candidateQuality) {
        score += 80.0;
      } else {
        final diff = (candidate.qualityRank - (target.quality != null ? _parseQualityRank(target.quality!) : 0)).abs();
        if (diff == 1) {
          score += 25.0; // Adjacent quality
        }
      }
    }

    // 5. Codec, HDR, and Release Group Tags Match
    final targetCombinedText = '${target.streamName ?? ''} ${target.streamTitle ?? ''} ${target.streamDescription ?? ''}'.toLowerCase();
    final candidateCombinedText = '${candidate.name ?? ''} ${candidate.title ?? ''} ${candidate.description ?? ''}'.toLowerCase();

    // HDR Match
    final targetIsHDR = targetCombinedText.contains('hdr') || targetCombinedText.contains('dolby vision') || targetCombinedText.contains('dv');
    if (targetIsHDR && candidate.isHDR) {
      score += 30.0;
    } else if (!targetIsHDR && !candidate.isHDR) {
      score += 10.0;
    }

    // Codec Match
    final candidateCodec = candidate.codec?.toLowerCase();
    if (candidateCodec != null && targetCombinedText.contains(candidateCodec)) {
      score += 30.0;
    }

    // 6. Release Group & Video Scene Tags Match
    const knownTags = [
      'web-dl', 'webdl', 'webrip', 'bluray', 'bdrip', 'brrip', 'hdrip', 'remux',
      'atmos', 'ddp5.1', 'dts', 'aac', 'ac3', 'truehd', '5.1', '7.1',
      '10bit', '8bit', 'hevc', 'x265', 'h265', 'x264', 'h264', 'av1',
      'flux', 'psa', 'yts', 'eztv', 'galaxy', 'galaxyrg', 'rarbg', 'qxr', 'd3g', 'ntb',
      'amzn', 'nf', 'atvp', 'hmax', 'dnp', 'dsnp', 'hulu', 'bcore', 'framestor', 'epsilon',
      'proper', 'repack', 'subbed', 'dubbed', 'dual-audio', 'multi',
    ];

    for (final tag in knownTags) {
      final inTarget = _hasWordBoundary(targetCombinedText, tag);
      final inCandidate = _hasWordBoundary(candidateCombinedText, tag);
      if (inTarget && inCandidate) {
        score += 35.0; // Boost for matching release groups and video tags!
      }
    }

    // 7. Token Overlap / Word Similarity on File Name & Description
    final targetTokens = _extractMeaningfulTokens(targetCombinedText);
    final candidateTokens = _extractMeaningfulTokens(candidateCombinedText);

    if (targetTokens.isNotEmpty && candidateTokens.isNotEmpty) {
      int matchingTokens = 0;
      for (final token in candidateTokens) {
        if (targetTokens.contains(token)) {
          matchingTokens++;
        }
      }
      final overlapRatio = (2.0 * matchingTokens) / (targetTokens.length + candidateTokens.length);
      score += overlapRatio * 120.0;
    }

    // 8. Stream Type Consistency (Torrent vs Debrid vs Direct HTTP)
    if (target.isTorrent == candidate.isTorrent) {
      score += 40.0;
    }

    return score;
  }

  static bool _hasWordBoundary(String text, String word) {
    if (!text.contains(word)) return false;
    final regex = RegExp('(^|[^a-z0-9])${RegExp.escape(word)}([^a-z0-9]|\$)', caseSensitive: false);
    return regex.hasMatch(text);
  }

  static Set<String> _extractMeaningfulTokens(String text) {
    final rawWords = text.split(RegExp(r'[\s\.\-_/\[\]\(\)\+:]+'));
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'to', 'for', 'with', 'by',
      'season', 'episode', 'series', 'movie', 'complete', 's', 'e', 'gb', 'mb', 'tb',
      'kib', 'mib', 'gib', 'torrent', 'stream', 'seeds', 'seeders', 'peers',
    };
    final result = <String>{};
    for (final w in rawWords) {
      final clean = w.trim().toLowerCase();
      if (clean.length >= 3 && !stopWords.contains(clean) && !RegExp(r'^\d+$').hasMatch(clean)) {
        result.add(clean);
      }
    }
    return result;
  }

  static int _parseQualityRank(String quality) {
    final q = quality.toUpperCase();
    if (q.contains('4K') || q.contains('2160')) return 4;
    if (q.contains('1080')) return 3;
    if (q.contains('720')) return 2;
    if (q.contains('480')) return 1;
    return 0;
  }

  static String _normalizeForComparison(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\.\-_·\|:/\(\)\[\]]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
