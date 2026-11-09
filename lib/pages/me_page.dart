import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'accounts_page.dart';
import 'package:pica_comic/pages/download_page.dart';
import 'package:pica_comic/pages/tools.dart';
import 'package:pica_comic/foundation/app.dart';
import 'history_page.dart';
import 'reading_stats_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'image_favorites.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> with WidgetsBindingObserver {
  /// 等级胶囊是否切换到"经验值"显示
  bool _showExp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constrains) {
          final width = constrains.maxWidth;
          bool shouldShowTwoPanel = width > 600;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, MainTopInset.of(context), 12, 100),
            child: Column(
              children: [
                const SizedBox(height: 12),
                buildProfile(),
                const SizedBox(height: 12),
                buildHistory(context),
                if (shouldShowTwoPanel)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            buildDownload(context, width),
                            const SizedBox(height: 12),
                            buildImageFavorite(context, width),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            buildTools(width),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  const SizedBox(height: 12),
                  buildDownload(context, width),
                  const SizedBox(height: 12),
                  buildImageFavorite(context, width),
                  const SizedBox(height: 12),
                  buildTools(width),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 读取 PicaCG 的本地用户资料, 未登录或数据损坏时返回 null
  Profile? getPicacgProfile() {
    var raw = ComicSource.find('picacg')?.data['user'];
    if (raw == null) return null;
    try {
      return Profile.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      return null;
    }
  }

  /// 根据当前时间生成问候语
  String getGreeting() {
    var hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 10) return "早上好".tl;
    if (hour >= 11 && hour <= 13) return "中午好".tl;
    if (hour >= 14 && hour <= 18) return "下午好".tl;
    return "晚上好".tl;
  }

  /// 给整数加上千分位分隔符, 例如 80000 -> 80,000
  String _formatNumber(int value) {
    var str = value.abs().toString();
    var buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return value < 0 ? "-$buffer" : buffer.toString();
  }

  /// 时长的紧凑文案（拉丁缩写，与语言无关）
  String _formatUsage(Duration d) {
    final minutes = d.inMinutes;
    if (d.inSeconds <= 0) return "0m";
    if (minutes < 1) return "<1m";
    if (minutes < 60) return "${minutes}m";
    final hours = d.inHours;
    final remMin = minutes % 60;
    if (hours < 24) {
      return remMin == 0 ? "${hours}h" : "${hours}h ${remMin}m";
    }
    final days = d.inDays;
    final remHours = hours % 24;
    return remHours == 0 ? "${days}d" : "${days}d ${remHours}h";
  }

  Widget buildProfile() {
    final context = App.globalContext!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final miuixColors = MiuixTheme.of(context).colors;
    final primary = miuixColors.primary;
    final onCard = miuixColors.onSurface;

    final profile = getPicacgProfile();
    final logged = profile != null;
    final enabledSources = ComicSource.sources.length;
    final historyCount = HistoryManager().count();
    final todayReadMs = ReadingStats.instance.today[0];
    final usageText = _formatUsage(Duration(milliseconds: todayReadMs));

    final name = logged ? profile.name : "请登录您的PicACG".tl;
    final slogan = logged ? (profile.slogan ?? '') : "登录后即可展示你的个人信息".tl;
    final avatarUrl = logged ? profile.avatarUrl : null;

    /// 等级胶囊, 点击可在 "Lv1 萌新" 与 "经验值" 之间切换
    Widget? buildLevelBadge() {
      if (!logged) return null;
      var level = profile.level;
      var title = profile.title.trim();
      var levelText = title.isEmpty ? "Lv$level" : "Lv$level $title";
      var expText = "${_formatNumber(profile.exp)} EXP";
      var text = _showExp ? expText : levelText;
      return GestureDetector(
        onTap: () => setState(() => _showExp = !_showExp),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: ShapeDecoration(
            color: primary.withOpacity(0.14),
            shape: const MiuixSquircleBorder(cornerRadius: 7),
          ),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: primary,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final levelBadge = buildLevelBadge();

    Widget buildStat({
      required String title,
      required String value,
      required bool highlight,
      VoidCallback? onTap,
    }) {
      final body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color: isDark ? const Color(0x0DFFFFFF) : const Color(0x0A000000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: onCard.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: highlight ? primary : onCard,
              ),
            ),
          ],
        ),
      );

      return Expanded(
        child: MiuixPressable(
          shape: MiuixSquircleBorder(
            cornerRadius: 16,
            side: BorderSide(
              color: isDark ? const Color(0x0DFFFFFF) : const Color(0x0A000000),
              width: 0.6,
            ),
          ),
          feedbackType: onTap != null
              ? MiuixPressFeedbackType.sink
              : MiuixPressFeedbackType.none,
          onPressed: onTap,
          button: onTap != null,
          child: body,
        ),
      );
    }

    // 个人信息卡：整卡 tilt；仅「漫画源」小磁贴进入账号管理。
    return MiuixCard(
      cornerRadius: 18,
      feedbackType: MiuixPressFeedbackType.tilt,
      insideMargin: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(
                size: 60,
                avatarUrl: avatarUrl,
                name: name,
                slogan: profile?.slogan,
                level: profile?.level ?? 0,
                couldBeShown: logged,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getGreeting(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: onCard.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: onCard,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      slogan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: onCard.withOpacity(0.62),
                      ),
                    ),
                  ],
                ),
              ),
              if (levelBadge != null) ...[
                const SizedBox(width: 10),
                levelBadge,
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              buildStat(
                title: "漫画源".tl,
                value: enabledSources.toString(),
                highlight: enabledSources > 0,
                onTap: () async {
                  await showPopUpWidget(context, const AccountsPage());
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(width: 10),
              buildStat(
                title: "浏览数".tl,
                value: historyCount.toString(),
                highlight: historyCount > 0,
              ),
              const SizedBox(width: 10),
              buildStat(
                title: "今日阅读".tl,
                value: usageText,
                // 与「漫画源」一致：为 0 时走 onSurface（主题文字色），有值时用 primary
                highlight: todayReadMs > 0,
                onTap: () => context.to(() => const ReadingStatsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildHistory(BuildContext context) {
    var history = HistoryManager().getRecent();
    final primary = Theme.of(context).colorScheme.primary;

    return MiuixCard(
      cornerRadius: 18,
      onPressed: () => context.to(() => const HistoryPage()),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Column(
        children: [
          MiuixBasicComponent(
            startAction: Container(
              width: 38,
              height: 38,
              decoration: ShapeDecoration(
                shape: const MiuixSquircleBorder(cornerRadius: 12),
                color: primary.withOpacity(0.1),
              ),
              child: Icon(Icons.history, color: primary, size: 20),
            ),
            title: "历史记录".tl,
            endActions: const [Icon(Icons.chevron_right, size: 20)],
          ),
          if (history.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                const horizontalPadding = 14.0;
                final itemWidth = (constraints.maxWidth -
                        horizontalPadding * 2 -
                        spacing * 2) /
                    3;
                final itemHeight = itemWidth * 1.42;
                return SizedBox(
                  height: itemHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding),
                    itemCount: history.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: spacing),
                    itemBuilder: (context, index) {
                      return SizedBox(
                        width: itemWidth,
                        child: MiuixPressable(
                          shape: const MiuixSquircleBorder(cornerRadius: 12),
                          feedbackType: MiuixPressFeedbackType.sink,
                          onPressed: () =>
                              toComicPageWithHistory(context, history[index]),
                          child: ClipPath(
                            clipper: const ShapeBorderClipper(
                              shape: MiuixSquircleBorder(cornerRadius: 12),
                            ),
                            child: Container(
                              decoration: ShapeDecoration(
                                shape: const MiuixSquircleBorder(
                                    cornerRadius: 12),
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                              ),
                              child: AnimatedImage(
                                image: CachedImageProvider(
                                  history[index].cover,
                                  sourceKey:
                                      history[index].type.comicSource?.key,
                                ),
                                forceFit: BoxFit.cover,
                                width: itemWidth,
                                height: itemHeight,
                                clipShape: const MiuixSquircleBorder(
                                    cornerRadius: 12),
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget buildDownload(BuildContext context, double width) {
    return _MePageCard(
      icon: const Icon(Icons.download_for_offline),
      title: "已下载".tl,
      description:
          "共 @a 部漫画".tlParams({"a": DownloadManager().total.toString()}),
      onTap: () => context.to(() => const DownloadPage()),
    );
  }

  Widget buildImageFavorite(BuildContext context, double width) {
    return _MePageCard(
      icon: const Icon(Icons.image),
      title: "图片收藏".tl,
      description:
          "@a 条图片收藏".tlParams({"a": ImageFavoriteManager.length.toString()}),
      onTap: () => context.to(() => const ImageFavoritesPage()),
    );
  }

  Widget buildTools(double width) {
    Widget buildItem(String name) {
      return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: ShapeDecoration(
          color: Theme.of(App.globalContext!)
              .colorScheme
              .primary
              .withOpacity(0.08),
          shape: const MiuixSquircleBorder(cornerRadius: 13),
        ),
        child: Center(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(App.globalContext!).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return _MePageCard(
      icon: const Icon(Icons.build_circle),
      title: "工具".tl,
      description: "使用工具发现更多漫画".tl,
      onTap: openTool,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          buildItem("EH订阅".tl),
          buildItem("图片搜索".tl),
          buildItem("打开链接".tl),
        ],
      ).paddingHorizontal(16).paddingBottom(16),
    );
  }

}

class _MePageCard extends StatelessWidget {
  const _MePageCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.child,
  });

  final Widget icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return MiuixCard(
      cornerRadius: 18,
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixBasicComponent(
            startAction: Container(
              width: 38,
              height: 38,
              decoration: ShapeDecoration(
                shape: const MiuixSquircleBorder(cornerRadius: 12),
                color: primary.withOpacity(0.1),
              ),
              child: IconTheme(
                data: IconThemeData(color: primary, size: 20),
                child: icon,
              ),
            ),
            title: title,
            endActions: const [Icon(Icons.chevron_right, size: 20)],
          ),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.8),
            ),
          )
              .paddingHorizontal(16)
              .paddingBottom(child != null ? 8 : 16)
              .paddingTop(2),
          if (child != null) child!,
        ],
      ),
    );
  }
}