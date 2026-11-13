import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// Animated shimmer skeleton shown while a poster image is loading.
class PosterSkeleton extends StatefulWidget {
  const PosterSkeleton({super.key});

  @override
  State<PosterSkeleton> createState() => _PosterSkeletonState();
}

class _PosterSkeletonState extends State<PosterSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.2,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FadeTransition is hardware accelerated and bypasses expensive paint/layout
    // phases during animation, making it extremely performant for scrolling lists.
    return FadeTransition(
      opacity: _animation,
      child: ColoredBox(color: ZplayTokens.of(context).surface),
    );
  }
}

/// Placeholder shown when a poster image fails to load.
class MissingPoster extends StatelessWidget {
  const MissingPoster({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    return ColoredBox(
      color: tokens.surface,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 46, color: tokens.textDisabled),
      ),
    );
  }
}
