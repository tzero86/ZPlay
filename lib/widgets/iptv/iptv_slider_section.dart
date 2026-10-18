import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_settings.dart';
import '../common/section_header.dart';
import '../common/slider_arrow.dart';
import 'iptv_channel_card.dart';
import 'iptv_health_badge.dart';

class IptvCardSizing {
  final double cardWidth;
  final double posterHeight;
  final double totalHeight;
  final double spacing;
  final double sidePadding;

  const IptvCardSizing({
    required this.cardWidth,
    required this.posterHeight,
    required this.totalHeight,
    required this.spacing,
    required this.sidePadding,
  });

  factory IptvCardSizing.fromWidth(double screenWidth) {
    double cardWidth;
    if (screenWidth < 600) {
      cardWidth = 145;
    } else if (screenWidth < 1000) {
      cardWidth = 165;
    } else if (screenWidth < 1400) {
      cardWidth = 185;
    } else {
      cardWidth = 205;
    }

    final density = IptvSettings.cardDensity.value;
    if (density == CardDensity.compact) {
      cardWidth *= 0.85;
    } else if (density == CardDensity.cinematic) {
      cardWidth *= 1.20;
    }

    final posterHeight = cardWidth * 1.35;
    final totalHeight = posterHeight + 66;

    return IptvCardSizing(
      cardWidth: cardWidth,
      posterHeight: posterHeight,
      totalHeight: totalHeight,
      spacing: 16,
      sidePadding: 18,
    );
  }
}

class IptvSliderSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<HardcodedChannel> channels;
  final Function(HardcodedChannel) onChannelTap;
  final VoidCallback? onSeeAll;

  /// Per-channel feed health keyed by [HardcodedChannel.id], or null for a rail
  /// whose caller has nothing to say about health - in which case no card draws
  /// a badge and the rail is the rail it always was.
  final Map<String, IptvHitHealth>? healthByChannelId;

  const IptvSliderSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.channels,
    required this.onChannelTap,
    this.onSeeAll,
    this.healthByChannelId,
  });

  @override
  State<IptvSliderSection> createState() => _IptvSliderSectionState();
}

class _IptvSliderSectionState extends State<IptvSliderSection> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHoveringSlider = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;
    final canLeft = _scrollController.position.pixels > 10;
    final canRight = _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 10;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;
    final viewportWidth = _scrollController.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.8 * directionMultiplier;
    final target = (_scrollController.position.pixels + scrollAmount)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) return const SizedBox.shrink();

    final sizing = IptvCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final isDesktop = _isDesktop();

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header matching Home & Anime Pages
          SectionHeader(
            title: widget.title,
            count: widget.channels.length,
            subtitle: widget.subtitle,
            onSeeAll: widget.onSeeAll,
          ),

          // Horizontal List with Desktop Navigation Arrows
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringSlider = true),
            onExit: (_) => setState(() => _isHoveringSlider = false),
            child: SizedBox(
              height: sizing.totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.channels.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(width: sizing.spacing),
                    itemBuilder: (context, index) {
                      final ch = widget.channels[index];
                      return SizedBox(
                        width: sizing.cardWidth,
                        child: IptvChannelCard(
                          channel: ch,
                          health: widget.healthByChannelId?[ch.id],
                          onTap: () => widget.onChannelTap(ch),
                        ),
                      );
                    },
                  ),

                  // Desktop Floating Scroll Arrows
                  if (isDesktop) ...[
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      left: _canScrollLeft && _isHoveringSlider ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scroll(-1),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      right: _canScrollRight && _isHoveringSlider ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_forward_ios_rounded,
                          onTap: () => _scroll(1),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
