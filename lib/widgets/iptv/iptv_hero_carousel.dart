import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/storage/app_image_cache.dart';
import '../common/focusable_card.dart';
import 'iptv_hero_artwork.dart';

class IptvHeroCarousel extends StatefulWidget {
  final List<HardcodedChannel> channels;
  final Function(HardcodedChannel) onWatchNow;
  final Function(HardcodedChannel) onSourcesTap;

  const IptvHeroCarousel({
    super.key,
    required this.channels,
    required this.onWatchNow,
    required this.onSourcesTap,
  });

  @override
  State<IptvHeroCarousel> createState() => _IptvHeroCarouselState();
}

class _IptvHeroCarouselState extends State<IptvHeroCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    IptvSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    _startTimer();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _startTimer();
  }

  @override
  void dispose() {
    IptvSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!IptvSettings.heroAutoRotate.value) return;
    if (widget.channels.length <= 1) return;
    final interval = Duration(seconds: IptvSettings.heroRotateSeconds.value);
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || _isHovering || !_pageController.hasClients) return;
      final next = (_currentIndex + 1) % widget.channels.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  double _heroHeight(double screenWidth, double screenHeight) {
    final style = IptvSettings.heroStyle.value;
    if (style == HeroStyle.compact) {
      return (screenHeight * 0.38).clamp(300.0, 400.0);
    } else if (style == HeroStyle.minimalist) {
      return (screenHeight * 0.28).clamp(210.0, 260.0);
    }
    // Default Immersive
    return (screenHeight * 0.52).clamp(380.0, 560.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = _heroHeight(screenWidth, screenHeight);
    final isDesktop = _isDesktop();
    final tokens = context.tokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: RepaintBoundary(
        child: SizedBox(
          height: heroHeight,
          width: screenWidth,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Page View
              PageView.builder(
                controller: _pageController,
                itemCount: widget.channels.length,
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                },
                itemBuilder: (context, index) {
                  final ch = widget.channels[index];
                  return _IptvHeroSlide(
                    channel: ch,
                    onWatchNow: () => widget.onWatchNow(ch),
                    onSourcesTap: () => widget.onSourcesTap(ch),
                  );
                },
              ),

              // Desktop Previous / Next Hover Arrows
              if (isDesktop && _isHovering && widget.channels.length > 1) ...[
                Positioned(
                  left: 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () {
                        final prev = (_currentIndex - 1 + widget.channels.length) %
                            widget.channels.length;
                        _pageController.animateToPage(
                          prev,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () {
                        final next = (_currentIndex + 1) % widget.channels.length;
                        _pageController.animateToPage(
                          next,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                        );
                      },
                    ),
                  ),
                ),
              ],

              // Indicator Dots
              if (widget.channels.length > 1)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        widget.channels.length,
                        (index) => FocusableCard(
                          onTap: () {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          builder: (context, state) => CardFocusRing(
                            focused: state.focused,
                            radius: ZplayRadius.xsAll,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4),
                              width: _currentIndex == index ? 26 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _currentIndex == index
                                    ? tokens.accent
                                    : tokens.textDisabled,
                                borderRadius: ZplayRadius.xsAll,
                                boxShadow: _currentIndex == index
                                    ? [
                                        BoxShadow(
                                          color: tokens.accent.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
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

class _IptvHeroSlide extends StatelessWidget {
  final HardcodedChannel channel;
  final VoidCallback onWatchNow;
  final VoidCallback onSourcesTap;

  const _IptvHeroSlide({
    required this.channel,
    required this.onWatchNow,
    required this.onSourcesTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primaryColor =
        channel.gradient.isNotEmpty ? channel.gradient.first : tokens.accent;
    // Second stop of a channel's data-driven gradient; falls back to the info hue.
    final secondaryColor =
        channel.gradient.length > 1 ? channel.gradient.last : tokens.info;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Gradient & Ambient Glow Mesh (Fallback base)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primaryColor.withValues(alpha: 0.45),
                secondaryColor.withValues(alpha: 0.20),
                tokens.bg,
              ],
              stops: const [0.0, 0.4, 0.9],
            ),
          ),
        ),

        // The channel's art, in whatever form it can take: its backdrop when
        // one loads, its own wordmark when none does. The band's picture area is
        // never left bare - see [IptvHeroArtwork] for why it is filled rather
        // than collapsed.
        Positioned.fill(child: IptvHeroArtwork(channel: channel)),

        // Dark top/bottom gradient overlay for readability
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tokens.bg.withValues(alpha: 0.25),
                  tokens.bg.withValues(alpha: 0.60),
                  tokens.bg.withValues(alpha: 0.92),
                  tokens.bg,
                ],
                stops: const [0.0, 0.42, 0.82, 1.0],
              ),
            ),
          ),
        ),

        // Left-to-right gradient overlay to make logo and buttons pop
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  tokens.bg.withValues(alpha: 0.88),
                  tokens.bg.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.50, 1.0],
              ),
            ),
          ),
        ),

        // Content
        Positioned(
          left: 32,
          right: 32,
          bottom: 44,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // LIVE Pulse & Category row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.danger.withValues(alpha: 0.9),
                      borderRadius: ZplayRadius.smAll,
                      boxShadow: [
                        BoxShadow(
                          color: tokens.danger.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors_rounded, color: tokens.textPrimary, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          'LIVE BROADCAST',
                          style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong),
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                      ),
                    ),
                    child: Text(
                      channel.category,
                      style: ZplayType.caption.toStyle(color: tokens.textEmphasis),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Channel Logo (instead of plain text name)
              if (channel.iconUrl != null && channel.iconUrl!.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 280,
                    maxHeight: 65,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: channel.iconUrl!,
                    cacheManager: AppImageCache.manager,
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.contain,
                    memCacheWidth: 512,
                    errorWidget: (_, __, ___) => Text(
                      channel.name,
                      style: ZplayType.display.toStyle(color: tokens.textPrimary),
                    )),
                )
              else
                Text(
                  channel.name,
                  style: ZplayType.display.toStyle(color: tokens.textPrimary),
                ),

              const SizedBox(height: 12),

              // Description / stream info
              Text(
                'Instant live multi-source streaming with real-time stream resolution & high-framerate playback.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZplayType.body.toStyle(color: tokens.textEmphasis),
              ),

              const SizedBox(height: 18),

              // Action Buttons
              Row(
                children: [
                  // Primary Watch Live Button
                  FocusableCard(
                    onTap: onWatchNow,
                    builder: (context, state) => CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.mdAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s24,
                          vertical: ZplaySpacing.s12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: ZplayRadius.mdAll,
                          gradient: LinearGradient(
                            colors: [tokens.accent, tokens.info],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: tokens.onAccent, size: 22),
                            const SizedBox(width: ZplaySpacing.s8),
                            Text(
                              'Watch Live',
                              style: ZplayType.subtitle.toStyle(color: tokens.onAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Sources / Stream Selector Pill
                  FocusableCard(
                    onTap: onSourcesTap,
                    builder: (context, state) => CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.mdAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: ZplaySpacing.s12),
                        decoration: BoxDecoration(
                          color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: tokens.borderStrong),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded, color: tokens.textEmphasis, size: 18),
                            const SizedBox(width: ZplaySpacing.s8),
                            Text(
                              'Stream Feeds',
                              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeroArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.lgAll,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Arrow sits over the hero artwork: the black scrim keeps its alpha.
            color: state.highlighted
                ? tokens.accent
                : tokens.bg.withValues(alpha: 0.55),
            border: Border.all(
              color: state.highlighted
                  ? tokens.accent
                  : tokens.borderStrong,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: state.highlighted
                    ? tokens.accent.withValues(alpha: 0.45)
                    : Colors.black45,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: tokens.textPrimary,
            size: 26,
          ),
        ),
      ),
    );
  }
}
