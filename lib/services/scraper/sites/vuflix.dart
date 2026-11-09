import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

class _ProviderInfo {
  final String id;
  final String name;
  const _ProviderInfo({required this.id, required this.name});
}

class _UnwrappedUrl {
  final String url;
  final Map<String, String> headers;
  const _UnwrappedUrl({required this.url, required this.headers});
}

/// Dynamic Vuflix Stream Scraper for ZPlayHTTP.
///
/// Automatically discovers active provider backends via `/api/player/providers`,
/// queries stream sources concurrently, and unpacks `v-relay` / `a-relay` tokens
/// into direct stream endpoints with required provider-specific headers.
class VuflixScraper extends HttpScraper {
  static const _apiBase = 'https://vuflix.co';
  static const _referer = 'https://vuflix.co/';
  static const _origin = 'https://vuflix.co';
  static const _ua = kZplayUserAgent;

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Referer': _referer,
    'Origin': _origin,
    'Accept': 'application/json, text/plain, */*',
  };

  static List<_ProviderInfo>? _cachedProviders;
  static DateTime? _lastProvidersFetch;

  static const _fallbackProviders = [
    _ProviderInfo(id: 'vsembed', name: 'Sigma'),
    _ProviderInfo(id: 'moonflix', name: 'Source 40'),
    _ProviderInfo(id: 'megasource', name: 'Source 39'),
    _ProviderInfo(id: 'hdghar', name: 'Source 44'),
    _ProviderInfo(id: 'moviebox', name: 'Pi'),
    _ProviderInfo(id: 'cineplay', name: '4K'),
    _ProviderInfo(id: 'huhu', name: 'Beta'),
    _ProviderInfo(id: 'bingr', name: 'Upsilon'),
    _ProviderInfo(id: 'onlyflix', name: 'Gamma'),
    _ProviderInfo(id: 'vaplayer', name: 'Alpha'),
    _ProviderInfo(id: 'flixhqz', name: 'Gamma'),
    _ProviderInfo(id: 'castle', name: 'Source 40'),
    _ProviderInfo(id: 'cinejoy', name: '4K2'),
    _ProviderInfo(id: 'filesun', name: 'Tau'),
    _ProviderInfo(id: 'yoru', name: 'Yoru'),
  ];

  /// Dynamically queries active providers from Vuflix, caching results for 15 minutes.
  static Future<List<_ProviderInfo>> _getProviders() async {
    if (_cachedProviders != null &&
        _lastProvidersFetch != null &&
        DateTime.now().difference(_lastProvidersFetch!).inMinutes < 15) {
      return _cachedProviders!;
    }

    try {
      final uri = Uri.parse('$_apiBase/api/player/providers');
      final res = await http
          .get(uri, headers: _defaultHeaders)
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['ok'] == true && data['providers'] is List) {
          final list = <_ProviderInfo>[];
          for (final p in data['providers']) {
            if (p is! Map) continue;
            final id = (p['id'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            final name = (p['publicLabel'] ??
                    p['providerName'] ??
                    p['name'] ??
                    id)
                .toString();
            list.add(_ProviderInfo(id: id, name: name));
          }
          if (list.isNotEmpty) {
            _cachedProviders = list;
            _lastProvidersFetch = DateTime.now();
            return list;
          }
        }
      }
    } catch (_) {}

    return _fallbackProviders;
  }

  /// Unpacks relay URLs (e.g. `v-relay?t=...`, `a-relay?t=...`) to extract the
  /// direct stream URL and the provider's exact HTTP headers (Referer, Origin, etc.).
  static _UnwrappedUrl _unwrapUrl(
    String rawUrl, {
    Map<String, String>? fallbackHeaders,
  }) {
    final defaultH = fallbackHeaders ?? {
      'User-Agent': _ua,
      'Referer': _referer,
      'Origin': _origin,
    };

    if (rawUrl.isEmpty) return _UnwrappedUrl(url: '', headers: defaultH);
    if (!rawUrl.contains('v-relay?t=') && !rawUrl.contains('a-relay?t=')) {
      return _UnwrappedUrl(url: rawUrl, headers: defaultH);
    }

    try {
      final uri = Uri.parse(rawUrl);
      final t = uri.queryParameters['t'];
      if (t == null || t.isEmpty) {
        return _UnwrappedUrl(url: rawUrl, headers: defaultH);
      }

      var b64 = t.replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }

      final jsonStr = utf8.decode(base64Decode(b64));
      final parsed = jsonDecode(jsonStr);
      if (parsed is Map) {
        final directUrl = (parsed['u'] ?? '').toString().trim();
        final headersMap = <String, String>{
          'User-Agent': _ua,
          'Referer': _referer,
          'Origin': _origin,
        };

        if (parsed['h'] is Map) {
          for (final entry in (parsed['h'] as Map).entries) {
            headersMap[entry.key.toString()] = entry.value.toString();
          }
        }

        if (directUrl.isNotEmpty) {
          return _UnwrappedUrl(url: directUrl, headers: headersMap);
        }
      }
    } catch (e) {
      debugPrint('[VuflixScraper] Error decoding relay token: $e');
    }

    return _UnwrappedUrl(url: rawUrl, headers: defaultH);
  }

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) {
    final controller = StreamController<StreamSource>();
    final isTv = (type == 'series' || type == 'tv');
    final mediaType = isTv ? 'tv' : 'movie';

    () async {
      try {
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: mediaType,
          year: year,
        );

        if (tmdbId == null || tmdbId <= 0) {
          debugPrint('[VuflixScraper] Could not resolve TMDb ID for "$title"');
          controller.close();
          return;
        }

        debugPrint(
            '[VuflixScraper] Starting concurrent scrape for "$title" (tmdb: $tmdbId, S:${season}E:$episode)');

        final baseParams = StringBuffer('type=$mediaType&tmdbId=$tmdbId');
        if (isTv) {
          baseParams.write('&season=${season ?? 1}&episode=${episode ?? 1}');
        }

        final providers = await _getProviders();
        final seenUrls = <String>{};

        final providerTasks = providers.map((prov) async {
          try {
            final uri = Uri.parse(
                '$_apiBase/api/player/sources?${baseParams.toString()}&provider=${prov.id}');
            final client = http.Client();
            final res = await client
                .get(uri, headers: _defaultHeaders)
                .timeout(const Duration(seconds: 8));

            if (res.statusCode != 200) {
              client.close();
              return;
            }

            final data = jsonDecode(res.body);
            client.close();

            if (data is! Map || data['ok'] != true || data['sources'] is! List) {
              return;
            }

            final sourcesList = data['sources'] as List;

            for (final item in sourcesList) {
              if (item is! Map) continue;

              final providerName = (item['providerName'] ??
                      item['publicLabel'] ??
                      prov.name)
                  .toString();
              final primaryRawUrl = (item['url'] ?? '').toString().trim();
              final itemType = (item['type'] ?? 'hls').toString().toLowerCase();
              final itemLanguage = (item['language'] ?? '').toString();
              final itemLabel = (item['label'] ?? '').toString();

              // 1. Check quality variants (e.g. 2160p 4K, 1080p, 720p, 480p)
              final qualities = item['qualities'];
              if (qualities is List && qualities.isNotEmpty) {
                for (final q in qualities) {
                  if (q is! Map) continue;
                  final qRawUrl = (q['url'] ?? '').toString().trim();
                  if (qRawUrl.isEmpty) continue;

                  final unwrapped = _unwrapUrl(qRawUrl);
                  if (unwrapped.url.isEmpty || seenUrls.contains(unwrapped.url)) {
                    continue;
                  }
                  seenUrls.add(unwrapped.url);

                  final qQuality = (q['quality'] ?? 'Auto').toString();
                  final qType = (q['type'] ?? itemType).toString().toUpperCase();
                  final streamTitle = '[Vuflix - $providerName] $qQuality';
                  final desc = '$providerName • $qQuality • $qType';

                  if (!controller.isClosed) {
                    controller.add(
                      _buildSource(
                        url: unwrapped.url,
                        title: streamTitle,
                        quality: qQuality,
                        description: desc,
                        headers: unwrapped.headers,
                      ),
                    );
                  }
                }
              }

              // 2. Check candidate mirrors (e.g. Alpha mirror 1, 2, 3)
              final candidates = item['candidates'];
              if (candidates is List && candidates.isNotEmpty) {
                var candIndex = 1;
                for (final c in candidates) {
                  if (c is! Map) continue;
                  final cRawUrl = (c['url'] ?? '').toString().trim();
                  if (cRawUrl.isEmpty) continue;

                  final unwrapped = _unwrapUrl(cRawUrl);
                  if (unwrapped.url.isEmpty || seenUrls.contains(unwrapped.url)) {
                    continue;
                  }
                  seenUrls.add(unwrapped.url);

                  final cQuality = (c['quality'] ?? '1080p').toString();
                  final cType = (c['type'] ?? itemType).toString().toUpperCase();
                  final streamTitle =
                      '[Vuflix - $providerName] Mirror $candIndex • $cQuality';
                  final desc = '$providerName Mirror $candIndex • $cType';
                  candIndex++;

                  if (!controller.isClosed) {
                    controller.add(
                      _buildSource(
                        url: unwrapped.url,
                        title: streamTitle,
                        quality: cQuality,
                        description: desc,
                        headers: unwrapped.headers,
                      ),
                    );
                  }
                }
              }

              // 3. Check multi-language audio tracks with switchable URLs
              final audioTracks = item['audioTracks'];
              if (audioTracks is List && audioTracks.isNotEmpty) {
                for (final a in audioTracks) {
                  if (a is! Map) continue;
                  final aRawUrl =
                      (a['switchUrl'] ?? a['url'] ?? '').toString().trim();
                  if (aRawUrl.isEmpty) continue;

                  final unwrapped = _unwrapUrl(aRawUrl);
                  if (unwrapped.url.isEmpty || seenUrls.contains(unwrapped.url)) {
                    continue;
                  }
                  seenUrls.add(unwrapped.url);

                  final rawLabel = (a['label'] ??
                          a['name'] ??
                          a['language'] ??
                          'Audio')
                      .toString()
                      .trim();
                  final cleanLabel = rawLabel.replaceAll(RegExp(r'\s*audio\s*$', caseSensitive: false), '').trim();
                  final aLabel = cleanLabel.isNotEmpty ? cleanLabel : 'Audio';
                  final streamTitle = '[Vuflix - $providerName] $aLabel Audio';
                  final desc =
                      '$providerName • $aLabel Audio • ${itemType.toUpperCase()}';

                  if (!controller.isClosed) {
                    controller.add(
                      _buildSource(
                        url: unwrapped.url,
                        title: streamTitle,
                        quality: 'HD',
                        description: desc,
                        headers: unwrapped.headers,
                      ),
                    );
                  }
                }
              }

              // 4. Primary URL fallback
              if (primaryRawUrl.isNotEmpty) {
                final unwrapped = _unwrapUrl(primaryRawUrl);
                if (unwrapped.url.isNotEmpty && !seenUrls.contains(unwrapped.url)) {
                  seenUrls.add(unwrapped.url);

                  var displayQuality = (item['quality'] ?? '').toString();
                  if (displayQuality.isEmpty) {
                    displayQuality = itemType == 'mp4' ? 'MP4' : 'HD';
                  }

                  var cleanLabel = itemLabel;
                  if (cleanLabel.isEmpty) {
                    cleanLabel = providerName;
                  }

                  final streamTitle = cleanLabel.startsWith('[')
                      ? cleanLabel
                      : '[Vuflix - $providerName] $displayQuality';
                  final desc = itemLanguage.isNotEmpty
                      ? '$providerName • $itemLanguage • ${itemType.toUpperCase()}'
                      : '$providerName • ${itemType.toUpperCase()}';

                  if (!controller.isClosed) {
                    controller.add(
                      _buildSource(
                        url: unwrapped.url,
                        title: streamTitle,
                        quality: displayQuality,
                        description: desc,
                        headers: unwrapped.headers,
                      ),
                    );
                  }
                }
              }
            }
          } catch (_) {
            // Skip individual provider error
          }
        });

        await Future.wait(providerTasks);
      } catch (e) {
        debugPrint('[VuflixScraper] Error scraping "$title": $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  StreamSource _buildSource({
    required String url,
    required String title,
    required String quality,
    required String description,
    required Map<String, String> headers,
  }) {
    return StreamSource.zplayHttp(
      name: title,
      title: title,
      description: description,
      url: url,
      headers: headers,
    );
  }
}
