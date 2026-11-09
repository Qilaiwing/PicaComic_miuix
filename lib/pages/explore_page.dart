
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:sliver_tools/sliver_tools.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class ExplorePageController extends StateController {
  List<String> pages = [];
  late TabController tabController;

  void init(TickerProvider vsync) {
    String? previous;
    try {
      previous = pages[tabController.index];
    } catch (_) {}
    pages = appdata.appSettings.explorePages;
    var all = ComicSource.sources
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    pages = pages.where((e) => all.contains(e)).toList();
    if (pages.isEmpty && appdata.appSettings.explorePages.isNotEmpty) {
      if (appdata.appSettings.explorePages.first.isNum) {
        // is odd data, update
        appdata.appSettings.explorePages = all;
        pages = all;
        appdata.updateSettings();
      }
    }
    var initial = previous == null ? 0 : pages.indexOf(previous);
    tabController = TabController(
      length: pages.length,
      vsync: vsync,
      initialIndex: initial < 0 ? 0 : initial,
    );
  }
}

class _ExplorePageState extends State<ExplorePage> {
  bool showFB = true;

  double location = 0;

  void refresh() {
    final logic = StateController.find<ExplorePageController>();
    if (logic.pages.isEmpty) return;
    int page = logic.tabController.index;
    String currentPageId = logic.pages[page];
    StateController.find<SimpleController>(tag: currentPageId).refresh();
  }

  Widget buildFAB() {
    final primary = Theme.of(context).colorScheme.primary;

    return MiuixPressable(
        key: const Key("FAB"),
        shape: const MiuixSquircleBorder(cornerRadius: 16),
        onPressed: refresh,
        child: Container(
          width: 48,
          height: 48,
          decoration: ShapeDecoration(
            color: primary,
            shape: const MiuixSquircleBorder(cornerRadius: 16),
            shadows: [
              BoxShadow(
                color: primary.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: MiuixIcon(
              vector: MiuixIcons.os4.refresh,
              tint: Colors.white,
              size: 22,
            ),
          ),
        ));
  }

  Tab buildTab(String i) {
    return Tab(text: i.tl, key: Key(i));
  }

  Widget buildBody(String i) => _SingleExplorePage(i, key: Key(i));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ComicSource.sourcesChanged,
      builder: (context, version, _) => KeyedSubtree(
        key: ValueKey("explore_$version"),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final logic = StateController.find<ExplorePageController>();
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notifications) {
              if (notifications.metrics.axis == Axis.horizontal) {
                if (!showFB) {
                  setState(() {
                    showFB = true;
                  });
                }
                return true;
              }

              var current = notifications.metrics.pixels;

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
              return false;
            },
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: TabBarView(
                controller: logic.tabController,
                children: logic.pages.map((e) => buildBody(e)).toList(),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 88,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            reverseDuration: const Duration(milliseconds: 150),
            child: showFB ? buildFAB() : const SizedBox(),
            transitionBuilder: (widget, animation) {
              var tween = Tween<Offset>(
                  begin: const Offset(0, 1), end: const Offset(0, 0));
              return SlideTransition(
                position: tween.animate(animation),
                child: widget,
              );
            },
          ),
        )
      ],
    );
  }
}

class _SingleExplorePage extends StatefulWidget {
  const _SingleExplorePage(this.title, {super.key});

  final String title;

  @override
  State<_SingleExplorePage> createState() => _SingleExplorePageState();
}

class _SingleExplorePageState extends StateWithController<_SingleExplorePage> {
  late final ExplorePageData data;

  bool loading = true;

  String? message;

  List<ExplorePagePart>? parts;

  late final String comicSourceKey;

  int key = 0;

  @override
  void initState() {
    super.initState();
    for (var source in ComicSource.sources) {
      for (var d in source.explorePages) {
        if (d.title == widget.title) {
          data = d;
          comicSourceKey = source.key;
          return;
        }
      }
    }
    throw "Explore Page ${widget.title} Not Found!";
  }

  @override
  Widget build(BuildContext context) {
    if (data.loadMultiPart != null) {
      return buildMultiPart();
    } else if (data.loadPage != null) {
      return buildComicList();
    } else if (data.loadMixed != null) {
      return _MixedExplorePage(
        data,
        comicSourceKey,
        key: ValueKey(key),
      );
    } else if (data.overridePageBuilder != null) {
      return TopInsetPadding(
        key: ValueKey(key),
        child: Builder(
          builder: (context) {
            return data.overridePageBuilder!(context);
          },
        ),
      );
    } else {
      return const TopInsetPadding(
        child: Center(child: Text("Empty Page")),
      );
    }
  }

  Widget buildComicList() =>
      _ComicList(data.loadPage!, tag.toString(), comicSourceKey);

  void load() async {
    var res = await data.loadMultiPart!();
    loading = false;
    if (mounted) {
      setState(() {
        if (res.error) {
          message = res.errorMessageWithoutNull;
        } else {
          parts = res.data;
        }
      });
    }
  }

  Widget buildMultiPart() {
    if (loading) {
      load();
      return const TopInsetPadding(
        child: Center(child: MiuixCircularProgressIndicator()),
      );
    } else if (message != null) {
      return TopInsetPadding(
        child: NetworkError(
          message: message!,
          retry: refresh,
          withAppbar: false,
        ),
      );
    } else {
      return buildPage();
    }
  }

  Widget buildPage() {
    return SmoothCustomScrollView(
      slivers: [const TopInsetSliver(), ..._buildPage()],
    );
  }

  Iterable<Widget> _buildPage() sync* {
    for (var part in parts!) {
      yield* _buildExplorePagePart(part, comicSourceKey);
    }
    yield const SliverToBoxAdapter(
      child: SizedBox(height: 100),
    );
  }

  @override
  Object? get tag => widget.title;

  @override
  void refresh() {
    message = null;
    if (data.loadMultiPart != null) {
      setState(() {
        loading = true;
      });
    } else if (data.loadPage != null) {
      StateController.findOrNull<ComicsPageLogic>(tag: tag.toString())
          ?.refresh();
    } else {
      setState(() {
        key++;
      });
    }
  }
}

class _ComicList extends ComicsPage<BaseComic> {
  const _ComicList(this.builder, this.tag, this.sourceKey);

  @override
  final String tag;

  final ComicListBuilder builder;

  @override
  final String sourceKey;

  @override
  Future<Res<List<BaseComic>>> getComics(int i) {
    return builder(i);
  }

  @override
  String? get title => null;

  @override
  // 顶栏占位由 ComicsPage 统一插入（滚动态用吸顶占位，加载/出错态用 SizedBox）。
  Widget? get header => const SliverToBoxAdapter(child: SizedBox(height: 12));
}

class _MixedExplorePage extends StatefulWidget {
  const _MixedExplorePage(this.data, this.sourceKey, {super.key});

  final ExplorePageData data;

  final String sourceKey;

  @override
  State<_MixedExplorePage> createState() => _MixedExplorePageState();
}

class _MixedExplorePageState
    extends MultiPageLoadingState<_MixedExplorePage, Object> {
  Iterable<Widget> buildSlivers(BuildContext context, List<Object> data) sync* {
    List<BaseComic> cache = [];
    for (var part in data) {
      if (part is ExplorePagePart) {
        if (cache.isNotEmpty) {
          yield SliverGridComics(
            comics: (cache),
            sourceKey: widget.sourceKey,
          );
          yield const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: MiuixHorizontalDivider()));
          cache.clear();
        }
        yield* _buildExplorePagePart(part, widget.sourceKey);
        yield const SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: MiuixHorizontalDivider()));
      } else {
        cache.addAll(part as List<BaseComic>);
      }
    }
    if (cache.isNotEmpty) {
      yield SliverGridComics(
        comics: (cache),
        sourceKey: widget.sourceKey,
      );
    }
  }

  @override
  Widget buildContent(BuildContext context, List<Object> data) {
    return SmoothCustomScrollView(
      slivers: [
        const TopInsetSliver(),
        ...buildSlivers(context, data),
        if (haveNextPage) const ListLoadingIndicator().toSliver()
      ],
    );
  }

  @override
  Future<Res<List<Object>>> loadData(int page) async {
    var res = await widget.data.loadMixed!(page);
    if (res.error) {
      return res;
    }
    for (var element in res.data) {
      if (element is! ExplorePagePart && element is! List<BaseComic>) {
        return const Res.error("function loadMixed return invalid data");
      }
    }
    return res;
  }
}

/// Strip JM home-section instructional suffixes like 「→右滑看更多→」 from titles.
String cleanExplorePartTitle(String raw) {
  var t = raw.trim();
  if (t.contains("連載更新") || t.contains("连载更新")) {
    return "连载更新".tl;
  }
  const suffixes = <String>[
    "→右滑看更多→",
    "->右滑看更多->",
    "→右滑查看更多→",
    "->右滑查看更多->",
    "右滑查看更多",
    "右滑看更多",
    "→",
    "->",
  ];
  for (final s in suffixes) {
    t = t.replaceAll(s, "");
  }
  return t.trim();
}

Iterable<Widget> _buildExplorePagePart(
    ExplorePagePart part, String sourceKey) sync* {
  Widget buildTitle(ExplorePagePart part) {
    // 分区标题吸顶；被下一分区标题推走。禁漫 API 标题常带「右滑看更多」提示文案，这里剥掉。
    final titleText = cleanExplorePartTitle(part.title);
    Widget? trailing;
    if (part.viewMore != null) {
      trailing = Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return MiuixPressable(
          shape: const StadiumBorder(),
          onPressed: () {
            var navContext = App.mainNavigatorKey!.currentContext!;
            if (part.viewMore!.startsWith("search:")) {
              navContext.to(
                () => SearchResultPage(
                  keyword: part.viewMore!.replaceFirst("search:", ""),
                  sourceKey: sourceKey,
                ),
              );
            } else if (part.viewMore!.startsWith("category:")) {
              var cp = part.viewMore!.replaceFirst("category:", "");
              var c = cp.split('@').first;
              String? p = cp.split('@').last;
              if (p == c) {
                p = null;
              }
              // 二级页标题用清洗后的文案；加载仍走 param（分区 id/slug）。
              navContext.to(
                () => CategoryComicsPage(
                  category: titleText.isNotEmpty ? titleText : cleanExplorePartTitle(c),
                  categoryKey:
                      ComicSource.find(sourceKey)!.categoryData!.key,
                  param: p,
                ),
              );
            }
          },
          child: Container(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: stickyCapsuleColor(context),
            ),
            padding: kStickyCapsulePadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "查看更多".tl,
                  style: TextStyle(
                    fontSize: kStickyCapsuleFontSize,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                    height: 1.15,
                  ),
                ),
                MiuixIcon(
                  vector: MiuixIcons.os4.chevronForward,
                  size: kStickyCapsuleIconSize,
                  tint: scheme.primary,
                ),
              ],
            ),
          ),
        );
      });
    }
    return StickySectionHeader(title: titleText, trailing: trailing);
  }
  Widget buildComics(ExplorePagePart part) {
    return SliverGridComics(comics: part.comics, sourceKey: sourceKey);
  }

  yield MultiSliver(
    pushPinnedChildren: true,
    children: [buildTitle(part), buildComics(part)],
  );
}
