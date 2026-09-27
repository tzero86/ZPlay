import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/iptv/iptv_models.dart';
import 'pastesh_decryptor.dart';
import '../player/player_settings.dart';

/// Xtream-Codes player_api client. Login + categories + streams + episodes + EPG.
class IptvClient {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static String _enc(String s) => Uri.encodeComponent(s);

  static Future<String?> _httpGet(String url, {Duration? timeout}) async {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = _ua
        ..headers['Accept'] = 'application/json,*/*';
      final stream =
          await req.send().timeout(timeout ?? const Duration(seconds: 10));
      if (stream.statusCode < 200 || stream.statusCode >= 300) return null;
      return await stream.stream.bytesToString();
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> login(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final url =
        '${p.url}/player_api.php?username=${_enc(p.username)}&password=${_enc(p.password)}';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return null;
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final info = (root['user_info'] as Map<String, dynamic>?) ?? root;
      final auth = info['auth']?.toString();
      final status = (info['status']?.toString() ?? '').toLowerCase();
      final ok = auth == '1' || status == 'active' || root.containsKey('user_info');
      if (!ok) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  static Future<VerifiedPortal?> verifyOrNull(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final info = await login(p, timeout: timeout);
    if (info == null) return null;
    return VerifiedPortal(
      portal: p,
      name: (info['username']?.toString() ?? '').isNotEmpty
          ? info['username'].toString()
          : p.username,
      expiry: _formatExpiry(info['exp_date']?.toString()),
      maxConnections: info['max_connections']?.toString() ?? '1',
      activeConnections: info['active_cons']?.toString() ?? '0',
    );
  }

  static String _formatExpiry(String? raw) {
    if (raw == null) return 'Unlimited';
    final ts = int.tryParse(raw);
    if (ts == null) return 'Unlimited';
    try {
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  static Future<List<IptvCategory>> categories(
      IptvPortal p, IptvSection kind) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_categories',
      IptvSection.vod => 'get_vod_categories',
      IptvSection.series => 'get_series_categories',
    };
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final text = await _httpGet(url, timeout: const Duration(seconds: 8));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr
          .map((e) {
            final o = e as Map<String, dynamic>;
            return IptvCategory(
              id: o['category_id']?.toString() ?? '',
              name: o['category_name']?.toString() ?? '',
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvStream>> streams(
      IptvPortal p, IptvSection kind, String categoryId) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_streams',
      IptvSection.vod => 'get_vod_streams',
      IptvSection.series => 'get_series',
    };
    final base = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final url = categoryId.isEmpty ? base : '$base&category_id=${_enc(categoryId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        final ext = switch (kind) {
          IptvSection.live => 'ts',
          IptvSection.vod => () {
              final v = o['container_extension']?.toString() ?? '';
              return v.isEmpty ? 'mp4' : v;
            }(),
          IptvSection.series => '',
        };
        final id = switch (kind) {
          IptvSection.series => () {
              final v = o['series_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
          _ => () {
              final v = o['stream_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
        };
        return IptvStream(
          streamId: id,
          name: () {
            final n = o['name']?.toString() ?? '';
            return n.isEmpty ? (o['title']?.toString() ?? '') : n;
          }(),
          icon: () {
            final i = o['stream_icon']?.toString() ?? '';
            return i.isEmpty ? (o['cover']?.toString() ?? '') : i;
          }(),
          categoryId: o['category_id']?.toString() ?? '',
          containerExt: ext,
          epgChannelId: o['epg_channel_id']?.toString() ?? '',
          kind: switch (kind) {
            IptvSection.live => 'live',
            IptvSection.vod => 'vod',
            IptvSection.series => 'series',
          },
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvEpisode>> seriesEpisodes(
      IptvPortal p, String seriesId) async {
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=get_series_info&series_id=${_enc(seriesId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final episodesObj = root['episodes'] as Map<String, dynamic>?;
      if (episodesObj == null) return [];
      final out = <IptvEpisode>[];
      episodesObj.forEach((seasonKey, value) {
        final arr = value as List?;
        if (arr == null) return;
        final seasonNum = int.tryParse(seasonKey) ?? 0;
        for (final e in arr) {
          final o = e as Map<String, dynamic>?;
          if (o == null) continue;
          final info = o['info'] as Map<String, dynamic>?;
          out.add(IptvEpisode(
            id: o['id']?.toString() ?? '',
            title: o['title']?.toString() ?? '',
            containerExt: () {
              final c = o['container_extension']?.toString() ?? '';
              return c.isEmpty ? 'mp4' : c;
            }(),
            season: seasonNum,
            episode: (o['episode_num'] is num)
                ? (o['episode_num'] as num).toInt()
                : (int.tryParse(o['episode_num']?.toString() ?? '') ?? 0),
            plot: info?['plot']?.toString() ?? '',
            image: info?['movie_image']?.toString() ?? '',
          ));
        }
      });
      out.sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episode.compareTo(b.episode);
      });
      return out;
    } catch (_) {
      return [];
    }
  }

  static String streamUrl(IptvPortal p, IptvStream s) {
    final user = _enc(p.username);
    final pass = _enc(p.password);
    switch (s.kind) {
      case 'live':
        return '${p.url}/live/$user/$pass/${s.streamId}.${s.containerExt}';
      case 'vod':
        return '${p.url}/movie/$user/$pass/${s.streamId}.${s.containerExt}';
      default:
        return '';
    }
  }

  static String episodeUrl(IptvPortal p, IptvEpisode e) =>
      '${p.url}/series/${_enc(p.username)}/${_enc(p.password)}/${e.id}.${e.containerExt}';

  /// Fetches the next [limit] EPG programmes for [streamId] via Xtream's
  /// `get_short_epg`. Returns an empty list on any failure.
  static Future<List<EpgEntry>> shortEpg(
    IptvPortal p,
    String streamId, {
    int limit = 2,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (streamId.isEmpty) return const [];
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}'
        '&action=get_short_epg&stream_id=${_enc(streamId)}&limit=$limit';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return const [];
    try {
      final root = json.decode(text);
      final List arr = root is Map<String, dynamic>
          ? (root['epg_listings'] as List? ?? const [])
          : (root is List ? root : const []);
      DateTime? parseTs(dynamic v) {
        if (v == null) return null;
        final s = v.toString();
        final secs = int.tryParse(s);
        if (secs != null && secs > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true)
              .toLocal();
        }
        try {
          return DateTime.parse(s.replaceFirst(' ', 'T')).toLocal();
        } catch (_) {
          return null;
        }
      }

      String decode64(dynamic v) {
        if (v == null) return '';
        final s = v.toString();
        if (s.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(s), allowMalformed: true).trim();
        } catch (_) {
          return s;
        }
      }

      final out = <EpgEntry>[];
      for (final e in arr) {
        if (e is! Map<String, dynamic>) continue;
        final start = parseTs(e['start_timestamp']) ?? parseTs(e['start']);
        final stop = parseTs(e['stop_timestamp']) ?? parseTs(e['end']);
        if (start == null || stop == null) continue;
        out.add(EpgEntry(
          title: decode64(e['title']),
          description: decode64(e['description']),
          start: start,
          stop: stop,
        ));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    } catch (_) {
      return const [];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verifier — bounded concurrency, abort once `target` portals authenticated.
// ─────────────────────────────────────────────────────────────────────────────
class IptvVerifier {
  static const _parallel = 4;

  static Future<List<VerifiedPortal>> verifyUntil({
    required List<IptvPortal> portals,
    int target = 5,
    void Function(int checked, int total, int alive)? onProgress,
    void Function(VerifiedPortal v)? onAlive,
    void Function(IptvPortal p)? onAttempted,
    bool Function()? isCancelled,
  }) async {
    if (portals.isEmpty) return const [];

    var nextIdx = 0;
    var checked = 0;
    final alive = <VerifiedPortal>[];
    final completer = Completer<void>();
    var stopped = false;

    void stop() {
      if (!stopped) {
        stopped = true;
        if (!completer.isCompleted) completer.complete();
      }
    }

    Future<void> worker() async {
      while (!stopped) {
        if (isCancelled?.call() == true) {
          stop();
          break;
        }
        if (alive.length >= target) {
          stop();
          break;
        }
        final idx = nextIdx++;
        if (idx >= portals.length) break;
        onAttempted?.call(portals[idx]);
        VerifiedPortal? v;
        try {
          v = await IptvClient.verifyOrNull(portals[idx]);
        } catch (_) {
          v = null;
        }
        if (stopped) break;
        checked++;
        if (v != null && alive.length < target) {
          alive.add(v);
          onAlive?.call(v);
        }
        onProgress?.call(checked, portals.length, alive.length);
        if (alive.length >= target) {
          stop();
          break;
        }
      }
    }

    final workers = List.generate(
      _parallel.clamp(1, portals.length),
      (_) => worker(),
    );
    await Future.any([
      Future.wait(workers),
      completer.future,
    ]);
    return List.unmodifiable(alive);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alive checker — partial-content stream sniffing (24 concurrency).
// ─────────────────────────────────────────────────────────────────────────────
class AliveProgress {
  final int checked;
  final int total;
  final int alive;
  const AliveProgress(this.checked, this.total, this.alive);
}

class IptvAliveChecker {
  static const int _minBytes = 16 * 1024;
  static const int _maxBytes = 64 * 1024;
  static const Duration _timeout = Duration(seconds: 8);
  static const int _concurrency = 24;

  static Future<void> launchCheck({
    required List<MapEntry<String, String>> streams,
    required Future<void> Function(String id, bool alive) onResult,
    required Future<void> Function(AliveProgress p) onProgress,
    required Future<void> Function() onDone,
    bool Function()? isCancelled,
  }) async {
    var checked = 0;
    var alive = 0;
    final total = streams.length;
    final pending = List<MapEntry<String, String>>.from(streams);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        if (pending.isEmpty) return;
        final job = pending.removeAt(0);
        final ok = await _isAlive(job.value);
        if (isCancelled?.call() == true) return;
        checked++;
        if (ok) alive++;
        await onResult(job.key, ok);
        await onProgress(AliveProgress(checked, total, alive));
      }
    }

    final workers = List.generate(_concurrency, (_) => worker());
    await Future.wait(workers);
    if (isCancelled?.call() != true) await onDone();
  }

  static Future<bool> _isAlive(String url) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers.addAll(PlayerSettings.resolveStreamHeaders(
          url,
          const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
        ))
        ..headers['Range'] = 'bytes=0-${_maxBytes - 1}';
      final resp = await client.send(req).timeout(_timeout);
      final code = resp.statusCode;
      if (code != 206 && (code < 200 || code >= 300)) return false;
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      final cl = int.tryParse(resp.headers['content-length'] ?? '') ?? -1;
      if (_isDeadContentType(ct)) return false;

      final buf = <int>[];
      var ended = true;
      try {
        await for (final chunk in resp.stream.timeout(_timeout)) {
          buf.addAll(chunk);
          if (buf.length >= _maxBytes) {
            ended = false;
            break;
          }
          if (buf.length >= _minBytes) {
            ended = false;
            break;
          }
        }
      } catch (_) {}

      final isM3U8 = ct.contains('mpegurl') || url.toLowerCase().contains('.m3u8');
      if (isM3U8) {
        final headStr = utf8.decode(
            buf.sublist(0, buf.length < 1024 ? buf.length : 1024),
            allowMalformed: true);
        return headStr.contains('#EXTM3U');
      }
      if (ended && buf.length < _minBytes) return false;
      if (cl >= 1 && cl <= 5000000) return false;

      // MPEG-TS sync byte (0x47)
      if (buf.isNotEmpty && buf[0] == 0x47) {
        var validTs = true;
        var checkedPackets = 0;
        var i = 0;
        while (i < buf.length - 188 && checkedPackets < 10) {
          if (buf[i] != 0x47) {
            validTs = false;
            break;
          }
          checkedPackets++;
          i += 188;
        }
        if (validTs && checkedPackets >= 3) return true;
      }
      // MP4 ftyp
      if (buf.length >= 8) {
        final s = String.fromCharCodes(buf.sublist(4, 8));
        if (s == 'ftyp') return true;
      }
      if (_hasVideoSignature(buf)) return true;
      if (buf.length >= 32 * 1024) return true;
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static bool _isDeadContentType(String ct) =>
      ct.contains('text/html') ||
      ct.contains('application/json') ||
      ct.contains('text/xml') ||
      ct.contains('text/plain');

  static bool _hasVideoSignature(List<int> buf) {
    if (buf.length < 4) return false;
    if (buf[0] == 0x47) return true;
    if (buf.length >= 7) {
      final s = String.fromCharCodes(buf.sublist(0, 7));
      if (s == '#EXTM3U') return true;
    }
    if (buf.length >= 4) {
      final s = String.fromCharCodes(buf.sublist(0, 4));
      if (s == '#EXT') return true;
    }
    if (buf[0] == 0xFF && (buf[1] & 0xE0) == 0xE0) return true;
    if (buf[0] == 0x1A && buf[1] == 0x45 && buf[2] == 0xDF && buf[3] == 0xA3) {
      return true;
    }
    if (buf[0] == 0x4F && buf[1] == 0x67 && buf[2] == 0x67 && buf[3] == 0x53) {
      return true;
    }
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x00 && buf[3] == 0x01) {
      return true;
    }
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x01 && (buf[3] & 0xFF) >= 0xB0) {
      return true;
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalog Xtream-Codes scraper
// ─────────────────────────────────────────────────────────────────────────────

enum CatalogSource {
  cloudVault('Cloud Vault', 'High-speed cloud database with 9,000+ live IPTV servers'),
  reddit('Reddit', 'Live scrapers from Reddit IPTV subreddits');

  final String label;
  final String description;
  const CatalogSource(this.label, this.description);
}

class IptvScraper {
  static const _cloudVaultPrimaryUrl =
      'https://pub-38f23eb5f3304328b9774fadfa233a38.r2.dev/xtreamity-plus-db.csv.gz';
  static const _cloudVaultBackupUrl =
      'https://s3.us-west-004.backblazeb2.com/Xtream-STBemu/xtreamity-plus-db.csv.gz';

  static List<IptvPortal>? _cachedCloudPortals;
  static bool _isLoadingCloudPortals = false;

  static const _catalogSubs = ['IPTV_ZONENEW', 'FreeIPTV', 'iptvguru', 'IPTVfree'];
  static const _oauthUa =
      'android:io.github.tzero86.zplay:v1.2.1 (+https://github.com/tzero86/ZPlay)';
  static const _oauthClientIds = [
    'ohXpoqrZYub1kg', // Slide for Reddit
    'NOe2iKrPPzwscA', // RedReader
    'JrPdG8Z6dkWNxA', // Stealth
  ];
  static String? _oauthToken;
  static DateTime? _oauthTokenExpiry;
  static int _oauthClientIdx = 0;
  static const _ua = 'Mozilla/5.0 (Linux; Android 11; ZPlay) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36';

  static const _pasteDomains = [
    'paste.sh', 'pastebin.com', 'justpaste.it', 'controlc.com',
    'pastes.dev', 'text.is', 'rentry.co',
  ];

  static final _b64 = RegExp(r'aHR0c[a-zA-Z0-9+/=]{10,}');
  static final _rawPaste = RegExp(
    r'https?://(?:paste\.sh|pastebin\.com|justpaste\.it|controlc\.com|pastes\.dev|text\.is|rentry\.co)/[a-zA-Z0-9#_=-]+',
    caseSensitive: false,
  );

  static const _junkTokens = [
    'type=m3u', 'output=ts', 'password=', 'username=', 'password', 'username',
  ];

  static Future<List<IptvPortal>> _loadCloudVaultDatabase() async {
    if (_cachedCloudPortals != null && _cachedCloudPortals!.isNotEmpty) {
      return _cachedCloudPortals!;
    }
    if (_isLoadingCloudPortals) {
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_cachedCloudPortals != null && _cachedCloudPortals!.isNotEmpty) {
          return _cachedCloudPortals!;
        }
      }
    }
    _isLoadingCloudPortals = true;

    try {
      List<int>? bytes;
      for (final url in [_cloudVaultPrimaryUrl, _cloudVaultBackupUrl]) {
        try {
          final res = await http
              .get(Uri.parse(url), headers: {'User-Agent': _ua})
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            break;
          }
        } catch (_) {}
      }

      if (bytes == null || bytes.isEmpty) {
        _isLoadingCloudPortals = false;
        return const [];
      }

      final decompressed = gzip.decode(bytes);
      final text = utf8.decode(decompressed, allowMalformed: true);
      final lines = const LineSplitter().convert(text);

      final list = <IptvPortal>[];
      final seen = <String>{};

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = _parseCsvLine(line);
        if (parts.length >= 3) {
          final host = parts[0].trim();
          final user = parts[1].trim();
          final pass = parts[2].trim();
          if (host.startsWith('http://') || host.startsWith('https://')) {
            if (user.isNotEmpty && pass.isNotEmpty) {
              final key = '$user|$pass'.toLowerCase();
              if (seen.add(key)) {
                list.add(IptvPortal(
                  url: host.endsWith('/') ? host.substring(0, host.length - 1) : host,
                  username: user,
                  password: pass,
                  source: 'Cloud Vault',
                ));
              }
            }
          }
        }
      }

      list.shuffle();
      _cachedCloudPortals = list;
      return list;
    } catch (e) {
      debugPrint('[IptvScraper] Error loading Cloud Vault database: $e');
      return const [];
    } finally {
      _isLoadingCloudPortals = false;
    }
  }

  static List<String> _parseCsvLine(String line) {
    final res = <String>[];
    final sb = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        res.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    res.add(sb.toString().trim());
    return res;
  }

  static Future<ScrapePage> _scrapeCloudVaultCatalog({
    int maxResults = 50,
    String? after,
  }) async {
    final allPortals = await _loadCloudVaultDatabase();
    if (allPortals.isEmpty) {
      return const ScrapePage(portals: [], nextAfter: null);
    }

    var offset = 0;
    if (after != null && after.startsWith('cloud:')) {
      offset = int.tryParse(after.replaceFirst('cloud:', '')) ?? 0;
    }

    if (offset >= allPortals.length) {
      return const ScrapePage(portals: [], nextAfter: null);
    }

    final slice = allPortals.skip(offset).take(maxResults).toList();
    final nextOffset = offset + slice.length;
    final nextAfter = nextOffset < allPortals.length ? 'cloud:$nextOffset' : null;

    return ScrapePage(portals: slice, nextAfter: nextAfter);
  }

  static Future<ScrapePage> scrapeCatalogPage({
    int maxResults = 50,
    String? after,
    CatalogSource source = CatalogSource.cloudVault,
  }) async {
    if (source == CatalogSource.cloudVault) {
      return _scrapeCloudVaultCatalog(maxResults: maxResults, after: after);
    }
    String? redditAfter;
    if (after != null && after.startsWith('reddit:')) {
      final t = after.substring(7);
      redditAfter = t.isEmpty ? null : t;
    } else if (after != null && after.isNotEmpty) {
      redditAfter = after;
    }
    return _scrapeRedditCatalog(maxResults: maxResults, after: redditAfter);
  }

  static Future<ScrapePage> _scrapeRedditCatalog(
      {int maxResults = 50, String? after}) async {
    final out = <String, IptvPortal>{};

    var subIdx = 0;
    String? redditAfter;
    if (after != null && after.isNotEmpty) {
      final parts = after.split(':');
      if (parts.length >= 3) {
        subIdx = int.tryParse(parts[1]) ?? 0;
        redditAfter = parts.sublist(2).join(':');
        if (redditAfter.isEmpty || redditAfter == 'null') redditAfter = null;
      } else if (parts.length == 2) {
        redditAfter = parts[1];
        if (redditAfter.isEmpty || redditAfter == 'null') redditAfter = null;
      }
    }
    if (subIdx >= _catalogSubs.length) subIdx = 0;
    final currentSub = _catalogSubs[subIdx];

    final catalogJson = await _fetchCatalogOAuth(
        sub: currentSub, after: redditAfter);
    if (catalogJson != null) {
      Map<String, dynamic>? data;
      try {
        data = (json.decode(catalogJson) as Map<String, dynamic>)['data']
            as Map<String, dynamic>?;
      } catch (_) {}
      if (data != null) {
        final posts = data['children'] as List? ?? [];
        final nextAfterRaw = data['after']?.toString();
        final hasMore = nextAfterRaw != null &&
            nextAfterRaw.isNotEmpty &&
            nextAfterRaw != 'null';
        String? nextAfter;
        if (hasMore) {
          nextAfter = 'reddit:$subIdx:$nextAfterRaw';
        } else if (subIdx + 1 < _catalogSubs.length) {
          nextAfter = 'reddit:${subIdx + 1}:';
        }

        _processPosts(posts, out, maxResults);
        await _processDeepLinks(posts, out, maxResults);
        return ScrapePage(portals: out.values.toList(), nextAfter: nextAfter);
      }
    }

    // Fallback: RSS
    final rssBody = await _fetchCatalogRss(sub: currentSub, after: redditAfter);
    if (rssBody == null) {
      if (subIdx + 1 < _catalogSubs.length) {
        return ScrapePage(
            portals: const [], nextAfter: 'reddit:${subIdx + 1}:');
      }
      return const ScrapePage(portals: [], nextAfter: null);
    }

    final entryRe = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    final titleRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
    final contentRe = RegExp(r'<content[^>]*>(.*?)</content>', dotAll: true);
    final idRe = RegExp(r'<id>(t3_[^<]+)</id>');

    final entries = entryRe.allMatches(rssBody).toList();
    final postIds = idRe.allMatches(rssBody).map((m) => m.group(1)!).toList();
    final lastPostId = postIds.isNotEmpty ? postIds.last : null;
    String? nextAfter;
    if (lastPostId != null && entries.length >= 20) {
      nextAfter = 'reddit:$subIdx:$lastPostId';
    } else if (subIdx + 1 < _catalogSubs.length) {
      nextAfter = 'reddit:${subIdx + 1}:';
    }

    var postIdx = 0;
    for (final entry in entries) {
      postIdx++;
      if (out.length >= maxResults) break;
      final entryText = entry.group(1)!;
      final titleMatch = titleRe.firstMatch(entryText);
      final title = _decodeXmlEntities(titleMatch?.group(1) ?? '');
      final contentMatch = contentRe.firstMatch(entryText);
      final rawContent = _decodeXmlEntities(contentMatch?.group(1) ?? '');
      final body = '$title ${rawContent.replaceAll(
        RegExp(r'<(?:p|br|div|li|h\d)[^>]*>', caseSensitive: false),
        '\n',
      ).replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ')}'
          .trim();
      _processPostBody(body, title, postIdx, out, maxResults);
    }

    return ScrapePage(portals: out.values.toList(), nextAfter: nextAfter);
  }

  static void _processPosts(
      List posts, Map<String, IptvPortal> out, int maxResults) {
    var postIdx = 0;
    for (final post in posts) {
      postIdx++;
      if (out.length >= maxResults) break;
      final pdata =
          ((post as Map<String, dynamic>)['data']) as Map<String, dynamic>?;
      if (pdata == null) continue;
      final title = pdata['title']?.toString() ?? '';
      final body = '$title ${pdata['selftext']?.toString() ?? ''}'.trim();
      _processPostBody(body, title, postIdx, out, maxResults);
    }
  }

  static void _processPostBody(String body, String title, int postIdx,
      Map<String, IptvPortal> out, int maxResults) {
    final direct = _extractPortals(body, 'Catalog');
    for (final p in direct) {
      _addPortal(out, p, maxResults);
    }
  }

  static Future<void> _processDeepLinks(
      List posts, Map<String, IptvPortal> out, int maxResults) async {
    for (final post in posts) {
      if (out.length >= maxResults) break;
      final pdata =
          ((post as Map<String, dynamic>)['data']) as Map<String, dynamic>?;
      if (pdata == null) continue;
      final title = pdata['title']?.toString() ?? '';
      final body = '$title ${pdata['selftext']?.toString() ?? ''}'.trim();

      final deepLinks = <String>[];
      for (final m in _b64.allMatches(body)) {
        try {
          final decoded = utf8.decode(base64.decode(m.group(0)!),
              allowMalformed: true);
          if (decoded.startsWith('http') && _isPasteSite(decoded)) {
            deepLinks.add(decoded);
          } else if (!decoded.startsWith('http') && decoded.contains(':')) {
            _extractPortals(decoded, 'Catalog (decoded)')
                .forEach((p) => _addPortal(out, p, maxResults));
          }
        } catch (_) {}
      }
      for (final m in _rawPaste.allMatches(body)) {
        deepLinks.add(m.group(0)!);
      }
      final unique = deepLinks.toSet().take(4);
      for (final dl in unique) {
        if (out.length >= maxResults) break;
        final text = await _fetchPaste(dl);
        if (text == null || text.isEmpty) continue;
        final found = _extractPortals(text, 'Catalog (deep)');
        for (final p in found) {
          _addPortal(out, p, maxResults);
        }
      }
    }
  }

  static void _addPortal(
      Map<String, IptvPortal> sink, IptvPortal p, int max) {
    if (sink.length >= max) return;
    sink.putIfAbsent(p.key, () => p);
  }

  static String _normalizeUnicode(String input) {
    final buf = StringBuffer();
    for (final char in input.runes) {
      // 1. Mathematical Bold / Italic / Sans-Serif / Monospace uppercase (A-Z)
      if ((char >= 0x1D400 && char <= 0x1D419) ||
          (char >= 0x1D434 && char <= 0x1D44D) ||
          (char >= 0x1D468 && char <= 0x1D481) ||
          (char >= 0x1D5A0 && char <= 0x1D5B9) ||
          (char >= 0x1D5D4 && char <= 0x1D5ED) ||
          (char >= 0x1D608 && char <= 0x1D621) ||
          (char >= 0x1D670 && char <= 0x1D689)) {
        final offset = (char - 0x1D400) % 26;
        buf.writeCharCode(0x41 + offset);
        continue;
      }
      // 2. Mathematical Bold / Italic / Sans-Serif / Monospace lowercase (a-z)
      if ((char >= 0x1D41A && char <= 0x1D433) ||
          (char >= 0x1D44E && char <= 0x1D467) ||
          (char >= 0x1D482 && char <= 0x1D49B) ||
          (char >= 0x1D5BA && char <= 0x1D5D3) ||
          (char >= 0x1D5EE && char <= 0x1D607) ||
          (char >= 0x1D622 && char <= 0x1D63B) ||
          (char >= 0x1D68A && char <= 0x1D6A3)) {
        final offset = (char - 0x1D41A) % 26;
        buf.writeCharCode(0x61 + offset);
        continue;
      }
      // 3. Mathematical Digits 0-9
      if ((char >= 0x1D7CE && char <= 0x1D7D7) ||
          (char >= 0x1D7E2 && char <= 0x1D7EB) ||
          (char >= 0x1D7EC && char <= 0x1D7F5) ||
          (char >= 0x1D7F6 && char <= 0x1D7FF)) {
        final offset = (char - 0x1D7CE) % 10;
        buf.writeCharCode(0x30 + offset);
        continue;
      }
      // 4. Small Caps
      const smallCaps = {
        0x1D00: 'A', 0x0299: 'B', 0x1D04: 'C', 0x1D05: 'D', 0x1D07: 'E',
        0x0262: 'G', 0x029C: 'H', 0x026A: 'I', 0x1D0A: 'J', 0x1D0B: 'K',
        0x029F: 'L', 0x1D0D: 'M', 0x0274: 'N', 0x1D0F: 'O', 0x1D18: 'P',
        0x0280: 'R', 0x1D1B: 'T', 0x1D1C: 'U', 0x1D20: 'V', 0x1D21: 'W',
        0x028F: 'Y', 0x1D22: 'Z',
      };
      if (smallCaps.containsKey(char)) {
        buf.write(smallCaps[char]);
        continue;
      }
      // 5. Fullwidth ASCII
      if (char >= 0xFF01 && char <= 0xFF5E) {
        buf.writeCharCode(char - 0xFEE0);
        continue;
      }
      buf.writeCharCode(char);
    }
    return buf.toString();
  }

  static List<IptvPortal> _extractPortals(String rawText, String source) {
    if (rawText.length < 10 || _isJunkCode(rawText)) return const [];
    final normalized = _normalizeUnicode(
      rawText
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll(
            RegExp(r'<(?:p|br|div|li|h\d)[^>]*>', caseSensitive: false),
            '\n',
          )
          .replaceAll(RegExp(r'<[^>]+>'), ' '),
    );

    final acc = <String, IptvPortal>{};

    // 1. URL with query params (user first: username=...&password=...)
    final urlParamUserFirst = RegExp(
      r'''(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:username|user|usr|login|account)=([^&\s"'<]+)\s*&(?:[^\s"'<]*?&)?(?:password|pass|pwd)=([^&\s"'<]+)''',
      caseSensitive: false,
    );
    for (final m in urlParamUserFirst.allMatches(normalized)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }

    // 2. URL with query params (pass first: password=...&username=...)
    final urlParamPassFirst = RegExp(
      r'''(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:password|pass|pwd)=([^&\s"'<]+)\s*&(?:[^\s"'<]*?&)?(?:username|user|usr|login|account)=([^&\s"'<]+)''',
      caseSensitive: false,
    );
    for (final m in urlParamPassFirst.allMatches(normalized)) {
      _finalize(acc, m.group(1)!, m.group(3)!, m.group(2)!, source);
    }

    // 3. Multi-line labeled blocks (Host/Portal + Username + Password + optional Port)
    final labelRe = RegExp(
      r'''(?:Portal(?:-URL)?|Host(?:\s*URL)?|Panel|Server|Real-URL|URL|M3U(?:-Link)?|Link|Servidor|H[ôo]te|Сервер|🌐|🌍|🔗|📡)\s*[:=➤\-•*|]?\s*(https?://[^\s<"'\n]+)[\s\S]{1,600}?(?:Username|User|Usr|Usu[áa]rio|Usuario|Utilisateur|Login|Account|Compte|Логин|👤|🗣️)\s*[:=➤\-•*|]?\s*([^\s|<"'\n]+)[\s\S]{1,300}?(?:Password|Pass|Pwd|Senha|Contrase[ñn]a|Clave|Mot\s*de\s*passe|Пароль|🔑|🔒|🔐)\s*[:=➤\-•*|]?\s*([^\s|<"'\n]+)(?:[\s\S]{1,200}?(?:Port|Porta|Puerto|Порт)\s*[:=➤\-•*|]?\s*(\d+))?''',
      caseSensitive: false,
    );
    for (final m in labelRe.allMatches(normalized)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source, m.group(4));
    }

    // 4. Stream URI path (http://host:port/live/user/pass/123.ts)
    final streamRe = RegExp(
      r'''(https?://[^\s/]+(?::\d+)?)/(?:live|movie|series)/([^/\s]+)/([^/\s]+)/\d+''',
      caseSensitive: false,
    );
    for (final m in streamRe.allMatches(normalized)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }

    // 5. Line combo format (http://host:port:user:pass or http://host:port|user|pass or http://host:port user pass)
    final comboRe = RegExp(
      r'''(?:^|\n)\s*(https?://[a-zA-Z0-9.\-_]+(?::\d+)?(?:/[^\s:|,\t\n]*)?)\s*[:|,\t ]\s*([a-zA-Z0-9_\-.@]+)\s*[:|,\t ]\s*([a-zA-Z0-9_\-.@!#$%^&*+=]+)''',
      multiLine: true,
    );
    for (final m in comboRe.allMatches(normalized)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }

    return acc.values.toList();
  }

  static bool _isJunkCode(String text) {
    const markers = [
      'Array.isArray', 'prototype.', 'function(', 'var ', 'const ',
      'let ', 'return!', 'void ', '.message}', 'window.', 'document.',
    ];
    var hits = 0;
    for (final m in markers) {
      if (text.contains(m)) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  static void _finalize(Map<String, IptvPortal> acc, String rawUrl,
      String rawUser, String rawPass, String source, [String? rawPort]) {
    var url = _cleanPortalUrl(rawUrl);
    final user = _cleanCred(rawUser);
    final pass = _cleanCred(rawPass);

    if (rawPort != null && rawPort.isNotEmpty && !url.contains(RegExp(r':\d+$'))) {
      final portNum = int.tryParse(rawPort.trim());
      if (portNum != null && portNum > 0 && portNum <= 65535) {
        url = '$url:$portNum';
      }
    }

    if (url.length < 10 || user.length < 3 || pass.length < 3) return;
    if (user.contains('http') || pass.contains('http')) return;

    // Reject non-credentials like scripts or extensions
    final lu = user.toLowerCase();
    final lp = pass.toLowerCase();
    if (lp.endsWith('.php') || lp.endsWith('.ts') || lp.endsWith('.m3u') || lp.endsWith('.m3u8') || lp.endsWith('.mp4')) return;
    if (lu.endsWith('.php') || lu == 'play') return;

    for (final j in _junkTokens) {
      if (lu == j || lp == j || lu.contains(j) || lp.contains(j)) return;
    }
    final p = IptvPortal(url: url, username: user, password: pass, source: source);
    acc.putIfAbsent(p.key, () => p);
  }

  static String _cleanPortalUrl(String raw) {
    var clean = raw.replaceAll(RegExp(r'\s+'), '');
    final qIdx = clean.indexOf('?');
    if (qIdx >= 0) clean = clean.substring(0, qIdx);
    clean = clean.trim();
    if (clean.contains('@')) {
      clean = 'http://${clean.substring(clean.lastIndexOf('@') + 1)}';
    }
    clean = clean.replaceAll(
      RegExp(
        r'/(?:get|live|movie|series|portal|c|index|playlist|player_api|xmltv|index\.php|portal\.php)\.php$',
        caseSensitive: false,
      ),
      '',
    );
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http')) clean = 'http://$clean';
    return clean;
  }

  static String _cleanCred(String raw) {
    var s = raw.trim();
    while (s.startsWith('=') || s.startsWith(':') || s.startsWith('➤') || s.startsWith('•')) {
      s = s.substring(1).trim();
    }
    final parts = s.split(RegExp(r'[\s\n&?|<>]'));
    var res = parts.isEmpty ? '' : parts.first.trim();
    res = res.replaceAll(RegExp(r'[,;]+$'), '');
    return res;
  }

  static bool _isPasteSite(String url) =>
      _pasteDomains.any((d) => url.contains(d));

  static Future<String?> _fetchPaste(String url) async {
    if (url.contains('paste.sh/') && url.contains('#')) {
      final out = await PasteShDecryptor.decrypt(url);
      return out.isEmpty ? null : out;
    }
    if (url.contains('pastebin.com/') && !url.contains('/raw/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://pastebin.com/raw/$id');
    }
    if (url.contains('pastes.dev/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://api.pastes.dev/$id');
    }
    if (url.contains('rentry.co/') && !url.contains('/raw')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://rentry.co/$id/raw');
    }
    return _httpGetText(url);
  }

  static String _lastPathSegment(String url) {
    var s = url;
    final h = s.indexOf('#');
    if (h >= 0) s = s.substring(0, h);
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    final slash = s.lastIndexOf('/');
    return slash >= 0 ? s.substring(slash + 1) : s;
  }

  static Future<String?> _httpGetText(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/json,*/*',
      }).timeout(const Duration(seconds: 15));
      return resp.body;
    } catch (_) {
      return null;
    }
  }

  static String _decodeXmlEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#32;', ' ');

  static Future<String?> _getOAuthToken() async {
    if (_oauthToken != null &&
        _oauthTokenExpiry != null &&
        DateTime.now().isBefore(_oauthTokenExpiry!)) {
      return _oauthToken;
    }
    for (var i = 0; i < _oauthClientIds.length; i++) {
      final idx = (_oauthClientIdx + i) % _oauthClientIds.length;
      final clientId = _oauthClientIds[idx];
      try {
        final resp = await http.post(
          Uri.parse('https://www.reddit.com/api/v1/access_token'),
          headers: {
            'User-Agent': _oauthUa,
            'Authorization':
                'Basic ${base64.encode(utf8.encode('$clientId:'))}',
          },
          body: {
            'grant_type':
                'https://oauth.reddit.com/grants/installed_client',
            'device_id': 'DO_NOT_TRACK_THIS_DEVICE',
          },
        ).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final token = data['access_token'] as String?;
          final expiresIn = data['expires_in'] as int? ?? 3600;
          if (token != null && token.isNotEmpty) {
            _oauthToken = token;
            _oauthTokenExpiry = DateTime.now()
                .add(Duration(seconds: expiresIn - 60));
            _oauthClientIdx = idx;
            return token;
          }
        }
      } catch (_) {}
    }
    _oauthClientIdx =
        (_oauthClientIdx + 1) % _oauthClientIds.length;
    _oauthToken = null;
    _oauthTokenExpiry = null;
    return null;
  }

  static Future<String?> _fetchCatalogOAuth(
      {required String sub, String? after}) async {
    final token = await _getOAuthToken();
    if (token == null) return null;

    final base =
        'https://oauth.reddit.com/r/$sub/new?limit=100&sort=new&raw_json=1';
    final url = (after == null || after.isEmpty)
        ? base
        : '$base&after=$after';

    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _oauthUa,
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final t = resp.body.trimLeft();
        if (t.startsWith('{') || t.startsWith('[')) return resp.body;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        _oauthToken = null;
        _oauthTokenExpiry = null;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _fetchCatalogRss(
      {required String sub, String? after}) async {
    final base =
        'https://www.reddit.com/r/$sub/new/.rss?limit=25';
    final url = (after == null || after.isEmpty)
        ? base
        : '$base&after=$after';

    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _oauthUa,
        'Accept': 'application/atom+xml, application/xml, */*',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.body.contains('<entry>')) {
        return resp.body;
      }
    } catch (_) {}
    return null;
  }
}
