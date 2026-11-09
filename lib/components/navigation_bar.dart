part of 'components.dart';

Widget _buildNaviEntryIcon({
  required PaneItemEntry entry,
  required bool isSelected,
  required Color color,
  double size = 21,
}) {
  MiuixVectorIcon? vector;
  final label = entry.label;
  if (label.contains('收藏')) {
    vector = isSelected
        ? MiuixIcons.extended.byName('favoritesFill')
        : MiuixIcons.extended.byName('favorites');
  } else if (label.contains('探索')) {
    return Icon(
      isSelected ? Icons.explore : Icons.explore_outlined,
      size: size,
      color: color,
    );
  } else if (label.contains('分类')) {
    vector = MiuixIcons.extended.byName('all') ??
        MiuixIcons.extended.byName('gridView');
  } else if (label.contains('设置')) {
    vector = MiuixIcons.os4.settings;
  } else if (label.contains('我') || label.contains('个人')) {
    vector = MiuixIcons.extended.byName('contactsCircle') ??
        MiuixIcons.extended.byName('contacts');
  }

  if (vector != null) {
    return MiuixIcon(
      vector: vector,
      size: size,
      tint: color,
    );
  }

  return Icon(
    isSelected ? entry.activeIcon : entry.icon,
    size: size,
    color: color,
  );
}

class PaneItemEntry {
  String label;

  String? title;

  IconData icon;

  IconData activeIcon;

  PaneItemEntry(
      {required this.label,
      this.title,
      required this.icon,
      required this.activeIcon});
}

class PaneActionEntry {
  String label;

  IconData icon;

  VoidCallback onTap;

  PaneActionEntry(
      {required this.label, required this.icon, required this.onTap});
}

class NaviPane extends StatefulWidget {
  const NaviPane(
      {required this.paneItems,
      required this.paneActions,
      required this.pageBuilder,
      this.initialPage = 0,
      this.onPageChange,
      required this.observer,
      super.key});

  final List<PaneItemEntry> paneItems;

  final List<PaneActionEntry> paneActions;

  final Widget Function(int page) pageBuilder;

  final void Function(int index)? onPageChange;

  final int initialPage;

  final NaviObserver observer;

  @override
  State<NaviPane> createState() => _NaviPaneState();
}

class _NaviPaneState extends State<NaviPane>
    with TickerProviderStateMixin {
  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    _behavior.state.heightOffset = 0;
    _behavior.state.contentOffset = 0;
    StateController.findOrNull<MainTabController>()?.setIndex(value);
    widget.onPageChange?.call(value);
  }

  late final MiuixExitUntilCollapsedScrollBehavior _behavior;

  String? _lastFavState;

  late AnimationController controller;

  double? _dragIndicatorIndex;
  bool _isNavDragging = false;
  DateTime? _lastBackTime;

  static const _kBottomBarHeight = 62.0;

  static const _kFloatingBottomMargin = 22.0;

  static const _kFoldedSideBarWidth = 80.0;

  static const _kSideBarWidth = 256.0;

  static const _kTopBarHeight = 114.0;

  /// 带 Tab 条时的顶栏估算高度（114 + 44 的 Tab 条）。
  static const _kTopBarHeightWithTabs = 176.0;

  /// 顶栏可折叠掉的高度（折叠带以外的标题区域），仅用于首帧估算。
  static const _kCollapsibleHeight = 62.0;

  /// Tab 条的固定高度（与 [FilledTabBar._kTabHeight] 保持一致），
  /// 用于顶栏首帧的高度预估，避免内容先按无 Tab 条的高度占位再跳一下。
  static const _kTabBarHeight = 44.0;

  /// 顶栏「展开 / 完全折叠」时的真实高度（均含状态栏），由 [MiuixTopAppBar] 实测上报。
  ///
  /// 之前这里用写死的 114 / 176 估算页面内容上沿，而顶栏真实高度是
  /// 「状态栏 + 52 + 大标题行高 + 6 (+ Tab 条)」。状态栏偏高或系统字体被放大的
  /// 设备上，两者能差到十几 dp，于是内容要么被顶栏压住，要么上方空一截。
  ///
  /// 按页面索引缓存：探索/分类页带 Tab 条、收藏页带返回按钮，高度各不相同，
  /// 只存一个值会在切换 Tab 的瞬间沿用上一页的高度而闪一下。
  final Map<int, MiuixTopAppBarHeightInfo> _topBarHeights = {};

  /// 当前页面还没上报过时，用这个值顶上，避免首帧内容从 0 跳上来。
  ///
  /// 先借用已经测量过的页面高度（标题样式完全相同，只差 Tab 条），这样
  /// 第二次切页时首帧就是准的；只有冷启动首屏才退回经验值。
  MiuixTopAppBarHeightInfo get _topBarHeightInfo {
    final measured = _topBarHeights[currentPage];
    if (measured != null) return measured;
    final hasTabs = currentPage == 2 || currentPage == 3;
    final reference = _topBarHeights[0] ?? _topBarHeights[1];
    final tabExtra = hasTabs ? _kTabBarHeight : 0.0;
    if (reference != null) {
      return MiuixTopAppBarHeightInfo(
        expanded: reference.expanded + tabExtra,
        collapsed: reference.collapsed + tabExtra,
      );
    }
    final base = hasTabs ? _kTopBarHeightWithTabs : _kTopBarHeight;
    return MiuixTopAppBarHeightInfo(
      expanded: base,
      collapsed: base - _kCollapsibleHeight,
    );
  }

  /// 顶栏上报尺寸时所在的页面索引，避免切换 Tab 的同一帧把高度记到新页面上。
  void _onTopBarHeightChanged(int page, MiuixTopAppBarHeightInfo info) {
    if (!mounted) return;
    if (_topBarHeights[page] == info) return;
    setState(() => _topBarHeights[page] = info);
    if (page == currentPage) {
      StateController.findOrNull<NaviPaddingWidgetController>()
          ?.setTopBarHeight(info.expanded);
    }
  }

  double get bottomBarHeight =>
      _kBottomBarHeight + _kFloatingBottomMargin + MediaQuery.of(context).padding.bottom;

  void onNavigatorStateChange() {
    onRebuild(context);
  }

  @override
  void initState() {
    _behavior = MiuixExitUntilCollapsedScrollBehavior();
    controller = AnimationController(
        duration: const Duration(milliseconds: 250),
        lowerBound: 0,
        upperBound: 3,
        vsync: this);
    widget.observer.addListener(onNavigatorStateChange);
    StateController.put(NaviPaddingWidgetController());

    final exploreLogic = StateController.put(ExplorePageController());
    exploreLogic.init(this);

    final categoryLogic = StateController.put(CategoryPageController());
    categoryLogic.init(this);

    StateController.putIfNotExists(FavoritesPageController());
    StateController.putIfNotExists(MainTabController(widget.initialPage));

    ComicSource.sourcesChanged.addListener(_onSourcesChanged);

    super.initState();
  }

  @override
  void didChangeDependencies() {
    controller.value = targetFormContext(context);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    ComicSource.sourcesChanged.removeListener(_onSourcesChanged);
    StateController.findOrNull<ExplorePageController>()?.tabController.dispose();
    StateController.remove<ExplorePageController>();
    StateController.findOrNull<CategoryPageController>()?.tabController.dispose();
    StateController.remove<CategoryPageController>();
    StateController.remove<NaviPaddingWidgetController>();
    StateController.remove<MainTabController>();
    controller.dispose();
    widget.observer.removeListener(onNavigatorStateChange);
    super.dispose();
  }

  /// 启用的漫画源变化：重新计算探索/分类标签并重建 TabController
  void _onSourcesChanged() {
    final explore = StateController.findOrNull<ExplorePageController>();
    if (explore != null) {
      final old = explore.tabController;
      explore.init(this);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final category = StateController.findOrNull<CategoryPageController>();
    if (category != null) {
      final old = category.tabController;
      category.init(this);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (mounted) setState(() {});
  }

  double targetFormContext(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    double target = 0;
    if (widget.observer.pageCount > 1) {
      target = 1;
    }
    if (width > changePoint) {
      target = 2;
    }
    if (width > changePoint2) {
      target = 3;
    }
    return target;
  }

  double? animationTarget;

  void onRebuild(BuildContext context) {
    double target = targetFormContext(context);
    if (controller.value != target || animationTarget != target) {
      if (controller.isAnimating) {
        if (animationTarget == target) {
          return;
        } else {
          controller.stop();
        }
      }
      if (target == 1) {
        StateController.find<NaviPaddingWidgetController>()
            .setWithPadding(true);
        controller.value = target;
      } else if (controller.value == 1 && target == 0) {
        StateController.findOrNull<NaviPaddingWidgetController>()
            ?.setWithPadding(false);
        controller.value = target;
      } else {
        controller.animateTo(target,
            duration: const Duration(milliseconds: 160), curve: Curves.ease);
      }
      animationTarget = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    onRebuild(context);
    return _NaviPopScope(
      action: () {
        // 1. 最高优先级：当前 Tab 的内部 Navigator 若有子页面在栈上，优先将其 pop 出栈！
        final subNav = widget.observer.navigator;
        if (subNav != null && subNav.canPop()) {
          subNav.pop();
          return;
        }

        // 2. 次高优先级：全局根 Navigator 若有模态页/全局页在栈上，将其 pop 出栈！
        final mainNav = App.mainNavigatorKey?.currentState;
        if (mainNav != null && mainNav.canPop()) {
          mainNav.pop();
          return;
        }

        // 3. 第三优先级：当前 Tab 页面内部的二级状态回退
        // 收藏页面（currentPage == 1）：
        if (currentPage == 1) {
          final favController =
              StateController.findOrNull<FavoritesPageController>();
          if (favController != null) {
            // 如果处于多选漫画状态，先退出多选
            if (favController.selectedComics.isNotEmpty) {
              favController.selectedComics.clear();
              favController.update();
              return;
            }
            // 如果当前正在查看某个文件夹的内容，退回到所有文件夹列表
            if (!favController.selectingFolder) {
              favController.selectingFolder = true;
              favController.update();
              appdata.implicitData[0] = "1;;";
              appdata.writeImplicitData();
              return;
            }
          }
        }

        // 4. 最底优先级：已经位于顶层主页且无任何可回退内容时，双击/确认退出应用，防止误触直接闪退到桌面
        final now = DateTime.now();
        if (_lastBackTime == null ||
            now.difference(_lastBackTime!) > const Duration(seconds: 2)) {
          _lastBackTime = now;
          showToast(message: "再按一次退出应用".tl);
          return;
        }
        SystemNavigator.pop();
      },
      popGesture: App.isIOS && !UiMode.m1(context),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final value = controller.value;
          final scaffoldBg = MiuixTheme.of(context).colors.background;
          return Material(
            color: scaffoldBg,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: _kFoldedSideBarWidth * ((value - 1).clamp(0, 1)) +
                      (_kSideBarWidth - _kFoldedSideBarWidth) *
                          ((value - 2).clamp(0, 1)),
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Colors.transparent,
                  child: MiuixScrollBehaviorListener(
                    behavior: _behavior,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MediaQuery.removePadding(
                            removeTop: value == 0,
                            context: context,
                            child: AnimatedBuilder(
                              animation: _behavior.state,
                              builder: (context, _) {
                              // 顶栏高度随折叠进度线性收缩：展开态取上报值，
                              // 折叠到底取上报的 collapsed，中途按 fraction 插值。
                              // 这样状态栏、大标题行高、Tab 条全都自动算进去。
                              final topPadding = value == 0
                                  ? _topBarHeightInfo.heightAt(
                                          _behavior.state.collapsedFraction)
                                      .clamp(0.0, double.infinity)
                                  : 0.0;
                              // 主页面：内容从顶栏下方穿过（顶栏毛玻璃），
                              // 由页面自身的透明吸顶占位让出顶栏高度。
                              final underBar = value == 0;
                              return Padding(
                                padding: EdgeInsets.only(
                                    top: underBar ? 0 : topPadding),
                                child: MainTopInset(
                                  height: underBar ? topPadding : 0,
                                  child: widget.pageBuilder(currentPage),
                                ),
                              );
                              },
                            ),
                          ),
                        ),
                        if (value <= 1)
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: (1 - value).clamp(0.0, 1.0),
                              child: MiuixBarTextStyle(
                                  child: frostEnabled
                                      ? FrostedBackground(child: buildTop())
                                      : buildTop()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _kFoldedSideBarWidth * ((value - 2.0).clamp(-1.0, 0.0)),
                top: 0,
                bottom: 0,
                child: buildLeft(),
              ),
              if (value <= 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -150 * value,
                  child: buildBottom(),
                ),
            ],
          ),
        );
      },
    ),
  );
}

  Widget buildTop() {
    final item = widget.paneItems[currentPage];

    Widget buildActionIcon(PaneActionEntry action) {
      final color = Theme.of(context).colorScheme.onSurface;
      if (action.icon == Icons.search || action.label.contains('搜索')) {
        return MiuixIcon(
          vector: MiuixIcons.os4.search,
          size: 20,
          tint: color,
        );
      } else if (action.icon == Icons.settings || action.label.contains('设置')) {
        return MiuixIcon(
          vector: MiuixIcons.os4.settings,
          size: 20,
          tint: color,
        );
      }
      return Icon(action.icon, color: color, size: 20);
    }

    if (currentPage == 1) {
      final favController =
          StateController.findOrNull<FavoritesPageController>();
      if (favController != null) {
        return StateBuilder<FavoritesPageController>(
          builder: (fav) {
            final isViewingComics = !fav.selectingFolder && fav.current != null;
            final title = isViewingComics
                ? fav.current!.tl
                : (item.title ?? item.label);
            final favStateKey = '${fav.selectingFolder}_${fav.current}';
            if (_lastFavState != null && _lastFavState != favStateKey) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _behavior.state.heightOffset = 0;
                  _behavior.state.contentOffset = 0;
                }
              });
            }
            _lastFavState = favStateKey;
            return MiuixTopAppBar(
              key: ValueKey('top_bar_1_${fav.selectingFolder}_${fav.current}'),
              title: title,
              color: frostEnabled
                  ? Colors.transparent
                  : MiuixTheme.of(context).colors.background,
              scrollBehavior: _behavior,
              blurred: false,
              onHeightChanged: (info) => _onTopBarHeightChanged(1, info),
              navigationIcon: isViewingComics
                  ? MiuixIconButton(
                      child: MiuixIcon(
                        vector: MiuixIcons.extended.byName('chevronBackward') ??
                            MiuixIcons.os4.back,
                        size: 21,
                        tint: Theme.of(context).colorScheme.onSurface,
                      ),
                      onPressed: () {
                        fav.selectingFolder = true;
                        fav.current = null;
                        fav.update();
                        _behavior.state.heightOffset = 0;
                        _behavior.state.contentOffset = 0;
                        appdata.implicitData[0] = "1;;";
                        appdata.writeImplicitData();
                      },
                    )
                  : null,
              actions: [
                for (var action in widget.paneActions)
                  AppTooltip(
                    message: action.label,
                    child: MiuixIconButton(
                      onPressed: action.onTap,
                      child: buildActionIcon(action),
                    ),
                  ),
              ],
            );
          },
        );
      }
    }

    if (currentPage == 2) {
      final exploreLogic = StateController.findOrNull<ExplorePageController>();
      final hasTabs =
          exploreLogic != null && exploreLogic.pages.isNotEmpty;
      return MiuixTopAppBar(
        key: ValueKey('top_bar_2_${exploreLogic?.pages.length}_$hasTabs'),
        title: item.title ?? item.label,
        color: frostEnabled
            ? Colors.transparent
            : MiuixTheme.of(context).colors.background,
        scrollBehavior: _behavior,
        // 毛玻璃由外层 FrostedBackground 负责；包内 blurred=true 即使 sigma/tint 为 0
        // 也会在滚动时创建 BackdropFilter，白白耗电掉帧。
        blurred: false,
        onHeightChanged: (info) => _onTopBarHeightChanged(2, info),
        bottomContentHeightHint: hasTabs ? _kTabBarHeight : 0,
        bottomContent: hasTabs
            ? FilledTabBar(
                tabs: exploreLogic.pages
                    .map((e) => Tab(text: e.tl, key: Key(e)))
                    .toList(),
                controller: exploreLogic.tabController,
              )
            : null,
        actions: [
          for (var action in widget.paneActions)
            AppTooltip(
              message: action.label,
              child: MiuixIconButton(
                onPressed: action.onTap,
                child: buildActionIcon(action),
              ),
            ),
        ],
      );
    }

    if (currentPage == 3) {
      final categoryLogic =
          StateController.findOrNull<CategoryPageController>();
      final hasTabs =
          categoryLogic != null && categoryLogic.categories.isNotEmpty;
      return MiuixTopAppBar(
        key: ValueKey('top_bar_3_${categoryLogic?.categories.length}_$hasTabs'),
        title: item.title ?? item.label,
        color: frostEnabled
            ? Colors.transparent
            : MiuixTheme.of(context).colors.background,
        scrollBehavior: _behavior,
        // 毛玻璃由外层 FrostedBackground 负责；包内 blurred=true 即使 sigma/tint 为 0
        // 也会在滚动时创建 BackdropFilter，白白耗电掉帧。
        blurred: false,
        onHeightChanged: (info) => _onTopBarHeightChanged(3, info),
        bottomContentHeightHint: hasTabs ? _kTabBarHeight : 0,
        bottomContent: hasTabs
            ? FilledTabBar(
                tabs: categoryLogic.categories.map((e) {
                  String title = e;
                  try {
                    title = getCategoryDataWithKey(e).title;
                  } catch (_) {}
                  return Tab(text: title.tl, key: Key(e));
                }).toList(),
                controller: categoryLogic.tabController,
              )
            : null,
        actions: [
          for (var action in widget.paneActions)
            AppTooltip(
              message: action.label,
              child: MiuixIconButton(
                onPressed: action.onTap,
                child: buildActionIcon(action),
              ),
            ),
        ],
      );
    }

    return MiuixTopAppBar(
      key: ValueKey('top_bar_$currentPage'),
      title: item.title ?? item.label,
      color: frostEnabled
          ? Colors.transparent
          : MiuixTheme.of(context).colors.background,
      scrollBehavior: _behavior,
      blurred: false,
      onHeightChanged: (info) => _onTopBarHeightChanged(0, info),
      actions: [
        for (var action in widget.paneActions)
          AppTooltip(
            message: action.label,
            child: MiuixIconButton(
              onPressed: action.onTap,
              child: buildActionIcon(action),
            ),
          ),
      ],
    );
  }

  Widget buildBottom() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final unselectedColor =
        isDark ? const Color(0x99FFFFFF) : const Color(0x8A000000);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final bottomPaddingValue =
        bottomInset > 0 ? 6.0 + bottomInset : 24.0;

    return Padding(
      padding: EdgeInsets.only(
        left: 44,
        right: 44,
        bottom: bottomPaddingValue,
      ),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 390),
            height: _kBottomBarHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(31),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0x55000000)
                    : const Color(0x18000000),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: FrostBlur(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  color: MiuixTheme.of(context).colors.background.withValues(
                    // 关毛玻璃：纯色底栏；开毛玻璃：略提高不透明度保证可读。
                    alpha: frostEnabled
                        ? (frostTintAlpha(context) + 0.22).clamp(0.0, 1.0)
                        : 1.0,
                  ),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x24FFFFFF)
                        : const Color(0x14000000),
                    width: 0.6,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final itemCount = widget.paneItems.length;
                    final tabWidth = totalWidth / itemCount;
                    final displayIndex = _isNavDragging && _dragIndicatorIndex != null
                        ? _dragIndicatorIndex!
                        : currentPage.toDouble();
                    final indicatorLeft = displayIndex * tabWidth + 2;

                    void onPointerMove(double dx) {
                      final clampedDx = dx.clamp(0.0, totalWidth);
                      final rawIndex =
                          (clampedDx / tabWidth - 0.5).clamp(0.0, (itemCount - 1).toDouble());
                      final targetIndex =
                          (clampedDx / tabWidth).floor().clamp(0, itemCount - 1);
                      if (currentPage != targetIndex) {
                        HapticFeedback.lightImpact();
                        setState(() {
                          currentPage = targetIndex;
                          _dragIndicatorIndex = rawIndex;
                        });
                      } else if (_dragIndicatorIndex != rawIndex) {
                        setState(() {
                          _dragIndicatorIndex = rawIndex;
                        });
                      }
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final targetIndex = (details.localPosition.dx / tabWidth)
                            .floor()
                            .clamp(0, itemCount - 1);
                        HapticFeedback.lightImpact();
                        if (currentPage != targetIndex) {
                          setState(() {
                            currentPage = targetIndex;
                            _isNavDragging = false;
                            _dragIndicatorIndex = null;
                          });
                        }
                      },
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _isNavDragging = true;
                        });
                        onPointerMove(details.localPosition.dx);
                      },
                      onHorizontalDragUpdate: (details) {
                        onPointerMove(details.localPosition.dx);
                      },
                      onHorizontalDragEnd: (details) {
                        setState(() {
                          _isNavDragging = false;
                          _dragIndicatorIndex = null;
                        });
                      },
                      onHorizontalDragCancel: () {
                        setState(() {
                          _isNavDragging = false;
                          _dragIndicatorIndex = null;
                        });
                      },
                      onLongPressStart: (details) {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _isNavDragging = true;
                        });
                        onPointerMove(details.localPosition.dx);
                      },
                      onLongPressMoveUpdate: (details) {
                        onPointerMove(details.localPosition.dx);
                      },
                      onLongPressEnd: (details) {
                        setState(() {
                          _isNavDragging = false;
                          _dragIndicatorIndex = null;
                        });
                      },
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          AnimatedPositioned(
                            duration: _isNavDragging
                                ? const Duration(milliseconds: 30)
                                : const Duration(milliseconds: 240),
                            curve: _isNavDragging
                                ? Curves.linear
                                : Curves.easeOutCubic,
                            left: indicatorLeft,
                            width: tabWidth - 4 + (_isNavDragging ? 4 : 0),
                            height: 52,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(
                                  isDark
                                      ? (_isNavDragging ? 0.28 : 0.22)
                                      : (_isNavDragging ? 0.16 : 0.12),
                                ),
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (int i = 0; i < widget.paneItems.length; i++)
                                Expanded(
                                  child: SizedBox(
                                    height: _kBottomBarHeight,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _buildNaviEntryIcon(
                                          entry: widget.paneItems[i],
                                          isSelected: currentPage == i,
                                          color: currentPage == i
                                              ? primaryColor
                                              : unselectedColor,
                                          size: 22,
                                        ),
                                        const SizedBox(height: 3.0),
                                        Text(
                                          widget.paneItems[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: currentPage == i
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: currentPage == i
                                                ? primaryColor
                                                : unselectedColor,
                                            decoration: TextDecoration.none,
                                            letterSpacing: -0.2,
                                            height: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  Widget buildLeft() {
    final value = controller.value;
    const paddingHorizontal = 12.0;
    return Material(
      child: Container(
        width: _kFoldedSideBarWidth +
            (_kSideBarWidth - _kFoldedSideBarWidth) * ((value - 2).clamp(0, 1)),
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
        child: Row(
          children: [
            SizedBox(
              width: value == 3
                  ? (_kSideBarWidth - paddingHorizontal * 2)
                  : (_kFoldedSideBarWidth - paddingHorizontal * 2),
              child: Column(
                children: [
                  const SizedBox(
                    height: 16,
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).padding.top,
                  ),
                  ...List<Widget>.generate(
                    widget.paneItems.length,
                    (index) => _SideNaviWidget(
                      enabled: currentPage == index,
                      entry: widget.paneItems[index],
                      showTitle: value == 3,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          currentPage = index;
                        });
                      },
                      key: ValueKey(index),
                    ),
                  ),
                  const Spacer(),
                  ...List<Widget>.generate(
                    widget.paneActions.length,
                    (index) => _PaneActionWidget(
                      entry: widget.paneActions[index],
                      showTitle: value == 3,
                      key: ValueKey(index + widget.paneItems.length),
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  )
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SideNaviWidget extends StatefulWidget {
  const _SideNaviWidget(
      {required this.enabled,
      required this.entry,
      required this.onTap,
      required this.showTitle,
      super.key});

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  final bool showTitle;

  @override
  State<_SideNaviWidget> createState() => _SideNaviWidgetState();
}

class _SideNaviWidgetState extends State<_SideNaviWidget> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = widget.enabled
        ? colorScheme.primary
        : (isDark ? const Color(0xB3FFFFFF) : colorScheme.onSurfaceVariant);
    final icon = _buildNaviEntryIcon(
      entry: widget.entry,
      isSelected: widget.enabled,
      color: iconColor,
      size: 20,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (details) => setState(() => isHovering = true),
      onExit: (details) => setState(() => isHovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            width: double.infinity,
            height: widget.showTitle ? 42 : 34,
            decoration: ShapeDecoration(
                color: widget.enabled
                    ? colorScheme.primaryContainer
                    : isHovering
                        ? colorScheme.surfaceContainerHigh
                        : null,
                shape: const MiuixSquircleBorder(cornerRadius: 12)),
            child: widget.showTitle
                ? Row(
                    children: [
                      icon,
                      const SizedBox(
                        width: 12,
                      ),
                      Text(widget.entry.label)
                    ],
                  )
                : Center(
                    child: icon,
                  )),
      ),
    );
  }
}

class _PaneActionWidget extends StatefulWidget {
  const _PaneActionWidget(
      {required this.entry, required this.showTitle, super.key});

  final PaneActionEntry entry;

  final bool showTitle;

  @override
  State<_PaneActionWidget> createState() => _PaneActionWidgetState();
}

class _PaneActionWidgetState extends State<_PaneActionWidget> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(widget.entry.icon);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (details) => setState(() => isHovering = true),
      onExit: (details) => setState(() => isHovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.entry.onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            width: double.infinity,
            height: widget.showTitle ? 42 : 34,
            decoration: ShapeDecoration(
                color: isHovering ? colorScheme.surfaceContainerHigh : null,
                shape: const MiuixSquircleBorder(cornerRadius: 12)),
            child: widget.showTitle
                ? Row(
                    children: [
                      icon,
                      const SizedBox(
                        width: 12,
                      ),
                      Text(widget.entry.label)
                    ],
                  )
                : Center(
                    child: icon,
                  )),
      ),
    );
  }
}

class _SingleBottomNaviWidget extends StatefulWidget {
  const _SingleBottomNaviWidget(
      {required this.enabled,
      required this.entry,
      required this.onTap,
      super.key});

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  @override
  State<_SingleBottomNaviWidget> createState() =>
      _SingleBottomNaviWidgetState();
}

class _SingleBottomNaviWidgetState extends State<_SingleBottomNaviWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  bool isHovering = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SingleBottomNaviWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        controller.forward(from: 0);
      } else {
        controller.reverse(from: 1);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      value: widget.enabled ? 1 : 0,
      vsync: this,
      duration: _fastAnimationDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: controller, curve: Curves.ease),
      builder: (context, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (details) => setState(() => isHovering = true),
          onExit: (details) => setState(() => isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            child: buildContent(),
          ),
        );
      },
    );
  }

  Widget buildContent() {
    final value = controller.value;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = colorScheme.primary;
    final inactiveColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    final iconColor = Color.lerp(inactiveColor, activeColor, value)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 28,
            decoration: ShapeDecoration(
              shape: const MiuixSquircleBorder(cornerRadius: 14),
              color: value > 0.01
                  ? activeColor.withOpacity(0.12 * value)
                  : (isHovering
                      ? (isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0x0A000000))
                      : Colors.transparent),
            ),
            child: Center(
              child: Icon(
                widget.enabled ? widget.entry.activeIcon : widget.entry.icon,
                size: 20,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.entry.label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.1,
              fontWeight: value > 0.5 ? FontWeight.w600 : FontWeight.normal,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}

class NaviObserver extends NavigatorObserver implements Listenable {
  var routes = Queue<Route>();

  /// Effective page depth for chrome visibility.
  /// Multiple AppPageRoute(isRootRoute: true) entries (if any) count as one
  /// so top/bottom bars are not briefly hidden when pageCount flickers to 2.
  int get pageCount {
    int count = 0;
    bool hasRoot = false;
    for (var r in routes) {
      if (r is AppPageRoute && r.isRootRoute) {
        if (!hasRoot) {
          count++;
          hasRoot = true;
        }
      } else {
        count++;
      }
    }
    return count;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    routes.removeLast();
    notifyListeners();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    routes.addLast(route);
    notifyListeners();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute != null) {
      routes.add(newRoute);
    }
    notifyListeners();
  }

  List<VoidCallback> listeners = [];

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  void notifyListeners() {
    for (var listener in listeners) {
      listener();
    }
  }
}

class _NaviPopScope extends StatelessWidget {
  const _NaviPopScope(
      {required this.child, this.popGesture = false, required this.action});

  final Widget child;
  final bool popGesture;
  final VoidCallback action;

  static bool panStartAtEdge = false;

  @override
  Widget build(BuildContext context) {
    Widget res = App.isIOS
        ? child
        : PopScope(
            canPop: App.isAndroid ? false : true,
            onPopInvokedWithResult: (value, result) {
              action();
            },
            child: child,
          );
    if (popGesture) {
      res = GestureDetector(
          onPanStart: (details) {
            if (details.globalPosition.dx < 64) {
              panStartAtEdge = true;
            }
          },
          onPanEnd: (details) {
            if (details.velocity.pixelsPerSecond.dx < 0 ||
                details.velocity.pixelsPerSecond.dx > 0) {
              if (panStartAtEdge) {
                action();
              }
            }
            panStartAtEdge = false;
          },
          child: res);
    }
    return res;
  }
}

/// Tracks the selected bottom-nav tab so the root route can keep an
/// [IndexedStack] of tab pages alive across switches (avoids remount jitter).
class MainTabController extends StateController {
  MainTabController(this.index);

  int index;

  void setIndex(int value) {
    if (index == value) return;
    index = value;
    update();
  }
}

class NaviPaddingWidgetController extends StateController {
  NaviPaddingWidgetController() {
  }

  bool _withPadding = false;

  /// 顶栏实测高度（含状态栏），为空时退回默认估算值。
  double? topBarHeight;

  void setWithPadding(bool value) {
    _withPadding = value;
    update();
  }

  void setTopBarHeight(double height) {
    if (topBarHeight != null && (topBarHeight! - height).abs() < 0.5) return;
    topBarHeight = height;
    if (_withPadding) update();
  }
}

class NaviPaddingWidget extends StatelessWidget {
  const NaviPaddingWidget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<NaviPaddingWidgetController>(
      builder: (controller) {
        return FloatingBottomBarScope(
          visible: controller._withPadding,
          child: Padding(
            padding: EdgeInsets.only(
              top: controller._withPadding
                  ? (controller.topBarHeight ??
                      _NaviPaneState._kTopBarHeight + context.padding.top)
                  : 0,
              bottom: 0,
            ),
            child: child,
          ),
        );
      },
    );
  }
}


/// 标记当前页面是否被悬浮底栏覆盖，供列表在底部留出空间。
class FloatingBottomBarScope extends InheritedWidget {
  const FloatingBottomBarScope(
      {super.key, required this.visible, required super.child});

  final bool visible;

  @override
  bool updateShouldNotify(FloatingBottomBarScope oldWidget) =>
      oldWidget.visible != visible;

  /// 列表底部应留出的高度：有悬浮底栏时为「底栏高度 + 底栏底边距（含安全区）」，
  /// 否则仅为安全区。与 [_NaviPaneState.buildBottom] 的布局保持一致。
  static double bottomInsetOf(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    final scope =
        context.dependOnInheritedWidgetOfExactType<FloatingBottomBarScope>();
    if (scope == null || !scope.visible) return inset;
    final barBottom = inset > 0 ? 6.0 + inset : 24.0;
    return _NaviPaneState._kBottomBarHeight + barBottom + 8;
  }
}
