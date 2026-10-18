import '../../models/iptv/iptv_models.dart';
import 'iptv_storage.dart';

/// Health-first ranking for one curated channel's portal hits.
///
/// The hub hands the player every portal that carried the fight, in the order
/// the scan happened to resolve them, and the player opened the first one. So
/// the app already knew two things - which streams a probe just answered for,
/// and which URLs playback had just failed - and used neither. That is the
/// trial-and-error the Live page was reported for: open, watch it die, open the
/// sources drawer, guess again, during a live event that will not wait.
///
/// Order: fresh-alive, then unknown, then known-dead, stable inside each group
/// so the controller's favourites-first arrangement survives the regroup.
class IptvHealthOrdering {
  /// Returns the same [ChannelHit] instances, regrouped and never dropped: the
  /// player keeps one index into this list and the sources drawer draws it, so
  /// a permutation is the whole contract.
  static List<ChannelHit> sort(List<ChannelHit> hits) {
    if (hits.length < 2) return hits;
    final alive = <ChannelHit>[];
    final unknown = <ChannelHit>[];
    final dead = <ChannelHit>[];
    for (final hit in hits) {
      // Dead before alive: a probe is one HTTP request that answered, while a
      // recorded failure is playback that did not happen. When they disagree,
      // the failure is the later and stronger evidence.
      if (IptvDeadUrlStore.instance.isDead(hit.streamUrl)) {
        dead.add(hit);
      } else if (_isFreshAlive(hit)) {
        alive.add(hit);
      } else {
        unknown.add(hit);
      }
    }
    return <ChannelHit>[...alive, ...unknown, ...dead];
  }

  /// Index of the next source to try after [from] failed, or null when there is
  /// nothing left to try.
  ///
  /// [hits] must be the list the player is walking (the [sort] result), because
  /// the search starts just after the failed source and wraps once. [tried]
  /// holds the URLs that already failed in this player session, which is what
  /// stops a five-source channel from cycling between two dead panels; the
  /// dead store is consulted as well, because this failure has just been
  /// written to it and the order was computed before that happened.
  static int? nextUntriedIndex(
    List<ChannelHit> hits,
    int from,
    Set<String> tried,
  ) {
    if (hits.length < 2) return null;
    final start = from < 0 || from >= hits.length ? 0 : from;
    final currentUrl = hits[start].streamUrl;
    for (var step = 1; step < hits.length; step++) {
      final index = (start + step) % hits.length;
      final url = hits[index].streamUrl;
      if (url.isEmpty || url == currentUrl) continue;
      if (tried.contains(url)) continue;
      if (IptvDeadUrlStore.instance.isDead(url)) continue;
      return index;
    }
    return null;
  }

  static bool _isFreshAlive(ChannelHit hit) {
    final snapshot =
        IptvAliveStore.cached(IptvAliveStore.portalKey(hit.portal.portal));
    if (!IptvAliveStore.isFresh(snapshot)) return false;
    return snapshot!.aliveIds.contains(hit.stream.streamId);
  }
}
