import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/movie/movie.dart';
import '../metadata/tmdb_service.dart';

/// Fills the wide artwork and trailer key a hero band needs.
///
/// A catalog response carries a backdrop on some resources and none on others,
/// so the hero resolves what is missing from TMDb once the catalog lands.
/// Every step is best-effort: an item that cannot be resolved comes back as
/// the same [Movie] it went in as, and nothing here throws at a caller.
abstract final class HeroMediaResolver {
  /// How many items one call resolves. A hero shows about six slides, so the
  /// tail past this is work nobody ever sees.
  static const int maxItemsPerCall = 12;

  /// Sockets opened at once. A TV box has 2GB of RAM and a flaky link; twelve
  /// simultaneous TMDb reads time out more often than four do.
  static const int concurrency = 4;

  static const String _backdropBaseUrl = 'https://image.tmdb.org/t/p/w780';

  /// Looked-up hero media by IMDb id, including the ones that came back empty
  /// so a second visit to Home does not re-ask TMDb for a title it does not
  /// have.
  static final Map<String, _HeroMedia> _cache = {};

  /// [movies] with hero media resolved on the first [maxItemsPerCall] entries
  /// and everything after that left as it was.
  ///
  /// Returns the input list itself when TMDb is unconfigured, when there is
  /// nothing to do, or when every read fails.
  static Future<List<Movie>> enrich(List<Movie> movies) async {
    if (movies.isEmpty) return movies;
    if (!TmdbService.isConfigured) return movies;

    final limit = min(movies.length, maxItemsPerCall);
    final enriched = List<Movie>.of(movies);

    for (var start = 0; start < limit; start += concurrency) {
      final batch = movies.sublist(start, min(start + concurrency, limit));
      final resolved = await Future.wait(batch.map(_resolve));
      for (var i = 0; i < resolved.length; i++) {
        final result = resolved[i];
        if (result != null) enriched[start + i] = result;
      }
    }
    return enriched;
  }

  /// Forgets every resolved item. A changed TMDb credential can make a cached
  /// result wrong, and a memory-constrained TV should be able to drop the
  /// whole table on demand.
  static void clearCache() => _cache.clear();

  /// The same item with its hero media filled, or null when there is nothing
  /// to add. Never throws.
  static Future<Movie?> _resolve(Movie movie) async {
    if (_hasBackdrop(movie) && _hasTrailer(movie)) return null;

    final imdbId = movie.id.trim();
    if (!imdbId.startsWith('tt')) return null;

    final cached = _cache[imdbId];
    if (cached != null) return _apply(movie, cached);

    try {
      final found = await TmdbService.getJson(
        '/find/$imdbId',
        {'external_source': 'imdb_id'},
      );
      if (found == null) return null;

      final match = _matchOf(found);
      if (match == null) {
        _cache[imdbId] = const _HeroMedia();
        return null;
      }

      final detail = await TmdbService.getJson(
        '/${match.mediaType}/${match.id}',
        {'append_to_response': 'videos'},
      );
      if (detail == null) return null;

      final media = _HeroMedia.from(detail);
      _cache[imdbId] = media;
      return _apply(movie, media);
    } catch (e) {
      debugPrint('[HeroMediaResolver] lookup failed for $imdbId: $e');
      return null;
    }
  }

  /// The TMDb id for an IMDb id, preferring the movie namespace over the
  /// series one: an IMDb title can be filed under both, and only the movie
  /// namespace carries a backdrop the hero can fill.
  static _TmdbMatch? _matchOf(Map<String, dynamic> found) {
    int? movieId;
    int? seriesId;
    for (final entry in found['movie_results'] ?? const <Object?>[]) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is int && movieId == null) movieId = id;
    }
    for (final entry in found['tv_results'] ?? const <Object?>[]) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is int && seriesId == null) seriesId = id;
    }
    if (movieId != null) return _TmdbMatch(movieId, 'movie');
    if (seriesId != null) return _TmdbMatch(seriesId, 'tv');
    return null;
  }

  static bool _hasBackdrop(Movie movie) {
    final backdrop = movie.backdrop;
    return backdrop != null && backdrop.isNotEmpty;
  }

  static bool _hasTrailer(Movie movie) {
    final trailerKey = movie.trailerKey;
    return trailerKey != null && trailerKey.isNotEmpty;
  }

  static Movie? _apply(Movie movie, _HeroMedia media) {
    if (media.isEmpty) return null;
    return movie.withHeroMedia(
      backdrop: media.backdrop,
      trailerKey: media.trailerKey,
    );
  }
}

class _HeroMedia {
  const _HeroMedia({this.backdrop, this.trailerKey});

  final String? backdrop;
  final String? trailerKey;

  bool get isEmpty => backdrop == null && trailerKey == null;

  factory _HeroMedia.from(Map<String, dynamic> detail) {
    final path = detail['backdrop_path']?.toString();
    return _HeroMedia(
      backdrop: path == null || path.isEmpty
          ? null
          : '${HeroMediaResolver._backdropBaseUrl}$path',
      trailerKey: _trailerKeyOf(detail['videos']),
    );
  }

  /// The video most likely to be the title's own: an official YouTube trailer
  /// first, then any trailer, then anything official, then anything at all.
  /// A teaser beats an empty hero.
  static String? _trailerKeyOf(Object? videos) {
    if (videos is! Map) return null;
    final results = videos['results'];
    if (results is! List) return null;

    String? anyVideo;
    String? official;
    String? anyTrailer;
    for (final entry in results) {
      if (entry is! Map) continue;
      final key = entry['key']?.toString();
      if (key == null || key.isEmpty) continue;
      anyVideo ??= key;
      if (entry['official'] == true) official ??= key;
      if (entry['type'] != 'Trailer') continue;
      anyTrailer ??= key;
      if (entry['site'] == 'YouTube' && entry['official'] == true) return key;
    }
    return anyTrailer ?? official ?? anyVideo;
  }
}

class _TmdbMatch {
  const _TmdbMatch(this.id, this.mediaType);

  final int id;
  final String mediaType;
}
