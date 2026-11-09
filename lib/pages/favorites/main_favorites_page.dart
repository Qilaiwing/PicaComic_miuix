import "dart:async";

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:sliver_tools/sliver_tools.dart";
import "package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart";
import "package:pica_comic/base.dart";
import "package:pica_comic/comic_source/comic_source.dart";
import 'package:pica_comic/components/components.dart';
import "package:pica_comic/foundation/app.dart";
import "package:pica_comic/foundation/local_favorites.dart";
import "package:pica_comic/foundation/log.dart";
import "package:pica_comic/network/download.dart";
import "package:pica_comic/tools/translations.dart";

import "../../network/net_fav_to_local.dart";
import "../../tools/io_tools.dart";
import "local_favorites.dart";
import "local_search_page.dart";
import "network_favorite_page.dart";

class FavoritesPageController extends StateController {
  String? current;

  bool? isNetwork;

  bool selectingFolder = true;

  FavoriteData? networkData;

  var selectedComics = <FavoriteItem>[];

  var openComicMenuFuncs = <FavoriteItem, Function>{};

  bool get isSelectingComics => selectedComics.isNotEmpty;

  FavoritesPageController() {
    var data = appdata.implicitData[0].split(";");
    selectingFolder = data[0] == "1";
    if (data[1] == "") {
      isNetwork = null;
    } else {
      isNetwork = data[1] == "1";
    }
    if (data.length > 3) {
      current = data.sublist(2).join(";");
    } else {
      current = data[2];
    }
    if (current == "") {
      current = null;
    }
    if (isNetwork ?? false) {
      final folders =
          appdata.settings[68].split(',').map((e) => getFavoriteDataOrNull(e));
      networkData =
          folders.firstWhereOrNull((element) => element?.title == current);
      if (networkData == null) {
        current = null;
        selectingFolder = true;
        isNetwork = null;
      }
    }
  }

  @override
  void update([List<Object>? ids]) {
    if (selectedComics.isEmpty) {
      openComicMenuFuncs.clear();
    }
    super.update(ids);
  }
}

const _kSecondaryTopBarHeight = 38.0;

class FavoritesPage extends StatelessWidget with _LocalFavoritesManager {
  FavoritesPage({super.key});

  final controller = StateController.putIfNotExists<FavoritesPageController>(
      FavoritesPageController());

  @override
  Widget build(BuildContext context) {
    return StateBuilder<FavoritesPageController>(builder: (controller) {
      final isViewingFolder = !controller.selectingFolder && controller.current != null;
      final canPop = !isViewingFolder && !controller.isSelectingComics;
      return PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (controller.isSelectingComics) {
            controller.selectedComics.clear();
            controller.update();
            return;
          }
          if (!controller.selectingFolder) {
            controller.selectingFolder = true;
            controller.update();
            appdata.implicitData[0] = "1;;";
            appdata.writeImplicitData();
            return;
          }
        },
        child: buildPage(context),
      );
    });
  }

  Widget buildPage(BuildContext context) {
    final isViewingComics = !controller.selectingFolder && controller.current != null;

    return Stack(
      children: [
        Positioned.fill(
          // Instant swap: AnimatedSwitcher cross-fade stacked folder list
          // and comic grid for 200ms and looked like a flash when going back.
          child: isViewingComics
                ? KeyedSubtree(
                    key: ValueKey('content_${controller.current}'),
                    child: buildContent(context),
                  )
                : KeyedSubtree(
                    key: const ValueKey('folders_list'),
                    child: buildFoldersList(context),
                  ),
        ),
        if (controller.isSelectingComics)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: buildTopBar(context),
          ),
      ],
    );
  }

  void multiSelectedMenu() async {
    final size = MediaQuery.of(App.globalContext!).size;
    final actions = <String, VoidCallback>{
      "删除".tl: () {
        for (var comic in controller.selectedComics) {
          LocalFavoritesManager().deleteComic(controller.current!, comic);
        }
        controller.selectedComics.clear();
        controller.update();
      },
      "复制到".tl: () {
        Future.delayed(
          const Duration(milliseconds: 200),
          () => copyAllTo(controller.current!, controller.selectedComics),
        );
      },
      "下载".tl: () {
        Future.delayed(
          const Duration(milliseconds: 200),
          () {
            var comics = controller.selectedComics;
            for (var comic in comics) {
              DownloadManager().addFavoriteDownload(comic);
            }
            showToast(message: "已添加下载任务".tl);
          },
        );
      },
      "更新漫画信息".tl: () {
        Future.delayed(
          const Duration(milliseconds: 200),
          () {
            var comics = controller.selectedComics;
            UpdateFavoritesInfoDialog.show(comics, controller.current!);
          },
        );
      },
    };
    final i = await showMiuixMenu(
      context: App.globalContext!,
      anchorBounds: Rect.fromLTWH(size.width, 0, 0, 0),
      alignment: MiuixPopupAlign.end,
      items: actions.keys.toList(),
    );
    if (i != null) actions.values.elementAt(i)();
  }


  Widget buildTopBar(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (controller.isSelectingComics) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Container(
          height: _kSecondaryTopBarHeight,
          decoration: ShapeDecoration(
            shape: MiuixSquircleBorder(
              cornerRadius: 16,
              side: BorderSide(
                color: isDark ? const Color(0x18FFFFFF) : const Color(0x0A000000),
                width: 0.6,
              ),
            ),
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            shadows: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
              height: _kSecondaryTopBarHeight,
              child: Row(children: [
                Icon(
                  Icons.rule_folder,
                  color: iconColor,
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  "已选择 @num 个项目".tlParams(
                      {"num": controller.selectedComics.length.toString()}),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ).paddingBottom(3),
                const Spacer(),
                MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("全选".tl)),
 child: MiuixIconButton(
                    child: MiuixIcon(
                      vector: MiuixIcons.extended.byName('selectAll') ??
                          MiuixIcons.basic.check,
                      size: 20,
                    ),
                    onPressed: () {
                      controller.selectedComics = LocalFavoritesManager()
                          .getAllComics(controller.current!)
                          .toList();
                      controller.update();
                    },
                  ),
),
                MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("取消".tl)),
 child: MiuixIconButton(
                    child: MiuixIcon(
                      vector: MiuixIcons.basic.close,
                      size: 20,
                    ),
                    onPressed: () {
                      controller.selectedComics.clear();
                      controller.update();
                    },
                  ),
),
                MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("菜单".tl)),
 child: MiuixIconButton(
                    child: MiuixIcon(
                      vector: MiuixIcons.os4.more,
                      size: 20,
                    ),
                    onPressed: () {
                      if (controller.selectedComics.length == 1) {
                        controller.openComicMenuFuncs[controller.selectedComics[0]]
                            ?.call();
                      } else {
                        multiSelectedMenu();
                      }
                    },
                  ),
),
              ]).paddingHorizontal(16),
            ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Container(
        height: _kSecondaryTopBarHeight,
        decoration: ShapeDecoration(
          shape: MiuixSquircleBorder(
            cornerRadius: 12,
            side: BorderSide(
              color: isDark ? const Color(0x18FFFFFF) : const Color(0x0A000000),
              width: 0.6,
            ),
          ),
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shadows: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: MiuixPressable(
 onPressed: () {
              if (controller.selectingFolder) {
                if (controller.current == null) {
                  showToast(message: "选择收藏夹".tl);
                  return;
                }
                controller.selectingFolder = false;
                controller.update();
              } else {
                controller.selectingFolder = true;
                controller.update();
                appdata.implicitData[0] = "1;;";
                appdata.writeImplicitData();
              }
            },
 feedbackType: MiuixPressFeedbackType.sink,
 shape: const MiuixSquircleBorder(cornerRadius: 12),
 child: SizedBox(
              height: _kSecondaryTopBarHeight,
              child: Row(children: [
                MiuixIcon(
                  vector: controller.isNetwork == true
                      ? (MiuixIcons.extended.byName('favoriteFolder') ?? MiuixIcons.os4.folder)
                      : MiuixIcons.os4.folder,
                  tint: iconColor,
                  size: 17,
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  controller.selectingFolder
                      ? (controller.current != null ? controller.current!.tl : "所有收藏夹".tl)
                      : (controller.current != null ? controller.current!.tl : "未选择".tl),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ).paddingBottom(2),
                const Spacer(),
                if (controller.selectingFolder)
                  const Icon(Icons.keyboard_arrow_up, size: 18)
                else
                  MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("切换收藏夹".tl)),
 child: const Icon(Icons.unfold_more, size: 18),
),
              ]).paddingHorizontal(14),
            ),
),
      ),
    );
  }

  Widget buildFoldersList(BuildContext context) {
    // 漫画源开关变化时即时刷新网络收藏
    return ValueListenableBuilder<int>(
      valueListenable: ComicSource.sourcesChanged,
      builder: (context, _, __) => _buildFoldersList(context),
    );
  }

  Widget _buildFoldersList(BuildContext context) {
    var networkFolders = appdata.appSettings.networkFavorites
        .map((e) => getFavoriteDataOrNull(e))
        .whereType<FavoriteData>();
    final hasNetwork = networkFolders.isNotEmpty;

    return SmoothCustomScrollView(
        slivers: [
          const TopInsetSliver(),
          if (hasNetwork)
            MultiSliver(pushPinnedChildren: true, children: [
              StickySectionHeader(title: "网络".tl),
              buildNetwork().sliverPaddingHorizontal(14),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: MiuixHorizontalDivider(thickness: 0.6),
                ),
              ),
            ]),
          MultiSliver(pushPinnedChildren: true, children: [
            StickySectionHeader(title: "本地".tl),
            buildUtils(context),
            buildLocal().sliverPaddingHorizontal(14),
          ]),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      );
  }

  Widget buildTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Theme.of(App.globalContext!).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget buildNetwork() {
    var folders = appdata.appSettings.networkFavorites
        .map((e) => getFavoriteDataOrNull(e));
    folders = folders.whereType<FavoriteData>();
    final isDark = Theme.of(App.globalContext!).brightness == Brightness.dark;
    final primary = Theme.of(App.globalContext!).colorScheme.primary;

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedHeight(
        maxCrossAxisExtent: 240,
        itemHeight: 56,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final data = folders.elementAt(index);
        return Padding(
          padding: const EdgeInsets.all(3.5),
          child: MiuixPressable(
 onPressed: () {
                controller.current = data?.title;
                controller.isNetwork = true;
                controller.selectingFolder = false;
                controller.networkData = data;
                controller.update();
                appdata.implicitData[0] = "0;1;${data?.title ?? ""}";
                appdata.writeImplicitData();
              },
 feedbackType: MiuixPressFeedbackType.sink,
 shape: const MiuixSquircleBorder(cornerRadius: 14),
 child: Container(
                decoration: ShapeDecoration(
                  shape: MiuixSquircleBorder(
                    cornerRadius: 14,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0x0A000000),
                      width: 0.6,
                    ),
                  ),
                  color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: const MiuixSquircleBorder(cornerRadius: 10),
                        color: primary.withOpacity(isDark ? 0.20 : 0.10),
                      ),
                      child: MiuixIcon(
                        vector: MiuixIcons.os4.folder,
                        tint: primary,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data?.title != null ? data!.title.tl : "未知".tl,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
),
        );
      }, childCount: folders.length),
    );
  }

  Widget buildLocal() {
    final folders = LocalFavoritesManager().folderNames;
    final isDark = Theme.of(App.globalContext!).brightness == Brightness.dark;
    final primary = Theme.of(App.globalContext!).colorScheme.primary;

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedHeight(
        maxCrossAxisExtent: 260,
        itemHeight: 56,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final data = folders.elementAt(index);
        return Padding(
          padding: const EdgeInsets.all(3.5),
          child: GestureDetector(
            onLongPressStart: (details) =>
                _showMenu(data, details.globalPosition),
            onSecondaryTapUp: (details) =>
                _showDesktopMenu(data, details.globalPosition),
            child: MiuixPressable(
 onPressed: () {
                  controller.current = data;
                  controller.isNetwork = false;
                  controller.selectingFolder = false;
                  controller.update();
                  appdata.implicitData[0] = "0;0;$data";
                  appdata.writeImplicitData();
                },
 feedbackType: MiuixPressFeedbackType.sink,
 shape: const MiuixSquircleBorder(cornerRadius: 14),
 child: Container(
                  decoration: ShapeDecoration(
                    shape: MiuixSquircleBorder(
                      cornerRadius: 14,
                      side: BorderSide(
                        color: isDark
                            ? const Color(0x18FFFFFF)
                            : const Color(0x0A000000),
                        width: 0.6,
                      ),
                    ),
                    color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          shape: const MiuixSquircleBorder(cornerRadius: 10),
                          color: primary.withOpacity(isDark ? 0.20 : 0.10),
                        ),
                        child: MiuixIcon(
                          vector: MiuixIcons.os4.folder,
                          tint: primary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          data,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: ShapeDecoration(
                          shape: const StadiumBorder(),
                          color: primary.withOpacity(isDark ? 0.22 : 0.12),
                        ),
                        child: Text(
                          LocalFavoritesManager().count(data).toString(),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
),
          ),
        );
      }, childCount: folders.length),
    );
  }

  Widget buildUtils(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    Widget buildItem(String title, dynamic icon, VoidCallback onTap) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: MiuixPressable(
 onPressed: onTap,
 feedbackType: MiuixPressFeedbackType.sink,
 shape: const MiuixSquircleBorder(cornerRadius: 14),
 child: Container(
                height: 44,
                decoration: ShapeDecoration(
                  shape: MiuixSquircleBorder(
                    cornerRadius: 14,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0x0A000000),
                      width: 0.6,
                    ),
                  ),
                  color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon is MiuixVectorIcon)
                      MiuixIcon(vector: icon, size: 18, tint: primary)
                    else
                      Icon(icon as IconData, size: 18, color: primary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        child: Row(
          children: [
            buildItem("新建".tl,
                MiuixIcons.extended.byName('addFolder') ?? MiuixIcons.os4.folder,
                () {
              CreateFolderDialog.show(context)
                  .then((value) => controller.update());
            }),
            buildItem("搜索".tl, MiuixIcons.os4.search,
                () => App.to(context, () => const LocalSearchPage())),
            buildItem("排序".tl, MiuixIcons.basic.arrowUpDown, () {
              context.to(() => const _FoldersReorderPage());
            }),
          ],
        ),
      ),
    );
  }

  Widget buildContent(BuildContext context) {
    if (controller.current == null) {
      return const SizedBox();
    } else if (controller.isNetwork!) {
      // ComicsPage / multi-folder list apply MainTopInset themselves; wrapping
      // again here doubles the gap under the top bar (esp. PicACG flat list).
      return NetworkFavoritePage(
        controller.networkData!,
        key: Key(controller.current ?? ""),
      );
    } else {
      var count = LocalFavoritesManager().count(controller.current!);
      return ComicsPageView(
        key: Key(controller.current! + count.toString()),
        folder: controller.current!,
        selectedComics: controller.selectedComics,
        onClick: (key) {
          if (controller.isSelectingComics) {
            if (controller.selectedComics.contains(key)) {
              controller.selectedComics.remove(key);
            } else {
              controller.selectedComics.add(key);
            }
            controller.update();
            return true;
          }
          return false;
        },
        onLongPressed: (key) {
          if (controller.selectedComics.contains(key)) {
            controller.selectedComics.remove(key);
          } else {
            controller.selectedComics.add(key);
          }
          controller.update();
        },
      );
    }
  }

  void _showMenu(String folder, Offset location) async {
    // 与原 showMenu 一致：菜单先关闭，再执行对应操作（原 onTap 中的 App.globalBack 保留）
    final actions = <String, VoidCallback>{
      "删除".tl: () {
        App.globalBack();
        deleteFolder(folder);
      },
      "排序".tl: () {
        App.globalBack();
        App.globalTo(() => LocalFavoritesFolder(folder))
            .then((value) => controller.update());
      },
      "重命名".tl: () {
        App.globalBack();
        rename(folder);
      },
      "检查漫画存活".tl: () {
        App.globalBack();
        checkFolder(folder).then((value) {
          controller.update();
        });
      },
      "导出".tl: () {
        App.globalBack();
        export(folder);
      },
      "下载全部".tl: () {
        App.globalBack();
        addDownload(folder);
      },
      "更新漫画信息".tl: () {
        App.globalBack();
        var comics = LocalFavoritesManager().getAllComics(folder);
        UpdateFavoritesInfoDialog.show(comics, folder);
      },
    };
    final i = await showMiuixMenu(
      context: App.globalContext!,
      anchorBounds: Rect.fromLTWH(location.dx, location.dy, 0, 0),
      items: actions.keys.toList(),
    );
    if (i != null) actions.values.elementAt(i)();
  }

  void _showDesktopMenu(String folder, Offset location) {
    showDesktopMenu(App.globalContext!, location, [
      DesktopMenuEntry(
          text: "删除".tl,
          onClick: () {
            deleteFolder(folder);
          }),
      DesktopMenuEntry(
          text: "排序".tl,
          onClick: () {
            App.globalTo(() => LocalFavoritesFolder(folder))
                .then((value) => controller.update());
          }),
      DesktopMenuEntry(
          text: "重命名".tl,
          onClick: () {
            rename(folder);
          }),
      DesktopMenuEntry(
          text: "检查漫画存活".tl,
          onClick: () {
            checkFolder(folder).then((value) {
              controller.update();
            });
          }),
      DesktopMenuEntry(
          text: "导出".tl,
          onClick: () {
            export(folder);
          }),
      DesktopMenuEntry(
          text: "下载全部".tl,
          onClick: () {
            addDownload(folder);
          }),
      DesktopMenuEntry(
          text: "更新漫画信息".tl,
          onClick: () {
            var comics = LocalFavoritesManager().getAllComics(folder);
            UpdateFavoritesInfoDialog.show(comics, folder);
          }),
    ]);
  }
}

mixin class _LocalFavoritesManager {
  void deleteFolder(String folder) {
    showConfirmDialog(App.globalContext!, "确认删除".tl, "此操作无法撤销, 是否继续?".tl, () {
      App.globalBack();
      LocalFavoritesManager().deleteFolder(folder);
      final controller = StateController.find<FavoritesPageController>();
      if (controller.current == folder && !controller.isNetwork!) {
        controller.current = null;
        controller.isNetwork = null;
      }
      controller.update();
    });
  }

  void rename(String folder) async {
    await RenameFolderDialog.show(App.globalContext!, folder);
    StateController.find<FavoritesPageController>().update();
  }

  void export(String folder) async {
    var controller = showLoadingDialog(
      App.globalContext!,
      onCancel: () {},
      message: "正在导出".tl,
    );
    try {
      await exportStringDataAsFile(
          LocalFavoritesManager().folderToJsonString(folder), "$folder.json");
      controller.close();
    } catch (e, s) {
      controller.close();
      showToast(message: e.toString());
      log("$e\n$s", "IO", LogLevel.error);
    }
  }

  void addDownload(String folder) {
    for (var comic in LocalFavoritesManager().getAllComics(folder)) {
      comic.addDownload();
    }
    showToast(message: "已添加下载任务".tl);
  }
}

class ComicsPageView extends StatefulWidget {
  const ComicsPageView(
      {required this.folder,
      required this.onClick,
      required this.selectedComics,
      required this.onLongPressed,
      super.key});

  final String folder;

  /// return true to disable default action
  final bool Function(FavoriteItem item) onClick;

  final void Function(FavoriteItem item) onLongPressed;

  final List<FavoriteItem> selectedComics;

  @override
  State<ComicsPageView> createState() => _ComicsPageViewState();
}

class _ComicsPageViewState extends StateWithController<ComicsPageView> {
  late ScrollController scrollController;
  bool showFB = true;
  double location = 0;

  String get folder => widget.folder;

  FolderSync? folderSync() {
    final folderSyncArr = LocalFavoritesManager()
        .folderSync
        .where((element) => element.folderName == folder)
        .toList();
    if (folderSyncArr.isEmpty) return null;
    return folderSyncArr[0];
  }

  late List<FavoriteItem> comics;

  @override
  void initState() {
    scrollController = ScrollController();
    scrollController.addListener(() {
      var current = scrollController.offset;

      if ((current > location && current != 0) && showFB) {
        setState(() {
          showFB = false;
        });
      } else if ((current < location || current == 0) && !showFB) {
        setState(() {
          showFB = true;
        });
      }

      location = current;
    });
    comics = LocalFavoritesManager().getAllComics(folder);
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildFolderComics(folder);
  }

  void rebuild() {
    setState(() {
      comics = LocalFavoritesManager().getAllComics(folder);
    });
  }

  bool _isPullRefreshing = false;

  /// Miuix pull-to-refresh, enabled only when folder sync exists.
  Widget _wrapPullToRefresh(Widget child) {
    if (folderSync() == null) {
      return child;
    }
    return MiuixPullToRefresh(
      isRefreshing: _isPullRefreshing,
      onRefresh: () {
        setState(() => _isPullRefreshing = true);
        onRefresh(context).whenComplete(() {
          if (mounted) {
            setState(() => _isPullRefreshing = false);
          }
        });
      },
      child: child,
    );
  }

  Future<void> onRefresh(context) async {
    return startFolderSync(context, folderSync()!);
  }

  Widget buildFolderComics(String folder) {
    if (comics.isEmpty) {
      return TopInsetPadding(child: buildEmptyView());
    }

    return MiuixScaffold(
 floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        reverseDuration: const Duration(milliseconds: 150),
        child: showFB && folderSync() != null ? buildFAB() : const SizedBox(),
        transitionBuilder: (widget, animation) {
          var tween =
              Tween<Offset>(begin: const Offset(0, 1), end: const Offset(0, 0));
          return SlideTransition(
            position: tween.animate(animation),
            child: widget,
          );
        },
      ),
 content: (_) => MediaQuery.removePadding(
        key: Key(folder),
        removeTop: true,
        context: context,
        child: _wrapPullToRefresh(Stack(
            children: [
              ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(scrollbars: false),
                child: SmoothScrollProvider(
                  controller: scrollController,
                  builder: (context, controller, physic) {
                    return GridView.builder(
                      key: Key(folder),
                      primary: false,
                      controller: controller,
                      gridDelegate: SliverGridDelegateWithComics(),
                      itemCount: comics.length,
                      padding: EdgeInsets.fromLTRB(0, 16 + MainTopInset.of(context), 0, 100),
                      physics: physic,
                      itemBuilder: (BuildContext context, int index) {
                        var comic = comics[index];
                        var tile = LocalFavoriteTile(
                          key: ValueKey(comic.toString()),
                          comic,
                          folder,
                          () {
                            rebuild();
                            if(widget.selectedComics.contains(comic)) {
                              var c = StateController.find<FavoritesPageController>();
                              c.selectedComics.remove(comic);
                              c.update();
                            }
                          },
                          true,
                          onTap: () => widget.onClick(comic),
                          onLongPressed: () => widget.onLongPressed(comic),
                          showFolderInfo: true,
                        );
                        StateController.find<FavoritesPageController>()
                            .openComicMenuFuncs[comic] = tile.showMenu;

                        Color? color;

                        if (widget.selectedComics.contains(comic)) {
                          color = Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest;
                        }
                        return AnimatedContainer(
                          decoration: ShapeDecoration(
                            color: color,
                            shape: const MiuixSquircleBorder(cornerRadius: 14),
                          ),
                          margin: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 4),
                          duration: const Duration(milliseconds: 160),
                          child: tile,
                        );
                      },
                    );
                  },
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: MiuixVerticalScrollBar(
                  adapter: MiuixScrollBarAdapter(scrollController),
                ),
              ),
            ],
          ),
        ),
      ),
);
  }

  Widget buildFAB() => MiuixFloatingActionButton(
        key: const Key("FAB"),
        onPressed: () => onRefresh(context),
        child: MiuixIcon(
          vector: MiuixIcons.os4.refresh,
          size: 22,
        ),
      );

  Widget buildEmptyView() {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("这里什么都没有".tl),
          const SizedBox(
            height: 8,
          ),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '前往'.tl,
                ),
                TextSpan(
                  text: '探索页面'.tl,
                ),
                TextSpan(
                  text: '寻找漫画'.tl,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Object? get tag => "ComicsPageView $folder";

  @override
  refresh() {
    comics = LocalFavoritesManager().getAllComics(folder);
    update();
  }
}

class _FoldersReorderPage extends StatefulWidget {
  const _FoldersReorderPage();

  @override
  State<_FoldersReorderPage> createState() => _FoldersReorderPageState();
}

class _FoldersReorderPageState extends State<_FoldersReorderPage> {
  var folders = LocalFavoritesManager().folderNames;
  var changed = false;

  final reorderKey = UniqueKey();
  final _scrollController = ScrollController();
  final _key = GlobalKey();

  Color lightenColor(Color color, double lightenValue) {
    int red = (color.red + ((255 - color.red) * lightenValue)).round();
    int green = (color.green + ((255 - color.green) * lightenValue)).round();
    int blue = (color.blue + ((255 - color.blue) * lightenValue)).round();

    return Color.fromARGB(color.alpha, red, green, blue);
  }

  @override
  void dispose() {
    if (changed) {
      LocalFavoritesManager().updateOrder(Map<String, int>.fromEntries(
          folders.mapIndexed((index, element) => MapEntry(element, index))));
      scheduleMicrotask(() {
        StateController.find<FavoritesPageController>().update();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var tiles = List.generate(
        folders.length,
        (index) => MouseRegion(
              key: ValueKey(folders[index]),
              cursor: SystemMouseCursors.click,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(
                    Icons.folder,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folders[index],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ));

    return MiuixScaffold(
 topBar: MiuixSmallTopAppBar(color: MiuixTheme.of(context).colors.background, 
 title: "排序".tl,
 navigationIcon: Navigator.of(context).canPop() ? MiuixIconButton(onPressed: () => Navigator.of(context).maybePop(), child: const Icon(Icons.arrow_back)) : null,
),
 content: (padding) => ScrollUnderBar(
 padding: padding,
 child: Column(
        children: [
          Expanded(
            child: ReorderableBuilder(
              key: reorderKey,
              scrollController: _scrollController,
              longPressDelay: App.isDesktop
                  ? const Duration(milliseconds: 100)
                  : const Duration(milliseconds: 500),
              onReorder: (reorderFunc) {
                changed = true;
                setState(() {
                  folders = reorderFunc(folders) as List<String>;
                });
              },
              dragChildBoxDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: lightenColor(
                      Theme.of(context).splashColor.withOpacity(1), 0.2)),
              builder: (children) {
                return GridView(
                  key: _key,
                  controller: _scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedHeight(
                    maxCrossAxisExtent: 260,
                    itemHeight: 56,
                  ),
                  children: children,
                );
              },
              children: tiles,
            ),
          )
        ],
      ),
 ),
);
  }
}
