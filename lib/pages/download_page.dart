import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/custom_download_model.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/tools/pdf.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/pages/downloading_page.dart';
import 'package:pica_comic/pages/ehentai/eh_gallery_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_comic_page.dart';
import 'package:pica_comic/pages/jm/jm_comic_page.dart';
import 'package:pica_comic/pages/nhentai/comic_page.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'dart:io';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

import 'htmanga/ht_comic_page.dart';

extension ReadComic on DownloadedItem {
  void read({int? ep}) async {
    final comic = this;
    if (comic.type == DownloadType.picacg) {
      var history =
          await History.findOrCreate((comic as DownloadedComic).comicItem);
      App.globalTo(
        () => ComicReadingPage.picacg(
          comic.id,
          ep ?? history.ep,
          comic.eps,
          comic.name,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.ehentai) {
      var history =
          await History.findOrCreate((comic as DownloadedGallery).gallery);
      App.globalTo(
        () => ComicReadingPage.ehentai(
          (comic).gallery,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.jm) {
      var history =
          await History.findOrCreate((comic as DownloadedJmComic).comic);
      App.globalTo(
        () => ComicReadingPage.jmComic(
          comic.comic,
          ep ?? history.ep,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.hitomi) {
      var history =
          await History.findOrCreate((comic as DownloadedHitomiComic).comic);
      App.globalTo(
        () => ComicReadingPage.hitomi(
          comic.comic,
          comic.link,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.htmanga) {
      var history =
          await History.findOrCreate((comic as DownloadedHtComic).comic);
      App.globalTo(
        () => ComicReadingPage.htmanga(
          comic.comic.id,
          comic.comic.title,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.nhentai) {
      var nc = NhentaiComic(
          comic.id.replaceFirst("nhentai", ""),
          comic.name,
          comic.subTitle,
          (comic as NhentaiDownloadedComic).cover,
          {},
          false,
          [],
          [],
          "");
      var history = await History.findOrCreate(nc);
      App.globalTo(
        () => ComicReadingPage.nhentai(
          comic.id.replaceFirst("nhentai", ""),
          comic.title,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.other) {
      comic as CustomDownloadedItem;
      var data = ComicInfoData(
        name,
        subTitle,
        comic.cover,
        null,
        {},
        null,
        null,
        null,
        0,
        null,
        comic.sourceKey,
        comic.id.replaceFirst("${comic.sourceKey}-", ""),
      );
      var history = await History.findOrCreate(data);
      App.globalTo(
        () => ComicReadingPage(
          CustomReadingData(
            data.target,
            data.title,
            ComicSource.find(comic.sourceKey),
            comic.chapters,
          ),
          ep == null ? history.page : 0,
          ep ?? history.ep,
        ),
      );
    }
  }
}

class DownloadPageLogic extends StateController {
  ///是否正在加载
  bool loading = true;

  ///是否处于选择状态
  bool selecting = false;

  ///已选择的数量
  int selectedNum = 0;

  ///已选择的漫画
  var selected = <bool>[];

  ///已下载的漫画
  var comics = <DownloadedItem>[];

  var baseComics = <DownloadedItem>[];

  bool searchMode = false;

  bool searchInit = false;

  /// 下载页搜索框焦点，仅 searchInit 时请求聚焦
  final FocusNode searchFocusNode = FocusNode();

  /// 下载页搜索框文本（唯一数据源）。
  final TextEditingController searchController = TextEditingController();

  String keyword = "";
  String keyword_ = "";

  void change() {
    loading = !loading;
    try {
      update();
    } catch (e) {
      //忽视
    }
  }

  void find() {
    if (keyword == keyword_) {
      return;
    }
    keyword_ = keyword;
    comics.clear();
    if (keyword == "") {
      comics.addAll(baseComics);
    } else {
      for (var element in baseComics) {
        if (element.name.toLowerCase().contains(keyword) ||
            element.subTitle.toLowerCase().contains(keyword)) {
          comics.add(element);
        }
      }
    }
    resetSelected(comics.length);
  }

  @override
  void refresh() {
    searchMode = false;
    selecting = false;
    selectedNum = 0;
    selected.clear();
    comics.clear();
    change();
  }

  void resetSelected(int length) {
    selected = List.generate(length, (index) => false);
    selectedNum = 0;
  }
}

class DownloadPage extends StatelessWidget {
  const DownloadPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StateBuilder<DownloadPageLogic>(
        init: DownloadPageLogic(),
        builder: (logic) {
          if (logic.loading) {
            Future.wait([
              getComics(logic),
              Future.delayed(const Duration(milliseconds: 300))
            ]).then((v) {
              logic.resetSelected(logic.comics.length);
              logic.change();
            });
            return MiuixScaffold(
 content: (_) => Center(
                child: MiuixCircularProgressIndicator(),
              ),
);
          } else {
            return MiuixScaffold(
              floatingActionButton: buildFAB(context, logic),
              content: (_) => SmoothCustomScrollView(
                slivers: [
                  buildAppbar(context, logic),
                  buildComics(context, logic),
                  SliverPadding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 16),
                  ),
                ],
              ),
            );
          }
        });
  }

  Widget buildComics(BuildContext context, DownloadPageLogic logic) {
    logic.find();
    final comics = logic.comics;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(childCount: comics.length,
          (context, index) {
        return buildItem(context, logic, index);
      }),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }

  Future<void> getComics(DownloadPageLogic logic) async {
    var order = '', direction = 'desc';
    switch (appdata.settings[26][0]) {
      case "0":
        order = 'time';
      case "1":
        order = 'title';
      case "2":
        order = 'subtitle';
      case "3":
        order = 'size';
      default:
        throw UnimplementedError();
    }
    if (appdata.settings[26][1] == "1") {
      direction = 'asc';
    }
    logic.comics = DownloadManager().getAll(order, direction);
    logic.baseComics = logic.comics.toList();
  }

  Future<void> export(DownloadPageLogic logic) async {
    var comics = <DownloadedItem>[];
    for (int i = 0; i < logic.selected.length; i++) {
      if (logic.selected[i]) {
        comics.add(logic.comics[i]);
      }
    }
    if (comics.isEmpty) {
      return;
    }
    bool res;
    if (comics.length > 1) {
      res = await exportComics(comics);
    } else {
      res = await exportComic(
          comics.first.id, comics.first.name, comics.first.eps);
    }
    App.globalBack();
    if (!res) {
      showToast(message: "导出失败".tl);
    }
  }

  void downloadFont() async {
    bool canceled = false;
    var cancelToken = CancelToken();
    var controller = showLoadingDialog(
      App.globalContext!,
      onCancel: () {
        canceled = true;
        cancelToken.cancel();
      },
      barrierDismissible: false,
      allowCancel: true,
      message: "Downloading",
    );
    var dio = logDio();
    try {
      await dio.download(
        "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/fonts/NotoSansSC-Regular.ttf",
        "${App.dataPath}/font.ttf",
        cancelToken: cancelToken,
      );
    } catch (e) {
      showToast(message: "下载失败".tl);
      controller.close();
      return;
    }
    if (!canceled) {
      controller.close();
      showToast(message: "下载完成".tl);
    }
  }

  void exportAsPdf(DownloadedItem? comic, DownloadPageLogic logic) async {
    if (comic == null) {
      for (int i = 0; i < logic.selected.length; i++) {
        if (logic.selected[i]) {
          comic = logic.comics[i];
        }
      }
    }
    if (comic == null) {
      showToast(message: "请选择一个漫画".tl);
      return;
    }
    var file = File("${App.dataPath}/font.ttf");
    if (!App.isWindows && !await file.exists()) {
      showConfirmDialog(App.globalContext!, "缺少字体".tl,
          "需要下载字体文件(10.1MB), 是否继续?".tl, downloadFont);
    } else {
      bool canceled = false;
      var controller = showLoadingDialog(
        App.globalContext!,
        onCancel: () => canceled = true,
        allowCancel: false,
      );
      var fileName = "${comic.name}.pdf";
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      await createPdfFromComicWithIsolate(
          title: comic.name,
          comicPath: "${downloadManager.path}/${downloadManager.getDirectory(comic.id)}",
          savePath: "${App.cachePath}/$fileName",
          chapters: comic.eps,
          chapterIndexes: comic.downloadedEps);
      if (!canceled) {
        controller.close();
        await exportPdf("${App.cachePath}/$fileName");
      }
    }
  }

  Widget buildItem(BuildContext context, DownloadPageLogic logic, int index) {
    bool selected = logic.selected[index];
    var type = logic.comics[index].type.name;
    if (logic.comics[index].type == DownloadType.other) {
      type = (logic.comics[index] as CustomDownloadedItem).sourceName;
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(16))),
        child: DownloadedComicTile(
          name: logic.comics[index].name,
          author: logic.comics[index].subTitle,
          imagePath: downloadManager.getCover(logic.comics[index].id),
          type: type,
          tag: logic.comics[index].tags,
          onTap: () async {
            if (logic.selecting) {
              logic.selected[index] = !logic.selected[index];
              logic.selected[index] ? logic.selectedNum++ : logic.selectedNum--;
              if (logic.selectedNum == 0) {
                logic.selecting = false;
              }
              logic.update();
            } else {
              showInfo(index, logic, context);
            }
          },
          size: () {
            if (logic.comics[index].comicSize != null) {
              return logic.comics[index].comicSize!.toStringAsFixed(2);
            } else {
              return "未知大小".tl;
            }
          }.call(),
          onLongTap: () {
            if (logic.selecting) return;
            logic.selected[index] = true;
            logic.selectedNum++;
            logic.selecting = true;
            logic.update();
          },
          onSecondaryTap: (details) {
            showDesktopMenu(App.globalContext!,
                Offset(details.globalPosition.dx, details.globalPosition.dy), [
              DesktopMenuEntry(
                text: "阅读".tl,
                onClick: () {
                  logic.comics[index].read();
                },
              ),
              DesktopMenuEntry(
                text: "删除".tl,
                onClick: () {
                  showConfirmDialog(context, "确认删除".tl, "此操作无法撤销, 是否继续?".tl,
                      () {
                    downloadManager.delete([logic.comics[index].id]);
                    logic.comics.removeAt(index);
                    logic.selected.removeAt(index);
                    logic.update();
                  });
                },
              ),
              DesktopMenuEntry(
                text: "导出".tl,
                onClick: () =>
                    Future.delayed(const Duration(milliseconds: 200), () {
                  Future<void>.delayed(
                    const Duration(milliseconds: 200),
                    () => showMiuixDialog(
                      context: App.globalContext!,
                      dismissible: false,
                      contentBuilder: (context, close) => SizedBox(
                        width: 200,
                        height: 200,
                        child: Center(
                          child: SizedBox(
                            width: 50,
                            height: 80,
                            child: Column(
                              children: [
                                const SizedBox(
                                  height: 10,
                                ),
                                const MiuixCircularProgressIndicator(),
                                const SizedBox(
                                  height: 9,
                                ),
                                Text("打包中".tl)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  Future<void>.delayed(const Duration(milliseconds: 500),
                      () async {
                    var res = await exportComic(logic.comics[index].id,
                        logic.comics[index].name, logic.comics[index].eps);
                    App.globalBack();
                    if (res) {
                      //忽视
                    } else {
                      showToast(message: "导出失败".tl);
                    }
                  });
                }),
              ),
              DesktopMenuEntry(
                text: "导出为pdf".tl,
                onClick: () {
                  exportAsPdf(logic.comics[index], logic);
                },
              ),
              DesktopMenuEntry(
                text: "查看漫画详情".tl,
                onClick: () {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    toComicInfoPage(logic.comics[index]);
                  });
                },
              ),
              DesktopMenuEntry(
                text: "复制路径".tl,
                onClick: () {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    var path =
                        "${downloadManager.path}/${downloadManager.getDirectory(logic.comics[index].id)}";
                    Clipboard.setData(ClipboardData(text: path));
                  });
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  void toComicInfoPage(DownloadedItem comic) => _toComicInfoPage(comic);

  void showInfo(int index, DownloadPageLogic logic, BuildContext context) {
    if (UiMode.m1(context)) {
      showMiuixBottomSheet(
        context: context,
        builder: (context, close) {
          return DownloadedComicInfoView(logic.comics[index], logic,
              inMiuixSheet: true);
        },
      );
    } else {
      showSideBar(
        context,
        DownloadedComicInfoView(logic.comics[index], logic),
        useSurfaceTintColor: true,
      );
    }
  }

  Widget buildFAB(BuildContext context, DownloadPageLogic logic) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final isSelecting = logic.selecting;
    final hasSelection = logic.selectedNum > 0;

    return MiuixPressable(
 onPressed: () {
          if (!logic.selecting) {
            logic.selecting = true;
            logic.update();
          } else {
            if (logic.selectedNum == 0) return;
            showConfirmDialog(
              context,
              "删除".tl,
              "要删除已选择的 @num 个项目吗? 此操作无法撤销".tlParams({"num": logic.selectedNum.toString()}),
              () async {
                var comics = <String>[];
                for (int i = 0; i < logic.selected.length; i++) {
                  if (logic.selected[i]) {
                    comics.add(logic.comics[i].id);
                  }
                }
                await downloadManager.delete(comics);
                logic.refresh();
              },
            );
          }
        },
 feedbackType: MiuixPressFeedbackType.sink,
 child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: isSelecting ? 18 : 16),
          decoration: ShapeDecoration(
            shape: const MiuixSquircleBorder(cornerRadius: 18),
            color: isSelecting
                ? (hasSelection
                    ? const Color(0xFFE53935)
                    : (isDark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE)))
                : primary,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSelecting) ...[
                MiuixIcon(
                  vector: MiuixIcons.extended.byName('delete') ?? MiuixIcons.os4.close,
                  size: 19,
                  tint: hasSelection
                      ? Colors.white
                      : (isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F)),
                ),
                const SizedBox(width: 6),
                Text(
                  hasSelection
                      ? "删除 (@num)".tlParams({"num": logic.selectedNum.toString()})
                      : "删除".tl,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasSelection
                        ? Colors.white
                        : (isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F)),
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.checklist_rounded,
                  size: 21,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  "多选".tl,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
);
  }

  Widget buildTitle(BuildContext context, DownloadPageLogic logic) {
    if (logic.searchMode && !logic.selecting) {
      if (logic.searchInit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (logic.searchFocusNode.context != null) {
            logic.searchFocusNode.requestFocus();
          }
        });
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          // 直接用 logic.searchController 作为唯一数据源；清空等改动只发生在事件回调中，
          // 不会在构建期间改写输入框文本。
          child: AppSearchField(
            controller: logic.searchController,
            focusNode: logic.searchFocusNode,
            hint: "搜索已下载漫画".tl,
            autofocus: false,
            onSubmitted: (_) {},
            onChanged: (s) {
              logic.keyword = s.toLowerCase();
              logic.searchInit = false;
              logic.update();
            },
          ),
        ),
      );
    } else {
      return logic.selecting
          ? Text("已选择 @num 个项目".tlParams({"num": logic.selectedNum.toString()}))
          : Text("已下载".tl);
    }
  }

  Widget buildAppbar(BuildContext context, DownloadPageLogic logic) {
    final selecting = logic.selecting;
    final searching = logic.searchMode && !selecting;
    return SliverAppbar(
      color: selecting
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      leading: selecting
          ? MiuixIconButton(
              onPressed: () {
                logic.selecting = false;
                logic.selectedNum = 0;
                for (int i = 0; i < logic.selected.length; i++) {
                  logic.selected[i] = false;
                }
                logic.update();
              },
              child: MiuixIcon(
                vector: MiuixIcons.os4.close,
                size: 20,
              ),
            )
          : null,
      title: Text(
        selecting
            ? "已选择 @num 个项目"
                .tlParams({"num": logic.selectedNum.toString()})
            : "已下载".tl,
      ),
      largeTitle: (selecting || logic.searchMode)
          ? null
          : Text("已下载".tl),
      bottom: searching ? buildTitle(context, logic) : null,
      bottomHeight: searching ? 46 : 0,
      actions: buildActions(context, logic),
    );
  }

  List<Widget> buildActions(BuildContext context, DownloadPageLogic logic) {
    return [
      if (!logic.selecting && !logic.searchMode)
        MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("排序".tl)),
 child: MiuixIconButton(
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('sort') ?? MiuixIcons.os4.more,
              size: 20,
            ),
            onPressed: () async {
              bool changed = false;
              await showMiuixDialog(
                  context: context,
                  title: "漫画排序模式".tl,
                  contentBuilder: (context, close) => SizedBox(
                        width: 400,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MiuixBasicComponent(
                              title: "漫画排序模式".tl,
                              endActions: [
                                Select(
                                  initialValue:
                                  int.parse(appdata.settings[26][0]),
                                  onChange: (i) {
                                    appdata.settings[26] = appdata
                                        .settings[26]
                                        .setValueAt(i.toString(), 0);
                                    appdata.updateSettings();
                                    changed = true;
                                  },
                                  values: ["时间", "漫画名", "作者名", "大小"].tl,
                                ),
                              ],
                            ),
                            MiuixBasicComponent(
                              title: "倒序".tl,
                              endActions: [
                                StatefulSwitch(
                                  initialValue:
                                  appdata.settings[26][1] == "1",
                                  onChanged: (b) {
                                    if (b) {
                                      appdata.settings[26] = appdata
                                          .settings[26]
                                          .setValueAt("1", 1);
                                    } else {
                                      appdata.settings[26] = appdata
                                          .settings[26]
                                          .setValueAt("0", 1);
                                    }
                                    appdata.updateSettings();
                                    changed = true;
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ));
              if (changed) {
                logic.refresh();
              }
            },
          ),
),
      if (!logic.selecting && !logic.searchMode)
        MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("下载管理器".tl)),
 child: MiuixIconButton(
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('download') ?? MiuixIcons.os4.download,
              size: 20,
            ),
            onPressed: () {
              showPopUpWidget(
                context,
                const DownloadingPage(),
              );
            },
          ),
)
      else if (logic.selecting)
        MiuixWindowIconDropdownMenu(
          entry: MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: "全选".tl,
                icon: const Icon(Icons.select_all_rounded, size: 18),
                onClick: () {
                  for (int i = 0; i < logic.selected.length; i++) {
                    logic.selected[i] = true;
                  }
                  logic.selectedNum = logic.comics.length;
                  logic.update();
                },
              ),
              MiuixDropdownItem(
                text: "导出".tl,
                icon: MiuixIcon(vector: MiuixIcons.os4.share, size: 18),
                onClick: () => exportSelectedComic(context, logic),
              ),
              MiuixDropdownItem(
                text: "导出为pdf".tl,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                onClick: () => exportAsPdf(null, logic),
              ),
              MiuixDropdownItem(
                text: "查看漫画详情".tl,
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                onClick: () => Future.delayed(
                  const Duration(milliseconds: 200),
                  () {
                    if (logic.selectedNum != 1) {
                      showToast(message: "请选择一个漫画".tl);
                    } else {
                      for (int i = 0; i < logic.selected.length; i++) {
                        if (logic.selected[i]) {
                          toComicInfoPage(logic.comics[i]);
                        }
                      }
                    }
                  },
                ),
              ),
              MiuixDropdownItem(
                text: "添加至本地收藏".tl,
                icon: MiuixIcon(vector: MiuixIcons.os4.favorites, size: 18),
                onClick: () => Future.delayed(
                  const Duration(milliseconds: 200),
                  () => addToLocalFavoriteFolder(context, logic),
                ),
              ),
            ],
          ),
          child: MiuixIcon(
            vector: MiuixIcons.os4.more,
            size: 20,
          ),
        ),
      if (!logic.selecting)
        MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text(logic.searchMode ? "关闭搜索".tl : "搜索".tl)),
 child: MiuixIconButton(
            child: MiuixIcon(
              vector: logic.searchMode ? MiuixIcons.os4.close : MiuixIcons.os4.search,
              size: 20,
            ),
            onPressed: () {
              logic.searchMode = !logic.searchMode;
              logic.searchInit = true;
              if (!logic.searchMode) {
                logic.keyword = "";
                logic.searchController.clear();
              }
              logic.update();
            },
          ),
)
    ];
  }

  void exportSelectedComic(BuildContext context, DownloadPageLogic logic) {
    if (logic.selectedNum == 0) {
      showToast(message: "请选择漫画".tl);
    } else {
      Future<void>.delayed(
        const Duration(milliseconds: 200),
        () => showMiuixDialog(
          context: App.globalContext!,
          dismissible: false,
          contentBuilder: (context, close) => SizedBox(
            width: 200,
            height: 200,
            child: Center(
              child: SizedBox(
                width: 50,
                height: 75,
                child: Column(
                  children: [
                    SizedBox(
                      height: 10,
                    ),
                    MiuixCircularProgressIndicator(),
                    SizedBox(
                      height: 9,
                    ),
                    Text("打包中".tl)
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void>.delayed(
          const Duration(milliseconds: 500), () => export(logic));
    }
  }

  void addToLocalFavoriteFolder(BuildContext context, DownloadPageLogic logic) {
    String? folder;
    showMiuixDialog(
        context: context,
        title: "复制到...".tl,
        contentBuilder: (context, close) => SizedBox(
                  width: 400,
                  height: 132,
                  child: Column(
                    children: [
                      MiuixBasicComponent(
                        title: "收藏夹".tl,
                        endActions: [
                          Select(
                            width: 156,
                            values: LocalFavoritesManager().folderNames,
                            initialValue: null,
                            onChange: (i) =>
                                folder = LocalFavoritesManager().folderNames[i],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Center(
                        child: MiuixButton(colors: MiuixButtonDefaults.buttonColorsPrimary(context), 
                          child: Text("确认".tl),
                          onPressed: () {
                            if (folder == null) {
                              return;
                            }
                            for (int i = 0; i < logic.selected.length; i++) {
                              if (logic.selected[i]) {
                                var comic = logic.comics[i];
                                LocalFavoritesManager().addComic(
                                    folder!,
                                    switch (comic.type) {
                                      DownloadType.picacg =>
                                        FavoriteItem.fromPicacg(
                                            (comic as DownloadedComic)
                                                .comicItem
                                                .toBrief()),
                                      DownloadType.ehentai =>
                                        FavoriteItem.fromEhentai(
                                            (comic as DownloadedGallery)
                                                .gallery
                                                .toBrief()),
                                      DownloadType.jm =>
                                        FavoriteItem.fromJmComic(
                                            (comic as DownloadedJmComic)
                                                .comic
                                                .toBrief()),
                                      DownloadType.nhentai => FavoriteItem
                                          .fromNhentai(NhentaiComicBrief(
                                              comic.name,
                                              (comic as NhentaiDownloadedComic)
                                                  .cover,
                                              comic.id,
                                              "",
                                              const [])),
                                      DownloadType.hitomi =>
                                        FavoriteItem.fromHitomi((comic
                                                as DownloadedHitomiComic)
                                            .comic
                                            .toBrief(comic.link, comic.cover)),
                                      DownloadType.htmanga =>
                                        FavoriteItem.fromHtcomic(
                                            (comic as DownloadedHtComic)
                                                .comic
                                                .toBrief()),
                                      DownloadType.other => () {
                                          var c =
                                              (comic as CustomDownloadedItem);
                                          return FavoriteItem.custom(
                                              CustomComic(
                                                  c.name,
                                                  c.subTitle,
                                                  c.cover,
                                                  c.comicId,
                                                  c.tags,
                                                  "",
                                                  c.sourceKey));
                                        }(),
                                      DownloadType.favorite =>
                                        throw UnimplementedError(),
                                    });
                              }
                            }
                            close();
                          },
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                    ],
                  ),
                ));
  }
}

class DownloadedComicInfoView extends StatefulWidget {
  const DownloadedComicInfoView(this.item, this.logic,
      {Key? key, this.inMiuixSheet = false})
      : super(key: key);
  final DownloadedItem item;
  final DownloadPageLogic logic;

  /// 是否显示在 showMiuixBottomSheet 中（外框由 Miuix 底部弹窗提供）
  final bool inMiuixSheet;

  @override
  State<DownloadedComicInfoView> createState() =>
      _DownloadedComicInfoViewState();
}

class _DownloadedComicInfoViewState extends State<DownloadedComicInfoView> {
  String name = "";
  List<String> eps = [];
  List<int> downloadedEps = [];
  late final comic = widget.item;

  deleteEpisode(int i) {
    showConfirmDialog(context, "确认删除".tl, "要删除这个章节吗".tl, () async {
      var message = await DownloadManager().deleteEpisode(comic, i);
      if (message == null) {
        setState(() {});
      } else {
        showToast(message: message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    getInfo();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final isMobile = UiMode.m1(context);

    Widget content = Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile && !widget.inMiuixSheet)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark ? const Color(0x38FFFFFF) : const Color(0x28000000),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MiuixTooltipBox(
 tooltip: (_, scope) => MiuixPlainTooltip(scope: scope, child: Text("关闭".tl)),
 child: MiuixIconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: MiuixIcon(
                    vector: MiuixIcons.os4.close,
                    size: 20,
                  ),
                ),
),
            ],
          ),
        ),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            gridDelegate: const SliverGridDelegateWithFixedHeight(
              maxCrossAxisExtent: 220,
              itemHeight: 48,
            ),
            itemBuilder: (BuildContext context, int i) {
              final isDownloaded = downloadedEps.contains(i);
              return GestureDetector(
 onLongPress: () => deleteEpisode(i),
 onSecondaryTapDown: (details) => deleteEpisode(i),
child: MiuixPressable(
 onPressed: () => readSpecifiedEps(i),
 feedbackType: MiuixPressFeedbackType.sink,
 child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: ShapeDecoration(
                      shape: MiuixSquircleBorder(
                        cornerRadius: 12,
                        side: BorderSide(
                          color: isDownloaded
                              ? primary.withOpacity(0.5)
                              : (isDark ? const Color(0x18FFFFFF) : const Color(0x0C000000)),
                          width: isDownloaded ? 1.0 : 0.6,
                        ),
                      ),
                      color: isDownloaded
                          ? primary.withOpacity(isDark ? 0.22 : 0.12)
                          : (isDark ? const Color(0xFF26262A) : Colors.white),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            eps[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isDownloaded ? FontWeight.w600 : FontWeight.w500,
                              color: isDownloaded ? primary : null,
                            ),
                          ),
                        ),
                        if (isDownloaded) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: primary,
                          ),
                        ],
                      ],
                    ),
                  ),
),
);
            },
            itemCount: eps.length,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            (MediaQuery.of(context).padding.bottom + 12).clamp(16.0, 60.0),
          ),
          child: Row(
            children: [
              Expanded(
                child: MiuixPressable(
 onPressed: () {
                      Navigator.of(context).pop();
                      _toComicInfoPage(widget.item);
                    },
 feedbackType: MiuixPressFeedbackType.sink,
 child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: const MiuixSquircleBorder(cornerRadius: 14),
                        color: isDark ? const Color(0x22FFFFFF) : const Color(0x14000000),
                      ),
                      child: Text(
                        "查看详情".tl,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixPressable(
 onPressed: () => read(),
 feedbackType: MiuixPressFeedbackType.sink,
 child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: const MiuixSquircleBorder(cornerRadius: 14),
                        color: primary,
                        shadows: [
                          BoxShadow(
                            color: primary.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        "阅读".tl,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
),
              ),
            ],
          ),
        ),
      ],
    );

    if (isMobile && widget.inMiuixSheet) {
      // 由 showMiuixBottomSheet 提供外框，这里只保留高度限制
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60,
        ),
        child: content,
      );
    }

    if (isMobile) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60,
        ),
        child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: FrostBlur(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Color(frostEnabled ? 0xF01C1C1E : 0xFF1C1C1E)
                      : Color(frostEnabled ? 0xF4F6F6F8 : 0xFFF6F6F8),
                ),
                child: content,
              ),
            ),
          ),
      );
    }

    return content;
  }

  void getInfo() {
    name = comic.name;
    eps = comic.eps;
    downloadedEps = comic.downloadedEps;
  }

  void read() {
    comic.read();
  }

  void readSpecifiedEps(int i) {
    comic.read(ep: i + 1);
  }
}

class DownloadedComicTile extends ComicTile {
  final String size;
  final File imagePath;
  final String author;
  final String name;
  final String type;
  final List<String> tag;
  final void Function() onTap;
  final void Function() onLongTap;
  final void Function(TapDownDetails details) onSecondaryTap;

  @override
  List<String>? get tags => tag.map((e) =>
    App.locale.languageCode == "zh"
        ? e.translateTagsToCN
        : e
  ).toList();

  @override
  String get description => "${size}MB";

  @override
  Widget get image => Image.file(
        imagePath,
        fit: BoxFit.cover,
        height: double.infinity,
      );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => author;

  @override
  String get title => name;

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(details) => onSecondaryTap(details);

  @override
  String? get badge => type;

  const DownloadedComicTile(
      {required this.size,
      required this.imagePath,
      required this.author,
      required this.name,
      required this.onTap,
      required this.onLongTap,
      required this.onSecondaryTap,
      required this.type,
      required this.tag,
      super.key});
}

void _toComicInfoPage(DownloadedItem comic) {
  var context = App.mainNavigatorKey!.currentContext!;
  if (comic is DownloadedComic) {
    context.to(() => PicacgComicPage((comic).comicItem.id, null));
  } else if (comic is DownloadedGallery) {
    context.to(() => EhGalleryPage((comic).gallery.toBrief()));
  } else if (comic is DownloadedJmComic) {
    context.to(() => JmComicPage((comic).comic.id));
  } else if (comic is DownloadedHitomiComic) {
    context.to(() => HitomiComicPage(comic.toBrief()));
  } else if (comic is DownloadedHtComic) {
    context.to(() => HtComicPage(comic.id.replaceFirst('Ht', '')));
  } else if (comic is NhentaiDownloadedComic) {
    context.to(() => NhentaiComicPage(comic.id.replaceFirst("nhentai", "")));
  } else if (comic is CustomDownloadedItem) {
    context.to(() => ComicPage(sourceKey: comic.sourceKey, id: comic.comicId));
  }
}
