import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/image_loader/base_image_provider.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/tools/save_image.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';

import 'reader/comic_reading_page.dart';

class ImageFavoritesPage extends StatefulWidget {
  const ImageFavoritesPage({super.key});

  @override
  State<ImageFavoritesPage> createState() => _ImageFavoritesPageState();
}

class _ImageFavoritesController extends SimpleController {
  bool selecting = false;
  final Set<String> selected = {};

  String keyOf(ImageFavorite f) => "${f.id}|${f.ep}|${f.page}";

  void enterSelect() {
    selecting = true;
    update();
  }

  void exitSelect() {
    selecting = false;
    selected.clear();
    update();
  }

  void toggle(ImageFavorite f) {
    final k = keyOf(f);
    if (selected.contains(k)) {
      selected.remove(k);
    } else {
      selected.add(k);
    }
    if (selected.isEmpty) {
      selecting = false;
    }
    update();
  }

  void selectAll(List<ImageFavorite> images) {
    if (selected.length == images.length && images.isNotEmpty) {
      selected.clear();
      selecting = false;
    } else {
      selected
        ..clear()
        ..addAll(images.map(keyOf));
      selecting = true;
    }
    update();
  }
}

class _ImageFavoritesPageState extends State<ImageFavoritesPage> {
  @override
  Widget build(BuildContext context) {
    return StateBuilder<_ImageFavoritesController>(
      tag: "image_favorites_page",
      init: _ImageFavoritesController(),
      builder: (logic) {
        final images = ImageFavoriteManager.getAll();
        final selecting = logic.selecting;
        return MiuixScaffold(
          content: (_) => SmoothCustomScrollView(
            slivers: [
              SliverAppbar(
                color: selecting
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                leading: selecting
                    ? MiuixIconButton(
                        onPressed: logic.exitSelect,
                        child: MiuixIcon(
                          vector: MiuixIcons.os4.close,
                          size: 20,
                        ),
                      )
                    : null,
                title: Text(
                  selecting
                      ? "已选择 @num 个项目"
                          .tlParams({"num": logic.selected.length.toString()})
                      : "图片收藏".tl,
                ),
                largeTitle: selecting ? null : Text("图片收藏".tl),
                actions: [
                  if (!selecting)
                    MiuixTooltipBox(
                      tooltip: (_, scope) => MiuixPlainTooltip(
                          scope: scope, child: Text("选择".tl)),
                      child: MiuixIconButton(
                        onPressed: images.isEmpty ? null : logic.enterSelect,
                        child: const Icon(Icons.checklist_rounded, size: 22),
                      ),
                    )
                  else ...[
                    MiuixTooltipBox(
                      tooltip: (_, scope) => MiuixPlainTooltip(
                          scope: scope, child: Text("全选".tl)),
                      child: MiuixIconButton(
                        onPressed: () => logic.selectAll(images),
                        child: const Icon(Icons.select_all_rounded, size: 22),
                      ),
                    ),
                    MiuixTooltipBox(
                      tooltip: (_, scope) => MiuixPlainTooltip(
                          scope: scope, child: Text("删除".tl)),
                      child: MiuixIconButton(
                        onPressed: () {
                          if (logic.selected.isEmpty) {
                            showToast(message: "选择".tl);
                            return;
                          }
                          showConfirmDialog(
                            context,
                            "删除".tl,
                            "要删除已选择的 @num 个项目吗? 此操作无法撤销".tlParams(
                                {"num": logic.selected.length.toString()}),
                            () {
                              final toDelete = images
                                  .where((e) =>
                                      logic.selected.contains(logic.keyOf(e)))
                                  .toList();
                              ImageFavoriteManager.deleteMany(toDelete);
                              logic.exitSelect();
                              showToast(message: "删除成功".tl);
                              StateController.findOrNull(
                                      tag: "image_favorites_page")
                                  ?.update();
                            },
                          );
                        },
                        child: MiuixIcon(
                          vector: MiuixIcons.extended.byName('delete') ??
                              MiuixIcons.os4.close,
                          size: 20,
                          tint: logic.selected.isEmpty
                              ? null
                              : const Color(0xFFE53935),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SliverPadding(
                padding: comicGridPadding(),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final image = images[index];
                      return FavoriteImageTile(
                        image,
                        selecting: selecting,
                        selected: logic.selected.contains(logic.keyOf(image)),
                        onToggleSelect: () => logic.toggle(image),
                      );
                    },
                    childCount: images.length,
                  ),
                  gridDelegate:
                      SliverGridDelegateWithComics(true, appdata.settings[74]),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FavoriteImageTile extends StatelessWidget {
  const FavoriteImageTile(
    this.image, {
    super.key,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final ImageFavorite image;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;

  String get _sourceKey => ComicSource.sourceKeyFromCompoundId(image.id);

  String get _sourceLabel =>
      ComicSource.displayNameOf(_sourceKey) ?? _sourceKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Material(
        color: Colors.transparent,
        shape: const MiuixSquircleBorder(cornerRadius: 14),
        clipBehavior: Clip.antiAlias,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: ShapeDecoration(
            shape: MiuixSquircleBorder(
              cornerRadius: 14,
              side: BorderSide(
                color: selected
                    ? primary.withOpacity(0.7)
                    : (isDark
                        ? const Color(0x18FFFFFF)
                        : const Color(0x0A000000)),
                width: selected ? 1.4 : 0.6,
              ),
            ),
            color: selected
                ? primary.withOpacity(isDark ? 0.18 : 0.08)
                : Theme.of(context).colorScheme.secondaryContainer,
            shadows: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image(
                  image: _FavoriteImageProvider(image),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: primary.withOpacity(0.92),
                    shape: const StadiumBorder(),
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    _sourceLabel,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (selecting)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 22,
                    color: selected ? primary : Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.4),
                        Colors.black.withOpacity(0.72),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                  child: Text(
                    image.title.replaceAll("\n", ""),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13.0,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  onSecondaryTapDown: onSecondaryTap,
                  child: MiuixPressable(
                    onPressed: () {
                      if (selecting) {
                        onToggleSelect?.call();
                      } else {
                        openImage();
                      }
                    },
                    onLongPress: () {
                      if (selecting) {
                        onToggleSelect?.call();
                      } else {
                        openReader();
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openImage() {
    Navigator.of(App.globalContext!).push(
      FavoriteImagePageRoute(image: image),
    );
  }

  void openReader() {
    var type = _sourceKey;
    _readWithKey(type, image.id.replaceFirst("$type-", ""), image.ep,
        image.page, image.title, image.otherInfo);
  }

  void _readWithKey(String key, String target, int ep, int page, String title,
      Map<String, dynamic> otherInfo) async {
    switch (key) {
      case "picacg":
        App.globalTo(() => ComicReadingPage.picacg(
            target, ep, List.from(otherInfo["eps"]), title,
            initialPage: page));
      case "ehentai":
        App.globalTo(
          () => ComicReadingPage.ehentai(
            Gallery.fromJson(otherInfo["gallery"]),
            initialPage: page,
          ),
        );
      case "jm":
        App.globalTo(
          () => ComicReadingPage(
            JmReadingData(
              title,
              target,
              List.from(otherInfo["eps"]),
              List.from(
                otherInfo["jmEpNames"],
              ),
            ),
            page,
            ep,
          ),
        );
      case "hitomi":
        App.globalTo(
          () => ComicReadingPage(
            HitomiReadingData(
              title,
              target,
              (otherInfo["hitomi"] as List)
                  .map((e) => HitomiFile.fromMap(e))
                  .toList(),
              target,
            ),
            page,
            0,
          ),
        );
      case "htManga":
      case "htmanga":
        App.globalTo(
          () => ComicReadingPage.htmanga(target, title, initialPage: page),
        );
      case "nhentai":
        App.globalTo(
          () => ComicReadingPage.nhentai(target, title, initialPage: page),
        );
      default:
        var source = ComicSource.find(key);
        if (source == null) throw "Unknown source $key";
        App.globalTo(
          () => ComicReadingPage(
            CustomReadingData(
              target,
              title,
              source,
              Map.from(otherInfo["eps"]),
            ),
            page,
            ep,
          ),
        );
    }
  }

  void deleteOne() {
    showConfirmDialog(
        App.globalContext!, "确认删除".tl, "要删除这个图片吗".tl, () {
      ImageFavoriteManager.delete(image);
      showToast(message: "删除成功".tl);
      StateController.findOrNull(tag: "image_favorites_page")?.update();
    });
  }

  void onSecondaryTap(TapDownDetails details) {
    showDesktopMenu(App.globalContext!, details.globalPosition, [
      DesktopMenuEntry(text: "查看图片".tl, onClick: openImage),
      DesktopMenuEntry(text: "打开阅读器".tl, onClick: openReader),
      DesktopMenuEntry(text: "删除".tl, onClick: deleteOne),
    ]);
  }
}

/// Immersive open for a favorited image: soft fade + short upward slide
/// (HyperOS-style emphasized decelerate). Avoids wrapping only the glass bars
/// in a separate opacity so BackdropFilter still samples the photo beneath.
class FavoriteImagePageRoute extends PageRoute<void> {
  FavoriteImagePageRoute({required this.image})
      : super(fullscreenDialog: true);

  final ImageFavorite image;

  @override
  Color? get barrierColor => Colors.black;

  @override
  String? get barrierLabel => "Dismiss";

  @override
  bool get barrierDismissible => false;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: ShowFavoriteImagePage(image),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final primary = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Curves.easeInOutCubic,
    );
    // Fade the whole page (including glass). Brief BackdropFilter white-flash
    // is acceptable here; the slide makes the open feel intentional vs a cut.
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(primary),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(primary),
        child: child,
      ),
    );
  }
}

/// 直接查看收藏的那一张本地图（不进入阅读器）
class ShowFavoriteImagePage extends StatelessWidget {
  const ShowFavoriteImagePage(this.image, {super.key});

  final ImageFavorite image;

  String get _sourceKey => ComicSource.sourceKeyFromCompoundId(image.id);

  String get _sourceLabel =>
      ComicSource.displayNameOf(_sourceKey) ?? _sourceKey;

  Future<File> _resolveLocalFile() async {
    final local = File("${App.dataPath}/images/${image.imagePath}");
    if (await local.exists()) {
      return local;
    }
    // Mirror _FavoriteImageProvider reload path so share/save work even if
    // the cached copy was wiped.
    final provider = _FavoriteImageProvider(image);
    final chunk = StreamController<ImageChunkEvent>();
    try {
      final bytes = await provider.load(chunk);
      await local.create(recursive: true);
      await local.writeAsBytes(bytes, flush: true);
      return local;
    } finally {
      await chunk.close();
    }
  }

  Future<void> _onShare() async {
    try {
      final file = await _resolveLocalFile();
      await shareImage(file);
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  Future<void> _onSave() async {
    try {
      final file = await _resolveLocalFile();
      await saveImage(file);
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  Widget _glassBar({
    required BuildContext context,
    required Widget child,
    double height = 52,
  }) {
    return MiuixGlassPanel(
      cornerRadius: 18,
      tint: const Color(0xDC1A1A1E),
      strokeColor: const Color(0x24FFFFFF),
      strokeWidth: 0.8,
      blurRadius: 24,
      shadow: BoxShadow(
        color: Colors.black.withOpacity(0.45),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
      child: SizedBox(height: height, child: child),
    );
  }

  Widget _bottomAction({
    required BuildContext context,
    required String label,
    required IconData fallbackIcon,
    String? vectorName,
    required VoidCallback onPressed,
  }) {
    final vector = vectorName == null
        ? null
        : (MiuixIcons.extended.byName(vectorName) ??
            (vectorName == "share" ? MiuixIcons.os4.share : null));
    return Expanded(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        borderRadius: BorderRadius.circular(14),
        onPressed: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (vector != null)
                MiuixIcon(vector: vector, size: 20, tint: Colors.white)
              else
                Icon(fallbackIcon, size: 20, color: Colors.white),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final title = image.title.replaceAll("\n", "").trim();
    final pageLabel =
        image.ep > 0 ? "E${image.ep} · P${image.page}" : "P${image.page}";

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MiuixScaffold(
        content: (_) => Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            PhotoView(
              minScale: PhotoViewComputedScale.contained * 0.9,
              maxScale: PhotoViewComputedScale.covered * 3.5,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              filterQuality: FilterQuality.high,
              imageProvider: _FavoriteImageProvider(image),
              loadingBuilder: (context, event) {
                final total = event?.expectedTotalBytes;
                final loaded = event?.cumulativeBytesLoaded ?? 0;
                final progress =
                    (total != null && total > 0) ? loaded / total : null;
                return Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: MiuixCircularProgressIndicator(
                          progress: progress,
                          size: 36,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          "${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            Positioned(
              top: 8 + topInset,
              left: 14,
              right: 14,
              child: _glassBar(
                context: context,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                  child: Row(
                    children: [
                      MiuixIconButton(
                        minWidth: 40,
                        minHeight: 40,
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: MiuixIcon(
                          vector: MiuixIcons.os4.chevronBackward,
                          size: 20,
                          tint: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title.isEmpty ? "图片".tl : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pageLabel,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.92),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          _sourceLabel,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 10 + bottomInset,
              child: _glassBar(
                context: context,
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      _bottomAction(
                        context: context,
                        label: "分享".tl,
                        fallbackIcon: Icons.share_outlined,
                        vectorName: "share",
                        onPressed: () { _onShare(); },
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.white.withOpacity(0.12),
                      ),
                      _bottomAction(
                        context: context,
                        label: "下载到本地".tl,
                        fallbackIcon: Icons.download_outlined,
                        vectorName: "download",
                        onPressed: () { _onSave(); },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteImageProvider extends BaseImageProvider<_FavoriteImageProvider> {
  _FavoriteImageProvider(this.image);

  final ImageFavorite image;

  @override
  String get key => image.id + image.ep.toString() + image.page.toString();

  @override
  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents) async {
    final localFile = File("${App.dataPath}/images/${image.imagePath}");
    if (localFile.existsSync()) {
      return await localFile.readAsBytes();
    } else {
      var type = image.id.split("-")[0];
      Stream<DownloadProgress> stream;
      switch (type) {
        case "ehentai":
          stream = ImageManager().getEhImageNew(
              Gallery.fromJson(image.otherInfo["gallery"]), image.page);
        case "jm":
          stream = ImageManager().getJmImage(image.otherInfo["url"], null,
              epsId: image.otherInfo["epsId"],
              scrambleId: "220980",
              bookId: image.otherInfo["bookId"]);
        case "hitomi":
          stream = ImageManager().getHitomiImage(
              HitomiFile.fromMap(image.otherInfo["hitomi"][image.page - 1]),
              image.otherInfo["galleryId"]);
        default:
          stream = ImageManager().getImage(image.otherInfo["url"]);
      }
      DownloadProgress? finishProgress;
      await for (var progress in stream) {
        if (progress.currentBytes == progress.expectedBytes) {
          finishProgress = progress;
        }
        chunkEvents.add(ImageChunkEvent(
            cumulativeBytesLoaded: progress.currentBytes,
            expectedTotalBytes: progress.expectedBytes));
      }
      var file = finishProgress!.getFile();
      var data = await file.readAsBytes();
      var file2 = File("${App.dataPath}/images/${image.imagePath}");
      if (!file2.existsSync()) {
        await file2.create(recursive: true);
      }
      await file2.writeAsBytes(data);
      return data;
    }
  }

  @override
  Future<_FavoriteImageProvider> obtainKey(ImageConfiguration configuration) async {
    return this;
  }
}
