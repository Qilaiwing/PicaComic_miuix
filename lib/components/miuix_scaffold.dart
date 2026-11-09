// App-side wrapper of flutter_miuix's MiuixScaffold (same API).
//
// Fixes (the submodule is intentionally left untouched):
//  1. Large-title clipping + top-bar jitter: the top bar sits under the
//     scaffold's Material, whose DefaultTextStyle is Material 3 bodyMedium
//     (height 1.43, even leading). MiuixTopAppBar sizes/clips its large title
//     with a TextPainter that does NOT see that inherited height, but the
//     rendered Text does, so the glyphs were pushed ~3px down (descenders such
//     as the "g" in "Picacg" got clipped) and the off-stage measurement made
//     the bar grow by ~7px one frame later (the jitter near the top bar).
//     [MiuixBarTextStyle] gives bars a neutral DefaultTextStyle so measured
//     and rendered heights are identical.
//  2. First-frame content offset: the package scaffold seeds the content
//     padding with an estimate and reports the real value a frame later. For
//     a MiuixTopAppBar we compute the exact expanded height synchronously
//     (same formula as the bar), so frame 0 already has the final layout.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as m;
import 'package:pica_comic/components/components.dart'
    show FrostedBackground, frostEnabled;

/// Neutral text style for top bars: keeps family/color, drops the inherited
/// Material line height so TextPainter measurements match rendering.
class MiuixBarTextStyle extends StatelessWidget {
  const MiuixBarTextStyle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    // The bar itself wraps its content in a (transparent) Material, which
    // re-applies Theme.textTheme.bodyMedium (M3: height 1.43) as the default
    // style. Give that inner Material a bodyMedium without a line height too.
    final theme = Theme.of(context);
    final bm = theme.textTheme.bodyMedium ?? const TextStyle();
    // inherit:false so Theme.localize() does not merge the typography's
    // height 1.43 back in (TextStyle.merge returns a non-inheriting style as is).
    final neutralBody = TextStyle(
      inherit: false,
      fontFamily: bm.fontFamily,
      fontFamilyFallback: bm.fontFamilyFallback,
      fontSize: bm.fontSize,
      fontWeight: bm.fontWeight,
      letterSpacing: bm.letterSpacing,
      color: bm.color,
      textBaseline: bm.textBaseline,
    );
    return Theme(
      data: theme.copyWith(
          textTheme: theme.textTheme.copyWith(bodyMedium: neutralBody)),
      child: DefaultTextStyle(
      style: TextStyle(
        fontFamily: base.fontFamily,
        fontFamilyFallback: base.fontFamilyFallback,
        color: base.color,
        fontSize: base.fontSize,
        locale: base.locale,
      ),
      child: child,
    ),
    );
  }
}

/// Exact expanded content top for a [m.MiuixTopAppBar] (mirrors the bar's own
/// computation). Returns null when it cannot be computed reliably.
double? miuixTopBarExpandedHeight(BuildContext context, m.MiuixTopAppBar bar) {
  if (bar.subtitle.isNotEmpty) return null;
  final theme = m.MiuixTheme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final adj = theme.fontWeightAdjustment;
  final largeStyle = (theme.textStyles.title1.copyWith(
          fontSize: 25, fontWeight: FontWeight.bold, letterSpacing: -0.4))
      .withMiuixWeight(adj);
  final smallStyle = (theme.textStyles.title3.copyWith(
          fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.2))
      .withMiuixWeight(adj);
  double measure(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final h = tp.height;
    tp.dispose();
    return h;
  }

  final largeH = measure(bar.largeTitle ?? bar.title, largeStyle);
  final smallH = measure(bar.title, smallStyle);
  const collapsed = m.MiuixTopAppBarDefaults.collapsedHeight;
  const pad = m.MiuixTopAppBarDefaults.largeTitleBottomPadding;
  final contentTop = math.max(
    collapsed + (bar.bottomContent != null ? largeH + pad : largeH) + pad,
    collapsed / 2 + smallH / 2 + pad,
  );
  final top =
      bar.defaultWindowInsetsPadding ? MediaQuery.paddingOf(context).top : 0.0;
  return contentTop + bar.bottomContentHeightHint + top;
}

class MiuixScaffold extends StatelessWidget {
  const MiuixScaffold({
    super.key,
    this.topBar,
    this.bottomBar,
    this.floatingActionButton,
    this.floatingActionButtonPosition = m.MiuixFabPosition.end,
    this.floatingToolbar,
    this.floatingToolbarPosition = m.MiuixToolbarPosition.bottomCenter,
    this.snackbarHost,
    this.popupHost,
    this.containerColor,
    this.contentWindowInsets,
    required this.content,
  });

  final Widget? topBar;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final m.MiuixFabPosition floatingActionButtonPosition;
  final Widget? floatingToolbar;
  final m.MiuixToolbarPosition floatingToolbarPosition;
  final Widget? snackbarHost;
  final Widget? popupHost;
  final Color? containerColor;
  final EdgeInsets? contentWindowInsets;
  final m.MiuixScaffoldContentBuilder content;

  @override
  Widget build(BuildContext context) {
    final bar = topBar;
    m.MiuixScaffoldContentBuilder builder = content;
    Widget? effectiveBar = bar;
    if (bar is m.MiuixTopAppBar) {
      final exact = miuixTopBarExpandedHeight(context, bar);
      builder = (padding) => _StableTopPadding(
            exactTop: exact,
            padding: padding,
            builder: content,
          );
    }
    if (bar is m.MiuixSmallTopAppBar) {
      if (frostEnabled) {
        // 小顶栏没有自带模糊：去掉实色背景，套统一毛玻璃。
        effectiveBar = FrostedBackground(
          child: m.MiuixSmallTopAppBar(
            key: bar.key,
            title: bar.title,
            color: Colors.transparent,
            titleColor: bar.titleColor,
            subtitle: bar.subtitle,
            subtitleColor: bar.subtitleColor,
            navigationIcon: bar.navigationIcon,
            actions: bar.actions,
            scrollBehavior: bar.scrollBehavior,
            defaultWindowInsetsPadding: bar.defaultWindowInsetsPadding,
            titlePadding: bar.titlePadding,
            navigationIconPadding: bar.navigationIconPadding,
            actionIconPadding: bar.actionIconPadding,
            bottomContent: bar.bottomContent,
          ),
        );
      } else {
        // 关毛玻璃：保持包内实色 Material，不要套半透明 FrostedBackground。
        effectiveBar = m.MiuixSmallTopAppBar(
          key: bar.key,
          title: bar.title,
          color: bar.color ?? m.MiuixTheme.of(context).colors.background,
          titleColor: bar.titleColor,
          subtitle: bar.subtitle,
          subtitleColor: bar.subtitleColor,
          navigationIcon: bar.navigationIcon,
          actions: bar.actions,
          scrollBehavior: bar.scrollBehavior,
          defaultWindowInsetsPadding: bar.defaultWindowInsetsPadding,
          titlePadding: bar.titlePadding,
          navigationIconPadding: bar.navigationIconPadding,
          actionIconPadding: bar.actionIconPadding,
          bottomContent: bar.bottomContent,
        );
      }
    }
    if (bar is m.MiuixTopAppBar && bar.blurred) {
      // 调用方常写 blurred:true + blurRadius:0。包内即便 sigma/tint 为 0，
      // 滚动时仍会创建 BackdropFilter，这里一律关掉包内 blurred，
      // 开毛玻璃时改由 FrostedBackground 提供模糊，并让栏身透明透出效果。
      final solid = bar.color ?? m.MiuixTheme.of(context).colors.background;
      final rebuilt = m.MiuixTopAppBar(
        key: bar.key,
        title: bar.title,
        color: frostEnabled ? Colors.transparent : solid,
        titleColor: bar.titleColor,
        largeTitle: bar.largeTitle,
        largeTitleColor: bar.largeTitleColor,
        subtitle: bar.subtitle,
        subtitleColor: bar.subtitleColor,
        navigationIcon: bar.navigationIcon,
        actions: bar.actions,
        scrollBehavior: bar.scrollBehavior,
        defaultWindowInsetsPadding: bar.defaultWindowInsetsPadding,
        titlePadding: bar.titlePadding,
        navigationIconPadding: bar.navigationIconPadding,
        actionIconPadding: bar.actionIconPadding,
        bottomContent: bar.bottomContent,
        blurred: false,
        largeTitleBlurRadius: bar.largeTitleBlurRadius,
        titleAlpha: bar.titleAlpha,
        clipBehavior: bar.clipBehavior,
        bottomContentHeightHint: bar.bottomContentHeightHint,
        onHeightChanged: bar.onHeightChanged,
      );
      effectiveBar = frostEnabled ? FrostedBackground(child: rebuilt) : rebuilt;
    }
    if (effectiveBar != null) {
      effectiveBar = MiuixBarTextStyle(child: effectiveBar);
    }
    return m.MiuixScaffold(
      topBar: effectiveBar,
      bottomBar: bottomBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonPosition: floatingActionButtonPosition,
      floatingToolbar: floatingToolbar,
      floatingToolbarPosition: floatingToolbarPosition,
      snackbarHost: snackbarHost,
      popupHost: popupHost,
      containerColor: containerColor,
      contentWindowInsets: contentWindowInsets,
      content: builder,
    );
  }
}

class _StableTopPadding extends StatefulWidget {
  const _StableTopPadding({
    required this.exactTop,
    required this.padding,
    required this.builder,
  });

  final double? exactTop;
  final EdgeInsets padding;
  final m.MiuixScaffoldContentBuilder builder;

  @override
  State<_StableTopPadding> createState() => _StableTopPaddingState();
}

class _StableTopPaddingState extends State<_StableTopPadding> {
  /// While true the scaffold may still be passing its first-frame estimate.
  bool _settling = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _settling) setState(() => _settling = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var padding = widget.padding;
    final exact = widget.exactTop;
    if (_settling && exact != null) {
      if ((padding.top - exact).abs() < 0.5) {
        _settling = false; // real value arrived
      } else {
        padding = padding.copyWith(top: exact);
      }
    }
    return widget.builder(padding);
  }
}
