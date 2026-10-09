import 'package:flutter/material.dart';

import '../../models/stream/stream_model.dart';
import '../../services/stream/stream_bitrate_resolver.dart';
import '../../services/theme/design_tokens.dart';

/// A source-card chip carrying the stream's video bitrate.
///
/// The value resolves in three tiers: a rate stated in the release name
/// (exact, instant), the peak variant read from the HLS master manifest
/// (exact, probed lazily), and a size/runtime estimate for torrent and debrid
/// sources. An estimate carries a leading `~` so it never masquerades as a
/// measurement.
///
/// The probe lives here rather than in the scraping pipeline on purpose: one
/// title fans out to hundreds of sources across our scrapers and addons, so
/// only the badges actually rendered may put manifest requests on the wire.
/// `StreamBitrateResolver`'s per-URL cache (misses included) dedupes across
/// cards and surfaces.
class StreamBitrateBadge extends StatefulWidget {
  const StreamBitrateBadge({
    super.key,
    required this.source,
    this.runtimeMinutes,
    this.margin = EdgeInsets.zero,
  });

  final StreamSource source;
  final int? runtimeMinutes;

  /// Applied only when the badge actually renders. A `Row` of chips spacing
  /// itself manually needs this; a `Wrap` supplies its own and wants none. It
  /// costs nothing when there is no bitrate to show, where a wrapping `Padding`
  /// would leave a gap for a chip that is not there.
  final EdgeInsetsGeometry margin;

  @override
  State<StreamBitrateBadge> createState() => _StreamBitrateBadgeState();
}

class _StreamBitrateBadgeState extends State<StreamBitrateBadge> {
  int? _probedKbps;

  @override
  void initState() {
    super.initState();
    _startProbe();
  }

  @override
  void didUpdateWidget(covariant StreamBitrateBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // List rows recycle States across sources, so a carried-over probe result
    // would show one stream's bitrate on another's card.
    if (!identical(oldWidget.source, widget.source)) {
      _probedKbps = null;
      _startProbe();
    }
  }

  void _startProbe() {
    // A rate stated in the name already decides the label, so the manifest
    // fetch behind it would be pure waste.
    if (widget.source.bitrateKbps != null) return;
    StreamBitrateResolver.resolveKbps(widget.source).then((kbps) {
      if (!mounted || kbps == null) return;
      setState(() => _probedKbps = kbps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final exactKbps = widget.source.bitrateKbps ?? _probedKbps;
    final isEstimate = exactKbps == null;
    final kbps =
        exactKbps ?? widget.source.estimatedBitrateKbps(widget.runtimeMinutes);
    if (kbps == null) return const SizedBox.shrink();

    final tokens = context.tokens;
    final color = kbps >= 15000
        ? tokens.success
        : kbps >= 4000
        ? tokens.info
        : tokens.warning;
    final label = StreamSource.formatBitrate(kbps);

    return Padding(
      padding: widget.margin,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: ZplayRadius.xsAll,
        ),
        child: Text(
          isEstimate ? '~$label' : label,
          style: ZplayType.overline
              .copyWith(weight: FontWeight.w700)
              .toStyle(color: color),
        ),
      ),
    );
  }
}
