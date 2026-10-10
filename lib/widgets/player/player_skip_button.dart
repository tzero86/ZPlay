import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/player/skip_segment_model.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';

/// Ultra-sleek, responsive glassmorphism Skip Button with dynamic hover effects
/// and a left-to-right sweep progress bar that auto-hides when complete.
class PlayerSkipButton extends StatefulWidget {
  final MediaSkipSegment segment;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;
  final Duration lifespan;

  const PlayerSkipButton({
    super.key,
    required this.segment,
    required this.onSkip,
    required this.onDismiss,
    this.lifespan = const Duration(seconds: 5),
  });

  @override
  State<PlayerSkipButton> createState() => _PlayerSkipButtonState();
}

class _PlayerSkipButtonState extends State<PlayerSkipButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;
  bool _isHovered = false;
  bool _isDismissHovered = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: widget.lifespan,
    );

    _sweepController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDismiss();
      }
    });

    _sweepController.forward();
  }

  @override
  void didUpdateWidget(PlayerSkipButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.uniqueKey != widget.segment.uniqueKey) {
      _sweepController.reset();
      _sweepController.forward();
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 640;

    final isCredits = widget.segment.type == 'credits';
    final accentColor = isCredits ? tokens.success : PlayerTheme.accent;
    final accentGlow = isCredits ? tokens.success : tokens.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        // Pause the auto-dismiss timer while user is hovering to let them click comfortably
        _sweepController.stop();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        // Resume the countdown
        if (mounted) {
          _sweepController.forward();
        }
      },
      child: AnimatedScale(
        scale: _isHovered ? (isCompact ? 1.02 : 1.04) : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: isCompact ? ZplayRadius.smAll : ZplayRadius.mdAll,
            border: Border.all(
              color: _isHovered
                  ? accentGlow.withValues(alpha: 0.85)
                  : tokens.borderStrong,
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              // Deep ambient drop shadow
              BoxShadow(
                color: tokens.bg.withValues(alpha: 0.75),
                offset: const Offset(0, 8),
                blurRadius: 28,
              ),
              // Reactive neon hover glow
              if (_isHovered) ...[
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.40),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: accentGlow.withValues(alpha: 0.20),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ],
          ),
          child: ClipRRect(
            borderRadius: isCompact ? ZplayRadius.smAll : ZplayRadius.mdAll,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: _isHovered
                    ? tokens.surfaceOverlay.withValues(alpha: 0.95)
                    : tokens.surfaceOverlay.withValues(alpha: 0.85),
                child: Stack(
                  children: [
                    // Dynamic Sweep Gradient Shimmer that follows countdown
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, _) {
                          final progress = _sweepController.value;
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: [
                                  (progress - 0.25).clamp(0.0, 1.0),
                                  progress.clamp(0.0, 1.0),
                                  (progress + 0.15).clamp(0.0, 1.0),
                                ],
                                colors: [
                                  Colors.transparent,
                                  accentColor.withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcOver,
                            child: Container(
                              color: tokens.textPrimary.withValues(alpha: 0.04),
                            ),
                          );
                        },
                      ),
                    ),

                    // Main Content Row
                    IntrinsicHeight(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Primary Clickable Skip Body
                          FocusableInkWell(
                            onTap: widget.onSkip,
                            hoverColor: accentColor.withValues(alpha: 0.15),
                            splashColor: accentGlow.withValues(alpha: 0.30),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 13 : 18,
                                vertical: isCompact ? 9 : 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Animated Action Icon
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    transform: Matrix4.translationValues(
                                      _isHovered ? 2.0 : 0.0,
                                      0.0,
                                      0.0,
                                    ),
                                    child: Icon(
                                      widget.segment.icon,
                                      size: isCompact ? 16 : 20,
                                      color: _isHovered ? accentGlow : accentColor,
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 7 : 10),

                                  // Action Label
                                  Text(
                                    widget.segment.label,
                                    style: (isCompact ? ZplayType.label : ZplayType.body)
                                        .toStyle(color: tokens.textPrimary)
                                        .copyWith(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              offset: const Offset(0, 1),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Vertical Frosted Divider
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            color: tokens.borderStrong,
                          ),

                          // '✕' Dismiss Button
                          MouseRegion(
                            onEnter: (_) => setState(() => _isDismissHovered = true),
                            onExit: (_) => setState(() => _isDismissHovered = false),
                            child: FocusableInkWell(
                              onTap: widget.onDismiss,
                              hoverColor: tokens.textPrimary
                                  .withValues(alpha: ZplayOpacity.overlayHover),
                              splashColor: tokens.textPrimary.withValues(alpha: 0.25),
                              child: Tooltip(
                                message: 'Dismiss (✕)',
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 9 : 12,
                                    vertical: isCompact ? 9 : 12,
                                  ),
                                  alignment: Alignment.center,
                                  child: AnimatedScale(
                                    scale: _isDismissHovered ? 1.15 : 1.0,
                                    duration: const Duration(milliseconds: 140),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: isCompact ? 15 : 17,
                                      color: _isDismissHovered
                                          ? tokens.textPrimary
                                          : tokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Left-to-Right Countdown Laser / Fade Line
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: isCompact ? 2.0 : 2.5,
                      child: AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, _) {
                          final sweepProgress = _sweepController.value.clamp(0.0, 1.0);

                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: sweepProgress,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: ZplayRadius.fullAll,
                                gradient: LinearGradient(
                                  colors: [
                                    accentColor.withValues(alpha: 0.5),
                                    accentGlow,
                                    tokens.textPrimary,
                                  ],
                                  stops: const [0.0, 0.85, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentGlow.withValues(alpha: 0.8),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                    offset: const Offset(0, -0.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
