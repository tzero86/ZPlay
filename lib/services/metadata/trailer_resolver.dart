import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/movie/movie.dart';
import '../hero/hero_media_resolver.dart';
import 'metadata_service.dart';
import 'tmdb_service.dart';

/// Finds the trailer for a title that arrives without one.
///
/// **The catalog usually names the trailer itself.** A live
/// `catalog/movie/top` response carried a `trailers` row on 49 of 49
/// items, and [Movie.fromJson] now reads it, so most cards never come
/// here. The rest - a rail built from a Trakt list, a search result, a
/// title the catalog had no trailer for - do.
///
/// Two sources, in this order:
///
/// 1. **The addon's own `meta` response.** It carries the same
///    `trailers` and `trailerStreams` rows the catalog does, it needs no
///    credential, and it is a request the app already makes for the
///    title's details. [MetadataService.fetchMeta] caches it, so the
///    second hover of the same card costs nothing.
/// 2. **TMDb.** Only when a credential is configured, because
///    [HeroMediaResolver] asks TMDb for `videos` and a request without a
///    credential is a guaranteed miss.
///
/// Never throws: a title with no trailer is an ordinary outcome, not an
/// error.
abstract final class TrailerResolver {
  /// The keys already resolved, by title id.
  ///
  /// A resolved *null* is remembered too, so a title with no trailer is
  /// asked about once rather than on every hover.
  static final Map<String, String?> _cache = <String, String?>{};

  /// The trailer key for [movie], or null when there is none.
  ///
  /// [movie]'s own key wins: it came with the catalog response and
  /// asking for it again would be a request the app already made.
  static Future<String?> resolve(Movie movie) async {
    final own = movie.trailerKey;
    if (own != null && own.isNotEmpty) return own;

    final id = movie.id;
    if (id.isEmpty) return null;
    if (_cache.containsKey(id)) return _cache[id];

    String? key = await _fromAddonMeta(movie);
    if (key == null && TmdbService.isConfigured) {
      key = await _fromTmdb(movie);
    }
    // A rail that is not built from a catalog has no id the addon's info
    // resource can answer for - the "because you watched" recommendations
    // carry `bestsimilar_<n>` - so the last resort is the title itself.
    key ??= await _fromTitle(movie);
    _cache[id] = key;
    return key;
  }

  /// Forgets everything resolved so far.
  ///
  /// A changed TMDb credential can make a cached answer wrong, and a
  /// profile import can bring in titles that were never resolved here.
  static void clearCache() => _cache.clear();

  /// The trailer named by the addon's own info response.
  static Future<String?> _fromAddonMeta(Movie movie) async {
    // Only an IMDb id is worth a request. The info resource is keyed by
    // the addon's own id space, and a rail carries ids that no addon can
    // answer for (`bestsimilar_*`, `torrentio:*`, `anilist:*`) - a read
    // for one of those is a guaranteed miss that spends a round trip to
    // find out.
    if (!movie.id.startsWith('tt')) return null;
    try {
      final detail = await MetadataService.fetchMeta(
        baseUrl: movie.addonBaseUrl,
        type: movie.type,
        imdbId: movie.id,
      );
      if (detail == null) return null;
      final key = detail.trailerKey;
      return (key != null && key.isNotEmpty) ? key : null;
    } catch (error) {
      debugPrint('[TrailerResolver] addon meta lookup failed: $error');
      return null;
    }
  }

  /// The trailer TMDb names for the title.
  static Future<String?> _fromTmdb(Movie movie) async {
    try {
      final resolved = await HeroMediaResolver.enrich(<Movie>[movie]);
      if (resolved.isEmpty) return null;
      final key = resolved.first.trailerKey;
      return (key != null && key.isNotEmpty) ? key : null;
    } catch (error) {
      debugPrint('[TrailerResolver] TMDb lookup failed: $error');
      return null;
    }
  }

  /// The trailer found by the title itself.
  ///
  /// A rail that is not built from a catalog carries ids no info resource
  /// can answer for - the "because you watched" recommendations carry
  /// `bestsimilar_<n>` - so the title is the only handle left.
  ///
  /// The addon's search finds the title and returns its IMDb id; the
  /// trailer itself is named by the *info* response, not by the search
  /// response, so the search is a way to get the id and the info response
  /// is where the trailer is read from.
  ///
  /// The year narrows the match, because a title alone is ambiguous: a
  /// 1934 and a 2024 film can share a name, and a recommendation rail is
  /// exactly where that happens.
  static Future<String?> _fromTitle(Movie movie) async {
    final name = movie.name.trim();
    if (name.isEmpty) return null;
    final year = movie.year?.trim();

    try {
      final results = await MetadataService.search(
        baseUrl: movie.addonBaseUrl,
        type: movie.type,
        catalogId: 'top',
        query: name,
      );
      for (final result in results) {
        if (result.name.toLowerCase() != name.toLowerCase()) continue;
        if (year != null && year.isNotEmpty) {
          final resultYear = result.year?.trim();
          if (resultYear != null && resultYear != year) continue;
        }
        final key = await _fromAddonMeta(result);
        if (key != null) return key;
      }
      return null;
    } catch (error) {
      debugPrint('[TrailerResolver] title lookup failed: $error');
      return null;
    }
  }
}
