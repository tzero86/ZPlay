import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../config/env_service.dart';
import '../../metadata/tmdb_service.dart';
import 'tmdb_helper.dart';

/// Videasy VOD Extractor ported 1:1 from Flyx (videasy.ts).
class VideasyScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _tmdbDirect = 'https://api.themoviedb.org/3';

  /// Scraper API host. There is no default: the upstream developer's host stays
  /// off unless `VIDEASY_API_BASE` names a deployment, and an empty value keeps
  /// the scraper off entirely.
  static String get _apiBase => EnvService.videasyApiBase;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Referer': 'https://player.videasy.to/',
    'Origin': 'https://player.videasy.to',
    'Accept': 'application/json, text/plain, */*',
  };

  static const _providers = [
    {'path': '/cdn/sources-with-title', 'label': 'Yoru'},
    {'path': '/neon2/sources-with-title', 'label': 'Neon'},
    {'path': '/m4uhd/sources-with-title', 'label': 'Breach'},
    {'path': '/meine/sources-with-title', 'label': 'Killjoy'},
    {'path': '/lamovie/sources-with-title', 'label': 'Omen'},
  ];

  static final List<int> _f = [
    1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993,
    2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987,
    1925078388, 2162078206, 2614888103, 3248222580,
  ];

  static final List<int> _magic = [109, 118, 109, 49]; // "mvm1"

  static int _imul(int a, int b) {
    return ((a & 0xffff) * b + (((a >> 16) * b & 0xffff) << 16)) & 0xffffffff;
  }

  static bool _isEvenTri(int e) => (((e * (e + 1)) & 1) == 0);
  static bool _isOddTri(int e) => (((e * (e + 1)) & 1) == 1);

  static int _mix(int e) {
    e &= 0xffffffff;
    e ^= (e >> 16);
    e = _imul(e, 2246822507) & 0xffffffff;
    e ^= (e >> 13);
    e = _imul(e, 3266489909) & 0xffffffff;
    return (e ^ (e >> 16)) & 0xffffffff;
  }

  static int _rotl(int e, int t) {
    e &= 0xffffffff;
    t &= 31;
    if (t == 0) return e & 0xffffffff;
    return (((e << t) & 0xffffffff) | (e >> (32 - t))) & 0xffffffff;
  }

  static int _fnv1a(String e) {
    int t = 2166136261;
    for (int s = 0; s < e.length; s++) {
      t = _imul(t ^ e.codeUnitAt(s), 16777619) & 0xffffffff;
    }
    return _mix(t);
  }

  static int _accSeed(String e) {
    int t = 1732584193;
    for (int s = 0; s < e.length; s++) {
      t = _rotl((t ^ _imul(e.codeUnitAt(s), _f[15 & s])) & 0xffffffff, 5);
    }
    return _mix(t);
  }

  static List<int> _rc4Sbox(String e) {
    final t = List<int>.generate(256, (i) => i);
    int s = 0;
    for (int a = 0; a < 256; a++) {
      s = (s + t[a] + e.codeUnitAt(a % e.length)) & 255;
      final r = t[a];
      t[a] = t[s];
      t[s] = r;
    }
    return t;
  }

  static Map<String, dynamic> _buildState(String seed, int mediaId) {
    if (_isOddTri(seed.length)) {
      return {'S': _rc4Sbox(seed), 'acc': _accSeed(seed)};
    }
    final s = List<int?>.filled(61, null);
    int a = _mix(_fnv1a(seed) ^ _mix((mediaId & 0xffffffff) ^ 2654435769)) & 0xffffffff;
    for (int e = 0; e < 8; e++) {
      if (_isEvenTri(e)) {
        final t = a % 61;
        a = _rotl((a + 2654435769) & 0xffffffff, 7 + (7 & e));
        s[t] = (a ^ _mix(a)) & 0xffffffff;
        a = _mix((a + t) & 0xffffffff);
      } else {
        s[e] = _f[15 & e];
      }
    }
    return {'S': s, 'acc': _mix(2779096485 ^ a) & 0xffffffff};
  }

  static int _nextWord(Map<String, dynamic> state, int counter) {
    final List<int?> r = state['S'];
    int acc = state['acc'];
    final n = acc % 61;
    final bool exists = n < r.length && r[n] != null;
    final i = 0 - (exists ? 1 : 0);
    final l = (exists ? r[n]! : 0) & 0xffffffff;
    final a = (l ^ (_imul(2654435769, counter + 1) & 0xffffffff)) & 0xffffffff;
    int d = (((acc ^ a) & 0xffffffff) | (((acc & a & i) & 0xffffffff))) & 0xffffffff;
    d = (_rotl((d + acc) & 0xffffffff, 31 & n) ^ _rotl(acc, 31 & _imul(n, 7))) & 0xffffffff;
    acc = _mix((d + 2654435769) & 0xffffffff);
    if (n < r.length) r[n] = acc & 0xffffffff;
    state['acc'] = acc;
    return acc & 0xffffffff;
  }

  static Uint8List _keystream(String seed, int mediaId, int len) {
    final state = _buildState(seed, mediaId);
    final out = Uint8List(len);
    int counter = 0;
    int e = 0;
    while (e < len) {
      final t = _nextWord(state, counter++);
      out[e++] = 255 & t;
      if (e < len) out[e++] = (t >> 8) & 255;
      if (e < len) out[e++] = (t >> 16) & 255;
      if (e < len) out[e++] = (t >> 24) & 255;
    }
    return out;
  }

  static String _decryptPayload(String payload, String seed, int mediaId) {
    String normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final r = base64Decode(normalized);
    final o = _keystream(seed, mediaId, r.length);
    final decrypted = Uint8List(r.length);
    for (int e = 0; e < r.length; e++) {
      decrypted[e] = r[e] ^ o[e];
    }
    for (int e = 0; e < _magic.length; e++) {
      if (decrypted[e] != _magic[e]) {
        throw Exception('Videasy decrypt failed');
      }
    }
    return utf8.decode(decrypted.sublist(_magic.length));
  }

  Future<String?> _getSeed(int mediaId) async {
    try {
      final uri = Uri.parse('$_apiBase/seed?mediaId=$mediaId');
      final res = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['seed']?.toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final sources = <StreamSource>[];
    if (_apiBase.isEmpty) return sources;
    final mediaType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';
    final tmdbId = await TmdbHelper.resolveTmdbId(imdbId: imdbId, title: title, type: mediaType, year: year);
    print('[VideasyScraper] Resolved tmdbId: $tmdbId for "$title" (year: $year, imdbId: $imdbId)');
    if (tmdbId == null) return sources;

    try {
      final isTv = (mediaType == 'tv');
      final seed = await _getSeed(tmdbId);
      if (seed == null) return sources;

      // TMDb metadata here is enrichment, not a dependency: the caller's own
      // title/year/imdbId already back these fields, so a keyless install just
      // queries with what it was given instead of `?api_key=` with nothing.
      String mediaTitle = title;
      int? mediaYear = year;
      String targetImdb = imdbId ?? '';

      if (TmdbService.hasScraperKey) {
        try {
          final metaPath = isTv
              ? '/tv/$tmdbId?api_key=${TmdbService.scraperKey}'
              : '/movie/$tmdbId?api_key=${TmdbService.scraperKey}';
          final metaRes = await http.get(Uri.parse('$_tmdbDirect$metaPath'), headers: _defaultHeaders).timeout(const Duration(seconds: 6));
          if (metaRes.statusCode == 200) {
            final meta = jsonDecode(metaRes.body);
            mediaTitle = (meta['title'] ?? meta['name'] ?? title).toString();
            final yStr = (meta['release_date'] ?? meta['first_air_date'] ?? '').toString();
            if (yStr.length >= 4) mediaYear = int.tryParse(yStr.substring(0, 4)) ?? year;
            if (meta['imdb_id'] != null) targetImdb = meta['imdb_id'].toString();
          }
        } catch (_) {}
      }

      final params = <String, String>{
        'title': mediaTitle,
        'mediaType': isTv ? 'tv' : 'movie',
        if (mediaYear != null) 'year': mediaYear.toString(),
        'tmdbId': tmdbId.toString(),
        if (targetImdb.isNotEmpty) 'imdbId': targetImdb,
        if (isTv && season != null) 'seasonId': season.toString(),
        if (isTv && episode != null) 'episodeId': episode.toString(),
        'enc': '2',
        'seed': seed,
      };

      for (final p in _providers) {
        if (sources.length >= 6) break;
        final uri = Uri.parse('$_apiBase${p['path']}').replace(queryParameters: params);

        try {
          final pRes = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 8));
          if (pRes.statusCode != 200) continue;
          String body = pRes.body.trim();
          if (body.startsWith('"') && body.endsWith('"')) {
            body = jsonDecode(body);
          }
          final decryptedJson = _decryptPayload(body, seed, tmdbId);
          final data = jsonDecode(decryptedJson);
          final rawSources = data['sources'] as List?;
          if (rawSources == null) continue;

          for (final s in rawSources) {
            final streamUrl = s['url'] ?? s['file'];
            if (streamUrl == null || !streamUrl.toString().startsWith('http')) continue;
            final q = s['quality']?.toString() ?? 'Auto';
            sources.add(StreamSource(
              name: 'ZPlayHTTP',
              addonName: 'ZPlayHTTP',
              title: 'Videasy ${p['label']} · $q',
              description: 'Videasy Multi-CDN HLS Stream',
              url: streamUrl.toString(),
              headers: {
                'User-Agent': _ua,
                'Referer': 'https://player.videasy.to/',
              },
            ));
          }
        } catch (_) {}
      }
    } catch (e) {
      print('VideasyScraper error: $e');
    }

    print('[VideasyScraper] Found ${sources.length} active stream(s)');
    return sources;
  }
}
