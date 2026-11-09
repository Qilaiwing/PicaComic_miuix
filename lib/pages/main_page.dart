import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/webdav.dart';
import 'package:pica_comic/tools/app_links.dart';
import 'package:pica_comic/tools/background_service.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'category_page.dart';
import 'explore_page.dart';
import 'favorites/main_favorites_page.dart';
import 'pre_search_page.dart';
import 'settings/settings_page.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/update.dart';
import 'me_page.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';

bool _haveClipboardDialog = false;

void checkClipboard() async {
  if (appdata.settings[61] == "0") {
    return;
  }
  var data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null && canHandle(data!.text!)) {
    await Future.delayed(const Duration(milliseconds: 200));
    if (_haveClipboardDialog) {
      return;
    }
    _haveClipboardDialog = true;
    final open = await showMiuixDialog<bool>(
      context: App.globalContext!,
      title: "发现剪切板中的链接".tl,
      summary: data.text!,
      actionsBuilder: (dialogContext, close) => [
        MiuixTextButton("打开".tl, onPressed: () {
          close(true);
        }),
      ],
    );
    if (open == true) {
      handleAppLinks(Uri.parse(data.text!));
    }
    _haveClipboardDialog = false;
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  static MainPageState of(BuildContext context) {
    return context.findAncestorStateOfType<MainPageState>()!;
  }

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  GlobalKey<NavigatorState>? _navigatorKey;

  late final NaviObserver _observer;
  DateTime? _lastBackTime;

  void _handleRootBack(int index) {
    // 1. 如果内部 Navigator 还能 pop，优先 pop 内部子页面
    if (_navigatorKey?.currentState?.canPop() ?? false) {
      _navigatorKey!.currentState!.pop();
      return;
    }
    // 2. 如果是收藏页（index == 1）：
    if (index == 1) {
      final favController =
          StateController.findOrNull<FavoritesPageController>();
      if (favController != null) {
        if (favController.selectedComics.isNotEmpty) {
          favController.selectedComics.clear();
          favController.update();
          return;
        }
        if (!favController.selectingFolder) {
          favController.selectingFolder = true;
          favController.update();
          appdata.implicitData[0] = "1;;";
          appdata.writeImplicitData();
          return;
        }
      }
    }
    // 3. 已经在根 Tab 且无任何可回退内容：双击退出保护
    final now = DateTime.now();
    if (_lastBackTime == null ||
        now.difference(_lastBackTime!) > const Duration(seconds: 2)) {
      _lastBackTime = now;
      showToast(message: "再按一次退出应用".tl);
      return;
    }
    SystemNavigator.pop();
  }

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    App.to(_navigatorKey!.currentContext!, widget);
  }

  void back() {
    _navigatorKey!.currentContext!.pop();
  }

  List<Widget> get _pages => [
        const MePage(),
        FavoritesPage(key: ValueKey("fav_$_sourcesVersion")),
        ExplorePage(
          key: Key(
              "${appdata.appSettings.explorePages.join(",")}_$_sourcesVersion"),
        ),
        AllCategoryPage(key: ValueKey("cat_$_sourcesVersion")),
      ];

  int _sourcesVersion = 0;

  void _onSourcesChanged() {
    if (mounted) {
      setState(() => _sourcesVersion = ComicSource.sourcesChanged.value);
    }
  }

  @override
  void dispose() {
    ComicSource.sourcesChanged.removeListener(_onSourcesChanged);
    super.dispose();
  }

  void _login() {
    network.updateProfile().then((res) {
      if (res.error) {
        final msg = res.errorMessageWithoutNull;
        LogManager.addLog(
            LogLevel.info, "Picacg", "launch updateProfile failed: $msg");
        // 冷启动刷新资料是非关键路径：服务端 5xx / 网络抖动不弹英文原文。
        // 仅登录失效给中文轻提示，其余静默（账号页仍可手动刷新）。
        final authFail = msg.contains("登录失效") ||
            msg.contains("未登录") ||
            msg.contains("401") ||
            msg.toLowerCase().contains("unauthorized");
        if (authFail) {
          showToast(message: "哔咔登录已失效，请重新登录".tl);
        }
      } else {
        //检查是否打卡
        if (network.user?.isPunched == false && appdata.settings[6] == "1") {
          // 前台直接打卡 (所有平台); 移动端另外注册后台任务作为兜底
          network.punchIn().then((b) {
            if (b) {
              network.user?.isPunched = true;
              network.user?.exp += 10;
              showToast(message: "打卡成功".tl);
            }
          });
          if (App.isMobile) {
            runBackgroundService();
          }
        }
      }
    });
  }

  void _checkUpdates() async {
    if (appdata.settings[2] != "1") return;
    var s = await SharedPreferences.getInstance();

    Future<void> showPending({
      required String? version,
      required String? notes,
      required String releaseUrl,
    }) async {
      if (!mounted || App.globalContext == null) return;
      showUpdateDialog(App.globalContext!,
          version: version,
          notes: notes,
          releaseUrl: releaseUrl);
    }

    Future<void> cachePending({
      required String version,
      String? tag,
      String? notes,
      required String url,
    }) async {
      await s.setString("pendingUpdateVersion", version);
      if (tag != null && tag.isNotEmpty) {
        await s.setString("pendingUpdateTag", tag);
      } else {
        await s.remove("pendingUpdateTag");
      }
      if (notes != null) {
        await s.setString("pendingUpdateNotes", notes);
      } else {
        await s.remove("pendingUpdateNotes");
      }
      await s.setString("pendingUpdateUrl", url);
    }

    Future<void> clearPending() async {
      await s.remove("pendingUpdateVersion");
      await s.remove("pendingUpdateTag");
      await s.remove("pendingUpdateNotes");
      await s.remove("pendingUpdateUrl");
      clearPendingUpdateMemory();
    }

    bool stillNewer(String? remote) {
      if (remote == null || remote.isEmpty) return false;
      return compareSemVer(remote, appVersion);
    }

    Future<bool> tryShowFromCache() async {
      final cachedVer = s.getString("pendingUpdateVersion");
      if (!stillNewer(cachedVer)) {
        if (cachedVer != null) await clearPending();
        return false;
      }
      final notes = s.getString("pendingUpdateNotes");
      final tag = s.getString("pendingUpdateTag");
      final ver = cachedVer!;
      final url = s.getString("pendingUpdateUrl") ??
          getReleasePageUrl(tag ?? "v$ver");
      hydratePendingUpdate(version: ver, tag: tag, notes: notes);
      await showPending(version: ver, notes: notes, releaseUrl: url);
      return true;
    }

    var lastCheck = s.getInt("lastCheckUpdate");
    final lastLocal = s.getString("lastCheckUpdateLocalVersion");
    // 本机版本变了 (升级/降级/测试包) 时强制重新联网, 不受 6 小时节流。
    final sameLocal = lastLocal == appVersion;
    final within6h = sameLocal &&
        lastCheck != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(lastCheck))
                .inHours <
            6;

    // 6 小时内已成功查过: 跳过网络, 但若仍有未安装的新版本, 冷启动照样弹窗。
    if (within6h) {
      await tryShowFromCache();
      return;
    }

    // 等首帧和登录/同步等启动请求先走, 避免和它们抢网络。
    await Future.delayed(const Duration(seconds: 3));
    bool? res;
    for (var i = 0; i < 2 && res == null; i++) {
      if (i > 0) await Future.delayed(const Duration(seconds: 5));
      res = await checkUpdate();
    }
    if (res == null) {
      // 网络失败时若缓存里仍有更新, 也弹一次。
      await tryShowFromCache();
      return;
    }
    await s.setInt("lastCheckUpdate", DateTime.now().millisecondsSinceEpoch);
    await s.setString("lastCheckUpdateLocalVersion", appVersion);
    if (res != true) {
      await clearPending();
      return;
    }
    var info = await getUpdatesInfo();
    var url = await getDownloadUrl();
    final ver = latestVersion;
    if (ver != null) {
      await cachePending(
          version: ver, tag: latestTag, notes: info, url: url);
    }
    await showPending(version: ver, notes: info, releaseUrl: url);
  }


  @override
  void initState() {
    _navigatorKey = GlobalKey();
    App.mainNavigatorKey = _navigatorKey;
    _login();
    notifications.requestPermission();
    notifications.cancelAll();
    _checkUpdates();

    if (appdata.firstUse[3] == "0") {
      appdata.firstUse[3] = "1";
      appdata.writeData();
    }

    Future.delayed(const Duration(milliseconds: 300), () => Webdav.syncData())
        .then((v) => checkClipboard());
    _observer = NaviObserver();
    ComicSource.sourcesChanged.addListener(_onSourcesChanged);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return NaviPane(
      initialPage: int.parse(appdata.settings[23]),
      observer: _observer,
      paneItems: [
        PaneItemEntry(
            label: '我'.tl,
            title: 'Pica Comic',
            icon: Icons.person_outline,
            activeIcon: Icons.person),
        PaneItemEntry(
            label: '收藏'.tl,
            icon: Icons.local_activity_outlined,
            activeIcon: Icons.local_activity),
        PaneItemEntry(
            label: '探索'.tl,
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore),
        PaneItemEntry(
            label: '分类'.tl,
            icon: Icons.account_tree_outlined,
            activeIcon: Icons.account_tree),
      ],
      paneActions: [
        PaneActionEntry(
            icon: Icons.search,
            label: "搜索".tl,
            onTap: () => to(() => PreSearchPage(), preventDuplicate: true)),
        PaneActionEntry(
            icon: Icons.settings,
            label: "设置".tl,
            onTap: () => SettingsPage.open()),
      ],
      pageBuilder: (index) {
        // One stable root route with IndexedStack: switching tabs must NOT
        // pushAndRemoveUntil a fresh page (that remounts Explore and jerks
        // TopInset / grid layout for a frame). Only nested routes are cleared.
        return Navigator(
          observers: [_observer],
          key: _navigatorKey,
          onGenerateRoute: (settings) => AppPageRoute(
            preventRebuild: true,
            isRootRoute: true,
            builder: (context) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  final tab = StateController.findOrNull<MainTabController>()
                          ?.index ??
                      index;
                  _handleRootBack(tab);
                },
                child: NaviPaddingWidget(
                  child: StateBuilder<MainTabController>(
                    builder: (tab) {
                      return IndexedStack(
                        index: tab.index,
                        sizing: StackFit.expand,
                        children: _pages,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
      onPageChange: (index) {
        StateController.findOrNull<MainTabController>()?.setIndex(index);
        // Drop comic-detail etc.; keep the IndexedStack root mounted.
        _navigatorKey!.currentState?.popUntil((route) => route.isFirst);
      },
    );
  }
}
