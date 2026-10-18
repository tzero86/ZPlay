import 'package:flutter/material.dart';

import '../../services/iptv/iptv_storage.dart';
import '../../services/theme/design_tokens.dart';

/// What the app already knows about one portal feed's liveness.
///
/// Two verdicts are not enough for the question a live-event viewer is actually
/// asking - "which of these feeds is worth pressing?" - so the states are three.
/// [working] and [dead] are claims the app holds evidence for; [unknown] is the
/// absence of a claim, and it is the common case: a channel nobody has scanned,
/// or one whose portal has not been probed inside [IptvAliveStore.ttl]. Calling
/// that state broken would condemn a feed for the crime of being unmeasured,
/// which is the judgement the whole feature exists to stop making.
enum IptvHitHealth {
  working,
  unknown,
  dead;

  /// Health of one feed from the two records that outlive a session.
  ///
  /// The dead-URL memory wins over the snapshot: a URL that failed to open is
  /// newer and more specific evidence than a portal-wide list of live stream
  /// ids that may have been written before that failure. A snapshot past its
  /// [IptvAliveStore.ttl] is no evidence at all, so a lapsed check degrades to
  /// [unknown] rather than to whatever it said last time. The check is on
  /// `streamId` because that is the key the snapshot stores, and on the URL
  /// because that is the key a failure is remembered under - the two records
  /// are keyed differently, so both are passed explicitly.
  static IptvHitHealth resolve({
    required String streamUrl,
    String? streamId,
    AliveSnapshot? snapshot,
  }) {
    if (IptvDeadUrlStore.instance.isDead(streamUrl)) return IptvHitHealth.dead;
    if (streamId != null &&
        streamId.isNotEmpty &&
        snapshot != null &&
        IptvAliveStore.isFresh(snapshot) &&
        snapshot.aliveIds.contains(streamId)) {
      return IptvHitHealth.working;
    }
    return IptvHitHealth.unknown;
  }

  /// One channel's health from the health of every feed the app knows for it.
  ///
  /// A channel counts as [working] as soon as one feed does, and as [dead] only
  /// when every known feed is: the card asks "is there anything here worth
  /// opening?", and a channel with one dead feed beside one unprobed feed still
  /// might have something. No known feeds is [unknown], never [dead].
  static IptvHitHealth ofChannel(Iterable<IptvHitHealth> feeds) {
    var known = false;
    var allDead = true;
    for (final feed in feeds) {
      known = true;
      if (feed == IptvHitHealth.working) return IptvHitHealth.working;
      if (feed != IptvHitHealth.dead) allDead = false;
    }
    return known && allDead ? IptvHitHealth.dead : IptvHitHealth.unknown;
  }
}

/// The quiet feed-health mark: a dot and one word, in the LIVE pill's own
/// chrome (background scrim, hairline edge, extra-small radius) so a card that
/// carries both reads as one family rather than as two overlays competing.
///
/// The word is not decoration: it is what keeps the three states apart for a
/// viewer who cannot separate the dot colours, and it is why the three labels
/// are distinct - an "unchecked" feed must not borrow the language of a broken
/// one.
class IptvHealthBadge extends StatelessWidget {
  const IptvHealthBadge({super.key, required this.health});

  final IptvHitHealth health;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (color, label) = switch (health) {
      IptvHitHealth.working => (tokens.success, 'ALIVE'),
      IptvHitHealth.unknown => (tokens.textDisabled, 'UNCHECKED'),
      IptvHitHealth.dead => (tokens.danger, 'DEAD'),
    };

    // Pointer-transparent: the mark rides on a tappable card and a tappable
    // row, and neither of those targets is the badge.
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: tokens.bg.withValues(alpha: 0.65),
          borderRadius: ZplayRadius.xsAll,
          border: Border.all(
            // The neutral state keeps a neutral edge: an unchecked feed is not
            // a warning, so it must not wear one's colour.
            color: color.withValues(alpha: health == IptvHitHealth.unknown ? 0.45 : 0.6),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: ZplaySpacing.s4),
            Text(
              label,
              style: ZplayType.overline.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
