library pica_settings;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/comic_source/built_in/jm.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/main.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/pages/logs_page.dart';
import 'package:pica_comic/pages/accounts_page.dart';
import 'package:pica_comic/foundation/js_engine.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../foundation/local_favorites.dart';
import '../../network/cookie_jar.dart';
import '../../network/download.dart';
import '../../network/eh_network/eh_main_network.dart';
import '../../network/http_client.dart';
import '../../network/http_proxy.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/nhentai_network/nhentai_main_network.dart';
import '../../network/update.dart';
import '../../network/webdav.dart';
import '../../tools/background_service.dart';
import '../../tools/debug.dart';
import '../welcome_page.dart';
import 'package:pica_comic/tools/translations.dart';

part "reading_settings.dart";
part "picacg_settings.dart";
part "network_setting.dart";
part "multi_pages_filter.dart";
part "local_favorite_settings.dart";
part "jm_settings.dart";
part "hi_settings.dart";
part "ht_settings.dart";
part "explore_settings.dart";
part "eh_settings.dart";
part "nh_settings.dart";
part "comic_source_settings.dart";
part "blocking_keyword_page.dart";
part "app_settings.dart";
part 'components.dart';

class SettingsPage extends StatefulWidget {
  static void open([int initialPage = -1]) {
    App.globalTo(() => SettingsPage(initialPage: initialPage));
  }

  /// 单独打开某个设置分区（如从账号管理跳转），返回时直接回到上一页
  static void openSection(int page) {
    App.globalTo(() => SettingsPage(initialPage: page, singlePage: true));
  }

  const SettingsPage({this.initialPage = -1, this.singlePage = false, super.key});

  /// 为 true 时只显示 [initialPage] 分区，返回即关闭整个页面
  final bool singlePage;

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> implements PopEntry{
  int currentPage = -1;

  MiuixColors get colors => MiuixTheme.of(context).colors;

  bool get enableTwoViews => !UiMode.m1(context);

  final categories = <String>["浏览", "漫画源", "阅读", "外观", "本地收藏", "APP", "网络", "关于"];

  final icons = <MiuixVectorIcon>[
    MiuixIcons.os4.layers,
    MiuixIcons.os4.store,
    MiuixIcons.os4.book,
    MiuixIcons.os4.theme,
    MiuixIcons.os4.favorites,
    MiuixIcons.os4.gridView,
    MiuixIcons.os4.link,
    MiuixIcons.os4.info
  ];

  double offset = 0;

  /// 路由滑入完成后再挂分类列表，避免首帧重布局与 Hyper 过渡抢同一帧。
  bool _entered = false;

  void _armEnterAfterTransition() {
    if (_entered) return;
    final animation = ModalRoute.of(context)?.animation;
    void mark() {
      if (!mounted || _entered) return;
      setState(() => _entered = true);
    }
    if (animation == null ||
        animation.status == AnimationStatus.completed) {
      mark();
      return;
    }
    late final void Function(AnimationStatus) listener;
    listener = (status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        mark();
      }
    };
    animation.addStatusListener(listener);
    // 兜底：动画被打断也尽快显示
    Future<void>.delayed(const Duration(milliseconds: 420), mark);
  }

  late final MiuixExitUntilCollapsedScrollBehavior _leftBehavior;
  late final MiuixExitUntilCollapsedScrollBehavior _rightBehavior;

  late final HorizontalDragGestureRecognizer gestureRecognizer;

  ModalRoute? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
  }

  @override
  void initState() {
    _leftBehavior = MiuixExitUntilCollapsedScrollBehavior();
    _rightBehavior = MiuixExitUntilCollapsedScrollBehavior();
    currentPage = widget.initialPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPopGesture();
      _armEnterAfterTransition();
    });
    gestureRecognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onUpdate = ((details) => setState(() => offset += details.delta.dx))
      ..onEnd = (details) async {
        if (details.velocity.pixelsPerSecond.dx.abs() > 1 &&
            details.velocity.pixelsPerSecond.dx >= 0) {
          setState(() {
            Future.delayed(const Duration(milliseconds: 300), () => offset = 0);
            currentPage = -1;
          });
          _syncPopGesture();
        } else if (offset > MediaQuery.of(context).size.width / 2) {
          setState(() {
            Future.delayed(const Duration(milliseconds: 300), () => offset = 0);
            currentPage = -1;
          });
          _syncPopGesture();
        } else {
          int i = 10;
          while (offset != 0) {
            setState(() {
              offset -= i;
              i *= 10;
              if (offset < 0) {
                offset = 0;
              }
            });
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      }
      ..onCancel = () async {
        int i = 10;
        while (offset != 0) {
          setState(() {
            offset -= i;
            i *= 10;
            if (offset < 0) {
              offset = 0;
            }
          });
          await Future.delayed(const Duration(milliseconds: 10));
        }
      };
    super.initState();
  }

  @override
  dispose() {
    _leftBehavior.state.dispose();
    _rightBehavior.state.dispose();
    super.dispose();
    gestureRecognizer.dispose();
    App.temporaryDisablePopGesture = false;
    _route?.unregisterPopEntry(this);
  }

  @override
  Widget build(BuildContext context) {
    // 不在 build 里改 PopGesture / canPop（会触发路由侧重建，打开动画掉帧）。
    // 外层不再套空 MiuixScaffold：分类页 / 分区页各自已有脚手架，嵌套会造成
    // 过渡动画期间多一次布局沉降，体感卡顿。
    final bg = MiuixTheme.of(context).colors.background;
    return ColoredBox(
      color: bg,
      child: Material(
        color: bg,
        child: buildBody(),
      ),
    );
  }

  void _syncPopGesture() {
    if (widget.singlePage) {
      canPop.value = true;
      App.temporaryDisablePopGesture = false;
    } else if (currentPage != -1 && !enableTwoViews) {
      canPop.value = false;
      App.temporaryDisablePopGesture = true;
    } else {
      canPop.value = true;
      App.temporaryDisablePopGesture = false;
    }
  }

  Widget buildBody() {
    if (widget.singlePage && currentPage != -1) {
      return buildRight();
    }
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(
            width: 320,
            height: double.infinity,
            child: buildLeft(),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: MiuixTheme.of(context).colors.dividerLine,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(child: buildRight())
        ],
      );
    } else {
      return Stack(
        children: [
          Positioned.fill(child: buildLeft()),
          if (currentPage != -1)
            Positioned(
              left: offset,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Listener(
                onPointerDown: handlePointerDown,
                child: MiuixScaffold(
                  content: (_) => buildRight(),
                ),
              ),
            )
        ],
      );
    }
  }

  void handlePointerDown(PointerDownEvent event) {
    if (widget.singlePage) return;
    if (event.position.dx < 20) {
      gestureRecognizer.addPointer(event);
    }
  }

  Widget buildLeft() {
    return MiuixScaffold(
      topBar: MiuixTopAppBar(color: MiuixTheme.of(context).colors.background, 
        title: "设置".tl,
        scrollBehavior: _leftBehavior,
        blurred: false,
        navigationIcon: Navigator.of(context).canPop()
            ? MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("返回".tl)),
 child: MiuixIconButton(
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('chevronBackward') ??
                        MiuixIcons.os4.back,
                    size: 20,
                  ),
                  onPressed: () => App.globalBack(),
                ),
)
            : null,
      ),
      content: (padding) => MiuixScrollBehaviorListener(
        behavior: _leftBehavior,
        child: _entered
            ? buildCategories(padding)
            : SizedBox(height: padding.top),
      ),
    );
  }

  Widget buildCategories([EdgeInsets padding = EdgeInsets.zero]) {
    Widget buildItem(String name, int id) {
      final bool selected = id == currentPage;

      const itemShape = MiuixSquircleBorder(cornerRadius: 16);
      Widget content = Container(
        width: double.infinity,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          color: selected
              ? colors.primary.withOpacity(0.15)
              : colors.surfaceContainer, // Miuix 卡片色（surface 在 Miuix 中等于页面背景）
          shape: itemShape,
        ),
        child: Row(children: [
          MiuixIcon(
            vector: icons[id],
            tint: selected ? colors.primary : colors.onSurface,
            size: 22,
          ),
          const SizedBox(
            width: 16,
          ),
          Text(
            name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? colors.primary : colors.onSurface,
            ),
          ),
          const Spacer(),
          MiuixIcon(vector: MiuixIcons.os4.chevronForward, size: 18, tint: colors.onSurfaceVariantSummary.withOpacity(0.5),
          ),
        ]),
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: MiuixPressable(
          onPressed: () {
            setState(() {
              _rightBehavior.state.heightOffset = 0;
              _rightBehavior.state.contentOffset = 0;
              currentPage = id;
            });
            _syncPopGesture();
          },
          feedbackType: MiuixPressFeedbackType.sink,
          shape: itemShape,
          child: content,
        ),
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: categories.length,
      itemBuilder: (context, index) => buildItem(categories[index].tl, index),
    );
  }

  Widget buildReadingSettings() {
    return const Placeholder();
  }

  Widget buildAppearanceSettings() => Column(
        children: [
          MiuixSmallTitle("主题与色彩".tl),
          MiuixSettingsCard(
            children: [
              SelectSettingWithAppdata(
                title: "主题选择".tl,
                icon: _mi(MiuixIcons.os4.theme),
                settingsIndex: 27,
                options: [
                  "动态色彩".tl,
                  "小米蓝".tl,
                  "玫瑰粉".tl,
                  "薰衣草紫".tl,
                  "靛青".tl,
                  "天蓝".tl,
                  "青色".tl,
                  "蓝绿".tl,
                  "抹茶绿".tl,
                  "青柠".tl,
                  "金黄".tl,
                  "琥珀".tl,
                  "珊瑚橙".tl,
                ],
                onChanged: () {
                  setState(() {});
                  MyApp.updater?.call();
                },
              ),
              SelectSettingWithAppdata(
                title: "深色模式".tl,
                icon: _mi(MiuixIcons.os4.background),
                settingsIndex: 32,
                options: ["跟随系统".tl, "禁用".tl, "启用".tl],
                onChanged: () {
                  setState(() {});
                  MyApp.updater?.call();
                },
              ),
              if (appdata.settings[32] == "0" || appdata.settings[32] == "2")
                MiuixSwitchPreference(
                  title: "纯黑色模式".tl,
                  startAction: _mi(MiuixIcons.os4.show),
                  value: appdata.settings[84] == "1",
                  onChanged: (i) {
                    setState(() {
                      appdata.settings[84] = i ? "1" : "0";
                    });
                    appdata.updateSettings();
                    MyApp.updater?.call();
                  },
                ),
            ],
          ),
          MiuixSmallTitle("显示与性能".tl),
          MiuixSettingsCard(
            children: [
              MiuixSwitchPreference(
                title: "毛玻璃效果".tl,
                summary: "关闭后顶栏与底栏使用纯色背景, 更省电".tl,
                startAction: _mi(MiuixIcons.os4.show),
                value: appdata.settings[92] != "0",
                onChanged: (b) {
                  setState(() {
                    appdata.settings[92] = b ? "1" : "0";
                  });
                  appdata.updateSettings();
                  MyApp.updater?.call();
                },
              ),
              if (App.isAndroid)
                SelectSetting(
                  leading: _mi(MiuixIcons.os4.screenMirroring),
                  title: "屏幕刷新率".tl,
                  values: ["跟随系统".tl, "高刷新率".tl, "60Hz"],
                  initialValue:
                      (int.tryParse(appdata.settings[38]) ?? 0).clamp(0, 2),
                  onChanged: (i) {
                    appdata.settings[38] = i.toString();
                    appdata.updateSettings();
                    applyRefreshRateSetting();
                  },
                ),
            ],
          ),
        ],
      );

  Widget buildAppSettings() {
    return Column(
      children: [
        MiuixSmallTitle("日志与调试".tl),
        MiuixSettingsCard(
          children: [
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.report),
              title: "Logs",
              summary: "查看运行与调试日志".tl,
              onClick: () => context.to(() => const LogsPage()),
            ),
          ],
        ),
        MiuixSmallTitle("版本与更新".tl),
        MiuixSettingsCard(
          children: [
            SwitchSetting(
              title: "启动时检查更新".tl,
              settingsIndex: 2,
              icon: _mi(MiuixIcons.os4.download),
            ),
          ],
        ),
        MiuixSmallTitle("存储与数据".tl),
        MiuixSettingsCard(
          children: [
            if (App.isDesktop || App.isAndroid)
              MiuixArrowPreference(
                startAction: _mi(MiuixIcons.os4.folder),
                title: "漫画下载目录".tl,
                summary: downloadFolderSummary(),
                onClick: () {
                  setDownloadFolder().then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
            if (App.isDesktop || App.isAndroid)
              MiuixArrowPreference(
                startAction: _mi(MiuixIcons.os4.image),
                title: "图片保存目录".tl,
                summary: imageSaveFolderSummary(),
                onClick: () {
                  setImageSaveFolder().then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.fileDownloads),
              title: "缓存大小限制".tl,
              summary: '${bytesLengthToReadableSize(CacheManager().currentSize)}'
                  ' / '
                  '${bytesLengthToReadableSize(CacheManager().limitSize)}',
              onClick: setCacheLimit,
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.clear),
              title: "清除缓存".tl,
              onClick: () {
                CacheManager().clear().then((value) {
                  if (mounted) {
                    setState(() {});
                  }
                });
              },
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.delete),
              title: "删除所有数据".tl,
              onClick: () => clearUserData(context),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.share),
              title: "导出用户数据".tl,
              onClick: () => exportDataSetting(context),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.import),
              title: "导入用户数据".tl,
              onClick: () => importDataSetting(context),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.refresh),
              title: "数据同步".tl,
              summary: () {
                final raw = appdata.settings[45];
                if (raw.isEmpty) return "未启用".tl;
                final url = raw.split(';').first;
                return url.isEmpty ? "未启用".tl : "已启用".tl;
              }(),
              onClick: () async {
                await syncDataSettings(context);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        MiuixSmallTitle("安全与隐私".tl),
        MiuixSettingsCard(
          children: [
            if (App.isAndroid)
              MiuixSwitchPreference(
                startAction: _mi(MiuixIcons.os4.screenCapture),
                title: "阻止屏幕截图".tl,
                summary: "需要重启App以应用更改".tl,
                value: appdata.settings[12] == "1",
                onChanged: (b) {
                  b ? appdata.settings[12] = "1" : appdata.settings[12] = "0";
                  setState(() {});
                  appdata.writeData();
                },
              ),
            SwitchSetting(
              title: "需要身份验证".tl,
              subTitle: "如果系统中未设置任何认证方法请勿开启".tl,
              settingsIndex: 13,
              icon: _mi(MiuixIcons.os4.lock),
            ),
          ],
        ),
        MiuixSmallTitle("其它偏好".tl),
        MiuixSettingsCard(
          children: [
            SelectSetting(
              leading: _mi(MiuixIcons.os4.translate),
              title: "语言".tl,
              initialValue:
                  ["", "cn", "tw", "en"].indexOf(appdata.settings[50]).clamp(0, 3),
              values: const ["System", "中文(简体)", "中文(繁體)", "English"],
              onChanged: (value) {
                appdata.settings[50] = ["", "cn", "tw", "en"][value];
                appdata.updateSettings();
                MyApp.updater?.call();
              },
            ),
            SelectSetting(
              leading: _mi(MiuixIcons.os4.download),
              title: "下载并行".tl,
              initialValue: ["1", "2", "4", "6", "8", "16"]
                  .indexOf(appdata.settings[79])
                  .clamp(0, 5),
              values: const ["1", "2", "4", "6", "8", "16"],
              onChanged: (value) {
                appdata.settings[79] = ["1", "2", "4", "6", "8", "16"][value];
                appdata.updateSettings();
              },
            ),
            if (App.isAndroid)
              MiuixArrowPreference(
                title: "应用链接".tl,
                summary: "在系统设置中管理APP支持的链接".tl,
                startAction: _mi(MiuixIcons.os4.link),
                onClick: () async {
                  try {
                    await const MethodChannel("pica_comic/settings")
                        .invokeMethod("link");
                  } catch (e) {
                    showToast(message: "无法打开系统设置".tl);
                  }
                },
              ),
            if (kDebugMode)
              MiuixArrowPreference(
                title: "Debug",
                onClick: debug,
              ),
          ],
        ),
        Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16))
      ],
    );
  }

  Widget buildAbout() {
    final colors = MiuixTheme.of(context).colors;
    void open(String url) =>
        launchUrlString(url, mode: LaunchMode.externalApplication);
    return Column(
      children: [
        const SizedBox(height: 12),
        MiuixSettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
              child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const ShapeDecoration(
                      shape: MiuixSquircleBorder(cornerRadius: 22),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const Image(
                      image: AssetImage("images/app_icon_no_bg.png"),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Pica Comic",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: ShapeDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      textAlign: TextAlign.center,
                      "v$appVersion · HyperOS Edition",
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "一个完全免费的漫画阅读APP · 仅用于学习交流".tl,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: colors.onSurfaceVariantSummary),
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
        MiuixSmallTitle("版本与更新".tl),
        MiuixSettingsCard(
          children: [
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.update),
              title: "检查更新".tl,
              summary: "${"当前:".tl} $appVersion",
              onClick: () => findUpdate(context),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.listView),
              title: "更新日志".tl,
              summary: "查看当前版本的更新内容".tl,
              onClick: () => showLatestChangelog(context),
            ),
          ],
        ),
        MiuixSmallTitle("开源与社区".tl),
        MiuixSettingsCard(
          children: [
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.community),
              title: "项目地址 (GitHub)".tl,
              summary: "Qilaiwing/PicaComic_miuix",
              onClick: () => open("https://github.com/Qilaiwing/PicaComic_miuix"),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.share),
              title: "上游地址（GitHub）".tl,
              summary: "Pacalini/PicaComic",
              onClick: () => open("https://github.com/Pacalini/PicaComic"),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.tasks),
              title: "问题反馈 (GitHub Issues)".tl,
              summary: "提交缺陷与功能建议".tl,
              onClick: () =>
                  open("https://github.com/Qilaiwing/PicaComic_miuix/issues"),
            ),
            MiuixArrowPreference(
              startAction: _mi(MiuixIcons.os4.info),
              title: "开源许可".tl,
              summary: "MIT License",
              onClick: () => open(
                  "https://github.com/Qilaiwing/PicaComic_miuix/blob/miuix/LICENSE"),
            ),
          ],
        ),
        Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 24))
      ],
    );
  }

  Widget buildRight() {
    final Widget body = switch (currentPage) {
      -1 => const SizedBox(),
      0 => buildExploreSettings(context, false),
      1 => const ComicSourceSettings(),
      2 => const ReadingSettings(false),
      3 => buildAppearanceSettings(),
      4 => const LocalFavoritesSettings(),
      5 => buildAppSettings(),
      6 => const NetworkSettings(),
      7 => buildAbout(),
      _ => throw UnimplementedError()
    };

    if (currentPage != -1) {
      return MiuixScaffold(
        topBar: MiuixTopAppBar(color: MiuixTheme.of(context).colors.background, 
          title: categories[currentPage].tl,
          scrollBehavior: _rightBehavior,
          blurred: false,
          navigationIcon: enableTwoViews && !widget.singlePage
              ? null
              : MiuixIconButton(
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('chevronBackward') ??
                        MiuixIcons.os4.back,
                    size: 20,
                  ),
                  onPressed: () {
                    if (widget.singlePage) {
                      _singlePageBack();
                    } else {
                      setState(() {
                        _leftBehavior.state.heightOffset = 0;
                        currentPage = -1;
                      });
                      _syncPopGesture();
                    }
                  },
                ),
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _rightBehavior,
          child: SingleChildScrollView(
            // 不能给 key 加 currentPage：换页时整棵子树会被重建，
            // 滚动位置与布局都会重置，进页面第一帧会「抖」一下。
            // 用 PageStorageKey 反而能记住每页各自的滚动位置。
            key: PageStorageKey<int>(currentPage),
            padding: padding,
            child: body,
          ),
        ),
      );
    }

    return body;
  }

  /// 单页模式返回：本页可能位于弹窗内部的嵌套 Navigator 根部，
  /// 此时内层 maybePop 无路由可弹，需要回落到外层/根 Navigator。
  void _singlePageBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      root.pop();
    } else {
      App.globalBack();
    }
  }

  var canPop = ValueNotifier(true);

  @override
  ValueListenable<bool> get canPopNotifier => canPop;

  @override
  void onPopInvokedWithResult(bool didPop, result) {
    if (widget.singlePage) return;
    if (currentPage != -1) {
      setState(() {
        _leftBehavior.state.heightOffset = 0;
        currentPage = -1;
      });
            _syncPopGesture();
    }
  }

  @override
  void onPopInvoked(bool didPop) {
    if (widget.singlePage) return;
    if (currentPage != -1) {
      setState(() {
        _leftBehavior.state.heightOffset = 0;
        currentPage = -1;
      });
            _syncPopGesture();
    }
  }
}
