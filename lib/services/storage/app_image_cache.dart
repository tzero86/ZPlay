import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared disk cache for the artwork/metadata images the UI streams from addons,
/// TMDB and user catalogs.
///
/// The `cached_network_image` default manager evicts aggressively and keeps a
/// short stale window, which makes browsing back into a catalog re-download
/// every poster. A single named manager keeps posters on disk across sessions
/// and bounds the cache so it cannot grow without limit.
class AppImageCache {
  AppImageCache._();

  static const String cacheKey = 'zplayImages';

  /// Hard budget for the artwork store, kept deliberately generous: on the
  /// television the cache is what stops every rail from re-downloading a wall
  /// of posters, so the count is not shrunk to save a little disk.
  static const int maxCachedObjects = 800;

  /// How long an untouched artwork file may sit before the store's periodic
  /// cleanup is allowed to sweep it.
  ///
  /// Art is resolved keylessly through metahub
  /// (`images.metahub.space/{background,poster,logo}/.../{imdbId}/img`), and
  /// those URLs are content-addressed by immutable IMDb id: the picture at one
  /// never changes, so a "stale" hit is still the correct picture and a short
  /// window would only re-download unchanged art on every revisit. The period
  /// is therefore purely disk reclaim for titles nobody comes back to. When a
  /// cached response really is wrong (dead link, replaced scan), the escape
  /// hatch is Settings -> Clear cache, which empties this store on demand.
  static const Duration stalePeriod = Duration(days: 30);

  static final CacheManager manager = CacheManager(
    Config(
      cacheKey,
      maxNrOfCacheObjects: maxCachedObjects,
      stalePeriod: stalePeriod,
    ),
  );

  /// Empties the artwork disk cache. Throws if the store cannot be cleared;
  /// callers report that rather than swallowing it.
  ///
  /// Runs through [emptyCacheForTesting] when one is set: `CacheManager`'s
  /// store is an sqflite database behind a platform channel a widget test
  /// cannot open, and the Settings clear control has to be provable there.
  static Future<void> emptyCache() {
    final override = emptyCacheForTesting;
    if (override != null) return override();
    return manager.emptyCache();
  }

  /// Spy hook for [emptyCache]. Production leaves this null.
  @visibleForTesting
  static Future<void> Function()? emptyCacheForTesting;
}
