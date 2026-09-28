import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../utils/search/relevance_scorer.dart';
import '../metadata/metadata_service.dart';
import '../p2p/p2p_settings_service.dart';
import '../content/content_settings.dart';

/// Manages installed Stremio metadata addons.
///
/// - Persists addon list + enabled state to SharedPreferences.
/// - On first launch, installs Cinemeta as default.
/// - Provides [fetchAllHomeSections] to aggregate catalogs across all active addons.
class AddonManager {
  AddonManager._();
  static final AddonManager instance = AddonManager._();

  static const String _storageKey = 'installed_addons_v5';

  List<InstalledAddon> _addons = [];
  bool _initialized = false;

  void _ensureBuiltInsExist() {
    bool changed = false;
    if (!_addons.any((a) => a.manifest.id == 'builtin.zplay' || a.baseUrl == 'builtin:zplay')) {
      _addons.add(zplayBuiltin);
      changed = true;
    }
    if (!_addons.any((a) => a.manifest.id == 'builtin.zplayhttp' || a.baseUrl == 'builtin:zplayhttp')) {
      _addons.add(zplayHttpBuiltin);
      changed = true;
    }
    if (changed && _initialized) {
      _save();
    }
  }

  List<InstalledAddon> get addons {
    _ensureBuiltInsExist();
    return List.unmodifiable(_addons);
  }

  /// NSFW-only addons (declared adult, or rated that way by the user) only
  /// contribute content while the global Adult Content switch is on. Hybrid and
  /// SFW addons stay active either way.
  bool _adultAllowed(InstalledAddon addon) =>
      ContentSettings.adultEnabled.value || !addon.isNsfwOnly;

  List<InstalledAddon> get activeAddons {
    _ensureBuiltInsExist();
    return _addons.where((a) => a.enabled && _adultAllowed(a)).toList();
  }

  List<InstalledAddon> get activeCatalogAddons {
    _ensureBuiltInsExist();
    return _addons.where((a) => a.isCatalogsActive && _adultAllowed(a)).toList();
  }

  List<InstalledAddon> get activeSearchAddons {
    _ensureBuiltInsExist();
    return _addons.where((a) => a.isSearchActive && _adultAllowed(a)).toList();
  }

  List<InstalledAddon> get activeSubtitleAddons {
    _ensureBuiltInsExist();
    return _addons.where((a) => a.isSubtitlesActive && _adultAllowed(a)).toList();
  }

  List<InstalledAddon> get activeStreamAddons {
    _ensureBuiltInsExist();
    return _addons
        .where((a) =>
            a.isStreamsActive &&
            !a.baseUrl.startsWith('builtin:') &&
            _adultAllowed(a))
        .toList();
  }

  bool get isZplayActive {
    _ensureBuiltInsExist();
    final p2p = _addons.firstWhere(
      (a) => a.manifest.id == 'builtin.zplay' || a.baseUrl == 'builtin:zplay',
      orElse: () => zplayBuiltin,
    );
    return p2p.isStreamsActive;
  }

  bool get isZplayHttpActive {
    _ensureBuiltInsExist();
    final http = _addons.firstWhere(
      (a) => a.manifest.id == 'builtin.zplayhttp' || a.baseUrl == 'builtin:zplayhttp',
      orElse: () => zplayHttpBuiltin,
    );
    return http.isStreamsActive;
  }

  /// Returns the logo URL or asset path for a given addon name or id.
  String? getAddonLogo(String addonName) {
    _ensureBuiltInsExist();
    final nameLower = addonName.trim().toLowerCase();
    if (nameLower == 'zplay' ||
        nameLower == 'zplayhttp' ||
        nameLower.startsWith('builtin')) {
      return 'asset:assets/icon_small.png';
    }
    for (final addon in _addons) {
      if (addon.manifest.name.toLowerCase() == nameLower ||
          addon.manifest.id.toLowerCase() == nameLower) {
        if (addon.manifest.logo != null && addon.manifest.logo!.isNotEmpty) {
          return addon.manifest.logo;
        }
      }
    }
    return null;
  }

  static final InstalledAddon zplayBuiltin = InstalledAddon(
    baseUrl: 'builtin:zplay',
    manifest: AddonManifest(
      id: 'builtin.zplay',
      name: 'ZPlay',
      version: '3.0.0',
      description: 'Built-in BitTorrent P2P streaming engine (TorrServer). Plays torrents, magnets, and infohashes directly.',
      resources: ['stream'],
      types: ['movie', 'series', 'anime'],
      idPrefixes: ['tt', 'tmdb:', 'kitsu:', 'mal:'],
      catalogs: [],
    ),
    enabled: true,
    enableCatalogs: false,
    enableSearch: false,
    enableSubtitles: false,
    enableStreams: true,
  );

  static final InstalledAddon zplayHttpBuiltin = InstalledAddon(
    baseUrl: 'builtin:zplayhttp',
    manifest: AddonManifest(
      id: 'builtin.zplayhttp',
      name: 'ZPlayHTTP',
      version: '3.0.0',
      description: 'Built-in fast HTTP stream scrapers (111477, Cinejoy, Vuflix, Movy, RiveStream, Vadapav, VidCore, VidSrc, etc.)',
      resources: ['stream'],
      types: ['movie', 'series', 'anime'],
      idPrefixes: ['tt', 'tmdb:', 'kitsu:', 'mal:'],
      catalogs: [],
    ),
    enabled: true,
    enableCatalogs: false,
    enableSearch: false,
    enableSubtitles: false,
    enableStreams: true,
  );

  // ── Initialization ────────────────────────────────────────────────────

  /// Re-reads the installed list from storage.
  ///
  /// [initialize] loads it once, behind an [_initialized] guard, so a profile
  /// import that replaces `installed_addons_v5` under a running app would keep
  /// the pre-import list in memory - and the next [_save] would write that
  /// stale list back over the imported one. Same path as startup, deliberately:
  /// after a restore the running app should hold what a restart would load.
  Future<void> reload() async {
    _initialized = false;
    await initialize();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);

    if (stored != null) {
      try {
        final list = jsonDecode(stored) as List<dynamic>;
        _addons = list
            .map((e) => InstalledAddon.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _addons = [];
      }
    }

    // First launch → install Cinemeta. It is seeded as a hybrid source: its
    // catalogs mix mainstream and adult titles, so it must keep working with
    // the Adult Content switch off while still being discoverable under `18+`.
    if (_addons.isEmpty) {
      try {
        await addAddon('https://v3-cinemeta.strem.io');
        for (final addon in _addons) {
          if (addon.manifest.id == 'com.linvo.cinemeta' ||
              addon.baseUrl.contains('cinemeta')) {
            addon.adultRating = AddonAdultRating.hybrid;
          }
        }
        await _save();
      } catch (_) {
        // Offline — will retry next time
      }
    }

    // Ensure ZPlay P2P engine is registered in the list
    if (!_addons.any((a) => a.manifest.id == 'builtin.zplay' || a.baseUrl == 'builtin:zplay')) {
      _addons.add(zplayBuiltin);
      await _save();
    }

    // Ensure ZPlayHTTP is registered in the list
    if (!_addons.any((a) => a.manifest.id == 'builtin.zplayhttp' || a.baseUrl == 'builtin:zplayhttp')) {
      _addons.add(zplayHttpBuiltin);
      await _save();
    }

    // Sync P2P state
    final p2pAddon = _addons.firstWhere(
      (a) => a.manifest.id == 'builtin.zplay' || a.baseUrl == 'builtin:zplay',
      orElse: () => zplayBuiltin,
    );
    P2pSettingsService.isP2pEnabled.value = p2pAddon.isStreamsActive;

    _initialized = true;
  }

  // ── Add / Remove / Toggle / Reorder ───────────────────────────────────

  /// Reorder addons by index and persist to storage.
  Future<void> reorderAddons(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _addons.length) return;
    if (newIndex < 0 || newIndex > _addons.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _addons.removeAt(oldIndex);
    _addons.insert(newIndex, item);
    MetadataService.clearCache();
    await _save();
  }

  /// Move addon up by 1 position.
  Future<void> moveAddonUp(int index) async {
    if (index <= 0 || index >= _addons.length) return;
    final item = _addons.removeAt(index);
    _addons.insert(index - 1, item);
    MetadataService.clearCache();
    await _save();
  }

  /// Move addon down by 1 position.
  Future<void> moveAddonDown(int index) async {
    if (index < 0 || index >= _addons.length - 1) return;
    final item = _addons.removeAt(index);
    _addons.insert(index + 1, item);
    MetadataService.clearCache();
    await _save();
  }

  /// Install an addon by its base URL or manifest URL.
  Future<InstalledAddon> addAddon(String url) async {
    final baseUrl = _normalizeBaseUrl(url);

    // Duplicate check by URL
    if (_addons.any((a) => a.baseUrl == baseUrl)) {
      throw Exception('This addon is already installed');
    }

    final manifest = await MetadataService.fetchManifest(baseUrl);

    // Duplicate check by addon ID
    if (_addons.any((a) => a.manifest.id == manifest.id)) {
      throw Exception('An addon with ID "${manifest.id}" is already installed');
    }

    final addon = InstalledAddon(
      baseUrl: baseUrl,
      manifest: manifest,
      enabled: true,
    );

    _addons.add(addon);
    MetadataService.clearCache();
    await _save();
    return addon;
  }

  /// Trims a pasted addon URL down to the base URL form the app stores.
  ///
  /// Placeholders such as `{realdebrid}` are preserved, they are resolved when a
  /// request is built and never persisted as a key.
  String _normalizeBaseUrl(String url) {
    var baseUrl = url.trim();

    // Convert stremio:// or stremio: URI scheme to https://
    if (baseUrl.startsWith('stremio://')) {
      baseUrl = 'https://${baseUrl.substring('stremio://'.length)}';
    } else if (baseUrl.startsWith('stremio:')) {
      baseUrl = 'https://${baseUrl.substring('stremio:'.length)}';
    } else if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
    }

    if (baseUrl.endsWith('/manifest.json')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - '/manifest.json'.length);
    }
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    return baseUrl;
  }

  /// Points an installed addon at a different base URL, keeping its settings.
  ///
  /// Used to connect or disconnect a Debrid configured URL on an addon that is
  /// already installed. [addAddon] refuses this because it rejects duplicate
  /// manifest ids, and a Debrid configured addon keeps the same id (Torrentio
  /// answers `com.stremio.torrentio.addon` for every provider variant), so the
  /// existing entry is replaced in place to preserve the user's ordering and
  /// per-feature toggles. Falls back to a plain install when the id is unknown.
  Future<InstalledAddon> replaceAddonUrl(String addonId, String newBaseUrl) async {
    final index = _addons.indexWhere((a) => a.manifest.id == addonId);
    if (index < 0) {
      return addAddon(newBaseUrl);
    }

    final baseUrl = _normalizeBaseUrl(newBaseUrl);
    final manifest = await MetadataService.fetchManifest(baseUrl);
    final old = _addons[index];
    final updated = InstalledAddon(
      baseUrl: baseUrl,
      manifest: manifest,
      enabled: old.enabled,
      enableCatalogs: old.enableCatalogs,
      enableSearch: old.enableSearch,
      enableSubtitles: old.enableSubtitles,
      enableStreams: old.enableStreams,
      adultRating: old.adultRating,
    );

    _addons[index] = updated;
    MetadataService.clearCache();
    await _save();
    return updated;
  }

  Future<void> removeAddon(String addonId) async {
    if (addonId == 'builtin.zplay' || addonId == 'builtin.zplayhttp') {
      // For built-in providers, disable instead of deleting
      await toggleAddon(addonId, false);
      return;
    }
    _addons.removeWhere((a) => a.manifest.id == addonId);
    MetadataService.clearCache();
    await _save();
  }

  Future<void> toggleAddon(String addonId, bool enabled) async {
    for (final addon in _addons) {
      if (addon.manifest.id == addonId) {
        addon.enabled = enabled;
        break;
      }
    }
    if (addonId == 'builtin.zplay') {
      await P2pSettingsService.setP2pEnabled(enabled);
    }
    MetadataService.clearCache();
    await _save();
  }

  /// Sets how much adult material an addon serves.
  ///
  /// [AddonAdultRating.nsfw] addons are excluded from every active-addon getter
  /// while the global Adult Content switch is off; hybrid addons stay active and
  /// additionally show up in the Discover 18+ view.
  Future<void> setAddonAdultRating(
    String addonId,
    AddonAdultRating rating,
  ) async {
    for (final addon in _addons) {
      if (addon.manifest.id == addonId) {
        addon.adultRating = rating;
        break;
      }
    }
    MetadataService.clearCache();
    await _save();
  }

  Future<void> updateAddonFeature({
    required String addonId,
    bool? enableCatalogs,
    bool? enableSearch,
    bool? enableSubtitles,
    bool? enableStreams,
  }) async {
    for (final addon in _addons) {
      if (addon.manifest.id == addonId) {
        if (enableCatalogs != null) addon.enableCatalogs = enableCatalogs;
        if (enableSearch != null) addon.enableSearch = enableSearch;
        if (enableSubtitles != null) addon.enableSubtitles = enableSubtitles;
        if (enableStreams != null) addon.enableStreams = enableStreams;
        break;
      }
    }
    if (addonId == 'builtin.zplay' && enableStreams != null) {
      await P2pSettingsService.setP2pEnabled(enableStreams);
    }
    MetadataService.clearCache();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_addons.map((a) => a.toJson()).toList()),
    );
  }

  // ── Home sections ─────────────────────────────────────────────────────

  /// Fetch all home page sections from every active addon's catalogs.
  /// Each addon's catalogs are fetched concurrently.
  Future<List<MovieSection>> fetchAllHomeSections() async {
    final active = activeCatalogAddons;

    final addonFutures = active.map(_fetchAddonSections);
    final results = await Future.wait(addonFutures);

    final allSections = <MovieSection>[];
    for (final sections in results) {
      allSections.addAll(sections);
    }

    return allSections;
  }

  /// Streams home page sections one by one as they load, so the UI can populate dynamically.
  Stream<MovieSection> streamHomeSections() async* {
    final active = activeCatalogAddons;
    final List<Future<MovieSection?>> sectionFutures = [];

    // 1. Kick off all network requests concurrently
    for (final addon in active) {
      // Only auto-load catalogs where NO extra has isRequired: true
      final catalogsToFetch = addon.manifest.catalogs.where((c) => c.canAutoLoadOnHome).toList();

      for (final catalog in catalogsToFetch) {
        sectionFutures.add(() async {
          try {
            // Bound each catalog so one slow (e.g. adult) source can't
            // head-of-line-block later sections past the timeout. Yield
            // order is unchanged, so UI stability is preserved.
            final movies = await MetadataService.fetchCatalog(
              baseUrl: addon.baseUrl,
              type: catalog.type,
              catalogId: catalog.id,
            ).timeout(const Duration(seconds: 10));
            if (movies.isEmpty) return null;

            return MovieSection(
              title: _catalogDisplayName(catalog),
              subtitle: addon.manifest.name,
              contentType: catalog.type,
              addonBaseUrl: addon.baseUrl,
              catalog: catalog,
              movies: movies,
            );
          } catch (_) {
            return null; // Gracefully handle failure
          }
        }());
      }
    }

    // 2. Yield them in order so the UI stays stable (top addons appear first)
    for (final future in sectionFutures) {
      final section = await future;
      if (section != null) yield section;
    }
  }

  Future<List<MovieSection>> _fetchAddonSections(
    InstalledAddon addon,
  ) async {
    // Only auto-load catalogs where NO extra has isRequired: true
    final catalogsToFetch = addon.manifest.catalogs.where((c) => c.canAutoLoadOnHome).toList();

    final futures = catalogsToFetch.map((catalog) async {
      try {
        // Same bound as the streamed path: one slow source can't stall the
        // whole home list past the timeout.
        final movies = await MetadataService.fetchCatalog(
          baseUrl: addon.baseUrl,
          type: catalog.type,
          catalogId: catalog.id,
        ).timeout(const Duration(seconds: 10));

        return MovieSection(
          title: _catalogDisplayName(catalog),
          subtitle: addon.manifest.name,
          contentType: catalog.type,
          addonBaseUrl: addon.baseUrl,
          catalog: catalog,
          movies: movies,
        );
      } catch (_) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);

    return results
        .where((s) => s != null && s.movies.isNotEmpty)
        .cast<MovieSection>()
        .toList();
  }

  /// Returns all available catalogs from active catalog addons.
  /// Includes selector-only catalogs (e.g. Tag, Performer) for Discover.
  List<({InstalledAddon addon, AddonCatalog catalog})> getAvailableDiscoverCatalogs({
    String? type,
  }) {
    final active = activeCatalogAddons;
    final list = <({InstalledAddon addon, AddonCatalog catalog})>[];
    for (final addon in active) {
      for (final catalog in addon.manifest.catalogs) {
        if (type != null && type.isNotEmpty && catalog.type != type) {
          continue;
        }
        list.add((addon: addon, catalog: catalog));
      }
    }
    return list;
  }

  /// Search across all active addons that support search.
  /// Optionally streams each [MovieSection] via [onSectionResult] as soon as it arrives.
  /// [onSourceError] is called once per addon whose search threw, naming that
  /// addon: the addon is the unit a user installs and blames, so counting per
  /// catalog would turn one dead multi-catalog addon into several phantom
  /// sources.
  Future<List<MovieSection>> searchAll(
    String query, {
    void Function(MovieSection section)? onSectionResult,
    void Function(String source, Object error)? onSourceError,
  }) async {
    final active = activeSearchAddons;
    final futures = <Future<MovieSection?>>[];
    // Keyed by the addon's position in [active] rather than its name, so two
    // addons sharing a display name stay distinct.
    final failures = <int, Object>{};
    void reportFailure(int addonIndex, String name, Object error) {
      if (failures.containsKey(addonIndex)) return;
      failures[addonIndex] = error;
      onSourceError?.call(name, error);
    }

    for (final addon in active) {
      final addonIndex = active.indexOf(addon);
      final addonName = addon.manifest.name;
      // Skip addons whose search extra is known to be ignored (Cinemeta).
      if (!MetadataService.catalogSearchIsTrustworthy(addon.baseUrl)) continue;

      final searchCatalogs = addon.manifest.catalogs
          .where((c) => c.supportsSearch)
          .toList();

      for (final catalog in searchCatalogs) {
        futures.add(() async {
          try {
            final movies = await MetadataService.search(
              baseUrl: addon.baseUrl,
              type: catalog.type,
              catalogId: catalog.id,
              query: query,
            );

            // An addon that answers with zero matches is healthy and simply
            // has nothing for this query. Only a throw is a dead source.
            if (movies.isEmpty) return null;

            // Sort movies within this section by relevance score
            final sortedMovies = List<Movie>.from(movies);
            sortedMovies.sort((a, b) {
              final scoreA = RelevanceScorer.score(title: a.name, query: query);
              final scoreB = RelevanceScorer.score(title: b.name, query: query);
              return scoreB.compareTo(scoreA);
            });

            final section = MovieSection(
              title: _catalogDisplayName(catalog),
              subtitle: addon.manifest.name,
              contentType: catalog.type,
              addonBaseUrl: addon.baseUrl,
              catalog: catalog,
              movies: sortedMovies,
            );

            onSectionResult?.call(section);
            return section;
          } catch (e) {
            reportFailure(addonIndex, addonName, e);
            return null;
          }
        }());
      }
    }

    final results = await Future.wait(futures);
    final validSections = results
        .where((s) => s != null && s.movies.isNotEmpty)
        .cast<MovieSection>()
        .toList();

    // Sort sections by the relevance score of their top match
    validSections.sort((a, b) {
      final topScoreA = a.movies.isNotEmpty ? RelevanceScorer.score(title: a.movies.first.name, query: query) : 0.0;
      final topScoreB = b.movies.isNotEmpty ? RelevanceScorer.score(title: b.movies.first.name, query: query) : 0.0;
      return topScoreB.compareTo(topScoreA);
    });

    return validSections;
  }

  /// Fetch catalogs filtered by a specific genre across all active addons.
  Future<List<MovieSection>> fetchByGenre(String genre) async {
    final active = activeCatalogAddons;
    final futures = <Future<MovieSection?>>[];

    for (final addon in active) {
      // Find catalogs that explicitly support filtering by genre via their 'extra' properties.
      final genreCatalogs = addon.manifest.catalogs.where((c) {
        final supportsGenre = c.genres.isNotEmpty;
        final isCinemetaTop = addon.manifest.id == 'com.linvo.cinemeta' && c.id == 'top';
        return supportsGenre || isCinemetaTop;
      }).toList();

      for (final catalog in genreCatalogs) {
        futures.add(() async {
          try {
            final movies = await MetadataService.fetchCatalog(
              baseUrl: addon.baseUrl,
              type: catalog.type,
              catalogId: catalog.id,
              genre: genre,
            );

            if (movies.isEmpty) return null;

            return MovieSection(
              title: '${_catalogDisplayName(catalog)} - $genre',
              subtitle: addon.manifest.name,
              contentType: catalog.type,
              addonBaseUrl: addon.baseUrl,
              catalog: catalog,
              movies: movies,
            );
          } catch (_) {
            return null;
          }
        }());
      }
    }

    final results = await Future.wait(futures);
    return results
        .where((s) => s != null && s.movies.isNotEmpty)
        .cast<MovieSection>()
        .toList();
  }

  /// Generate a human-readable name for a catalog.
  String _catalogDisplayName(AddonCatalog catalog) => catalogDisplayName(catalog);

  String catalogDisplayName(AddonCatalog catalog) {
    if (catalog.name != null && catalog.name!.isNotEmpty) {
      return catalog.name!;
    }

    final typeLabel = catalog.type == 'series'
        ? 'Series'
        : (catalog.type == 'anime'
            ? 'Anime'
            : (catalog.type == 'collections' || catalog.type == 'collection'
                ? 'Collections'
                : (catalog.type == 'movie' ? 'Movies' : catalog.type)));

    switch (catalog.id) {
      case 'top':
        return 'Popular $typeLabel';
      case 'year':
        return 'New $typeLabel';
      case 'imdbRating':
        return 'Top Rated $typeLabel';
      default:
        final id = catalog.id;
        final capitalized =
            id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';
        return '$capitalized $typeLabel';
    }
  }
}
