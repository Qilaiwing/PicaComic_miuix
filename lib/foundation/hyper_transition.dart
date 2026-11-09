part of 'app_page_route.dart';

/// HyperOS-like page transition: the new page slides in from the right with
/// an emphasized-decelerate curve and a slight fade, while the page below
/// moves left with parallax and dims a little. During a user gesture (iOS
/// edge swipe) the animation follows the finger linearly.
class HyperPageTransition extends StatelessWidget {
  const HyperPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.linear,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool linear;
  final Widget child;

  static const _curve = Easing.emphasizedDecelerate;
  static const _reverseCurve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    final primary = linear
        ? animation
        : CurvedAnimation(
            parent: animation, curve: _curve, reverseCurve: _reverseCurve);
    final secondary = linear
        ? secondaryAnimation
        : CurvedAnimation(
            parent: secondaryAnimation,
            curve: _curve,
            reverseCurve: _reverseCurve);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final dir = isRtl ? -1.0 : 1.0;
    return SlideTransition(
      position: Tween(begin: Offset(-0.28 * dir, 0), end: Offset.zero)
          .animate(ReverseAnimation(secondary)),
      child: AnimatedBuilder(
        animation: secondary,
        builder: (context, child) {
          final dim = 0.06 * secondaryAnimation.value;
          if (dim <= 0) return child!;
          return Stack(fit: StackFit.passthrough, children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                    color: Colors.black.withValues(alpha: dim)),
              ),
            ),
          ]);
        },
        child: SlideTransition(
          position: Tween(begin: Offset(dir, 0), end: Offset.zero)
              .animate(primary),
          // No fade on the incoming page: a half-transparent page over the
          // dimmed page below read as a gray scrim popping up first.
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                ),
              ]),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}