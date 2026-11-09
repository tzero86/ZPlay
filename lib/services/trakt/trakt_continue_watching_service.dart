import 'package:flutter/foundation.dart';

import '../../models/stremio/stremio_meta.dart';
import 'trakt_item_transformer.dart';
import 'trakt_service.dart';

class TraktContinueWatchingItem {
  final StremioMeta meta;
  final String traktContentType;
  final double? progress;
  final int? season;
  final int? episode;
  final int? runtime;
  final List<int> playbackIds;

  /// When Trakt last recorded playback for this item (epoch ms), parsed from the
  /// playback endpoint's `paused_at`. Null for items sourced from the
  /// recent-shows augmentation (which have no paused_at). Used to order a merged
  /// movies+shows list by "last watched".
  final int? pausedAtMs;

  const TraktContinueWatchingItem({
    required this.meta,
    required this.traktContentType,
    this.progress,
    this.season,
    this.episode,
    this.runtime,
    this.playbackIds = const [],
    this.pausedAtMs,
  });

  String get id => meta.effectiveImdbId ?? meta.id;
  String get title => meta.name;
  String? get year => meta.year;
  String? get posterUrl => meta.poster;
  bool get isSeries => meta.type == 'series';
}

class TraktContinueWatchingService {
  TraktContinueWatchingService._({TraktService? traktService})
    : _traktService = traktService ?? TraktService.instance;

  static final TraktContinueWatchingService instance =
      TraktContinueWatchingService._();

  static const moviesContentType = 'movies';
  static const showsContentType = 'episodes';

  final TraktService _traktService;

  Future<List<TraktContinueWatchingItem>> fetchMovies() {
    return fetchItems(moviesContentType);
  }

  Future<List<TraktContinueWatchingItem>> fetchShows() {
    return fetchItems(showsContentType);
  }

  Future<List<TraktContinueWatchingItem>> fetchItems(
    String traktContentType,
  ) async {
    try {
      final isAuth = await _traktService.isAuthenticated();
      if (!isAuth) return [];

      var rawItems = await _traktService.fetchPlaybackItems(traktContentType);

      if (traktContentType == showsContentType) {
        final playbackImdbIds = <String>{};
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final show = raw['show'] as Map<String, dynamic>?;
          final ids = show?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null) playbackImdbIds.add(imdbId);
        }

        final recentWithNext = await _traktService
            .fetchRecentShowsWithNextEpisode(excludeImdbIds: playbackImdbIds);
        if (recentWithNext.isNotEmpty) {
          rawItems = List<dynamic>.from(rawItems)..addAll(recentWithNext);
        }
      }

      if (rawItems.isEmpty) return [];

      return traktContentType == moviesContentType
          ? _buildMovieItems(rawItems)
          : _buildShowItems(rawItems);
    } catch (e) {
      debugPrint('TraktContinueWatchingService: fetchItems failed: $e');
      return [];
    }
  }

  /// Remove [item] from Trakt Continue Watching: delete every playback entry,
  /// then remove the title from watch history so shows don't reappear via the
  /// recent-shows "next episode" augmentation. Returns true if anything was
  /// removed.
  Future<bool> removeItem(TraktContinueWatchingItem item) async {
    var anySuccess = false;
    for (final pbId in item.playbackIds) {
      final ok = await _traktService.removePlaybackItem(pbId);
      if (ok) anySuccess = true;
    }
    final historyRemoved = await _traktService.removeFromHistory(
      item.id,
      item.meta.type,
    );
    return anySuccess || historyRemoved;
  }

  List<TraktContinueWatchingItem> _buildMovieItems(List<dynamic> rawItems) {
    final metas = TraktItemTransformer.transformList(
      rawItems,
      inferredType: 'movie',
    );
    final progressById = <String, double>{};
    final runtimeById = <String, int>{};
    final playbackIdsById = <String, List<int>>{};
    final pausedAtById = <String, int>{};

    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final progress = raw['progress'] as num?;
      final playbackId = raw['id'] as int?;
      final movie = raw['movie'] as Map<String, dynamic>?;
      final ids = movie?['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      if (imdbId == null) continue;
      if (progress != null) progressById[imdbId] = progress.toDouble();
      final runtime = movie?['runtime'] as int?;
      if (runtime != null && runtime > 0) runtimeById[imdbId] = runtime;
      if (playbackId != null) {
        playbackIdsById.putIfAbsent(imdbId, () => []).add(playbackId);
      }
      final pausedAt = _parsePausedAt(raw['paused_at']);
      if (pausedAt != null) pausedAtById.putIfAbsent(imdbId, () => pausedAt);
    }

    return metas
        .map(
          (meta) => TraktContinueWatchingItem(
            meta: meta,
            traktContentType: moviesContentType,
            progress: progressById[meta.id],
            runtime: runtimeById[meta.id],
            playbackIds: playbackIdsById[meta.id] ?? const [],
            pausedAtMs: pausedAtById[meta.id],
          ),
        )
        .toList();
  }

  /// Parse Trakt's ISO-8601 `paused_at` into epoch ms (null if absent/invalid).
  static int? _parsePausedAt(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
  }

  List<TraktContinueWatchingItem> _buildShowItems(List<dynamic> rawItems) {
    final metas = TraktItemTransformer.transformPlaybackEpisodes(rawItems);
    final progressById = <String, double>{};
    final playbackIdsById = <String, List<int>>{};
    final pausedAtById = <String, int>{};
    final episodeInfoById =
        <String, ({int season, int episode, int? runtime})>{};

    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final progress = raw['progress'] as num?;
      final playbackId = raw['id'] as int?;
      final show = raw['show'] as Map<String, dynamic>?;
      final ids = show?['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      final episode = raw['episode'] as Map<String, dynamic>?;
      if (imdbId == null) continue;

      if (progress != null) {
        progressById.putIfAbsent(imdbId, () => progress.toDouble());
      }
      if (playbackId != null) {
        playbackIdsById.putIfAbsent(imdbId, () => []).add(playbackId);
      }
      final pausedAt = _parsePausedAt(raw['paused_at']);
      if (pausedAt != null) pausedAtById.putIfAbsent(imdbId, () => pausedAt);
      if (episode != null && !episodeInfoById.containsKey(imdbId)) {
        episodeInfoById[imdbId] = (
          season: episode['season'] as int? ?? 0,
          episode: episode['number'] as int? ?? 0,
          runtime: episode['runtime'] as int?,
        );
      }
    }

    return metas.map((meta) {
      final episodeInfo = episodeInfoById[meta.id];
      return TraktContinueWatchingItem(
        meta: meta,
        traktContentType: showsContentType,
        progress: progressById[meta.id],
        season: episodeInfo?.season,
        episode: episodeInfo?.episode,
        runtime: episodeInfo?.runtime,
        playbackIds: playbackIdsById[meta.id] ?? const [],
        pausedAtMs: pausedAtById[meta.id],
      );
    }).toList();
  }
}
