// M3U-backed external sources — the two things that hand a curated channel
// streams that exist outside the user's portals.
//
// Neither of them claims anything about whether a stream plays. What they
// produce is a candidate: the scan still has to put every URL through
// `IptvAliveChecker`, which fetches real bytes and looks for a video signature,
// and only a survivor becomes a hit.
//
// Known limitation, deliberately not papered over: a few public CDN entries
// answer only when the request carries the site's own `Referer` (or a matching
// session/cookie). This file adds no per-host header plumbing — guessing a
// referrer per host is a maintenance burden that rots silently, and a wrong
// header would make a broken feed look alive. Such an entry fails the byte
// sniff on the first segments and is simply dropped, so the app never reports
// it as alive and never offers it to the player.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../m3u_parser.dart';
import '../m3u_store.dart';
import '../../../utils/security/log_redaction.dart';
import 'external_channel_source.dart';

/// How [RemoteM3uSource] reads the playlist body. Injectable so the parsing,
/// caching and failure behaviour can be exercised without a socket.
typedef PlaylistTextFetcher = Future<String> Function(String url);

/// A playlist served over HTTP by a public host, a provider, or anyone else.
class RemoteM3uSource implements ExternalChannelSource {
  RemoteM3uSource(this.label, this.url, {PlaylistTextFetcher? fetchText})
    : _fetchText = fetchText ?? fetchPlaylistText;

  @override
  final String label;

  final String url;
  final PlaylistTextFetcher _fetchText;

  /// How long one downloaded playlist is reused.
  ///
  /// These files change when a channel appears or dies, which is a matter of
  /// weeks, while a scan of one curated channel happens seconds apart. Six
  /// hours keeps a fight-night browsing session to a single GET without letting
  /// the list go weeks stale.
  static const Duration ttl = Duration(hours: 6);

  /// A playlist host that does not answer inside this window is not going to
  /// help this scan, and the scan is holding a user who is waiting.
  static const Duration timeout = Duration(seconds: 15);

  /// A desktop browser's UA. iptv-org's file is static and answers anything,
  /// but the hosts these lists point at (and some that serve playlists) reject
  /// a bare Dart client by UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  List<ExternalStream>? _cache;
  DateTime? _cachedAt;

  /// In-flight load, so two scans that overlap (the rail is re-entrant) share
  /// one download instead of racing two.
  Future<List<ExternalStream>>? _inFlight;

  @override
  Future<List<ExternalStream>> fetch() {
    final cached = _cache;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < ttl) {
      return Future.value(cached);
    }

    final running = _inFlight;
    if (running != null) return running;

    final load = _load();
    _inFlight = load;
    return load.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<List<ExternalStream>> _load() async {
    try {
      final text = await _fetchText(url);
      final streams = parseToStreams(text, label);
      _cache = streams;
      _cachedAt = DateTime.now();
      return streams;
    } catch (e) {
      // Nothing is cached on the way out: a host that was down for a minute
      // must not take this source out for the whole TTL.
      debugPrint('RemoteM3uSource "$label" failed: ${redactTextUrls('$e')}');
      return const [];
    }
  }

  /// Maps playlist text to streams labelled [label].
  ///
  /// Throws [FormatException] when the text is not an M3U playlist at all —
  /// [fetch] is what turns that into an empty list.
  static List<ExternalStream> parseToStreams(String content, String label) {
    final channels = M3uParser.parse(content);
    final out = <ExternalStream>[];
    for (final c in channels) {
      out.add(
        ExternalStream(
          name: c.name,
          url: c.url,
          label: label,
          icon: c.logo.isEmpty ? null : c.logo,
        ),
      );
    }
    return out;
  }

  /// GETs [url] and returns the body as text.
  ///
  /// Throws on a non-2xx answer, a timeout or a socket error; [fetch] is the
  /// caller that turns those into "no streams".
  static Future<String> fetchPlaylistText(String url) async {
    final uri = Uri.parse(url);
    final res = await http
        .get(uri, headers: const {'User-Agent': userAgent})
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'HTTP ${res.statusCode} while fetching playlist',
        uri: uri,
      );
    }
    // Decoded as UTF-8 rather than through `res.body`, which falls back to
    // latin-1 when the host sends no charset and would mangle the accented
    // channel names these lists carry.
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}

/// The playlists the user imported from the M3U page (a URL or a local file).
///
/// This reads [M3uStore] — the same store that page writes — rather than
/// mirroring the controller's in-memory copy, so a playlist added or deleted
/// between two scans is picked up without any wiring between the two. Nothing
/// is re-downloaded: a URL playlist's channels are the ones the user already
/// paid for in bytes, and re-fetching here would download the same file twice.
class SavedM3uSource implements ExternalChannelSource {
  /// Label prefix; one stream is labelled per playlist it came from, because
  /// "Your playlist" alone would not tell a user which of their lists answered.
  static const String labelPrefix = 'Your playlist: ';

  @override
  String get label => 'Your playlist';

  /// How long one store read is reused.
  ///
  /// The store holds every channel of every playlist as JSON, so the decode is
  /// real work; this is long enough to collapse the scans of one fight-night
  /// session and short enough that an edit is never more than a moment away.
  static const Duration ttl = Duration(seconds: 30);

  List<ExternalStream>? _cache;
  DateTime? _cachedAt;

  /// Drops the reuse window so the next [fetch] reads the store again.
  ///
  /// The M3U page cannot reach this instance (it is the hub's singleton), and a
  /// test needs two different store states from one process.
  @visibleForTesting
  void clearCache() {
    _cache = null;
    _cachedAt = null;
  }

  @override
  Future<List<ExternalStream>> fetch() async {
    final cached = _cache;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < ttl) {
      return cached;
    }
    try {
      final playlists = await M3uStore.loadAll();
      final out = <ExternalStream>[];
      for (final p in playlists) {
        final label = '$labelPrefix${p.name}';
        for (final c in p.channels) {
          if (c.url.isEmpty) continue;
          out.add(
            ExternalStream(
              name: c.name,
              url: c.url,
              label: label,
              icon: c.logo.isEmpty ? null : c.logo,
            ),
          );
        }
      }
      _cache = out;
      _cachedAt = DateTime.now();
      return out;
    } catch (e) {
      debugPrint('SavedM3uSource failed: ${redactTextUrls('$e')}');
      return const [];
    }
  }
}
