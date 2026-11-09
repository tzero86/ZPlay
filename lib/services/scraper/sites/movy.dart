import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Movy.bz Stream Scraper & Decryptor for ZPlayHTTP.
///
/// Queries all 14 Movy city servers (Miami 4K, Seattle, Denver, Chicago, Dallas, etc.)
/// and decrypts live HLS/m3u8 streaming sources using Movy's custom FNV-1a PRNG cipher.
class MovyScraper extends HttpScraper {
  static const _apiBase = 'https://api.wecollege.net';
  static const _referer = 'https://www.movy.bz/';
  static const _ua = kZplayUserAgent;

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Referer': _referer,
    'Origin': 'https://www.movy.bz',
  };

  static const _magic = [109, 118, 109, 49]; // "mvm1"

  static const _servers = [
    {'endpoint': 'miami', 'name': 'Miami', 'note': 'Original audio (Up to 4K)'},
    {'endpoint': 'seattle', 'name': 'Seattle', 'note': 'Original audio'},
    {'endpoint': 'denver', 'name': 'Denver', 'note': 'Original audio'},
    {'endpoint': 'chicago', 'name': 'Chicago', 'note': 'Original audio'},
    {'endpoint': 'dallas', 'name': 'Dallas', 'note': 'Original audio'},
    {'endpoint': 'atlanta', 'name': 'Atlanta', 'note': 'Original audio'},
    {'endpoint': 'houston', 'name': 'Houston', 'note': 'Original audio'},
    {'endpoint': 'austin', 'name': 'Austin', 'note': 'Original audio'},
    {'endpoint': 'boston', 'name': 'Boston', 'note': 'Original audio'},
    {'endpoint': 'munich', 'name': 'Munich', 'note': 'German audio', 'extra': 'language=german'},
    {'endpoint': 'berlin', 'name': 'Berlin', 'note': 'German audio'},
    {'endpoint': 'paris', 'name': 'Paris', 'note': 'French audio'},
    {'endpoint': 'delhi', 'name': 'Delhi', 'note': 'Hindi audio'},
    {'endpoint': 'cancun', 'name': 'Cancun', 'note': 'Spanish audio'},
  ];

  static final Map<int, _SeedEntry> _seedCache = {};

  static Future<String?> _getSeed(int tmdbId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _seedCache[tmdbId];
    if (cached != null && cached.expiresAt > now + 5000) {
      return cached.seed;
    }

    try {
      final client = http.Client();
      final uri = Uri.parse('$_apiBase/seed?mediaId=$tmdbId');
      final res = await client.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final seed = data['seed']?.toString() ?? '';
        final ttlMs = (data['ttlMs'] as num?)?.toInt() ?? 30000;
        if (seed.isNotEmpty) {
          _seedCache[tmdbId] = _SeedEntry(seed, now + ttlMs);
          return seed;
        }
      }
    } catch (e) {
      debugPrint('[MovyScraper] Failed to fetch seed for TMDB $tmdbId: $e');
    }
    return null;
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
          debugPrint('[MovyScraper] Could not resolve TMDb ID for "$title"');
          controller.close();
          return;
        }

        final seed = await _getSeed(tmdbId);
        if (seed == null || seed.isEmpty) {
          debugPrint('[MovyScraper] Could not acquire seed for TMDb $tmdbId');
          controller.close();
          return;
        }

        debugPrint('[MovyScraper] Starting scrape for "$title" (tmdb: $tmdbId, year: $year, S:${season}E:$episode)');

        final encTitle = Uri.encodeComponent(title);
        final qBuilder = StringBuffer();
        qBuilder.write('title=$encTitle');
        qBuilder.write('&mediaType=$mediaType');
        if (year != null && year > 0) qBuilder.write('&year=$year');
        if (isTv) {
          if (season != null) qBuilder.write('&seasonId=$season');
          if (episode != null) qBuilder.write('&episodeId=$episode');
        }
        qBuilder.write('&tmdbId=$tmdbId');
        if (imdbId != null && imdbId.isNotEmpty) qBuilder.write('&imdbId=$imdbId');
        qBuilder.write('&enc=2&seed=$seed');

        final baseQuery = qBuilder.toString();
        final seenUrls = <String>{};

        final futures = _servers.map((server) async {
          final endpoint = server['endpoint']!;
          final serverName = server['name']!;
          final note = server['note']!;
          final extra = server['extra'];

          var fullUrl = '$_apiBase/$endpoint/sources?$baseQuery';
          if (extra != null && extra.isNotEmpty) {
            fullUrl += '&$extra';
          }

          try {
            final client = http.Client();
            final res = await client
                .get(Uri.parse(fullUrl), headers: _defaultHeaders)
                .timeout(const Duration(seconds: 8));

            if (res.statusCode == 200) {
              final encText = res.body.trim();
              if (encText.isNotEmpty && !encText.startsWith('<')) {
                final decJsonStr = _decrypt(encText, seed, tmdbId);
                if (decJsonStr != null) {
                  final parsed = jsonDecode(decJsonStr);
                  final sourcesList = parsed['sources'];
                  if (sourcesList is List) {
                    for (final src in sourcesList) {
                      if (src is! Map) continue;
                      final streamUrl = src['url']?.toString() ?? '';
                      if (streamUrl.isEmpty || seenUrls.contains(streamUrl)) continue;
                      seenUrls.add(streamUrl);

                      final rawQuality = src['quality']?.toString() ?? 'Auto';
                      final cleanQuality = _formatQuality(rawQuality);
                      final isSpecificAudio = note.toLowerCase().contains('audio') &&
                          !note.toLowerCase().contains('original');
                      final langLabel = isSpecificAudio ? note.split(' ').first : '';
                      final streamTitle = isSpecificAudio
                          ? '[Movy - $serverName · $langLabel] $cleanQuality'
                          : '[Movy - $serverName] $cleanQuality';
                      final desc = '$note • HLS';

                      final source = StreamSource.zplayHttp(
                        name: streamTitle,
                        title: streamTitle,
                        description: desc,
                        url: streamUrl,
                        headers: {
                          'User-Agent': _ua,
                          'Referer': _referer,
                        },
                      );

                      if (!controller.isClosed) {
                        controller.add(source);
                      }
                    }
                  }
                }
              }
            }
          } catch (_) {
            // Silently ignore individual server timeouts
          }
        });

        await Future.wait(futures);
      } catch (e) {
        debugPrint('[MovyScraper] General error: $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
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
    final list = <StreamSource>[];
    await for (final s in scrapeStream(
      type: type,
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
    )) {
      list.add(s);
    }
    return list;
  }

  static String _formatQuality(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k')) return '4K';
    if (lower.contains('1080')) return '1080p';
    if (lower.contains('720')) return '720p';
    if (lower.contains('480')) return '480p';
    if (lower.contains('360')) return '360p';
    if (raw.isNotEmpty) return raw;
    return 'Auto';
  }

  // --- Decryption Cipher Implementation ---

  static int _l(int e) {
    var v = e & 0xFFFFFFFF;
    v = (v ^ (v >>> 16)) & 0xFFFFFFFF;
    v = (v * 0x85ebca6b) & 0xFFFFFFFF;
    v = (v ^ (v >>> 13)) & 0xFFFFFFFF;
    v = (v * 0xc2b2ae35) & 0xFFFFFFFF;
    return (v ^ (v >>> 16)) & 0xFFFFFFFF;
  }

  static int _u(int e, int t) {
    final shift = t & 31;
    if (shift == 0) return e & 0xFFFFFFFF;
    return (((e << shift) & 0xFFFFFFFF) | ((e & 0xFFFFFFFF) >>> (32 - shift))) & 0xFFFFFFFF;
  }

  static int _fnv1a(String str) {
    var t = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) {
      final code = str.codeUnitAt(i);
      t = (((t ^ code) & 0xFFFFFFFF) * 0x1000193) & 0xFFFFFFFF;
    }
    return _l(t);
  }

  static _KeyState _initKeyState(String seed, int tmdbId) {
    final s = List<int>.filled(61, 0);
    final isSet = List<bool>.filled(61, false);
    var r = _l(_fnv1a(seed) ^ _l((tmdbId & 0xFFFFFFFF) ^ 0x9e3779b9));

    for (var e = 0; e < 8; e++) {
      final t = r % 61;
      r = _u((r + 0x9e3779b9) & 0xFFFFFFFF, 7 + (7 & e));
      s[t] = (r ^ _l(r)) & 0xFFFFFFFF;
      isSet[t] = true;
      r = _l((r + t) & 0xFFFFFFFF);
    }

    final acc = _l(0xa5a5a5a5 ^ r);
    return _KeyState(s, isSet, acc);
  }

  static int _nextKeystreamWord(_KeyState state, int t) {
    final r = state.s;
    var nState = state.acc;
    final i = nState % 61;
    final oVal = state.isSet[i] ? -1 : 0;
    final d = state.isSet[i] ? r[i] : 0;
    final c = ((t + 1) * 0x9e3779b9) & 0xFFFFFFFF;
    final a = nState;
    final sVal = d ^ c;
    final h = ((a ^ sVal) | (a & sVal & oVal)) & 0xFFFFFFFF;
    final term1 = _u((h + nState) & 0xFFFFFFFF, 31 & i);
    final term2 = _u(nState, 31 & (i * 7));
    nState = _l(((term1 ^ term2) + 0x9e3779b9) & 0xFFFFFFFF);
    r[i] = nState;
    state.isSet[i] = true;
    state.acc = nState;
    return nState & 0xFFFFFFFF;
  }

  static Uint8List _generateKeyStream(String seed, int tmdbId, int len) {
    final state = _initKeyState(seed, tmdbId);
    final out = Uint8List(len);
    var wordIdx = 0;
    var byteIdx = 0;

    while (byteIdx < len) {
      final word = _nextKeystreamWord(state, wordIdx++);
      out[byteIdx++] = word & 0xFF;
      if (byteIdx < len) out[byteIdx++] = (word >>> 8) & 0xFF;
      if (byteIdx < len) out[byteIdx++] = (word >>> 16) & 0xFF;
      if (byteIdx < len) out[byteIdx++] = (word >>> 24) & 0xFF;
    }
    return out;
  }

  static String? _decrypt(String cipherB64, String seed, int tmdbId) {
    try {
      var normalized = cipherB64.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final cipherBytes = base64.decode(normalized);
      if (cipherBytes.length <= _magic.length) return null;

      final ks = _generateKeyStream(seed, tmdbId, cipherBytes.length);
      for (var i = 0; i < cipherBytes.length; i++) {
        cipherBytes[i] = cipherBytes[i] ^ ks[i];
      }

      for (var k = 0; k < _magic.length; k++) {
        if (cipherBytes[k] != _magic[k]) {
          return null;
        }
      }

      final payload = cipherBytes.sublist(_magic.length);
      return utf8.decode(payload);
    } catch (e) {
      return null;
    }
  }
}

class _SeedEntry {
  _SeedEntry(this.seed, this.expiresAt);
  final String seed;
  final int expiresAt;
}

class _KeyState {
  _KeyState(this.s, this.isSet, this.acc);
  final List<int> s;
  final List<bool> isSet;
  int acc;
}
