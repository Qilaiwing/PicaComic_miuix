part of 'components.dart';

/// Frosted backdrop shared by every pinned area (chip rows, sticky section
/// headers, pinned search bars): content scrolling underneath is blurred,
/// matching the Miuix top bar.
/// One frosted surface for every top bar and pinned header.
/// 降低模糊半径: 大 sigma 在中低端机上是主要的 GPU 开销之一。
const double kFrostSigma = 7;

/// Sticky section headers used a cheaper blur when they still frosted; kept for
/// any call sites that still pass an explicit sigma into [PinnedFrostHeader].
const double kStickyFrostSigma = 6;

/// Height of [StickySectionHeader]: short frost strip with an inline title capsule.
const double kStickySectionHeaderExtent = 36;

/// 设置「毛玻璃效果」(settings[92]), 关闭时改为不透明度较高的纯色底。
bool get frostEnabled => appdata.settings[92] != "0";

double frostTintAlpha(BuildContext context, {bool blur = true}) {
  if (!frostEnabled || !blur) return 1.0;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? 0.42 : 0.48;
}

/// 统一的毛玻璃: 开启时 BackdropFilter, 关闭时直接返回 child。
class FrostBlur extends StatelessWidget {
  const FrostBlur({super.key, this.sigma = kFrostSigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!frostEnabled) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// Live height of the main-frame top bar for pages whose content scrolls
/// underneath it (0 when the frame still pads the page itself).
class MainTopInset extends InheritedWidget {
  const MainTopInset({super.key, required this.height, required super.child});

  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainTopInset>()?.height ?? 0;

  @override
  bool updateShouldNotify(MainTopInset oldWidget) =>
      oldWidget.height != height;
}

/// Leading transparent pinned spacer: content starts below the top bar, then
/// scrolls under it; later pinned headers pin right below the bar.
class TopInsetSliver extends StatelessWidget {
  const TopInsetSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MainTopInset.of(context);
    if (h <= 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverPersistentHeader(pinned: true, delegate: _TopInsetDelegate(h));
  }
}

class _TopInsetDelegate extends SliverPersistentHeaderDelegate {
  _TopInsetDelegate(this.height);

  final double height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      const IgnorePointer(child: SizedBox.expand());

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(_TopInsetDelegate oldDelegate) => oldDelegate.height != height;
}

/// For non-scrolling states (loading / error) of an under-bar page.
class TopInsetPadding extends StatelessWidget {
  const TopInsetPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(top: MainTopInset.of(context)), child: child);
}

/// Content area of a page whose top bar floats over it: content starts below
/// the bar at rest and scrolls under it. Replaces `Padding(padding: padding)`
/// around a scaffold body. Box scroll views (ListView/GridView without an
/// explicit padding) pick the inset up from MediaQuery; CustomScrollViews add
/// [TopInsetSliver]; other scrollables use [MainTopInset.of].
class ScrollUnderBar extends StatelessWidget {
  const ScrollUnderBar({super.key, required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: padding.copyWith(top: 0),
      child: MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(
            top: padding.top,
            bottom: padding.bottom > 0 ? 0 : mq.padding.bottom,
          ),
        ),
        child: MainTopInset(height: padding.top, child: child),
      ),
    );
  }
}

class FrostedBackground extends StatelessWidget {
  const FrostedBackground({
    super.key,
    required this.child,
    this.alpha,
    this.enableBlur = true,
    this.sigma = kFrostSigma,
  });

  final Widget child;
  /// Defaults to the Miuix top bar's tint so pinned areas fuse with it.
  final double? alpha;
  /// When false, skip [BackdropFilter] and use a denser solid tint instead.
  final bool enableBlur;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final useBlur = enableBlur && frostEnabled;
    final tint = MiuixTheme.of(context).colors.background.withValues(
      alpha: alpha ?? frostTintAlpha(context, blur: useBlur),
    );
    final colored = ColoredBox(color: tint, child: child);
    if (!useBlur) {
      // Solid opaque tint: skip ClipRect save layer.
      return colored;
    }
    return ClipRect(
      child: FrostBlur(sigma: sigma, child: colored),
    );
  }
}

/// Full-width frosted sticky header. Blur only when content scrolls under it
/// ([overlapsContent]); otherwise a denser solid tint (no BackdropFilter).
/// When pinned under the main [FrostedBackground] top bar, skips a second
/// [BackdropFilter] and paints the same frost tint so the junction is seamless.
/// Prefer [StickySectionHeader] for section titles.
class PinnedFrostHeader extends StatelessWidget {
  const PinnedFrostHeader({
    super.key,
    required this.extent,
    required this.child,
    this.sigma = kFrostSigma,
  });

  final double extent;
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedFrostDelegate(
        extent: extent,
        child: child,
        sigma: sigma,
      ),
    );
  }
}

class _PinnedFrostDelegate extends SliverPersistentHeaderDelegate {
  _PinnedFrostDelegate({
    required this.extent,
    required this.child,
    required this.sigma,
  });

  final double extent;
  final Widget child;
  final double sigma;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final underTopBar = MainTopInset.of(context) > 0;

    // Under the main frosted top bar: never stack a second BackdropFilter.
    // Two adjacent ClipRect+blur layers truncate each other's blur kernels
    // and read as a darker horizontal seam. Match the top bar's frost tint
    // only, and nudge 1px under the bar so any ClipRect hairline is covered.
    if (underTopBar && overlapsContent) {
      final tint = FrostedBackground(
        enableBlur: false,
        alpha: frostEnabled
            ? frostTintAlpha(context, blur: true)
            : frostTintAlpha(context, blur: false),
        child: const SizedBox.expand(),
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, right: 0, top: -1, bottom: 0, child: tint),
          child,
        ],
      );
    }

    return FrostedBackground(
      enableBlur: overlapsContent,
      sigma: sigma,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedFrostDelegate oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.child != child ||
      oldDelegate.sigma != sigma;
}

/// Shared capsule metrics for sticky title + trailing actions (查看更多 / 刷新).
const double kStickyCapsuleFontSize = 13;
const EdgeInsets kStickyCapsulePadding =
    EdgeInsets.symmetric(horizontal: 12, vertical: 5);
const double kStickyCapsuleIconSize = 16;
const double kStickyCapsuleRefreshExtent = 28;

Color stickyCapsuleColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? scheme.primary.withValues(alpha: 0.24)
      : scheme.primary.withValues(alpha: 0.12);
}

/// Full-width frosted sticky section header that pins under the top bar while
/// its section is on screen. The title sits in a primary-tint stadium capsule
/// on a short frost strip (not a floating capsule over covers). Trailing
/// actions sit on the same strip. Put it as the first child of
/// `MultiSliver(pushPinnedChildren: true, ...)` so the next section's header
/// pushes it away.
class StickySectionHeader extends StatelessWidget {
  const StickySectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final capsuleColor = stickyCapsuleColor(context);

    return PinnedFrostHeader(
      extent: kStickySectionHeaderExtent,
      child: SizedBox(
        height: kStickySectionHeaderExtent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Expanded (not loose Flexible) keeps the title on the left and
              // pins [trailing] to the right edge of the strip.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: kStickyCapsulePadding,
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: capsuleColor,
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kStickyCapsuleFontSize,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
