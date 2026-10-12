import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../services/iptv/hardcoded_channels.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';

/// The Live TV hero's art: the channel's backdrop when one loads, and the
/// channel itself - its short code, or its name - when none does.
///
/// The defect this answers, from a device sweep: a featured channel with no
/// artwork left the band's picture area empty, so the hero showed about 120 dp
/// of bare background above the channel's title. Nothing was wrong with the
/// layout; the slot the layout reserves simply had nothing in it, and a blank
/// rectangle that size reads as a broken screen rather than as a channel.
/// A `backdropUrl` that 404s is the same hole, so this treats a dead URL and a
/// missing one as one state.
///
/// **Filled, not collapsed.** The band's height comes from the hero style, and
/// every slide in the reel shares it, so shrinking the band for an artless
/// channel would either move the page under the reader when the reel rotates or
/// make the other channels' art reflow the layout as it resolved. Both branches
/// here fill the same box, which is what keeps art landing exactly where the
/// wordmark stood when it arrives.
///
/// Same answer as Home's `_HeroLogoSlot`, one layer down, and the cousin of
/// Home's `HeroArtwork`: when a picture will not come, something that names the
/// thing still does.
class IptvHeroArtwork extends StatefulWidget {
  final HardcodedChannel channel;

  /// Defaults to the shared [AppImageCache.manager] and exists so tests can
  /// script a load failure - production always leaves it alone.
  final BaseCacheManager cacheManager;

  IptvHeroArtwork({
    super.key,
    required this.channel,
    BaseCacheManager? cacheManager,
  }) : cacheManager = cacheManager ?? AppImageCache.manager;

  @override
  State<IptvHeroArtwork> createState() => _IptvHeroArtworkState();
}

class _IptvHeroArtworkState extends State<IptvHeroArtwork> {
  /// Set once the backdrop has failed to load.
  ///
  /// One failure is the whole answer: a channel's data is fixed for the life of
  /// the page, so re-asking the same dead URL every rebuild would spend the
  /// request again for the same nothing.
  bool _failed = false;

  /// The backdrop to ask for, or null when the channel carries none.
  String? get _url {
    final url = widget.channel.backdropUrl?.trim();
    return (url == null || url.isEmpty) ? null : url;
  }

  /// Drops the image and paints the wordmark. Deferred one frame because the
  /// error surfaces while the image is building, where `setState` is not legal -
  /// the same reason Home's `_HeroLogoSlotState` defers its flip to text.
  void _onLoadFailed() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failed) return;
      setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null || _failed) return _wordmark(context);

    // Full-bleed and centred: a channel backdrop is drawn *through* the band
    // rather than fitted beside the text, so the scrims over it can carry the
    // title the way they carry it over any other hero art.
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: widget.cacheManager,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      memCacheWidth: 1920,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) {
        _onLoadFailed();
        return const SizedBox.shrink();
      },
    );
  }

  /// The channel's own mark, standing in for the art it does not have.
  ///
  /// The short code is what a viewer already reads on a broadcast bug to know
  /// which channel they are on, and it is the one string in the channel's data
  /// that is a mark rather than a sentence - so it holds the empty top of the
  /// band the way a logo would, at a size the type scale does not carry because
  /// no text role is this large. The name stands in when the data carries no
  /// short code, scaled down to fit instead of running off the edge.
  ///
  /// Dim on purpose: it sits under the same top scrim as the art it replaces,
  /// so the title, the pills and the buttons keep their contrast over it.
  Widget _wordmark(BuildContext context) {
    final tokens = context.tokens;
    final short = widget.channel.short.trim();
    final label = short.isEmpty ? widget.channel.name : short;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(
          top: ZplaySpacing.s24,
          left: ZplaySpacing.s32,
          right: ZplaySpacing.s32,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topRight,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: ZplayType.display
                .copyWith(size: 132, weight: FontWeight.w700)
                .toStyle(color: tokens.textPrimary.withValues(alpha: 0.14)),
          ),
        ),
      ),
    );
  }
}
