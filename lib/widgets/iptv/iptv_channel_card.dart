import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/storage/app_image_cache.dart';
import '../common/card_badges.dart';
import '../common/focusable_card.dart';

class IptvChannelCard extends StatelessWidget {
  final HardcodedChannel channel;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  const IptvChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ch = channel;
    final primaryColor = ch.gradient.isNotEmpty ? ch.gradient.first : tokens.accent;
    // Second stop of a channel's data-driven gradient; falls back to the info hue.
    final secondaryColor = ch.gradient.length > 1 ? ch.gradient.last : tokens.info;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => RepaintBoundary(
        child: AnimatedScale(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          scale: state.pressed ? 0.96 : (state.hovered ? IptvSettings.cardHoverZoom.value : 1.0),
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            transform: Matrix4.translationValues(0, state.hovered ? -3 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster / Gradient Box.
                //
                // `AspectRatio` at the 1.35 that `IptvCardSizing` budgets, so
                // the tile keeps the shape its own sizing claims. With a bare
                // `Expanded` the tile absorbed whatever the rail offered, which
                // is the same defect `MovieCard` had.
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 1 / 1.35,
                  child: CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.mdAll,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: ZplayRadius.mdAll,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primaryColor.withValues(alpha: 0.85),
                            secondaryColor.withValues(alpha: 0.70),
                            tokens.surface,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                        boxShadow: [
                          // The bloom is a pointer affordance only: on focus
                          // the ring is the single mark, as on every card.
                          BoxShadow(
                            color: state.hovered
                                ? primaryColor.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.35),
                            blurRadius: state.hovered ? 20 : 10,
                            offset: Offset(0, state.hovered ? 8 : 4),
                          ),
                        ],
                        // No border of its own. A focused card must paint
                        // exactly one edge, and that edge is `CardFocusRing`;
                        // the prototype's live rows carry a transparent border
                        // slot and nothing else, for the same reason.
                      ),
                      child: ClipRRect(
                        borderRadius: ZplayRadius.mdAll,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Ambient Pattern Lines / Glow
                            Positioned(
                              top: -20,
                              right: -20,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                                ),
                              ),
                            ),

                            // Channel Icon / Logo / Short text
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 28, 14, 16),
                                child: SizedBox(
                                  width: 130,
                                  height: 100,
                                  child: ch.iconUrl != null && ch.iconUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: ch.iconUrl!,
                                          cacheManager: AppImageCache.manager,
                                          // Logo box is 130x100; bound to ~3x.
                                          memCacheWidth: 390,
                                          fit: BoxFit.contain,
                                          placeholder: (_, _) => Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: tokens.textDisabled,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, _, _) => _buildShortBadge(context, ch))
                                      : _buildShortBadge(context, ch),
                                ),
                              ),
                            ),

                            // Type badge (top-left): the channel's category is
                            // the one classification a live stream carries, so it
                            // takes the poster's type-badge slot and is revealed
                            // on focus, like every other card.
                            if (state.focused && IptvSettings.showCategoryTag.value)
                              Positioned(
                                top: 10,
                                left: 10,
                                child: CardTypeBadge(
                                  label: ch.category.toUpperCase(),
                                ),
                              ),

                            // Live indicator (top-right), present in every state
                            // - a live channel is live whether or not it is
                            // focused.
                            if (IptvSettings.showHdBadge.value)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    // Live badge scrim over the channel artwork: the alpha stays.
                                    color: tokens.bg.withValues(alpha: 0.65),
                                    borderRadius: ZplayRadius.xsAll,
                                    border: Border.all(
                                      color: tokens.danger.withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: tokens.danger,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: tokens.danger,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: ZplaySpacing.s4),
                                      Text(
                                        'LIVE',
                                        style: ZplayType.overline.toStyle(color: tokens.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Gloss overlay on hover
                            if (state.highlighted)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ),

                // Title
                const SizedBox(height: ZplaySpacing.s8),
                Text(
                  ch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),

                // Category & Stream tag
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (IptvSettings.showCategoryTag.value) ...[
                      Text(
                        ch.category,
                        style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          width: 3.5,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: tokens.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                    Text(
                      'HD Live',
                      style: ZplayType.caption.toStyle(color: primaryColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShortBadge(BuildContext context, HardcodedChannel ch) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            // Monogram scrim over the card's gradient: the alpha stays.
            color: tokens.bg.withValues(alpha: 0.3),
            borderRadius: ZplayRadius.smAll,
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Text(
            ch.short,
            style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
          ),
        ),
      ],
    );
  }
}
