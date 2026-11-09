part of "components.dart";

void hideAllMessages() {
  _OverlayWidgetState.removeAll();
}

void showToast({required String message, Widget? icon, Widget? trailing}) {
  var newEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
            message: message,
            icon: icon,
            trailing: trailing,
          ));

  _OverlayWidgetState.addOverlay(newEntry);

  Timer(const Duration(seconds: 2), () => _OverlayWidgetState.remove(newEntry));
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.message, this.icon, this.trailing});

  final String message;

  final Widget? icon;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.bottomCenter,
        // Miuix 表面 + 阴影；透明 Material 只为 Text 提供默认文字样式。
        child: Material(
            type: MaterialType.transparency,
            child: ClipPath(
              clipper: const ShapeBorderClipper(
                shape: MiuixSquircleBorder(cornerRadius: 20),
              ),
              child: FrostBlur(
                child: MiuixSurface(
                  color: MiuixTheme.of(context)
                      .colors
                      .surfaceContainer
                      .withValues(alpha: frostEnabled ? 0.88 : 1.0),
                  cornerRadius: 20,
                  shadowElevation: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) icon!.paddingRight(8),
                        Flexible(
                          child: Text(
                            message,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: MiuixTheme.of(context).colors.onBackground,
                            ),
                            maxLines: 3,
                          ),
                        ),
                        if (trailing != null) trailing!.paddingLeft(8)
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ),
    );
  }
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget(this.child, {super.key});

  final Widget child;

  static void addOverlay(OverlayEntry entry) =>
      _OverlayWidgetState.addOverlay(entry);

  static void removeAll() => _OverlayWidgetState.removeAll();

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  static var overlayKey = GlobalKey<OverlayState>();

  static var entries = <OverlayEntry>[];

  static void addOverlay(OverlayEntry entry) {
    if (overlayKey.currentState != null) {
      overlayKey.currentState!.insert(entry);
      entries.add(entry);
    }
  }

  static void remove(OverlayEntry entry) {
    if (entries.remove(entry)) {
      entry.remove();
    }
  }

  static void removeAll() {
    for (var entry in entries) {
      entry.remove();
    }
    entries.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: overlayKey,
      initialEntries: [OverlayEntry(builder: (context) => widget.child)],
    );
  }
}

void showDialogMessage(BuildContext context, String title, String message) {
  showMiuixDialog<void>(
    context: context,
    title: title,
    summary: message,
    actionsBuilder: (context, close) => [
      MiuixButton(
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        onPressed: () => close(),
        child: Text("了解".tl),
      ),
    ],
  );
}

void showConfirmDialog(BuildContext context, String title, String content,
    void Function() onConfirm) {
  showMiuixDialog<bool>(
    context: context,
    title: title,
    summary: content,
    actionsBuilder: (context, close) => [
      MiuixTextButton("取消".tl, onPressed: () => close(false)),
      MiuixButton(
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        onPressed: () => close(true),
        child: Text("确认".tl),
      ),
    ],
  ).then((confirmed) {
    if (confirmed == true) onConfirm();
  });
}

class LoadingDialogController {
  void Function()? closeDialog;

  bool closed = false;

  void close() {
    if (closed) {
      return;
    }
    closed = true;
    if (closeDialog == null) {
      Future.microtask(closeDialog!);
    } else {
      closeDialog!();
    }
  }
}

LoadingDialogController showLoadingDialog(BuildContext context,
    {void Function()? onCancel,
    bool barrierDismissible = true,
    bool allowCancel = true,
    String? message,
    String cancelButtonText = "Cancel"}) {
  var controller = LoadingDialogController();

  var loadingDialogRoute = DialogRoute(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return _MiuixDialogShell(
          cornerRadius: 24,
          child: Container(
            width: 100,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: MiuixCircularProgressIndicator(),
                ),
                const SizedBox(
                  width: 16,
                ),
                Text(
                  message ?? 'Loading',
                  style: const TextStyle(fontSize: 16),
                ),
                const Spacer(),
                if (allowCancel)
                  MiuixTextButton(cancelButtonText.tl, onPressed: () {
                    controller.close();
                    onCancel?.call();
                  })
              ],
            ),
          ),
        );
      });

  var navigator = Navigator.of(context);

  navigator.push(loadingDialogRoute).then((value) => controller.closed = true);

  controller.closeDialog = () {
    navigator.removeRoute(loadingDialogRoute);
  };

  return controller;
}

class ContentDialog extends StatelessWidget {
  const ContentDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final String title;

  final Widget content;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    var content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Appbar(
          title: Text(title),
          backgroundColor: Colors.transparent,
        ),
        this.content,
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: actions,
        ).paddingRight(12),
        const SizedBox(height: 16),
      ],
    );
    return _MiuixDialogShell(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : Colors.white,
      cornerRadius: 28,
      insetPadding: context.width < 400
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            minWidth: math.min(400, context.width - 16),
          ),
          child: MediaQuery.removePadding(
            removeTop: true,
            removeBottom: true,
            context: context,
            child: content,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 命令式 Miuix 浮层辅助函数
//
// flutter_miuix 的 MiuixOverlayDialog / MiuixOverlayBottomSheet /
// MiuixOverlayListPopup 都是靠 `show` 状态驱动的声明式组件。下面这几个函数
// 推一个透明路由，在路由里放一个独立的 MiuixPopupScope + MiuixPopupHost，
// 再把对应的 Miuix 浮层以 show=true 挂上去；关闭时先播放退出动画，
// 在 onDismissFinished 里 pop 路由并带回结果，用法和 showDialog 一样返回 Future。
// ---------------------------------------------------------------------------

/// 关闭当前 Miuix 浮层并（可选）带回结果。
typedef MiuixCloseCallback<T> = void Function([T? result]);

/// 浮层内容构建器：`close([result])` 会播放退出动画后关闭并返回 result。
typedef MiuixOverlayContentBuilder<T> = Widget Function(
    BuildContext context, MiuixCloseCallback<T> close);

Future<T?> _pushMiuixOverlayRoute<T>(
  BuildContext context,
  Widget Function(BuildContext context, bool show, MiuixCloseCallback<T> close,
          VoidCallback onDismissFinished)
      builder, {
  bool useRootNavigator = true,
}) {
  final completer = Completer<T?>();
  Navigator.of(context, rootNavigator: useRootNavigator)
      .push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) =>
          _MiuixOverlayRouteHost<T>(builder: builder, completer: completer),
    ),
  )
      .then((value) {
    if (!completer.isCompleted) completer.complete(value);
  });
  return completer.future;
}

class _MiuixOverlayRouteHost<T> extends StatefulWidget {
  const _MiuixOverlayRouteHost(
      {super.key, required this.builder, required this.completer});

  final Completer<T?> completer;

  final Widget Function(BuildContext context, bool show,
      MiuixCloseCallback<T> close, VoidCallback onDismissFinished) builder;

  @override
  State<_MiuixOverlayRouteHost<T>> createState() =>
      _MiuixOverlayRouteHostState<T>();
}

class _MiuixOverlayRouteHostState<T> extends State<_MiuixOverlayRouteHost<T>> {
  bool _show = false;
  bool _closing = false;
  bool _popped = false;
  T? _result;

  @override
  void initState() {
    super.initState();
    // 先以 show=false 挂上，下一帧再置 true，保证播放进入动画。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) setState(() => _show = true);
    });
  }

  void _close([T? result]) {
    if (_closing) return;
    _closing = true;
    _result = result;
    if (!_show) {
      _finish();
      return;
    }
    setState(() => _show = false);
  }

  void _finish() {
    if (_popped || !mounted) return;
    _popped = true;
    if (!widget.completer.isCompleted) widget.completer.complete(_result);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      navigator.pop<T>(_result);
    } else {
      // 关闭动画期间上面又推了新页面时，只移除自己，不误伤新页面。
      navigator.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: MiuixPopupScope(
        establishRoot: true,
        child: MiuixPopupHost(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Builder(
                builder: (context) =>
                    widget.builder(context, _show, _close, _finish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出 Miuix 风格对话框（[MiuixOverlayDialog]）。
///
/// [contentBuilder] 构建正文；[actionsBuilder] 返回的按钮会等宽横排在底部
/// （HyperOS 对话框样式）。两者都会拿到 `close([result])`。
/// 点击遮罩 / 返回键在 [dismissible] 为 true 时以 null 关闭。
Future<T?> showMiuixDialog<T>({
  required BuildContext context,
  String? title,
  String? summary,
  MiuixOverlayContentBuilder<T>? contentBuilder,
  List<Widget> Function(BuildContext context, MiuixCloseCallback<T> close)?
      actionsBuilder,
  bool dismissible = true,
  bool useRootNavigator = true,
}) {
  return _pushMiuixOverlayRoute<T>(context, (context, show, close, finished) {
    final actions = actionsBuilder?.call(context, close) ?? const <Widget>[];
    return MiuixOverlayDialog(
      show: show,
      title: title,
      summary: summary,
      onDismissRequest: dismissible ? () => close() : null,
      onDismissFinished: finished,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (contentBuilder != null) contentBuilder(context, close),
          if (contentBuilder != null && actions.isNotEmpty)
            const SizedBox(height: 16),
          if (actions.isNotEmpty)
            Row(
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i != 0) const SizedBox(width: 12),
                  Expanded(child: actions[i]),
                ]
              ],
            ),
        ],
      ),
    );
  }, useRootNavigator: useRootNavigator);
}

/// 弹出 Miuix 风格底部抽屉（[MiuixOverlayBottomSheet]）。
Future<T?> showMiuixBottomSheet<T>({
  required BuildContext context,
  required MiuixOverlayContentBuilder<T> builder,
  String? title,
  Widget? startAction,
  Widget? endAction,
  bool allowDismiss = true,
  bool useRootNavigator = true,
}) {
  return _pushMiuixOverlayRoute<T>(context, (context, show, close, finished) {
    return MiuixOverlayBottomSheet(
      show: show,
      title: title,
      startAction: startAction,
      endAction: endAction,
      allowDismiss: allowDismiss,
      onDismissRequest: () => close(),
      onDismissFinished: finished,
      content: builder(context, close),
    );
  }, useRootNavigator: useRootNavigator);
}

/// 取某个 widget 在屏幕上的全局矩形，作为 [showMiuixMenu] 的锚点。
Rect miuixAnchorRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
}

/// 在 [anchorBounds] 附近弹出 Miuix 列表菜单（[MiuixOverlayListPopup] +
/// [MiuixDropdownImpl]），返回被点选项的下标，取消返回 null。
///
/// [disabledIndexes] 中的项显示为禁用；[selectedIndex] 会带勾号。
Future<int?> showMiuixMenu({
  required BuildContext context,
  required Rect anchorBounds,
  required List<String> items,
  int? selectedIndex,
  Set<int> disabledIndexes = const {},
  MiuixPopupAlign alignment = MiuixPopupAlign.start,
  double? minWidth,
  double? maxHeight,
  bool useRootNavigator = true,
}) {
  return _pushMiuixOverlayRoute<int>(context, (context, show, close, finished) {
    return MiuixOverlayListPopup(
      show: show,
      anchorBounds: anchorBounds,
      alignment: alignment,
      minWidth: minWidth ?? MiuixListPopupDefaults.minWidth,
      maxHeight: maxHeight,
      onDismissRequest: () => close(),
      onDismissFinished: finished,
      content: MiuixListPopupColumn(
        children: [
          for (int i = 0; i < items.length; i++)
            MiuixDropdownImpl.text(
              text: items[i],
              optionSize: items.length,
              isSelected: i == selectedIndex,
              index: i,
              enabled: !disabledIndexes.contains(i),
              onSelectedIndexChange: (index) => close(index),
            ),
        ],
      ),
    );
  }, useRootNavigator: useRootNavigator);
}

/// Miuix 风格的文字提示：长按 / 悬停时在控件下方弹出 [MiuixPlainTooltip]。
/// 用来替代 Material 的 `Tooltip(message:, child:)`，参数保持一致。
class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    return MiuixTooltipBox(
      semanticLabel: message,
      tooltip: (context, scope) => MiuixPlainTooltip(
        scope: scope,
        child: Text(message),
      ),
      child: child,
    );
  }
}

/// Miuix 风格的对话框外壳：替代 Material `Dialog`，用 [MiuixSurface] 画背景，
/// 保留 inset / 键盘避让，并提供透明 Material 作为文字样式与输入框的祖先。
class _MiuixDialogShell extends StatelessWidget {
  const _MiuixDialogShell({
    required this.child,
    this.color,
    this.cornerRadius = 28,
    this.insetPadding =
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
  });

  final Widget child;
  final Color? color;
  final double cornerRadius;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context) +
        insetPadding.copyWith(top: 24, bottom: 24);
    return AnimatedPadding(
      padding: padding,
      duration: const Duration(milliseconds: 100),
      curve: Curves.decelerate,
      child: MediaQuery.removeViewInsets(
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        context: context,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280),
            child: Material(
              type: MaterialType.transparency,
              child: MiuixSurface(
                color: color,
                cornerRadius: cornerRadius,
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: MiuixSquircleBorder(cornerRadius: cornerRadius),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
