part of 'components.dart';

/// MIUIX 风格的玻璃浮层
///
/// 阅读器的顶栏、底部工具栏以及阅读设置面板共用这一个组件。
///
/// 之前的写法是外层用 `MiuixSquircleBorder`、内层再用 `ClipRRect` 裁模糊层，
/// 两者形状并不一致：squircle 在 45° 方向比同半径的圆弧更靠外，
/// 于是角落会露出一圈没有被模糊盖住的背景（看起来像一道描边）；
/// 加上 0.8px 描边居中绘制、外侧被 Material 的 clip 裁掉一半，
/// 边缘就会显得毛糙并有锯齿。
///
/// 这里改成：
/// - 模糊层、底色、描边共用同一条 squircle 路径（同一个 [ShapeBorderClipper]），
///   边缘严格重合，不会再露出未模糊的缝；
/// - 模糊层向外扩 [reach] 再裁回，避免边缘采样不足发暗；
/// - 描边改为向内填充的细环，不再有一半被裁掉；
/// - 阴影画在裁剪层外面，可以正常向外扩散。
///
/// ## 入场动画为什么自己实现
///
/// `FadeTransition` / `Opacity` 会让子树做一次离屏合成（`saveLayer`），
/// 而 [BackdropFilter] 在离屏图层里采样不到身后的画面，首帧只能渲染成白色，
/// 等动画结束、opacity 回到 1.0 之后才「闪」成模糊。
///
/// 所以这里把淡入拆成两层：**模糊层固定 opacity 1 不参与动画**，
/// 只有底色、描边和内容淡入。这样第一帧就已经是模糊的，不会闪白。
class MiuixGlassPanel extends StatefulWidget {
  const MiuixGlassPanel({
    super.key,
    required this.child,
    this.cornerRadius = 22,
    this.tint,
    this.strokeColor,
    this.strokeWidth = 0,
    this.blurRadius = 24,
    this.shadow,
    this.padding = EdgeInsets.zero,
    this.animateReveal = true,
    this.revealDuration = const Duration(milliseconds: 200),
  });

  /// 内容
  final Widget child;

  /// squircle 圆角半径
  final double cornerRadius;

  /// 浮层底色（建议带透明度，太不透明会盖掉背后的模糊）
  final Color? tint;

  /// 描边颜色，为空时不画描边
  final Color? strokeColor;

  /// 描边宽度（向内绘制）
  final double strokeWidth;

  /// 模糊半径
  final double blurRadius;

  /// 外阴影
  final BoxShadow? shadow;

  /// 内容内边距
  final EdgeInsetsGeometry padding;

  /// 首次出现时淡入底色与内容（模糊层不参与，见类注释）
  final bool animateReveal;

  /// 淡入时长
  final Duration revealDuration;

  /// 模糊核触及范围，用来决定模糊层需要向外扩多少
  ///
  /// 3σ 足够覆盖高斯核的主要能量，但过大会让 GPU 每帧要多模糊一大圈。
  /// 上限从 160 收紧到 96：阅读器工具栏只有 48~150px 高，
  /// 96 已经远超实际需要。
  static double blurReach(double blurRadius) {
    return (blurRadius * 2.5).clamp(12.0, 96.0);
  }

  @override
  State<MiuixGlassPanel> createState() => _MiuixGlassPanelState();
}

class _MiuixGlassPanelState extends State<MiuixGlassPanel> {
  @override
  Widget build(BuildContext context) {
    final shape = MiuixSquircleBorder(cornerRadius: widget.cornerRadius);
    final reach = MiuixGlassPanel.blurReach(widget.blurRadius);

    // 模糊层：始终完全不透明，绝不参与淡入动画。
    // 一旦被 Opacity / FadeTransition 包住就会离屏合成，BackdropFilter
    // 采不到身后画面，首帧白闪。
    final Widget blurLayer = widget.blurRadius > 0 && frostEnabled
        ? Positioned(
            top: -reach,
            bottom: -reach,
            left: -reach,
            right: -reach,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: math.min(widget.blurRadius, kFrostSigma),
                sigmaY: math.min(widget.blurRadius, kFrostSigma),
              ),
              child: const SizedBox.expand(),
            ),
          )
        : const SizedBox.shrink();

    // 底色、描边、内容：这一组才做淡入
    Widget foreground = Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: widget.animateReveal
                ? widget.revealDuration
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, t, __) => DecoratedBox(
              decoration: ShapeDecoration(
                color: (widget.tint ?? Colors.transparent).withValues(
                  alpha: (frostEnabled || widget.tint == null
                          ? (widget.tint?.a ?? 0.0)
                          : 1.0) *
                      t,
                ),
                shape: shape,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _MiuixGlassStrokePainter(
              shape: shape,
              color: widget.strokeColor,
              width: widget.strokeWidth,
            ),
          ),
        ),
        // 内容不参与淡入：一直保持可见，避免文字跟着闪
        Padding(padding: widget.padding, child: widget.child),
      ],
    );

    // 子树里没有 BackdropFilter，这里的动画可以安全执行。
    // 注意：不能用 Opacity / FadeTransition 包住整块面板，
    // 那会让 BackdropFilter 进入离屏图层，采不到背景又变白闪。

    Widget panel = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [blurLayer, foreground],
      ),
    );

    if (widget.shadow != null) {
      panel = DecoratedBox(
        decoration: ShapeDecoration(shape: shape, shadows: [widget.shadow!]),
        child: panel,
      );
    }

    return panel;
  }
}

/// 在面板内侧画出等宽的描边环
///
/// 不用 `BorderSide` + stroke，是因为 stroke 以路径为中心绘制，
/// 外侧的一半会被裁剪掉，只剩半条线并带锯齿。
class _MiuixGlassStrokePainter extends CustomPainter {
  const _MiuixGlassStrokePainter({
    required this.shape,
    required this.color,
    required this.width,
  });

  final ShapeBorder shape;
  final Color? color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final c = color;
    if (c == null || width <= 0) return;
    final rect = Offset.zero & size;
    final outer = shape.getOuterPath(rect);
    final inner = shape.getOuterPath(
      Rect.fromLTRB(width, width, rect.width - width, rect.height - width),
    );
    final ring = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(ring, Paint()
      ..color = c
      ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MiuixGlassStrokePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.width != width ||
        oldDelegate.shape != shape;
  }
}
