part of 'components.dart';

class Appbar extends StatefulWidget implements PreferredSizeWidget {
  const Appbar(
      {required this.title,
      this.leading,
      this.actions,
      this.backgroundColor,
      super.key});

  final Widget title;

  final Widget? leading;

  final List<Widget>? actions;

  final Color? backgroundColor;

  @override
  State<Appbar> createState() => _AppbarState();

  @override
  Size get preferredSize => const Size.fromHeight(_kAppBarHeight);
}

class _AppbarState extends State<Appbar> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        defaultScrollNotificationPredicate(notification)) {
      final bool oldScrolledUnder = _scrolledUnder;
      final ScrollMetrics metrics = notification.metrics;
      switch (metrics.axisDirection) {
        case AxisDirection.up:
          // Scroll view is reversed
          _scrolledUnder = metrics.extentAfter > 0;
        case AxisDirection.down:
          _scrolledUnder = metrics.extentBefore > 0;
        case AxisDirection.right:
        case AxisDirection.left:
          // Scrolled under is only supported in the vertical axis, and should
          // not be altered based on horizontal notifications of the same
          // predicate since it could be a 2D scroller.
          break;
      }

      if (_scrolledUnder != oldScrolledUnder) {
        setState(() {
          // React to a change in MaterialState.scrolledUnder
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var content = SizedBox(
      height: _kAppBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: DefaultTextStyle(
                  style: DefaultTextStyle.of(context).style.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  child: widget.title,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            child: widget.leading ??
                (Navigator.of(context).canPop()
                    ? AppTooltip(
                        message: "返回".tl,
                        child: MiuixIconButton(
                          onPressed: () => Navigator.pop(context),
                          child: MiuixIcon(
                            vector:
                                MiuixIcons.extended.byName('chevronBackward') ??
                                    MiuixIcons.os4.back,
                            size: 20,
                            tint:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF111111),
                          ),
                        ),
                      )
                    : const SizedBox()),
          ),
          if (widget.actions != null)
            Positioned(
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: widget.actions!,
              ),
            ),
        ],
      ),
    ).paddingTop(context.padding.top);
    if (widget.backgroundColor != Colors.transparent) {
      final baseColor =
          widget.backgroundColor ?? MiuixTheme.of(context).colors.background;
      final barColor = baseColor.withValues(alpha: frostTintAlpha(context));
      if (!frostEnabled) {
        return ColoredBox(color: barColor, child: content);
      }
      return ClipRect(
        child: FrostBlur(
          child: ColoredBox(
            color: barColor,
            child: content,
          ),
        ),
      );
    }
    return content;
  }
}

/// 统一的大标题 Sliver 顶栏（全项目子页面共用）。
///
/// - 背景延伸到状态栏下（沉浸式），颜色取 Miuix 页面底色，避免与页面割裂；
/// - 大标题随滚动上移淡出，布局与 [MiuixTopAppBar] 一致：折叠带 52 + 标题行高
///   + 6，标题行高按字体实测，不再写死 bottom 偏移，避免字形（如 g）被裁掉；
/// - [bottom]（如筛选 Chip / Tab 行）作为顶栏的一部分固定显示，高度计入
///   min/maxExtent，滚动时不会被顶栏盖住。
class SliverAppbar extends StatelessWidget {
  const SliverAppbar({
    super.key,
    required this.title,
    this.largeTitle,
    this.leftSmallTitle = false,
    this.leading,
    this.actions,
    this.color,
    this.radius = 0,
    this.bottom,
    this.bottomHeight = 0,
  });

  final Widget? leading;

  final Widget title;

  final Widget? largeTitle;

  final bool leftSmallTitle;

  final List<Widget>? actions;

  final Color? color;

  final double radius;

  /// 固定在顶栏底部的附加内容（Tab / 筛选 Chip 行）。
  final Widget? bottom;

  /// [bottom] 的高度。
  final double bottomHeight;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return SliverPersistentHeader(
      pinned: true,
      delegate: _MySliverAppBarDelegate(
        leading: leading,
        title: title,
        largeTitle: largeTitle,
        leftSmallTitle: leftSmallTitle,
        actions: actions,
        topPadding: MediaQuery.of(context).padding.top,
        color: color ?? MiuixTheme.of(context).colors.background,
        radius: radius,
        bottom: bottom,
        bottomHeight: bottom == null ? 0 : bottomHeight,
        largeTitleLineHeight:
            textScaler.scale(_kLargeTitleFontSize) * _kLargeTitleLineHeight,
      ),
    );
  }
}

const _kAppBarHeight = 52.0;

/// 大标题字号 / 行高（与 [MiuixTopAppBar] 一致）。
const _kLargeTitleFontSize = 25.0;
const _kLargeTitleLineHeight = 1.3;

/// 大标题与折叠带、底部之间的统一间距。
const _kLargeTitleBottomPadding = 6.0;

class _MySliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget? leading;

  final Widget title;

  final Widget? largeTitle;

  final bool leftSmallTitle;

  final List<Widget>? actions;

  final double topPadding;

  final Color? color;

  final double radius;

  final Widget? bottom;

  final double bottomHeight;

  final double largeTitleLineHeight;

  _MySliverAppBarDelegate({
    this.leading,
    required this.title,
    this.largeTitle,
    this.leftSmallTitle = false,
    this.actions,
    this.color,
    required this.topPadding,
    this.radius = 0,
    this.bottom,
    this.bottomHeight = 0,
    required this.largeTitleLineHeight,
  });

  double get _expansion => largeTitleLineHeight + _kLargeTitleBottomPadding;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxShrink = maxExtent - minExtent;
    final shrink = shrinkOffset.clamp(0.0, maxShrink);
    final progress = maxShrink > 0 ? (shrink / maxShrink).clamp(0.0, 1.0) : 0.0;
    final largeTitleOpacity = (1.0 - progress * 2.2).clamp(0.0, 1.0);
    final smallTitleOpacity = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);

    final baseColor = color ?? MiuixTheme.of(context).colors.background;
    // 全局统一的毛玻璃：与吸顶分区头同 tint/sigma，无分割线，融为一体。
    final bgColor = baseColor.withValues(alpha: frostTintAlpha(context));
    final fg = isDark ? Colors.white : const Color(0xFF111111);

    Widget barBody = Container(
            color: bgColor,
            child: Stack(
              children: [
                // 大标题层：位于折叠带下方，随收缩上移并在折叠带下缘被裁掉。
                Positioned(
                  top: topPadding + _kAppBarHeight - 8,
                  left: 0,
                  right: 0,
                  height: largeTitleLineHeight + 8,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        if (largeTitleOpacity > 0.01)
                          Positioned(
                            left: 24,
                            right: 24,
                            top: 8 - shrink,
                            child: Opacity(
                              opacity: largeTitleOpacity,
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  fontSize: _kLargeTitleFontSize,
                                  height: _kLargeTitleLineHeight,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.4,
                                  color: fg,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                child: largeTitle ?? title,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: topPadding,
                  left: 0,
                  right: 0,
                  height: _kAppBarHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: leftSmallTitle
                            ? Padding(
                                padding:
                                    const EdgeInsets.only(left: 58, right: 54),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Opacity(
                                    opacity: smallTitleOpacity,
                                    child: Transform.translate(
                                      offset: Offset(0,
                                          10 * (1 - smallTitleOpacity) - 1.0),
                                      child: DefaultTextStyle(
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                          height: 1.2,
                                          color: fg,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.left,
                                        child: title,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 50),
                                  child: Opacity(
                                    opacity: smallTitleOpacity,
                                    child: Transform.translate(
                                      offset: Offset(0,
                                          10 * (1 - smallTitleOpacity) - 1.0),
                                      child: DefaultTextStyle(
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                          height: 1.2,
                                          color: fg,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        child: title,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        left: 8,
                        child: leading ??
                            (Navigator.of(context).canPop()
                                ? AppTooltip(
                                    message: "返回".tl,
                                    child: MiuixIconButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: MiuixIcon(
                                        vector: MiuixIcons.extended
                                                .byName('chevronBackward') ??
                                            MiuixIcons.os4.back,
                                        size: 20,
                                        tint: fg,
                                      ),
                                    ),
                                  )
                                : const SizedBox()),
                      ),
                      if (actions != null)
                        Positioned(
                          right: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions!,
                          ),
                        ),
                    ],
                  ),
                ),
                if (bottom != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: bottomHeight,
                    child: bottom!,
                  ),
              ],
            ),
    );
    if (!frostEnabled) {
      return SizedBox.expand(child: barBody);
    }
    return SizedBox.expand(
      child: ClipRect(
        child: FrostBlur(child: barBody),
      ),
    );
  }

  @override
  double get maxExtent =>
      topPadding + _kAppBarHeight + _expansion + bottomHeight;

  @override
  double get minExtent => topPadding + _kAppBarHeight + bottomHeight;

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _MySliverAppBarDelegate ||
        leading != oldDelegate.leading ||
        title != oldDelegate.title ||
        actions != oldDelegate.actions ||
        bottom != oldDelegate.bottom ||
        bottomHeight != oldDelegate.bottomHeight ||
        color != oldDelegate.color ||
        topPadding != oldDelegate.topPadding ||
        largeTitleLineHeight != oldDelegate.largeTitleLineHeight;
  }
}

class FloatingSearchBar extends StatefulWidget {
  const FloatingSearchBar({
    Key? key,
    this.height = 56,
    this.trailing,
    required this.onSearch,
    required this.controller,
    this.onChanged,
  }) : super(key: key);

  /// height of search bar
  final double height;

  /// end of search bar
  final Widget? trailing;

  /// callback when user do search
  final void Function(String) onSearch;

  /// controller of [TextField]
  final TextEditingController controller;

  final void Function(String)? onChanged;

  @override
  State<FloatingSearchBar> createState() => _FloatingSearchBarState();
}

class _FloatingSearchBarState extends State<FloatingSearchBar> {
  double get effectiveHeight {
    return math.max(widget.height, 53);
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      width: double.infinity,
      height: effectiveHeight,
      alignment: Alignment.center,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppTooltip(
            message: "返回".tl,
            child: MiuixIconButton(
              minWidth: 36,
              minHeight: 36,
              onPressed: () => context.pop(),
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('chevronBackward') ??
                    MiuixIcons.os4.back,
                size: 20,
                tint: isDark ? const Color(0xEEFFFFFF) : const Color(0xDD000000),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: AppSearchField(
              controller: widget.controller,
              hint: "Search",
              autofocus: false,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSearch,
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 2),
            widget.trailing!,
          ],
        ],
      ),
    );
  }
}



class FilledTabBar extends StatefulWidget {
  const FilledTabBar({super.key, this.controller, required this.tabs});

  final TabController? controller;

  final List<Tab> tabs;

  @override
  State<FilledTabBar> createState() => _FilledTabBarState();
}

class _FilledTabBarState extends State<FilledTabBar> {
  late TabController _controller;

  late List<GlobalKey> keys;

  static const _kTabHeight = 44.0;

  final scrollController = ScrollController();

  final tabBarKey = GlobalKey();

  int? previousIndex;

  @override
  void initState() {
    keys = widget.tabs.map((e) => GlobalKey()).toList();
    super.initState();
  }

  @override
  void didChangeDependencies() {
    _controller = widget.controller ?? DefaultTabController.of(context);
    _controller.animation!.addListener(onTabChanged);
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant FilledTabBar oldWidget) {
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? DefaultTabController.of(context);
      _controller.animation!.addListener(onTabChanged);
    }
    if (widget.tabs.length != keys.length) {
      keys = widget.tabs.map((e) => GlobalKey()).toList();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void onTabChanged() {
    final int i = _controller.index;
    if (i == previousIndex) {
      return;
    }
    _scrollToCenter(i);
    previousIndex = i;
  }

  void _scrollToCenter(int i) {
    if (i < 0 || i >= keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      final keyContext = keys[i].currentContext;
      if (keyContext == null) return;
      final renderBox = keyContext.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final position = renderBox.localToGlobal(Offset.zero,
          ancestor: tabBarKey.currentContext?.findRenderObject());
      final tabBarBox =
          tabBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (tabBarBox == null) return;
      final double tabCenter = position.dx + renderBox.size.width / 2;
      final double screenCenter = tabBarBox.size.width / 2;
      final double target = (scrollController.offset + tabCenter - screenCenter)
          .clamp(0.0, scrollController.position.maxScrollExtent);
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void onTabClicked(int i) {
    _controller.animateTo(i);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: buildTabBar,
    );
  }

  Widget buildTabBar(BuildContext context, Widget? _) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      key: tabBarKey,
      height: _kTabHeight,
      width: double.infinity,
      color: Colors.transparent,
      child: widget.tabs.isEmpty
          ? const SizedBox()
          : SmoothScrollProvider(
              controller: scrollController,
              builder: (context, controller, physics) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  controller: controller,
                  physics: physics,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < widget.tabs.length; i++)
                        _buildCapsuleTab(context, i, isDark, primaryColor),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildCapsuleTab(
      BuildContext context, int i, bool isDark, Color primaryColor) {
    final isSelected = i == _controller.index;
    final tab = widget.tabs[i];
    final String text =
        tab.text ?? (tab.child is Text ? (tab.child as Text).data ?? '' : '');

    return Padding(
      key: keys[i],
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MiuixPressable(
          shape: const StadiumBorder(),
          onPressed: () {
            onTabClicked(i);
            _scrollToCenter(i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            // HyperOS 风格胶囊：无描边；选中为主色实底，未选中为容器色浅底。
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: isSelected
                  ? MiuixTheme.of(context).colors.primary
                  // 未选中: 半透明对比底色, 浅色/深色背景上都能看清边界
                  : (isDark ? const Color(0x33FFFFFF) : const Color(0x17000000)),
            ),
            child: Text(
              text.isNotEmpty ? text : 'Tab ${i + 1}',
              style: TextStyle(
                fontSize: 14.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? MiuixTheme.of(context).colors.onPrimary
                    : MiuixTheme.of(context).colors.onSurface.withValues(alpha: 0.86),
                height: 1.2,
              ),
            ),          )),
    );
  }
}
