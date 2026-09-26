import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_detail.dart';
import '../addon/addon_url_resolver.dart';

/// Generic service for any Stremio-protocol addon.
/// All methods are static — provide the addon's base URL and they hit the
/// standard Stremio endpoints (catalog, meta, search).
class MetadataService {
  MetadataService._();

  static final Map<String, List<Movie>> _catalogCache = {};
  static final Map<String, MovieDetail> _metaCache = {};

  /// Raw IMDb suggestion bodies, keyed by request URL. Type and limit filters
  /// are applied when mapping, so one fetch serves every variant of a query.
  static final Map<String, String> _suggestionCache = {};

  /// Clear the memory cache (e.g. when addons change)
  static void clearCache() {
    _catalogCache.clear();
    _metaCache.clear();
    _suggestionCache.clear();
  }

  /// Clear catalog/search entries only (e.g. when the adult switch changes
  /// which addons contribute content). Per-title details in [_metaCache]
  /// are kept: they are not adult-sensitive.
  static void clearCatalogCache() {
    _catalogCache.clear();
  }

  // ── Manifest ──────────────────────────────────────────────────────────

  /// Fetch and parse a manifest from any Stremio addon.
  static Future<AddonManifest> fetchManifest(String baseUrl) async {
    final resolvedBaseUrl = await AddonUrlResolver.resolve(baseUrl);
    final url = '$resolvedBaseUrl/manifest.json';
    var response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200 &&
        !resolvedBaseUrl.contains('/%7B') &&
        !resolvedBaseUrl.contains('/{}')) {
      try {
        final configFallback = '$resolvedBaseUrl/%7B%7D/manifest.json';
        final fallbackResp = await http.get(
          Uri.parse(configFallback),
          headers: {'Accept': 'application/json'},
        );
        if (fallbackResp.statusCode == 200) {
          response = fallbackResp;
        }
      } catch (_) {}
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch manifest (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AddonManifest.fromJson(json);
  }

  // ── Catalog ───────────────────────────────────────────────────────────

  /// Generically builds a Stremio v3 catalog request URL:
  /// - Without extras: `/catalog/{type}/{id}.json`
  /// - With extras: `/catalog/{type}/{id}/{extraProps}.json`
  static String buildCatalogUrl({
    required String baseUrl,
    required String type,
    required String catalogId,
    Map<String, String>? extraParams,
  }) {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final cleanType = Uri.encodeComponent(type);
    final cleanId = Uri.encodeComponent(catalogId);

    if (extraParams != null && extraParams.isNotEmpty) {
      final pairs = <String>[];
      extraParams.forEach((key, val) {
        final k = key.trim();
        final v = val.trim();
        if (k.isNotEmpty && v.isNotEmpty) {
          pairs.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}');
        }
      });
      if (pairs.isNotEmpty) {
        return '$effectiveBaseUrl/catalog/$cleanType/$cleanId/${pairs.join("&")}.json';
      }
    }

    return '$effectiveBaseUrl/catalog/$cleanType/$cleanId.json';
  }

  /// Fetch catalog items from any addon using generic extras or legacy genre/skip parameters.
  static Future<List<Movie>> fetchCatalog({
    required String baseUrl,
    required String type,
    required String catalogId,
    String? genre,
    int? skip,
    Map<String, String>? extraParams,
  }) async {
    final resolvedBaseUrl = await AddonUrlResolver.resolve(baseUrl);
    final effectiveBaseUrl = (resolvedBaseUrl.trim().isEmpty || !resolvedBaseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (resolvedBaseUrl.endsWith('/') ? resolvedBaseUrl.substring(0, resolvedBaseUrl.length - 1) : resolvedBaseUrl);

    final mergedExtras = <String, String>{};
    if (extraParams != null) {
      mergedExtras.addAll(extraParams);
    }
    if (genre != null && genre.trim().isNotEmpty) {
      mergedExtras['genre'] = genre.trim();
    }
    if (skip != null && skip > 0) {
      mergedExtras['skip'] = skip.toString();
    }

    final url = buildCatalogUrl(
      baseUrl: effectiveBaseUrl,
      type: type,
      catalogId: catalogId,
      extraParams: mergedExtras.isNotEmpty ? mergedExtras : null,
    );

    if (_catalogCache.containsKey(url)) {
      return List.from(_catalogCache[url]!);
    }

    var response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 404 &&
        !effectiveBaseUrl.contains('/%7B') &&
        !effectiveBaseUrl.contains('/{}')) {
      try {
        final configFallbackUrl = buildCatalogUrl(
          baseUrl: '$effectiveBaseUrl/%7B%7D',
          type: type,
          catalogId: catalogId,
          extraParams: mergedExtras.isNotEmpty ? mergedExtras : null,
        );
        final fallbackResp = await http.get(
          Uri.parse(configFallbackUrl),
          headers: {'Accept': 'application/json'},
        );
        if (fallbackResp.statusCode == 200) {
          response = fallbackResp;
        }
      } catch (_) {}
    }

    if (response.statusCode != 200) {
      throw Exception('Catalog fetch failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final metas = decoded['metas'] as List<dynamic>? ?? [];

    final result = metas
        .map((item) => Movie.fromJson(item as Map<String, dynamic>, effectiveBaseUrl))
        .where((movie) => movie.id.isNotEmpty && movie.name.isNotEmpty)
        .toList();

    _catalogCache[url] = result;
    return List.from(result);
  }

  // ── Search ────────────────────────────────────────────────────────────

  /// Search an addon's catalog using generic /catalog/{type}/{id}/search={query}.json.
  static Future<List<Movie>> search({
    required String baseUrl,
    required String type,
    required String catalogId,
    required String query,
    int? skip,
    Map<String, String>? extraParams,
  }) async {
    final resolvedBaseUrl = await AddonUrlResolver.resolve(baseUrl);
    final effectiveBaseUrl = (resolvedBaseUrl.trim().isEmpty || !resolvedBaseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (resolvedBaseUrl.endsWith('/') ? resolvedBaseUrl.substring(0, resolvedBaseUrl.length - 1) : resolvedBaseUrl);

    final mergedExtras = <String, String>{'search': query.trim()};
    if (extraParams != null) {
      mergedExtras.addAll(extraParams);
    }
    if (skip != null && skip > 0) {
      mergedExtras['skip'] = skip.toString();
    }

    final url = buildCatalogUrl(
      baseUrl: effectiveBaseUrl,
      type: type,
      catalogId: catalogId,
      extraParams: mergedExtras,
    );

    // We can cache searches too!
    if (_catalogCache.containsKey(url)) {
      return List.from(_catalogCache[url]!);
    }

    var response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 404 &&
        !effectiveBaseUrl.contains('/%7B') &&
        !effectiveBaseUrl.contains('/{}')) {
      try {
        final configFallbackUrl = buildCatalogUrl(
          baseUrl: '$effectiveBaseUrl/%7B%7D',
          type: type,
          catalogId: catalogId,
          extraParams: mergedExtras,
        );
        final fallbackResp = await http.get(
          Uri.parse(configFallbackUrl),
          headers: {'Accept': 'application/json'},
        );
        if (fallbackResp.statusCode == 200) {
          response = fallbackResp;
        }
      } catch (_) {}
    }

    if (response.statusCode != 200) return [];
    
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) return [];

    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final metas = decoded['metas'] as List<dynamic>? ?? [];
      
      final result = metas
          .map((item) => Movie.fromJson(item as Map<String, dynamic>, effectiveBaseUrl))
          .where((movie) => movie.id.isNotEmpty && movie.name.isNotEmpty)
          .toList();
          
      _catalogCache[url] = result;
      return List.from(result);
    } catch (e) {
      return [];
    }
  }

  /// Whether an addon actually honours the `search` catalog extra. Cinemeta
  /// advertises the extra but ignores it: measured queries all return the same
  /// recency list, so its search catalogs are skipped instead of shown.
  static bool catalogSearchIsTrustworthy(String baseUrl) =>
      !baseUrl.toLowerCase().contains('cinemeta');

  // ── Meta (full details) ───────────────────────────────────────────────

  /// Fetch detailed metadata (background, description, rating, genres, etc.)
  static Future<MovieDetail?> fetchMeta({
    required String baseUrl,
    required String type,
    required String imdbId,
  }) async {
    final resolvedBaseUrl = await AddonUrlResolver.resolve(baseUrl);
    final effectiveBaseUrl = (resolvedBaseUrl.trim().isEmpty || !resolvedBaseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (resolvedBaseUrl.endsWith('/') ? resolvedBaseUrl.substring(0, resolvedBaseUrl.length - 1) : resolvedBaseUrl);

    final encodedId = Uri.encodeComponent(imdbId);
    final url = '$effectiveBaseUrl/meta/$type/$encodedId.json';

    if (_metaCache.containsKey(url)) {
      return _metaCache[url];
    }

    http.Response? response;
    try {
      response = await http.get(Uri.parse(url));
    } catch (_) {}

    // Fallback 1: If 404 and baseUrl lacks config prefix, retry with /%7B%7D
    if ((response == null || response.statusCode == 404) &&
        !effectiveBaseUrl.contains('/%7B') &&
        !effectiveBaseUrl.contains('/{}')) {
      try {
        final configUrl = '$effectiveBaseUrl/%7B%7D/meta/$type/$encodedId.json';
        final configResp = await http.get(Uri.parse(configUrl));
        if (configResp.statusCode == 200) {
          response = configResp;
        }
      } catch (_) {}
    }

    // Fallback 2: If 404 and type was 'collections' or 'collection', try 'movie'
    if ((response == null || response.statusCode == 404) &&
        (type == 'collections' || type == 'collection')) {
      try {
        final movieUrl = '$effectiveBaseUrl/meta/movie/$encodedId.json';
        var movieResp = await http.get(Uri.parse(movieUrl));
        if (movieResp.statusCode == 404 &&
            !effectiveBaseUrl.contains('/%7B') &&
            !effectiveBaseUrl.contains('/{}')) {
          final configMovieUrl = '$effectiveBaseUrl/%7B%7D/meta/movie/$encodedId.json';
          movieResp = await http.get(Uri.parse(configMovieUrl));
        }
        if (movieResp.statusCode == 200) {
          response = movieResp;
        }
      } catch (_) {}
    }

    // Fallback 3: If 404 and type was 'movie' but id starts with 'ctmdb.', try 'collections'
    if ((response == null || response.statusCode == 404) &&
        type == 'movie' &&
        imdbId.startsWith('ctmdb.')) {
      try {
        final collUrl = '$effectiveBaseUrl/meta/collections/$encodedId.json';
        var collResp = await http.get(Uri.parse(collUrl));
        if (collResp.statusCode == 404 &&
            !effectiveBaseUrl.contains('/%7B') &&
            !effectiveBaseUrl.contains('/{}')) {
          final configCollUrl = '$effectiveBaseUrl/%7B%7D/meta/collections/$encodedId.json';
          collResp = await http.get(Uri.parse(configCollUrl));
        }
        if (collResp.statusCode == 200) {
          response = collResp;
        }
      } catch (_) {}
    }

    if (response == null || response.statusCode != 200) return null;
    
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) return null;

    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final meta = decoded['meta'] as Map<String, dynamic>?;

      if (meta == null) return null;
      
      final result = MovieDetail.fromJson(meta);
      _metaCache[url] = result;
      return result;
    } catch (e) {
      return null;
    }
  }

  // ── Title suggestions (keyless) ───────────────────────────────────────

  static const String _suggestionBaseUrl = 'https://v3-cinemeta.strem.io';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  /// Keyless title lookup against IMDb's suggestion endpoint. Returns real
  /// imdb ids, so a result is immediately tappable through the normal details
  /// path. Results are filtered to titles (tt-prefixed) and mapped to [Movie]
  /// with baseUrl https://v3-cinemeta.strem.io.
  static Future<List<Movie>> suggestionSearch({
    required String query,
    String? type,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final encoded = Uri.encodeComponent(trimmed);
    final url = 'https://v3.sg.media-imdb.com/suggestion/x/$encoded'
        '.json?includeVideos=0';

    final cached = _suggestionCache[url];
    if (cached != null) {
      return parseSuggestions(cached, type: type, limit: limit);
    }

    String body;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': _browserUserAgent,
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      body = response.body;
    } catch (_) {
      return [];
    }

    _suggestionCache[url] = body;
    return parseSuggestions(body, type: type, limit: limit);
  }

  /// Maps an IMDb suggestion response body to [Movie]s. Kept separate from
  /// [suggestionSearch] so the mapping is testable without the network.
  static List<Movie> parseSuggestions(
    String body, {
    String? type,
    int limit = 10,
  }) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return [];

    List<dynamic> entries;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return [];
      entries = decoded['d'] as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }

    final result = <Movie>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;

      // Suggestion rows also cover people (`nm`) and companies (`in`).
      final id = entry['id']?.toString() ?? '';
      if (!id.startsWith('tt')) continue;

      final name = entry['l']?.toString().trim() ?? '';
      if (name.isEmpty) continue;

      // Unrecognised kinds are only kept when the caller accepts either type.
      final resolvedType = _suggestionType(entry['q']);
      if (type != null && resolvedType != type) continue;

      final year = entry['y']?.toString().trim();
      result.add(Movie(
        id: id,
        name: name,
        year: (year == null || year.isEmpty) ? null : year,
        type: resolvedType ?? 'movie',
        addonBaseUrl: _suggestionBaseUrl,
      ));

      if (result.length >= limit) break;
    }

    return result;
  }

  /// Suggestion rows carry a free-form kind in `q`: `feature`/`movie` are
  /// films, anything containing `series` is a show, the rest is neither
  /// (e.g. `video`).
  static String? _suggestionType(dynamic q) {
    final kind = q?.toString().toLowerCase() ?? '';
    if (kind == 'feature' || kind == 'movie') return 'movie';
    if (kind.contains('series')) return 'series';
    return null;
  }

  /// Resolves a title into a real imdb-backed [Movie] via the keyless IMDb
  /// suggestion endpoint, which is used instead of addon search because
  /// Cinemeta ignores the `search` extra and only ever returned junk.
  static Future<Movie?> findMovieByTitle({
    required String title,
    String? type,
    int? year,
    String? preferredBaseUrl,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return null;

    // The resolved title is served from the addon the caller came from, except
    // for the bestsimilar scraper, which serves no meta.
    final targetBaseUrl = (preferredBaseUrl != null &&
            preferredBaseUrl.startsWith('http') &&
            !preferredBaseUrl.contains('bestsimilar'))
        ? preferredBaseUrl
        : _suggestionBaseUrl;

    final isPreferredTv = (type == 'series' || type == 'tv' || type == 'anime');
    final firstType = isPreferredTv ? 'series' : 'movie';
    final secondType = isPreferredTv ? 'movie' : 'series';

    // Query both types to compare candidates across series and movie suggestions
    final results = await Future.wait([
      suggestionSearch(query: query, type: firstType),
      suggestionSearch(query: query, type: secondType),
    ]);

    final allCandidates = <Movie>[...results[0], ...results[1]];
    if (allCandidates.isEmpty) return null;

    final qLower = query.toLowerCase();

    // Scoring:
    // +100 for exact title match
    // +60 for exact year match (or year in range e.g. 2013-2018)
    // +20 for matching preferred type
    // +30 for title startsWith
    Movie? bestMatch;
    int highestScore = -1;

    for (final c in allCandidates) {
      int score = 0;
      final cName = c.name.toLowerCase().trim();
      final cYear = (c.year ?? '').trim();

      if (cName == qLower) {
        score += 100;
      } else if (cName.startsWith(qLower)) {
        score += 30;
      }

      if (year != null && cYear.isNotEmpty) {
        if (cYear.startsWith('$year') || cYear.contains('$year')) {
          score += 60;
        }
      }

      if (type != null) {
        final isCTv = (c.type == 'series' || c.type == 'tv' || c.type == 'anime');
        if (isCTv == isPreferredTv) {
          score += 20;
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestMatch = c;
      }
    }

    final best = bestMatch ?? allCandidates.first;
    if (best.addonBaseUrl == targetBaseUrl) return best;

    return Movie(
      id: best.id,
      name: best.name,
      poster: best.poster,
      year: best.year,
      type: best.type,
      addonBaseUrl: targetBaseUrl,
      imdbRating: best.imdbRating,
    );
  }
}
