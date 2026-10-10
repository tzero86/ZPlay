import 'package:flutter/material.dart';

import '../../../models/iptv/iptv_models.dart';
import '../../../services/iptv/hardcoded_channels.dart';
import '../../../services/iptv/iptv_controller.dart';
import '../../../services/iptv/iptv_network.dart';
import '../../../services/layout/form_factor.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../widgets/common/focusable_card.dart';
import '../../../widgets/common/pill_button.dart';

/// The prototype's Live TV pane: a channel list beside the programme guide for
/// the selected channel.
///
/// Everything on it is real. The channels are the app's own [HardcodedChannel]
/// rows, and the schedule is the panel's own `get_short_epg` payload, fetched
/// through [IptvController.epgForHit] so the answer is cached per
/// portal + stream and two panes never ask the same question twice.
///
/// When the channel has no verified stream there is no schedule to show - EPG
/// comes from an Xtream panel, and a channel nobody has scanned yet has no
/// panel behind it. The pane says so and offers the one action that can change
/// it, rather than drawing a plausible-looking fake schedule.
class LiveGuideBand extends StatefulWidget {
  const LiveGuideBand({
    super.key,
    required this.channels,
    required this.onWatchLive,
    required this.onFindStreams,
  });

  final List<HardcodedChannel> channels;

  /// Launch the selected channel's live stream. Wired to the page's existing
  /// playback path, unchanged.
  final void Function(HardcodedChannel channel) onWatchLive;

  /// Open the channel's source sheet, which scans the portals for live feeds.
  final void Function(HardcodedChannel channel) onFindStreams;

  @override
  State<LiveGuideBand> createState() => _LiveGuideBandState();
}

class _LiveGuideBandState extends State<LiveGuideBand> {
  final IptvController _controller = IptvController.instance;

  int _selected = 0;
  List<EpgEntry> _epg = const [];
  bool _loading = false;

  /// The guide's own schedule cache, keyed by portal + stream.
  ///
  /// The controller's `epgForHit` asks the panel for two entries, which is the
  /// right size for a now/next snippet in a channel row. A guide needs a
  /// lineup, so this asks for a longer window and keeps it per channel: moving
  /// the selection back and forth across the list must not re-hit the panel.
  final Map<String, List<EpgEntry>> _schedules = {};

  HardcodedChannel? get _channel =>
      widget.channels.isEmpty || _selected >= widget.channels.length
      ? null
      : widget.channels[_selected];

  /// The first verified live feed for the selected channel, or null while the
  /// channel has not been scanned on the active portal.
  ChannelHit? get _hit {
    final channel = _channel;
    if (channel == null) return null;
    if (_controller.activeHardcoded?.id != channel.id) return null;
    final results = _controller.channelResults;
    return results.isEmpty ? null : results.first;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEpg());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // The scan the sheet runs can finish after the sheet closes, which is when
    // this pane gains a schedule to show. Deferred to the end of the frame: the
    // controller notifies from inside its own update, and a synchronous
    // `setState` from there can land during a build.
    if (!mounted || _loading || _epg.isNotEmpty || _hit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _epg.isNotEmpty || _hit == null) return;
      _loadEpg();
    });
  }

  Future<void> _loadEpg() async {
    if (!mounted) return;
    final hit = _hit;
    if (hit == null) {
      setState(() {
        _epg = const [];
        _loading = false;
      });
      return;
    }

    final key = '${hit.portal.key}|${hit.stream.streamId}';
    final cached = _schedules[key];
    if (cached != null) {
      setState(() {
        _epg = cached;
        _loading = false;
      });
      return;
    }

    setState(() {
      _epg = const [];
      _loading = true;
    });

    final entries = await IptvClient.shortEpg(
      hit.portal.portal,
      hit.stream.streamId,
      limit: 6,
    );
    if (!mounted) return;
    _schedules[key] = entries;
    setState(() {
      _epg = entries;
      _loading = false;
    });
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    _loadEpg();
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    if (channel == null) return const SizedBox.shrink();

    final isCompact = FormFactorService.of(context) == FormFactor.compact;
    final channelList = _channelList(context, isCompact);
    final guide = _guidePane(context, channel, isCompact);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? ZplaySpacing.s12 : ZplaySpacing.s24,
      ),
      child: isCompact
          // A phone scrolls the whole guide with the page; a nested scroller
          // inside a nested scroller is a scroll trap on touch.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                channelList,
                const SizedBox(height: ZplaySpacing.s12),
                guide,
              ],
            )
          : SizedBox(
              height: 296,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 260, child: channelList),
                  const SizedBox(width: ZplaySpacing.s16),
                  Expanded(child: guide),
                ],
              ),
            ),
    );
  }

  Widget _channelList(BuildContext context, bool isCompact) {
    final tokens = context.tokens;
    final rows = <Widget>[
      for (var i = 0; i < widget.channels.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
          child: _GuideChannelRow(
            channel: widget.channels[i],
            selected: i == _selected,
            onTap: () => _select(i),
          ),
        ),
    ];

    if (isCompact) {
      // On a phone the rows scroll with the page: a nested scroller inside a
      // nested scroller is a scroll trap on touch.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s8),
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          children: rows,
        ),
      ),
    );
  }

  Widget _guidePane(
    BuildContext context,
    HardcodedChannel channel,
    bool isCompact,
  ) {
    final tokens = context.tokens;
    final now = _nowAiring();
    final upcoming = _upcoming(now);

    final header = <Widget>[
      Text(
        'Now Airing on ${channel.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ZplayType.overline.toStyle(color: tokens.accent),
      ),
      const SizedBox(height: ZplaySpacing.s4),
    ];

    final Widget upcomingSection = _upcomingSection(
      context,
      upcoming,
      isCompact,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            if (_loading)
              // Fixed, not `Expanded`: on a phone this pane sits in the page's
              // own scroll view, where the vertical constraint is unbounded and
              // a flex child would throw.
              const SizedBox(
                height: 132,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (now == null)
              _emptyState(context, channel, isCompact)
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          now.title.isEmpty ? 'Live broadcast' : now.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.title.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ZplaySpacing.s4),
                        Text(
                          _scheduleLine(now),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.caption.toStyle(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s16),
                  _WatchLiveButton(
                    onPressed: () => widget.onWatchLive(channel),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s12),
              _LiveProgressBar(entry: now),
              const SizedBox(height: ZplaySpacing.s16),
              upcomingSection,
            ],
          ],
        ),
      ),
    );
  }

  /// The lineup below the now-airing card. In the fixed-height television pane
  /// it takes the remaining room and scrolls inside it; on a phone it is part
  /// of the page and grows to fit.
  Widget _upcomingSection(
    BuildContext context,
    List<EpgEntry> upcoming,
    bool isCompact,
  ) {
    final tokens = context.tokens;

    final Widget label = Text(
      'Upcoming On This Channel',
      style: ZplayType.overline.toStyle(color: tokens.textMuted),
    );

    final Widget empty = Text(
      'Nothing else listed for this channel.',
      style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: ZplaySpacing.s8),
          if (upcoming.isEmpty)
            empty
          else
            for (final entry in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
                child: _UpcomingRow(entry: entry),
              ),
        ],
      );
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: ZplaySpacing.s8),
          Expanded(
            child: upcoming.isEmpty
                ? Align(alignment: Alignment.topLeft, child: empty)
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    itemCount: upcoming.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: ZplaySpacing.s8),
                    itemBuilder: (context, index) =>
                        _UpcomingRow(entry: upcoming[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    HardcodedChannel channel,
    bool isCompact,
  ) {
    final tokens = context.tokens;
    final height = isCompact ? 40.0 : kMinInteractiveDimension;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No programme guide for this channel yet.',
          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: ZplaySpacing.s4),
        Text(
          'Programme data comes from the channel\'s own panel, so it appears '
          'once one of your portals has a verified live feed for '
          '${channel.name}.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: ZplaySpacing.s12),
        FocusableCard(
          onTap: () => widget.onFindStreams(channel),
          builder: (context, state) => CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: AnimatedContainer(
              duration: ZplayMotion.fast,
              curve: ZplayMotion.standard,
              height: height,
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s16,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state.highlighted
                    ? tokens.borderStrong
                    : tokens.borderDefault,
                borderRadius: ZplayRadius.smAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 18,
                    color: tokens.textEmphasis,
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  Text(
                    'Find Live Streams',
                    style: ZplayType.label.toStyle(
                      color: tokens.textEmphasis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  EpgEntry? _nowAiring() {
    if (_epg.isEmpty) return null;
    for (final entry in _epg) {
      if (entry.isNow) return entry;
    }
    return _epg.first;
  }

  List<EpgEntry> _upcoming(EpgEntry? now) {
    if (now == null) return const [];
    final index = _epg.indexOf(now);
    return _epg.skip(index + 1).toList();
  }

  static String _scheduleLine(EpgEntry entry) {
    final total = entry.stop.difference(entry.start);
    final elapsed = DateTime.now().difference(entry.start);
    final clamped = elapsed < Duration.zero
        ? Duration.zero
        : (elapsed > total ? total : elapsed);
    final minutes = clamped.inMinutes;
    final percent = total.inSeconds <= 0
        ? 0
        : ((clamped.inSeconds / total.inSeconds) * 100).round().clamp(0, 100);

    return '${_clock(entry.start)} – ${_clock(entry.stop)} · '
        '$minutes mins elapsed ($percent% complete)';
  }

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// One channel in the guide's list: the short-name badge, the channel, its
/// category, and the LIVE tag.
///
/// Selection is a fill and a label colour, focus is the app's single 2 dp ring.
/// There is no left accent rule like the prototype's `.channel-card-row.active`
/// for the same reason the rail dropped its own: a second accent edge on the
/// row that also carries the focus ring reads as two borders on one control.
class _GuideChannelRow extends StatelessWidget {
  const _GuideChannelRow({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final HardcodedChannel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isCompact = FormFactorService.of(context) == FormFactor.compact;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          constraints: BoxConstraints(
            minHeight: isCompact ? 48.0 : 56.0,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s12,
            vertical: ZplaySpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accentSubtle
                : (state.highlighted ? tokens.borderDefault : Colors.transparent),
            borderRadius: ZplayRadius.smAll,
          ),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s8,
                  vertical: ZplaySpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: tokens.borderStrong,
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: Text(
                  channel.short,
                  textAlign: TextAlign.center,
                  style: ZplayType.caption
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: tokens.textPrimary),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.subtitle.toStyle(
                        color: selected ? tokens.accent : tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: ZplaySpacing.s2),
                    Text(
                      channel.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.danger,
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s4,
                    vertical: ZplaySpacing.s2,
                  ),
                  child: Text(
                    'LIVE',
                    style: ZplayType.overline
                        .copyWith(letterSpacing: 0.5)
                        .toStyle(color: tokens.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `[Watch Live Stream]`, the prototype's primary action on the guide.
class _WatchLiveButton extends StatelessWidget {
  const _WatchLiveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // The app's one primary control: white fill, dark label, and the shared
    // ring as its only focus marker. Its height comes from the pill, so the
    // guide no longer has to special-case the phone's shorter button.
    return PillButton(
      label: 'Watch Live Stream',
      icon: Icons.play_arrow_rounded,
      onPressed: onPressed,
    );
  }
}

/// The live-progress bar under the now-airing card: how far through the
/// programme the current time is.
class _LiveProgressBar extends StatelessWidget {
  const _LiveProgressBar({required this.entry});

  final EpgEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final total = entry.stop.difference(entry.start).inSeconds;
    final elapsed = DateTime.now().difference(entry.start).inSeconds;
    final fraction = total <= 0
        ? 0.0
        : (elapsed / total).clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: ZplayRadius.xsAll,
      child: SizedBox(
        height: ZplaySpacing.s4,
        // `double.infinity` so the track spans the pane: the guide's column is
        // start-aligned, which hands children a loose width, and a Stack sized
        // by its own non-positioned child would have shrunk the track to the
        // width of the fill.
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: tokens.textPrimary.withValues(
                alpha: ZplayOpacity.borderMedium,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: ColoredBox(color: tokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the upcoming lineup. Not a focus target: it is a listing, and a
/// listing that takes focus without doing anything is a dead stop in a D-pad
/// path. The prototype marks these `tv-focusable` and gives them no action.
class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.entry});

  final EpgEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.bg,
        borderRadius: ZplayRadius.xsAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s12,
          vertical: ZplaySpacing.s8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                '${_LiveGuideBandState._clock(entry.start)} – '
                '${_LiveGuideBandState._clock(entry.stop)}',
                style: ZplayType.caption.toStyle(color: tokens.textMuted),
              ),
            ),
            const SizedBox(width: ZplaySpacing.s8),
            Expanded(
              child: Text(
                entry.title.isEmpty ? 'Scheduled programme' : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZplayType.bodySmall
                    .copyWith(weight: FontWeight.w600)
                    .toStyle(color: tokens.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
