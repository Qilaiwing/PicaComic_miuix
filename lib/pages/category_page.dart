import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:flutter/material.dart';
import "package:sliver_tools/sliver_tools.dart";
import 'package:pica_comic/pages/ranking_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/tools/translations.dart';

class CategoryPageController extends StateController {
  List<String> categories = [];
  late TabController tabController;

  void init(TickerProvider vsync) {
    String? previous;
    try {
      previous = categories[tabController.index];
    } catch (_) {}
    categories = appdata.appSettings.categoryPages;
    var allCategories = ComicSource.sources
        .map((e) => e.categoryData?.key)
        .where((element) => element != null)
        .map((e) => e!)
        .toList();
    categories =
        categories.where((element) => allCategories.contains(element)).toList();
    var initial = previous == null ? 0 : categories.indexOf(previous);
    tabController = TabController(
        length: categories.length,
        vsync: vsync,
        initialIndex: initial < 0 ? 0 : initial);
  }
}

class AllCategoryPage extends StatelessWidget {
  const AllCategoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ComicSource.sourcesChanged,
      builder: (context, version, _) {
        final logic = StateController.find<CategoryPageController>();
        return Material(
          key: ValueKey("category_$version"),
          color: Colors.transparent,
          child: TabBarView(
            controller: logic.tabController,
            children: logic.categories.map((e) => CategoryPage(e)).toList(),
          ),
        );
      },
    );
  }
}

typedef ClickTagCallback = void Function(String, String?);

class CategoryPage extends StatelessWidget {
  const CategoryPage(this.category, {super.key});

  final String category;

  CategoryData get data => getCategoryDataWithKey(category);

  String findComicSourceKey() {
    for (var source in ComicSource.sources) {
      if (source.categoryData?.key == category) {
        return source.key;
      }
    }
    return "";
  }

  void handleClick(
    String tag,
    String? param,
    String type,
    String namespace,
    String categoryKey,
  ) {
    if (type == 'search') {
      App.mainNavigatorKey?.currentContext?.to(
        () => SearchResultPage(
          keyword: tag,
          options: const [],
          sourceKey: findComicSourceKey(),
        ),
      );
    } else if (type == "search_with_namespace") {
      if (tag.contains(" ")) {
        tag = '"$tag"';
      }
      App.mainNavigatorKey?.currentContext?.to(
        () => SearchResultPage(
          keyword: "$namespace:$tag",
          options: const [],
          sourceKey: findComicSourceKey(),
        ),
      );
    } else if (type == "category") {
      App.mainNavigatorKey!.currentContext!.to(
        () => CategoryComicsPage(
          category: tag,
          categoryKey: categoryKey,
          param: param,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var children = <Widget>[];
    if (data.enableRankingPage || data.buttons.isNotEmpty) {
      children.add(
        _categorySection(
          "热门推荐".tl,
           Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (data.enableRankingPage)
                  buildTag("排行榜".tl, (p0, p1) {
                    context
                        .to(() => RankingPage(sourceKey: findComicSourceKey()));
                  }),
                for (var buttonData in data.buttons)
                  buildTag(buttonData.label.tl, (p0, p1) => buttonData.onTap())
              ],
            ),
          ),
        ),
      );
    }

    for (var part in data.categories) {
      if (part.enableRandom) {
        children.add(StatefulBuilder(builder: (context, updater) {
          return _categorySection(
            part.title,
            buildTagsWithParams(
              part.categories,
              part.categoryParams,
              part.title,
              (key, param) => handleClick(
                key,
                param,
                part.categoryType,
                part.title,
                category,
              ),
            ),
            trailing: Builder(builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return MiuixPressable(
                shape: const StadiumBorder(),
                onPressed: () => updater(() {}),
                child: Container(
                  width: kStickyCapsuleRefreshExtent,
                  height: kStickyCapsuleRefreshExtent,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: stickyCapsuleColor(context),
                  ),
                  child: Icon(
                    Icons.refresh,
                    size: kStickyCapsuleIconSize,
                    color: scheme.primary,
                  ),
                ),
              );
            }),
          );
        }));
      } else {
        children.add(
          _categorySection(
            part.title,
            buildTagsWithParams(
              part.categories,
              part.categoryParams,
              part.title,
              (tag, param) => handleClick(
                tag,
                param,
                part.categoryType,
                part.title,
                data.key,
              ),
            ),
          ),
        );
      }
    }
    // 每个分组标题吸顶（毛玻璃，压住内容时才模糊），下一组的标题会把它顶走。
    return CustomScrollView(
      slivers: [
        const TopInsetSliver(),
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        ...children,
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Widget buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title.tl,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    );
  }


  Widget buildTagsWithParams(
    List<String> tags,
    List<String>? params,
    String? namespace,
    ClickTagCallback onClick,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: List<Widget>.generate(
          tags.length,
          (index) => buildTag(
            tags[index],
            onClick,
            namespace,
            params?.elementAtOrNull(index),
          ),
        ),
      ),
    );
  }

  Widget buildTag(String tag, ClickTagCallback onClick,
      [String? namespace, String? param]) {
    String translateTag(String tag) {
      if (enableTranslation) {
        if (namespace != null) {
          tag = TagsTranslation.translationTagWithNamespace(tag, namespace);
        } else {
          tag = tag.translateTagsToCN;
        }
      }
      return tag;
    }

    final isDark = Theme.of(App.globalContext!).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
      child: MiuixPressable(
          shape: const StadiumBorder(),
          onPressed: () => onClick(tag, param),
          child: Container(
            decoration: ShapeDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F4),
              shape: StadiumBorder(
                side: BorderSide(
                  color: isDark
                      ? const Color(0x18FFFFFF)
                      : const Color(0x0C000000),
                  width: 0.6,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              translateTag(tag),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          )),
    );
  }

  bool get enableTranslation => App.locale.languageCode == 'zh';
}

/// Frosted sticky section header + the group's card body.
Widget _categorySection(String title, Widget body, {Widget? trailing}) {
  return MultiSliver(pushPinnedChildren: true, children: [
    StickySectionHeader(title: title.tl, trailing: trailing),
    SliverToBoxAdapter(
      child: _CategoryGroupCard(title: title, showTitle: false, child: body),
    ),
  ]);
}

class _CategoryGroupCard extends StatelessWidget {
  const _CategoryGroupCard({
    required this.title,
    required this.child,
    this.showTitle = true,
  });

  final bool showTitle;

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: ShapeDecoration(
        shape: MiuixSquircleBorder(
          cornerRadius: 18,
          side: BorderSide(
            color: isDark ? const Color(0x18FFFFFF) : const Color(0x0A000000),
            width: 0.6,
          ),
        ),
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.14 : 0.025),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Row(
              children: [
                Text(
                  title.tl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
