// The second source family for a curated channel: streams that live outside
// Xtream panels.
//
// A curated rail resolved streams only through the verified portals, so a fight
// carried by a public playlist was invisible to a user whose portals simply did
// not have it — the rail said "No alive streams found" while the feed was up.
// [ExternalStream] is one playable URL from anywhere that is not a panel,
// [ExternalChannelSource] is anything that can produce them, and
// [ExternalSources] is the hub a channel scan asks.
//
// Admission is the app's own judgement: a stream name is put through the same
// [HardcodedChannels.matches] call the panel path uses, so an entry reaches a
// curated channel under exactly the keyword/exclude rules that channel was
// written with, and a source cannot smuggle in a channel the user did not ask
// for.

import 'package:flutter/foundation.dart';

import '../hardcoded_channels.dart';
import '../iptv_settings.dart';
import 'm3u_remote_source.dart';

/// A playable stream discovered outside Xtream portals (a public M3U playlist,
/// a user-supplied playlist, ...).
class ExternalStream {
  final String name; // advertised name; matched with HardcodedChannels.matches
  final String url; // absolute, directly playable URL
  final String label; // honest source label, e.g. 'Free Sports (iptv-org)'
  final String? icon;
  const ExternalStream({
    required this.name,
    required this.url,
    required this.label,
    this.icon,
  });
}

abstract class ExternalChannelSource {
  /// Shown to the user as the hit's source label.
  String get label;

  /// Never throws; returns const [] on any failure. Must cache internally.
  Future<List<ExternalStream>> fetch();
}

class ExternalSources {
  static const String freeSportsLabel = 'Free Sports (iptv-org)';
  static const String freeSportsUrl =
      'https://iptv-org.github.io/iptv/categories/sports.m3u';

  /// Most external streams one channel scan carries.
  ///
  /// Every candidate costs an aliveness sniff (8s timeout, 24 at a time), and a
  /// public sports playlist names hundreds of feeds, so the list is bounded
  /// rather than "everything that matched". Portals keep their own 8-per-scan
  /// budget; this is the extra family's.
  static const int maxCandidates = 12;

  // One instance each, so a source's in-memory cache outlives the scan that
  // built it: [active] is called on every scan and every "Scan More".
  static final ExternalChannelSource _freeSports =
      RemoteM3uSource(freeSportsLabel, freeSportsUrl);
  static final SavedM3uSource _savedPlaylists = SavedM3uSource();

  /// The saved-playlist source. Production reaches it through [active]; a test
  /// that changes the playlist store needs it to drop the store-read window it
  /// caches.
  @visibleForTesting
  static SavedM3uSource get savedPlaylists => _savedPlaylists;

  /// Test seam: when set, [active] returns exactly this list and the real
  /// sources are never consulted (so a unit test cannot reach iptv-org).
  @visibleForTesting
  static List<ExternalChannelSource>? sourcesOverride;

  /// Free/public sources, included only when
  /// [IptvSettings.includeFreeSources] is true.
  static List<ExternalChannelSource> active() {
    final override = sourcesOverride;
    if (override != null) return override;
    return [
      if (IptvSettings.includeFreeSources.value) _freeSports,
      _savedPlaylists,
    ];
  }

  /// Streams from every active source whose name matches the channel via
  /// [HardcodedChannels.matches], deduped by url, capped at [maxCandidates].
  ///
  /// Never throws and never returns a stream without a URL, so a caller can
  /// hand the result straight to the aliveness sniff.
  static Future<List<ExternalStream>> candidatesFor(HardcodedChannel ch) async {
    final out = <ExternalStream>[];
    final seenUrls = <String>{};
    for (final source in active()) {
      List<ExternalStream> streams;
      try {
        streams = await source.fetch();
      } catch (_) {
        // fetch() promises not to throw. A source that breaks that promise is
        // dropped on its own, and the remaining sources still get their turn.
        continue;
      }
      for (final s in streams) {
        if (s.url.isEmpty) continue;
        if (!HardcodedChannels.matches(s.name, ch.keywords, ch.exclude)) {
          continue;
        }
        // Deduped across sources, not just inside one: the same feed is often
        // listed by the public playlist and by a playlist the user imported.
        if (!seenUrls.add(s.url)) continue;
        out.add(s);
        if (out.length >= maxCandidates) return out;
      }
    }
    return out;
  }
}
