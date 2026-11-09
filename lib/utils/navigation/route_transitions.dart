import 'package:flutter/material.dart';

import '../../services/diagnostics/perf_monitor.dart';
import '../../services/theme/design_tokens.dart';

/// Standard Material-style push transition helper.
Route<T> materialRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) =>
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return _TransitionTimer(
          animation: animation,
          routeName: settings?.name ?? 'material',
          child: FadeTransition(
            opacity: animation,
            child: RepaintBoundary(child: child),
          ),
        );
      },
      settings: settings,
    );

/// A fade-through push: the new screen cross-fades in over the old one.
///
/// This replaced a 380 ms circular reveal, which clipped the incoming page from
/// the tap point. That mask re-clipped the whole screen every frame and read as
/// theatre: every push announced its own machinery instead of saying "this is
/// the next screen". One opacity animation says the same thing for the cost of
/// one animation, and it is the motion the identity charter in
/// `docs/REDESIGN_DIRECTION.md` asks for.
///
/// Reduced motion: when [MediaQueryData.disableAnimations] is set the incoming
/// page is shown immediately, so nothing moves. The route's duration stays
/// fixed, and the duration is deliberately not read from the context:
/// [transitionDuration] is settled when the route is constructed,
/// before it has a [BuildContext], and a duration that varied per push would
/// make [PerfMonitor]'s route timings incomparable and the back gesture's
/// timing unpredictable. Only the visible motion depends on that setting.
///
/// The route stays opaque, so the previous route stops being painted once the
/// transition completes, and pops take the same builder in reverse.
class FadeThroughRoute extends PageRouteBuilder {
  final Widget page;

  FadeThroughRoute({
    required this.page,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: ZplayMotion.slow,
          reverseTransitionDuration: ZplayMotion.base,
          opaque: true, // During transition it will still show the previous route, but stops rendering it when finished!
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // A route has no context when it is built, so the only place the
            // reduced-motion setting can be read is here, per frame.
            final reducedMotion =
                MediaQuery.maybeOf(context)?.disableAnimations ?? false;

            return _TransitionTimer(
              animation: animation,
              routeName: page.runtimeType.toString(),
              child: reducedMotion
                  ? child
                  : FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: ZplayMotion.standard,
                      ),
                      // The page sits behind its own layer so the fade does not
                      // repaint page content every frame.
                      child: RepaintBoundary(child: child),
                    ),
            );
          },
        );
}

/// A cinematic content-slide transition for the Watch Screen.
///
/// The incoming page's content slides in from the right and fades in.
/// Slide (transform-only) + a single fade: no clip, no scale stacking.
/// The page sits in a [RepaintBoundary] so the slide does not repaint content.
class CinematicSlideRoute extends PageRouteBuilder {
  final Widget page;

  CinematicSlideRoute({
    required this.page,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          opaque: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Incoming page: slide from right + fade in
            final inCurve = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.25, 0.1, 0.25, 1.0),
              reverseCurve: Curves.easeInCubic,
            );

            final slideIn = Tween<Offset>(
              begin: const Offset(0.15, 0),
              end: Offset.zero,
            ).animate(inCurve);

            final fadeIn = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ));

            return _TransitionTimer(
              animation: animation,
              routeName: page.runtimeType.toString(),
              child: SlideTransition(
                position: slideIn,
                child: FadeTransition(
                  opacity: fadeIn,
                  child: RepaintBoundary(child: child),
                ),
              ),
            );
          },
        );
}

/// Times one push (forward → completed) and one pop (reverse → dismissed)
/// per route and reports both to [PerfMonitor].
///
/// Zero render cost: [build] returns [child] untouched; the only work is a
/// single status listener plus a [Stopwatch].
class _TransitionTimer extends StatefulWidget {
  final Animation<double> animation;
  final String routeName;
  final Widget child;

  const _TransitionTimer({
    required this.animation,
    required this.routeName,
    required this.child,
  });

  @override
  State<_TransitionTimer> createState() => _TransitionTimerState();
}

class _TransitionTimerState extends State<_TransitionTimer> {
  late final Stopwatch _sw;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    widget.animation.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final ms = _sw.elapsedMilliseconds;
      _sw.stop();
      try {
        PerfMonitor.recordRoute('push', widget.routeName, durationMs: ms);
      } catch (_) {}
    } else if (status == AnimationStatus.reverse) {
      // Pop begins: restart the clock so the pop duration is measured alone.
      _sw
        ..reset()
        ..start();
    } else if (status == AnimationStatus.dismissed) {
      final ms = _sw.elapsedMilliseconds;
      _sw.stop();
      try {
        PerfMonitor.recordRoute('pop', widget.routeName, durationMs: ms);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}