import 'dart:math' as math;

import '../../models/stream/stream_model.dart';
import 'stream_health_checker.dart';

/// Finds the first source in a ranked list that actually answers right now.
///
/// The stalled player and the resume chain ask the same question: of the
/// candidates a provider ranked, which one opens? A probe is expensive - a
/// range request, or an HLS walk past the playlist - so this is a bounded
/// fan-out over the ranking rather than a walk of the whole list: four at a
/// time, eight seconds each, twenty-five seconds for the search.
///
/// Rank order survives the fan-out. A batch is concurrent only because waiting
/// for candidates one by one would spend the budget on the first three dead
/// ones; inside a batch the earliest ranked live source wins, so the answer is
/// the one a viewer would have picked after watching the first few fail.
///
/// Torrents are never probed. `infoHash` names a swarm, not an endpoint, and
/// nothing in this file has a DHT to ask; they are the fallback only when no
/// HTTP candidate answered at all, which is the case where opening one is still
/// better than leaving the player on a dead stream.
class BestSourceFinder {
  /// Probes in flight at once.
  static const int concurrency = 4;

  /// Wall-clock limit for the whole search.
  static const Duration budget = Duration(seconds: 25);

  /// Limit for one probe, which the remaining [budget] can shorten.
  static const Duration probeTimeout = Duration(seconds: 8);

  /// Removes duplicates and the source already playing, keeping rank order.
  ///
  /// Identity is the strongest thing a source has: its `infoHash`, else its
  /// `url`/`externalUrl`, else `name|title`. [exclude] is dropped by the same
  /// identity - with a facet overlap, so a candidate carrying only the url of
  /// the source that is playing is still recognised as that source.
  static List<StreamSource> prepare(
    List<StreamSource> sources, {
    StreamSource? exclude,
  }) {
    final List<StreamSource> prepared = <StreamSource>[];
    final Set<String> seen = <String>{};
    for (final source in sources) {
      if (exclude != null && _sameSource(source, exclude)) continue;
      if (!seen.add(_identity(source))) continue;
      prepared.add(source);
    }
    return prepared;
  }

  /// Probes the HTTP candidates in rank order and returns the first live one.
  ///
  /// Returns a torrent only when every HTTP candidate was probed and refused.
  /// Null means the caller has nothing to open: no candidate answered, the
  /// budget ran out before the ranking was exhausted, or [isCancelled] asked to
  /// stop.
  static Future<StreamSource?> find(
    List<StreamSource> sources, {
    Future<bool> Function(StreamSource)? probe,
    bool Function()? isCancelled,
    void Function(int checked, int total)? onProgress,
    Duration budget = BestSourceFinder.budget,
  }) async {
    final Future<bool> Function(StreamSource) probeSource =
        probe ?? StreamHealthChecker.isAlive;
    if (isCancelled?.call() ?? false) return null;

    final List<StreamSource> http = <StreamSource>[];
    final List<StreamSource> torrents = <StreamSource>[];
    for (final source in sources) {
      (_isTorrent(source) ? torrents : http).add(source);
    }
    if (http.isEmpty) return torrents.isEmpty ? null : torrents.first;

    final Stopwatch clock = Stopwatch()..start();
    final int total = http.length;
    int checked = 0;
    int next = 0;

    while (next < total) {
      final Duration remaining = budget - clock.elapsed;
      // A batch started on a spent budget could only be cut off mid-flight, and
      // the caller needs "nothing found" while it still has time to say so.
      if (remaining <= Duration.zero) return null;
      if (isCancelled?.call() ?? false) return null;

      final List<StreamSource> batch = http.sublist(
        next,
        math.min(next + concurrency, total),
      );
      next += batch.length;

      final List<bool> alive = await Future.wait(
        batch.map((source) => _probeOnce(probeSource, source, remaining)),
      );
      checked += batch.length;
      onProgress?.call(checked, total);

      for (int i = 0; i < batch.length; i++) {
        if (!alive[i]) continue;
        if (isCancelled?.call() ?? false) return null;
        return batch[i];
      }
    }

    if (isCancelled?.call() ?? false) return null;
    return torrents.isEmpty ? null : torrents.first;
  }

  /// One probe, cut off by [probeTimeout] or by what is left of the budget.
  ///
  /// A refused probe and a hung one are the same answer here: nothing was
  /// delivered, so the next candidate gets the turn.
  static Future<bool> _probeOnce(
    Future<bool> Function(StreamSource) probe,
    StreamSource source,
    Duration remaining,
  ) async {
    final Duration limit = remaining < probeTimeout ? remaining : probeTimeout;
    if (limit <= Duration.zero) return false;
    try {
      return await probe(source).timeout(limit);
    } catch (_) {
      return false;
    }
  }

  /// Whether [source] is a torrent, which no HTTP probe can answer for.
  static bool _isTorrent(StreamSource source) {
    final String hash = source.infoHash?.trim() ?? '';
    if (hash.isNotEmpty) return true;
    return source.url?.trim().startsWith('magnet:') ?? false;
  }

  static bool _sameSource(StreamSource a, StreamSource b) {
    final String? hashA = _hashKey(a);
    if (hashA != null && hashA == _hashKey(b)) return true;
    final String? urlA = _urlKey(a);
    if (urlA != null && urlA == _urlKey(b)) return true;
    final String? nameA = _nameKey(a);
    return nameA != null && nameA == _nameKey(b);
  }

  /// The strongest facet this source has, as a prefixed key.
  static String _identity(StreamSource source) {
    final String? hash = _hashKey(source);
    if (hash != null) return 'hash:$hash';
    final String? url = _urlKey(source);
    if (url != null) return 'url:$url';
    return 'name:${_nameKey(source) ?? ''}';
  }

  static String? _hashKey(StreamSource source) {
    final String hash = source.infoHash?.trim() ?? '';
    return hash.isEmpty ? null : hash;
  }

  static String? _urlKey(StreamSource source) {
    final String url = source.url?.trim() ?? '';
    if (url.isNotEmpty) return url;
    final String external = source.externalUrl?.trim() ?? '';
    return external.isEmpty ? null : external;
  }

  static String? _nameKey(StreamSource source) {
    final String name = source.name?.trim() ?? '';
    final String title = source.title?.trim() ?? '';
    if (name.isEmpty && title.isEmpty) return null;
    return '$name|$title';
  }
}
