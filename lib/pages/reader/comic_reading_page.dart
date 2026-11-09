library pica_reader;

import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/pages/settings/settings_page.dart' show SelectSetting;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/scrollable_list/src/item_positions_listener.dart';
import 'package:pica_comic/components/scrollable_list/src/scrollable_positioned_list.dart';
import 'package:pica_comic/components/window_frame.dart';
import 'package:pica_comic/foundation/image_loader/base_image_provider.dart';
import 'package:pica_comic/foundation/image_loader/file_image_loader.dart';
import 'package:pica_comic/foundation/image_loader/stream_image_provider.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/tools/keep_screen_on.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/tools/save_image.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import '../../foundation/app.dart';
import '../../foundation/ui_mode.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../tools/key_down_event.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/tools/translations.dart';

import '../jm/jm_comments_page.dart';

part 'eps_view.dart';

part 'image_view.dart';

part 'image.dart';

part 'touch_control.dart';

part 'reading_logic.dart';

part 'tool_bar.dart';

part 'reading_type.dart';

part 'reading_settings.dart';

part 'reading_data.dart';

///阅读器
class ComicReadingPage extends StatelessWidget {

  final ReadingData readingData;

  late final History? history = HistoryManager().findSync(readingData.id);

  final int initialPage;

  final int initialEp;

  ReadingType get type => readingData.type;

  ComicReadingPage(this.readingData, this.initialPage, this.initialEp,
      {super.key}) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.picacg(
      String target, this.initialEp, List<String> eps, String title,
      {super.key, this.initialPage = 1})
      : readingData = PicacgReadingData(title, target, eps) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.ehentai(Gallery gallery, {super.key, this.initialPage = 1})
      : initialEp = 1,
        readingData = EhReadingData(gallery) {
    StateController.put(ComicReadingPageLogic(
        1,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.jmComic(JmComicInfo comic, this.initialEp,
      {super.key, this.initialPage = 1})
      : readingData = JmReadingData(
          comic.name,
          comic.id,
          comic.series.values.toList(),
          comic.epNames,
        ) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.hitomi(HitomiComic comic, String link,
      {super.key, this.initialPage = 1})
      : initialEp = 1,
        readingData = HitomiReadingData(
          comic.title,
          comic.target,
          comic.files,
          link,
        ) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.htmanga(String target, String title,
      {super.key, this.initialPage = 1})
      : initialEp = 1,
        readingData = HtReadingData(title, target) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  ComicReadingPage.nhentai(String target, String title,
      {super.key, this.initialPage = 1})
      : initialEp = 1,
        readingData = NhentaiReadingData(title, target) {
    StateController.put(ComicReadingPageLogic(
        initialEp,
        readingData,
        initialPage,
        () => _updateHistory(
            StateController.find<ComicReadingPageLogic>(), false)));
  }

  _updateHistory(ComicReadingPageLogic? logic, bool updateMePage) {
    if (readingData.hasEp) {
      if (logic!.order == 1 && logic.index == 1) {
        history?.ep = 0;
        history?.page = 0;
      } else {
        if (logic.order == readingData.eps?.length &&
            logic.index == logic.length) {
          history?.ep = 0;
          history?.page = 0;
        } else {
          history?.ep = logic.order;
          history?.page = logic.index;
        }
      }
    } else {
      if (logic!.index == 1) {
        history?.ep = 0;
        history?.page = 0;
      } else {
        history?.ep = 1;
        history?.page = logic.index;
      }
    }
    history!.maxPage = logic.length;
    HistoryManager().saveReadHistory(history!, updateMePage);
  }

  static void _onStatsPage(int _) => ReadingStats.instance.pageTurned();

  bool get useDarkBackground => appdata.appSettings.useDarkBackground;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<ComicReadingPageLogic>(initState: (logic) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      if (appdata.settings[14] == "1") {
        setKeepScreenOn();
      }
      if (appdata.settings[76] == "1") {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ]);
      } else if (appdata.settings[76] == "2") {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown
        ]);
      }
      //进入阅读器时清除内存中的缓存, 并且增大限制
      BaseImageProvider.clearCache();
      if (history != null) {
        ReadingStats.instance.startSession(
            target: history!.target,
            title: history!.title,
            cover: history!.cover,
            type: history!.type.value);
      }
      logic.addIndexChangeCallback(_onStatsPage);
      // Larger decoded/byte caches while reading; no downscale/cacheWidth.
      BaseImageProvider.setCacheSizeLimit(150 * 1024 * 1024);
      PaintingBinding.instance.imageCache.maximumSize = 200;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 350 * 1024 * 1024;
      logic.openEpsView = openEpsDrawer;
      if (useDarkBackground) {
        Future.microtask(() =>
            StateController.findOrNull<WindowFrameController>()
                ?.setDarkTheme());
      }
    }, dispose: (logic) {
        logic.removeIndexChangeCallback(_onStatsPage);
        ReadingStats.instance.endSession();
      //清除缓存并减小最大缓存
      BaseImageProvider.clearCache();
      BaseImageProvider.setCacheSizeLimit(50 * 1024 * 1024);
      PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;
      logic.clearPhotoViewControllers();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      if (logic.listenVolume != null) {
        logic.listenVolume!.stop();
      }
      if (appdata.settings[14] == "1") {
        cancelKeepScreenOn();
      }
      logic.runningAutoPageTurning = false;
      ComicImage.clear();
      StateController.remove<ComicReadingPageLogic>();
      // 更新本地收藏
      LocalFavoritesManager().onReadEnd(readingData.favoriteId, readingData.favoriteType);
      // 保存历史记录
      if (history != null) {
        logic.flushHistory();
        _updateHistory(logic, true);
      }
      // 退出全屏
      if (logic.isFullScreen) {
        logic.fullscreen();
      }
      if (!DownloadManager().isDownloading) {
        // Really cancel in-flight reader image downloads.
        ImageManager.cancelTasks();
      }
      // 更新漫画详情页面
      Future.microtask(() {
        if (BaseComicPage.tagsStack.isNotEmpty) {
          BaseComicPage.tagsStack.last.updateHistory(history);
        }
      });
      if (appdata.settings[76] != "0") {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
      if (useDarkBackground) {
        Future.microtask(() =>
            StateController.findOrNull<WindowFrameController>()?.resetTheme());
      }
    }, builder: (logic) {
      return DefaultTextStyle.merge(
        style: TextStyle(
          color: useDarkBackground ? Colors.white : null,
          fontSize: 16,
        ),
        child: MiuixScaffold(containerColor: useDarkBackground ? Colors.black : MiuixTheme.of(context).colors.background, floatingActionButton: buildEpChangeButton(logic), content: (_) => StateBuilder<ComicReadingPageLogic>(builder: (logic) {
            if (logic.isLoading) {
              loadInfo(logic);
              return const Center(
                child: MiuixInfiniteProgressIndicator(),
              );
            } else if (logic.urls.isNotEmpty) {
              if (logic.readingMethod ==
                      ReadingMethod.topToBottomContinuously &&
                  !logic.haveUsedInitialPage &&
                  initialPage != 0) {
                Future.microtask(() {
                  logic.jumpToPage(initialPage);
                  logic.haveUsedInitialPage = true;
                });
              }
              //监听音量键
              if (appdata.settings[7] == "1") {
                if (logic.listenVolume == null) {
                  logic.listenVolume = ListenVolumeController(
                      () => logic.jumpToLastPage(),
                      () => logic.jumpToNextPage());
                  logic.listenVolume!.listenVolumeChange();
                }
              } else if (logic.listenVolume != null) {
                logic.listenVolume!.stop();
                logic.listenVolume = null;
              }

              if (appdata.settings[9] == "4") {
                logic.scrollManager ??= ScrollManager(logic);
              }

              var body = Listener(
                onPointerMove: TapController.onPointerMove,
                onPointerUp: TapController.onTapUp,
                onPointerDown: TapController.onTapDown,
                behavior: HitTestBehavior.translucent,
                onPointerCancel: TapController.onTapCancel,
                child: Stack(
                  children: [
                    buildComicView(
                      logic,
                      context,
                      readingData.id,
                    ),
                    if (MediaQuery.of(context).platformBrightness ==
                            Brightness.dark &&
                        appdata.appSettings.reduceBrightnessInDarkMode)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withOpacity(0.2),
                          ),
                        ),
                      ),

                    if (appdata.appSettings.showPageInfoInReader)
                      buildPageInfoText(logic, context),

                    //底部工具栏
                    buildBottomToolBar(logic, context, readingData.hasEp),

                    ...buildButtons(logic, context),

                    //顶部工具栏
                    buildTopToolBar(logic, context),
                  ],
                ),
              );

              return KeyboardListener(
                focusNode: logic.focusNode,
                autofocus: true,
                onKeyEvent: logic.handleKeyboard,
                child: body,
              );
            } else {
              return buildErrorView(logic, context);
            }
          }),
        ),
      );
    });
  }

  Widget buildErrorView(ComicReadingPageLogic logic, BuildContext context) {
    return SafeArea(
        child: Stack(
      children: [
        Positioned(
          left: 8,
          top: 12,
          child: MiuixIconButton(
            onPressed: () => App.globalBack(),
            child: const Icon(Icons.arrow_back),
          ),
        ),
        Positioned(
          top: MediaQuery.of(App.globalContext!).size.height / 2 - 80,
          left: 0,
          right: 0,
          child: const Align(
            alignment: Alignment.topCenter,
            child: Icon(
              Icons.error_outline,
              size: 60,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(App.globalContext!).size.height / 2 - 10,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              logic.errorMessage ?? "未知错误".tl,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(App.globalContext!).size.height / 2 + 30,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 250,
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: MiuixButton(colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      onPressed: () {
                        logic.change();
                      },
                      child: Text("重试".tl),
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Expanded(
                      child: MiuixButton(colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    onPressed: () {
                      if (!readingData.hasEp) {
                        showToast(message: "没有其它章节".tl);
                        return;
                      }
                      if (MediaQuery.of(context).size.width > 600) {
                        showSideBar(
                          context,
                          buildEpsView(),
                          title: null,
                          useSurfaceTintColor: true,
                          addTopPadding: true,
                          width: 400,
                        );
                      } else {
                        showMiuixBottomSheet<void>(
                          context: context,
                          builder: (context, close) => SizedBox(height: MediaQuery.of(context).size.height * 9 / 16, child: Material(type: MaterialType.transparency, child:  buildEpsView())),
                        );
                      }
                    },
                    child: Text("切换章节".tl),
                  )),
                ],
              ),
            ),
          ),
        ),
      ],
    ));
  }

  void loadInfo(ComicReadingPageLogic logic) async {
    // build() 在加载中可能被多次调用（任何 update() 都会重建），避免同一章节重复请求
    if (logic.loadingOrder == logic.order) return;
    final order = logic.order;
    history?.readEpisode.add(order);
    logic.loadingOrder = order;
    logic.urls = [];
    var res = await readingData.loadEp(order);
    if (logic.loadingOrder == order) {
      logic.loadingOrder = null;
    }
    // 已离开阅读器或已切换章节：丢弃过期结果
    if (StateController.findOrNull<ComicReadingPageLogic>() != logic ||
        logic.order != order) {
      return;
    }
    if (res.error) {
      logic.errorMessage = res.errorMessage;
    } else {
      logic.urls = res.data;
    }
    logic.isLoading = false;
    logic.update();
  }

  Widget buildEpsView() {
    return EpsView(readingData);
  }

  void openEpsDrawer() {
    var context = App.globalContext!;
    if (MediaQuery.of(context).size.width > 600) {
      showSideBar(
        context,
        buildEpsView(),
        title: null,
        useSurfaceTintColor: true,
        width: 400,
        addTopPadding: true,
      );
    } else {
      showMiuixBottomSheet<void>(
        context: context,
        builder: (context, close) => SizedBox(height: MediaQuery.of(context).size.height * 9 / 16, child: Material(type: MaterialType.transparency, child:  buildEpsView())),
      );
    }
  }

  /// Used when [ComicReadingPageLogic.readingMethod] is [ReadingMethod.topToBottomContinuously].
  ///
  /// Select a image form screen, to share or download
  /// 连续滚动时从屏幕上选一页。
  /// [forFavorite] 为 true 时标题用 P 数，并在已收藏页后显示胶囊标记。
  Future<int?> selectImage({bool forFavorite = false}) async {
    var logic = StateController.find<ComicReadingPageLogic>();
    var items = logic.itemScrollListener.itemPositions.value.toList();
    if (items.length == 1) {
      return items[0].index;
    }
    final comicId = "${logic.data.sourceKey}-${logic.data.id}";
    final ep = logic.order;
    final favored = forFavorite
        ? ImageFavoriteManager.favoritedPages(comicId, ep)
        : const <int>{};
    int? res;
    await showMiuixDialog<void>(
        context: App.globalContext!,
        title: "选择屏幕上的图片".tl,
        contentBuilder: (context, close) {
          final primary = Theme.of(context).colorScheme.primary;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var item in items)
                  MiuixArrowPreference(
                    title: "P${item.index + 1}",
                    endActions: forFavorite && favored.contains(item.index + 1)
                        ? [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: ShapeDecoration(
                                color: primary.withOpacity(0.14),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                "已收藏".tl,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: primary,
                                ),
                              ),
                            ),
                          ]
                        : null,
                    onClick: () {
                      res = item.index;
                      close();
                    },
                  )
              ],
            ),
          );
        });
    return res;
  }

  String getImageKey(int index) {
    var logic = StateController.find<ComicReadingPageLogic>();
    if (type == ComicType.ehentai) {
      return "${readingData.id}${index + 1}";
    }
    return type == ReadingType.hitomi
        ? (readingData as HitomiReadingData).images[index].hash
        : logic.urls[index];
  }

  Future<File> _getFileFromStream(Stream<DownloadProgress> stream) async {
    await for (var event in stream) {
      if (event.finished) {
        return event.getFile();
      }
    }
    throw "failed";
  }

  void share() async {
    try {
      var logic = StateController.find<ComicReadingPageLogic>();
      int? index = logic.index - 1;
      if (logic.readingMethod == ReadingMethod.topToBottomContinuously) {
        index = await selectImage();
      }
      if (index == null) {
        return;
      }

      var file = await _getFileFromStream(
          readingData.loadImage(logic.order, index, logic.urls[index]));

      await shareImage(file);
    } catch (e) {
      showToast(message: e.toString());
    }
  }


  void saveCurrentImage() async {
    try {
      var logic = StateController.find<ComicReadingPageLogic>();
      int? index = logic.index - 1;
      if (logic.readingMethod == ReadingMethod.topToBottomContinuously) {
        index = await selectImage();
      }
      if (index == null) {
        return;
      }

      var file = await _getFileFromStream(
          readingData.loadImage(logic.order, index, logic.urls[index]));

      await saveImage(file);
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  Widget? buildEpChangeButton(ComicReadingPageLogic logic) {
    if (!readingData.hasEp) return null;
    switch (logic.showFloatingButtonValue) {
      case -1:
        return MiuixFloatingActionButton(
          onPressed: () => logic.jumpToLastChapter(),
          child: const Icon(Icons.arrow_back_ios_outlined),
        );
      case 0:
        return null;
      case 1:
        return Hero(
            tag: "FAB",
            child: StateBuilder<ComicReadingPageLogic>(
              id: "FAB",
              builder: (logic) {
                return Container(
                  width: 58,
                  height: 58,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: Theme.of(App.globalContext!)
                          .colorScheme
                          .primaryContainer,
                      borderRadius: BorderRadius.circular(16)),
                  child: Stack(
                    children: [
                      Positioned.fill(child: MiuixPressable(feedbackType: MiuixPressFeedbackType.sink, borderRadius: BorderRadius.circular(16), onPressed: () => logic.jumpToNextChapter(), child: Center(
                              child: Icon(
                            Icons.arrow_forward_ios,
                            size: 24,
                            color: Theme.of(App.globalContext!)
                                .colorScheme
                                .onPrimaryContainer,
                          )))),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: logic.fABValue,
                        child: ColoredBox(
                          color: Theme.of(App.globalContext!)
                              .colorScheme
                              .surfaceTint
                              .withOpacity(0.2),
                          child: const SizedBox.expand(),
                        ),
                      )
                    ],
                  ),
                );
              },
            ));
    }
    return null;
  }
}
