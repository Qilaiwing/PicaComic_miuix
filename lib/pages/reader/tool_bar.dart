part of pica_reader;

extension ToolBar on ComicReadingPage {
  bool get isReversed => appdata.settings[9] == "2" || appdata.settings[9] == "6";
  ///构建底部工具栏
  Widget buildBottomToolBar(
      ComicReadingPageLogic logic, BuildContext context, bool showEps) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Positioned(
      left: 14,
      right: 14,
      bottom: 12 + bottomInset,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        builder: (logic) {
          var epText = logic.order > 0 ? "E${logic.order} · " : "";
          var pageText = "$epText${logic.index} / ${logic.urls.length}";

          Widget island = MiuixGlassPanel(
            cornerRadius: 22,
            tint: isDark ? const Color(0xE21C1C22) : const Color(0xF2FFFFFF),
            strokeColor:
                isDark ? const Color(0x28FFFFFF) : const Color(0x0E000000),
            strokeWidth: 0.8,
            blurRadius: 24,
            shadow: BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                        // 顶部胶囊：当前页码指示
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2.5),
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: isDark
                                  ? const Color(0x22FFFFFF)
                                  : const Color(0x12000000),
                            ),
                            child: Text(
                              pageText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF222222),
                                letterSpacing: -0.2,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // 进度条行：上一章 + Miuix进度条 + 下一章（高度居中持平）
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            MiuixIconButton(
                              minWidth: 36,
                              minHeight: 36,
                              onPressed: () => !isReversed
                                  ? logic.jumpToLastChapter()
                                  : logic.jumpToNextChapter(),
                              child: MiuixIcon(
                                vector: MiuixIcons.extended.byName('chevronBackward') ??
                                    MiuixIcons.os4.back,
                                size: 19,
                              ),
                            ),
                            Expanded(
                              child: buildSlider(logic),
                            ),
                            MiuixIconButton(
                              minWidth: 36,
                              minHeight: 36,
                              onPressed: () => !isReversed
                                  ? logic.jumpToNextChapter()
                                  : logic.jumpToLastChapter(),
                              child: MiuixIcon(
                                vector: MiuixIcons.extended.byName('chevronForward') ??
                                    MiuixIcons.os4.chevronForward,
                                size: 19,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // 下层：一排功能按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (App.isAndroid && appdata.settings[76] == "0")
                              MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("屏幕方向".tl)), child: MiuixIconButton(
                                  minWidth: 38,
                                  minHeight: 38,
                                  child: Icon(
                                    logic.rotation == null
                                        ? Icons.screen_rotation_alt
                                        : (logic.rotation == false
                                            ? Icons.screen_lock_portrait
                                            : Icons.screen_lock_landscape),
                                    size: 19,
                                  ),
                                  onPressed: () {
                                    if (logic.rotation == null) {
                                      logic.rotation = false;
                                      logic.update();
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.portraitUp,
                                        DeviceOrientation.portraitDown,
                                      ]);
                                    } else if (logic.rotation == false) {
                                      logic.rotation = true;
                                      logic.update();
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.landscapeLeft,
                                        DeviceOrientation.landscapeRight
                                      ]);
                                    } else {
                                      logic.rotation = null;
                                      logic.update();
                                      SystemChrome.setPreferredOrientations(
                                          DeviceOrientation.values);
                                    }
                                  },
                                ),
                              ),
                            if (showEps)
                              MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("章节".tl)), child: MiuixIconButton(
                                  minWidth: 38,
                                  minHeight: 38,
                                  onPressed: openEpsDrawer,
                                  child: MiuixIcon(
                                    vector: MiuixIcons.extended.byName('all') ??
                                        MiuixIcons.os4.more,
                                    size: 19,
                                  ),
                                ),
                              ),
                            MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("自动翻页".tl)), child: MiuixIconButton(
                                minWidth: 38,
                                minHeight: 38,
                                onPressed: () {
                                  logic.runningAutoPageTurning =
                                      !logic.runningAutoPageTurning;
                                  logic.update();
                                  logic.autoPageTurning();
                                },
                                child: MiuixIcon(
                                  vector: MiuixIcons.extended.byName('timer') ??
                                      MiuixIcons.os4.settings,
                                  size: 19,
                                  tint: logic.runningAutoPageTurning
                                      ? primaryColor
                                      : null,
                                ),
                              ),
                            ),
                            MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("收藏图片".tl)), child: MiuixIconButton(
                                minWidth: 38,
                                minHeight: 38,
                                child: MiuixIcon(
                                  vector: MiuixIcons.extended.byName('favorites') ??
                                      MiuixIcons.os4.favorites,
                                  size: 19,
                                  tint: ImageFavoriteManager.exist(
                                          "${logic.data.sourceKey}-${logic.data.id}",
                                          logic.order,
                                          logic.index)
                                      ? primaryColor
                                      : null,
                                ),
                                onPressed: () async {
                                  try {
                                    final id =
                                        "${logic.data.sourceKey}-${logic.data.id}";
                                    int? pageIndex = logic.index - 1;
                                    if (logic.readingMethod ==
                                        ReadingMethod.topToBottomContinuously) {
                                      pageIndex =
                                          await selectImage(forFavorite: true);
                                    }
                                    if (pageIndex == null) {
                                      return;
                                    }
                                    final page = pageIndex + 1;
                                    var file = await _getFileFromStream(
                                        readingData.loadImage(logic.order,
                                            pageIndex, logic.urls[pageIndex]));
                                    var imagePath =
                                        await persistentCurrentImage(file);
                                    imagePath = imagePath
                                        .split(RegExp(r'[/\\]'))
                                        .last;
                                    var otherInfo = <String, dynamic>{};
                                    if (logic.data.type == ReadingType.ehentai) {
                                      otherInfo["gallery"] =
                                          (logic.data as EhReadingData)
                                              .gallery
                                              .toJson();
                                    } else if (logic.data.type ==
                                        ReadingType.hitomi) {
                                      otherInfo["hitomi"] =
                                          (readingData as HitomiReadingData)
                                              .images
                                              .map((e) => e.toMap())
                                              .toList();
                                      otherInfo["galleryId"] = readingData.id;
                                    } else if (logic.data.type ==
                                        ReadingType.jm) {
                                      otherInfo["jmEpNames"] =
                                          readingData.eps!.values.toList();
                                      otherInfo["epsId"] = readingData
                                          .eps!.keys
                                          .elementAt(logic.order - 1);
                                      otherInfo["bookId"] = readingData.id;
                                    }
                                    if (logic.data.type != ComicType.other) {
                                      otherInfo["eps"] =
                                          readingData.eps?.keys.toList() ?? [];
                                    } else {
                                      otherInfo["eps"] = readingData.eps;
                                    }
                                    otherInfo["url"] = logic.urls[pageIndex];
                                    var favorite = ImageFavorite(
                                        id,
                                        imagePath,
                                        readingData.title,
                                        logic.order,
                                        page,
                                        otherInfo);
                                    if (!ImageFavoriteManager.exist(
                                        id, logic.order, page)) {
                                      ImageFavoriteManager.add(favorite);
                                      showToast(message: "已添加至图片收藏".tl);
                                    } else {
                                      ImageFavoriteManager.delete(favorite);
                                      showToast(message: "已取消图片收藏".tl);
                                    }
                                    logic.update(["ToolBar"]);
                                  } catch (e) {
                                    showToast(message: e.toString());
                                  }
                                },
                              ),
                            ),
                            MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("保存图片".tl)), child: MiuixIconButton(
                                minWidth: 38,
                                minHeight: 38,
                                onPressed: saveCurrentImage,
                                child: MiuixIcon(
                                  vector: MiuixIcons.extended.byName('download') ??
                                      MiuixIcons.os4.delete,
                                  size: 19,
                                ),
                              ),
                            ),
                            MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("分享".tl)), child: MiuixIconButton(
                                minWidth: 38,
                                minHeight: 38,
                                onPressed: share,
                                child: MiuixIcon(
                                  vector: MiuixIcons.os4.share,
                                  size: 19,
                                ),
                              ),
                            ),
                            if (App.isWindows)
                              MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("${"全屏".tl}(F12)")), child: MiuixIconButton(
                                  minWidth: 38,
                                  minHeight: 38,
                                  child: const Icon(Icons.fullscreen, size: 20),
                                  onPressed: () => logic.fullscreen(),
                                ),
                              ),
                          ],
                        ),
              ],
            ),
          );

          // 工具栏不加入场动画。
          //
          // 这里的子树里有 BackdropFilter：包上 Opacity 会把它送进离屏图层，
          // 采不到身后画面就会白闪；包上 Transform（SlideTransition）则会让它
          // 每帧重新采样并模糊一大块区域（还带 3σ 外扩），呼出时明显掉帧。
          //
          // 阅读器的工具栏本来就该即时响应，直接显隐手感反而更利落。
          return logic.tools ? island : const SizedBox.shrink();
        },
      ),
    );
  }

  Widget buildSlider(ComicReadingPageLogic logic) {
    if (logic.tools &&
        logic.index != 0 &&
        logic.index != logic.urls.length + 1 &&
        logic.urls.isNotEmpty) {
      final total = math.max(1, logic.urls.length);
      final double maxVal = total > 1 ? total.toDouble() : 2.0;
      final int steps = total > 1 ? total - 1 : 0;
      final double currentVal = logic.index.clamp(1, total).toDouble();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: MiuixSlider(
          value: currentVal,
          min: 1.0,
          max: maxVal,
          steps: steps,
          enabled: total > 1,
          reverseDirection: isReversed,
          height: 24,
          onValueChanged: (val) {
            final i = val.round();
            if (logic.readingMethod == ReadingMethod.topToBottomContinuously) {
              logic.jumpToPage(i);
              logic.index = i;
              logic.update();
            } else {
              logic.index = i;
              logic.jumpToPage(i);
              logic.update();
            }
          },
        ),
      );
    } else {
      return const SizedBox(
        height: 0,
      );
    }
  }

  Iterable<Widget> buildButtons(
      ComicReadingPageLogic logic, BuildContext context) sync* {
    if (context.width > context.height &&
        appdata.appSettings.showButtonsInReader) {
      if (appdata.settings[9] != "4" &&
          logic.readingMethod != ReadingMethod.topToBottom) {
        yield Positioned(
          left: 12,
          top: MediaQuery.of(context).size.height / 2 - 25,
          child: Button.icon(
            icon: const Icon(Icons.keyboard_arrow_left),
            onPressed: () {
              if (appdata.appSettings.flipPageWithClick) {
                return;
              }
              switch (logic.readingMethod) {
                case ReadingMethod.rightToLeft:
                case ReadingMethod.twoPageReversed:
                  logic.jumpToNextPage();
                default:
                  logic.jumpToLastPage();
              }
            },
            size: 24,
          ),
        );
      }
      if (appdata.settings[9] != "4" &&
          logic.readingMethod != ReadingMethod.topToBottom) {
        yield Positioned(
          right: 12,
          top: MediaQuery.of(context).size.height / 2 - 25,
          child: Button.icon(
            icon: const Icon(Icons.keyboard_arrow_right),
            onPressed: () {
              if (appdata.settings[0] == "1") {
                return;
              }
              switch (logic.readingMethod) {
                case ReadingMethod.rightToLeft:
                case ReadingMethod.twoPageReversed:
                  logic.jumpToLastPage();
                default:
                  logic.jumpToNextPage();
              }
            },
            size: 24,
          ),
        );
      }
      yield Positioned(
        left: 4,
        top: 4 + MediaQuery.of(context).padding.top,
        child: MiuixIconButton(child: const Icon(Icons.close, size: 24),
          onPressed: () => App.globalBack(),
        ),
      );
    }
  }

  ///构建顶部工具栏
  Widget buildTopToolBar(
      ComicReadingPageLogic comicReadingPageLogic, BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: 8 + topInset,
      left: 14,
      right: 14,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        // 同底栏：不加任何过渡动画，直接显隐
        builder: (logic) => comicReadingPageLogic.tools
            ? MiuixGlassPanel(
                  cornerRadius: 18,
                  tint: isDark
                      ? const Color(0xDC1A1A1E)
                      : const Color(0xEAFFFFFF),
                  strokeColor: isDark
                      ? const Color(0x24FFFFFF)
                      : const Color(0x0E000000),
                  strokeWidth: 0.8,
                  blurRadius: 24,
                  shadow: BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.45 : 0.1),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("返回".tl)), child: MiuixIconButton(
                              minWidth: 38,
                              minHeight: 38,
                              onPressed: () => App.globalBack(),
                              child: MiuixIcon(
                                vector: MiuixIcons.extended
                                        .byName('chevronBackward') ??
                                    MiuixIcons.os4.back,
                                size: 21,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Builder(builder: (context) {
                              final hasEp = readingData.hasEp;
                              final epName = hasEp
                                  ? (readingData.eps?.values.elementAtOrNull(
                                          comicReadingPageLogic.order - 1) ??
                                      "E${comicReadingPageLogic.order}")
                                  : null;
                              final secondary = Theme.of(context)
                                  .colorScheme.onSurface.withValues(alpha: 0.62);
                              if (!hasEp || epName == null) {
                                return Text(
                                  readingData.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    readingData.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.2,
                                      height: 1.15,
                                      color: secondary,
                                    ),
                                  ),
                                  Text(
                                    epName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                          const SizedBox(width: 4),
                          MiuixTooltipBox(tooltip: (context, scope) => MiuixPlainTooltip(scope: scope, child: Text("阅读设置".tl)), child: MiuixIconButton(
                              minWidth: 38,
                              minHeight: 38,
                              onPressed: () => showSettings(context),
                              child: MiuixIcon(
                                vector: MiuixIcons.os4.settings,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
      ),
    );
  }

  ///显示当前的章节和页面位置
  Widget buildPageInfoText(
      ComicReadingPageLogic comicReadingPageLogic, BuildContext context) {
    return Positioned(
      bottom: 13,
      left: 25,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        builder: (logic) {
          var epName = readingData.eps?.values
                  .elementAtOrNull(comicReadingPageLogic.order - 1) ??
              "E1";
          if (epName.length > 8) {
            epName = "${epName.substring(0, 8)}...";
          }
          var text = readingData.hasEp
              ? "$epName : ${comicReadingPageLogic.index}/${comicReadingPageLogic.urls.length}"
              : "${comicReadingPageLogic.index}/${comicReadingPageLogic.urls.length}";
          return Stack(
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.4
                    ..color = (useDarkBackground ||
                            Theme.of(context).brightness == Brightness.dark)
                        ? Colors.black
                        : Colors.white,
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: useDarkBackground ? Colors.white : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
