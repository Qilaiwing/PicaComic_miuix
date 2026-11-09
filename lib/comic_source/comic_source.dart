library comic_source;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/update.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';
import '../base.dart';
import '../foundation/js_engine.dart';
import '../network/base_comic.dart';
import '../network/res.dart';
import 'built_in/ehentai.dart';
import 'built_in/hitomi.dart';
import 'built_in/ht_manga.dart';
import 'built_in/jm.dart';
import 'built_in/nhentai.dart';
import 'built_in/picacg.dart';
import 'package:pica_comic/pages/js_web_login.dart';

part 'category.dart';

part 'favorites.dart';

part 'parser.dart';

/// build comic list, [Res.subData] should be maxPage or null if there is no limit.
typedef ComicListBuilder = Future<Res<List<BaseComic>>> Function(int page);

typedef LoginFunction = Future<Res<bool>> Function(String, String);

typedef LoadComicFunc = Future<Res<ComicInfoData>> Function(String id);

typedef LoadComicPagesFunc = Future<Res<List<String>>> Function(
    String id, String? ep);

typedef CommentsLoader = Future<Res<List<Comment>>> Function(
    String id, String? subId, int page, String? replyTo);

typedef SendCommentFunc = Future<Res<bool>> Function(
    String id, String? subId, String content, String? replyTo);

typedef GetImageLoadingConfigFunc = Map<String, dynamic> Function(
    String imageKey, String comicId, String epId)?;
typedef GetThumbnailLoadingConfigFunc = Map<String, dynamic> Function(
    String imageKey)?;

class ComicSource {
  static final builtIn = [picacg, ehentai, jm, hitomi, htManga, nhentai];

  static List<ComicSource> sources = [];

  static ComicSource? find(String key) =>
      sources.firstWhereOrNull((element) => element.key == key);

  static ComicSource? fromIntKey(int key) =>
      sources.firstWhereOrNull((element) => element.key.hashCode == key);

  /// 在所有已安装的源（含已停用的内置源 / JS 源）中查找，仅用于显示名称等元数据
  static ComicSource? fromIntKeyIncludingDisabled(int key) =>
      fromIntKey(key) ??
      disabledJsSources.firstWhereOrNull((e) => e.key.hashCode == key) ??
      builtIn.firstWhereOrNull((e) => e.key.hashCode == key);

  /// 历史/别名 key → 规范 ComicSource.key（图片收藏 id 等曾用过不同大小写）
  static const Map<String, String> keyAliases = {
    "htManga": "htmanga",
  };

  /// 将可能的别名 / 大小写差异规范成 ComicSource.key；无法识别则原样返回
  static String canonicalizeKey(String key) {
    final aliased = keyAliases[key];
    if (aliased != null) return aliased;
    final lower = key.toLowerCase();
    for (final e in keyAliases.entries) {
      if (e.key.toLowerCase() == lower || e.value.toLowerCase() == lower) {
        return e.value;
      }
    }
    ComicSource? hit(bool Function(ComicSource s) test) =>
        sources.firstWhereOrNull(test) ??
        disabledJsSources.firstWhereOrNull(test) ??
        builtIn.firstWhereOrNull(test);
    final byCase = hit((s) => s.key.toLowerCase() == lower);
    return byCase?.key ?? key;
  }

  static ComicSource? findIncludingDisabled(String key) {
    final canon = canonicalizeKey(key);
    return find(canon) ??
        disabledJsSources.firstWhereOrNull((e) => e.key == canon) ??
        builtIn.firstWhereOrNull((e) => e.key == canon) ??
        find(key) ??
        disabledJsSources.firstWhereOrNull((e) => e.key == key) ??
        builtIn.firstWhereOrNull((e) => e.key == key) ??
        sources.firstWhereOrNull(
            (e) => e.key.toLowerCase() == key.toLowerCase()) ??
        disabledJsSources.firstWhereOrNull(
            (e) => e.key.toLowerCase() == key.toLowerCase()) ??
        builtIn.firstWhereOrNull(
            (e) => e.key.toLowerCase() == key.toLowerCase());
  }

  /// 按 key 查找显示名称（含已停用的源、别名与大小写差异），找不到返回 null
  static String? displayNameOf(String key) {
    return findIncludingDisabled(key)?.name.tl;
  }

  /// 从 `sourceKey-comicId` 复合 id 取出源 key（最长前缀匹配，兼容 comicId 含 `-`）
  static String sourceKeyFromCompoundId(String id) {
    final known = <String>{
      ...sources.map((e) => e.key),
      ...disabledJsSources.map((e) => e.key),
      ...builtIn.map((e) => e.key),
      ...keyAliases.keys,
      ...keyAliases.values,
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in known) {
      if (id == k || id.startsWith("$k-")) {
        return k;
      }
    }
    final i = id.indexOf("-");
    return i <= 0 ? id : id.substring(0, i);
  }

  static Future<void> init() async {
    for (var source in builtInSources) {
      if (appdata.appSettings.isComicSourceEnabled(source)) {
        var s = builtIn.firstWhere((e) => e.key == source);
        sources.add(s);
        await s.loadData();
        s.initData?.call(s);
      } else {
        // 停用的内置源仍加载账号数据，以便在账号管理中显示
        var s = builtIn.firstWhere((e) => e.key == source);
        try {
          await s.loadData();
        } catch (e) {
          // ignore
        }
      }
    }
    final path = "${App.dataPath}/comic_source";
    if (!(await Directory(path).exists())) {
      await Directory(path).create(recursive: true);
    }
    disabledJsSources.clear();
    var disabled = await _readDisabledJs(path);
    await for (var entity in Directory(path).list()) {
      if (entity is File && entity.path.endsWith(".js")) {
        try {
          var source = await ComicSourceParser()
              .parse(await entity.readAsString(), entity.absolute.path);
          if (disabled.contains(source.key)) {
            disabledJsSources.add(source);
            continue;
          }
          sources.add(source);
        } catch (e, s) {
          log("$e\n$s", "ComicSource", LogLevel.error);
        }
      }
    }
  }

  /// 已启用的漫画源发生变化（开关/添加/删除）时递增，页面监听后即时刷新
  static final ValueNotifier<int> sourcesChanged = ValueNotifier(0);

  static void notifySourcesChanged() => sourcesChanged.value++;

  /// 账号管理显示的源：已启用的 + 停用的内置源 + 停用的 JS 源
  static List<ComicSource> get allSourcesForAccounts {
    var result = <ComicSource>[];
    for (var key in builtInSources) {
      var s = builtIn.firstWhereOrNull((e) => e.key == key);
      if (s != null) result.add(s);
    }
    for (var s in sources) {
      if (!s.isBuiltIn && result.every((e) => e.key != s.key)) result.add(s);
    }
    for (var s in disabledJsSources) {
      if (result.every((e) => e.key != s.key)) result.add(s);
    }
    return result;
  }

  /// 已停用的 JS 漫画源：脚本与数据保留，只是不加入 [sources]
  static final List<ComicSource> disabledJsSources = [];

  static const _disabledJsFile = ".disabled_js";

  static Future<Set<String>> _readDisabledJs(String path) async {
    try {
      var f = File("$path/$_disabledJsFile");
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as List)
          .map((e) => e.toString())
          .toSet();
    } catch (e) {
      return {};
    }
  }

  static bool isJsSourceEnabled(String key) =>
      disabledJsSources.every((s) => s.key != key);

  /// 启用/停用 JS 漫画源，状态写入 comic_source/.disabled_js 持久保存
  static Future<void> setJsSourceEnabled(ComicSource source, bool enabled) async {
    final path = "${App.dataPath}/comic_source";
    var disabled = await _readDisabledJs(path);
    if (enabled) {
      disabled.remove(source.key);
      disabledJsSources.removeWhere((s) => s.key == source.key);
      if (sources.every((s) => s.key != source.key)) sources.add(source);
    } else {
      disabled.add(source.key);
      sources.removeWhere((s) => s.key == source.key);
      if (disabledJsSources.every((s) => s.key != source.key)) {
        disabledJsSources.add(source);
      }
    }
    await File("$path/$_disabledJsFile")
        .writeAsString(jsonEncode(disabled.toList()));
  }

  static String? _scriptVersion(String code) =>
      RegExp(r'version\s*=\s*"([^"]+)"').firstMatch(code)?.group(1);
  static String? scriptVersionOf(String code) => _scriptVersion(code);

  /// 用远程脚本替换本地脚本并重新加载该源
  static Future<void> applyScriptUpdate(ComicSource old, String code) async {
    var newSource = await ComicSourceParser().parse(code, old.filePath, replaceKey: old.key);
    await File(old.filePath).writeAsString(code);
    sources.remove(old);
    sources.removeWhere((s) => s.key == newSource.key && s != newSource);
    sources.add(newSource);
    notifySourcesChanged();
  }

  /// 彻底删除一个 JS 漫画源：脚本、账号/设置数据、停用记录与 JS 运行时对象
  static Future<void> deleteJsSource(ComicSource source) async {
    final path = "${App.dataPath}/comic_source";
    final key = source.key;
    sources.removeWhere((s) => s.key == key);
    disabledJsSources.removeWhere((s) => s.key == key);
    try {
      JsEngine().runCode("delete ComicSource.sources.$key;");
    } catch (_) {}
    for (var f in [File(source.filePath), File("$path/$key.data")]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e, s) {
        log("$e\n$s", "ComicSource", LogLevel.error);
      }
    }
    try {
      var disabled = await _readDisabledJs(path);
      if (disabled.remove(key)) {
        await File("$path/$_disabledJsFile")
            .writeAsString(jsonEncode(disabled.toList()));
      }
    } catch (_) {}
    notifySourcesChanged();
  }

  /// 把漫画源的探索页、分类页、网络收藏加入用户的页面列表
  static void addPagesOf(ComicSource source) {
    var explorePages = appdata.appSettings.explorePages;
    var categoryPages = appdata.appSettings.categoryPages;
    var networkFavorites = appdata.appSettings.networkFavorites;
    explorePages.removeWhere((e) => e.isEmpty);
    categoryPages.removeWhere((e) => e.isEmpty);
    networkFavorites.removeWhere((e) => e.isEmpty);
    for (var page in source.explorePages) {
      if (!explorePages.contains(page.title)) explorePages.add(page.title);
    }
    if (source.categoryData != null &&
        !categoryPages.contains(source.categoryData!.key)) {
      categoryPages.add(source.categoryData!.key);
    }
    if (source.favoriteData != null &&
        !networkFavorites.contains(source.favoriteData!.key)) {
      networkFavorites.add(source.favoriteData!.key);
    }
    appdata.appSettings.explorePages = explorePages;
    appdata.appSettings.categoryPages = categoryPages;
    appdata.appSettings.networkFavorites = networkFavorites;
    appdata.updateSettings();
  }

  static Future reload() async {
    sources.clear();
    JsEngine().runCode("ComicSource.sources = {};");
    await init();
  }

  /// Name of this source.
  final String name;

  /// Identifier of this source.
  final String key;

  int get intKey {
    return key.hashCode;
  }

  /// Account config.
  final AccountConfig? account;

  /// Category data used to build a static category tags page.
  final CategoryData? categoryData;

  /// Category comics data used to build a comics page with a category tag.
  final CategoryComicsData? categoryComicsData;

  /// Favorite data used to build favorite page.
  final FavoriteData? favoriteData;

  /// Explore pages.
  final List<ExplorePageData> explorePages;

  /// Search page.
  final SearchPageData? searchPageData;

  /// Settings.
  final List<SettingItem> settings;

  /// Load comic info.
  final LoadComicFunc? loadComicInfo;

  /// Load comic pages.
  final LoadComicPagesFunc? loadComicPages;

  final Map<String, dynamic> Function(
      String imageKey, String comicId, String epId)? getImageLoadingConfig;

  final Map<String, dynamic> Function(String imageKey)?
      getThumbnailLoadingConfig;

  final String? matchBriefIdReg;

  var data = <String, dynamic>{};

  /// JS 漫画源在 `settings` 字段中声明的设置项（key -> 配置）。
  Map<String, dynamic> jsSettings = {};

  bool get isLogin => data["account"] != null;

  final String filePath;

  final String url;

  final String version;

  final CommentsLoader? commentsLoader;

  final SendCommentFunc? sendCommentFunc;

  final RegExp? idMatcher;

  final Widget Function(BuildContext context, String id, String? cover)? comicPageBuilder;

  Future<void> loadData() async {
    var file = File("${App.dataPath}/comic_source/$key.data");
    if (await file.exists()) {
      data = Map.from(jsonDecode(await file.readAsString()));
    }
  }

  bool _isSaving = false;
  bool _haveWaitingTask = false;

  Future<void> saveData() async {
    if (_haveWaitingTask) return;
    while (_isSaving) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 20));
      _haveWaitingTask = false;
    }
    _isSaving = true;
    var file = File("${App.dataPath}/comic_source/$key.data");
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(data));
    _isSaving = false;
  }

  /// 最近一次自动重新登录失败的原因（用于判断是否需要滑块验证等交互式处理）。
  String? lastReLoginError;

  Future<bool> reLogin() async {
    lastReLoginError = null;
    if (data["account"] == null) {
      lastReLoginError = "无账号数据";
      return false;
    }
    final List accountData = data["account"];
    var res = await account!.login!(accountData[0], accountData[1]);
    if (res.error) {
      lastReLoginError = res.errorMessage ?? "Error";
      Log.error("Failed to re-login", lastReLoginError!);
    }
    return !res.error;
  }

  // only for built-in comic sources
  final FutureOr<void> Function(ComicSource source)? initData;

  bool get isBuiltIn => filePath == 'built-in';

  final Widget Function(BuildContext, BaseComic, List<ComicTileMenuOption>?)?
      comicTileBuilderOverride;

  ComicSource(
      this.name,
      this.key,
      this.account,
      this.categoryData,
      this.categoryComicsData,
      this.favoriteData,
      this.explorePages,
      this.searchPageData,
      this.settings,
      this.loadComicInfo,
      this.loadComicPages,
      this.getImageLoadingConfig,
      this.getThumbnailLoadingConfig,
      this.matchBriefIdReg,
      this.filePath,
      this.url,
      this.version,
      this.commentsLoader,
      this.sendCommentFunc)
      : initData = null,
        comicTileBuilderOverride = null,
        idMatcher = null,
        comicPageBuilder = null;

  ComicSource.named({
    required this.name,
    required this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages = const [],
    this.searchPageData,
    this.settings = const [],
    this.loadComicInfo,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.matchBriefIdReg,
    required this.filePath,
    this.url = '',
    this.version = '',
    this.commentsLoader,
    this.sendCommentFunc,
    this.initData,
    this.comicTileBuilderOverride,
    this.idMatcher,
    this.comicPageBuilder,
  });

  ComicSource.unknown(this.key)
      : name = "Unknown",
        account = null,
        categoryData = null,
        categoryComicsData = null,
        favoriteData = null,
        explorePages = [],
        searchPageData = null,
        settings = [],
        loadComicInfo = null,
        loadComicPages = null,
        getImageLoadingConfig = null,
        getThumbnailLoadingConfig = null,
        matchBriefIdReg = null,
        filePath = "",
        url = "",
        version = "",
        commentsLoader = null,
        sendCommentFunc = null,
        initData = null,
        comicTileBuilderOverride = null,
        idMatcher = null,
        comicPageBuilder = null;
}

class AccountConfig {
  final LoginFunction? login;

  /// 需要滑块/图形验证时的登录函数：额外接收一次性通行证。
  ///
  /// 部分站点（如绅士漫画）在登录提交前强制校验滑块拼图，普通 [login]
  /// 会返回「請先完成滑塊驗證」。实现该函数后，登录页会在首次失败且错误
  /// 提示需要验证时弹出验证弹窗，通过后带上通行证重试。
  final Future<Res<bool>> Function(String account, String pwd, String sliderPass)?
      loginWithSlider;

  final FutureOr<void> Function(BuildContext)? onLogin;

  final String? loginWebsite;

  final String? registerWebsite;

  final void Function() logout;

  final bool allowReLogin;

  final List<AccountInfoItem> infoItems;

  const AccountConfig(
      this.login, this.loginWebsite, this.registerWebsite, this.logout,
      {this.onLogin, this.loginWithSlider})
      : allowReLogin = true,
        infoItems = const [];

  const AccountConfig.named({
    this.login,
    this.loginWithSlider,
    this.loginWebsite,
    this.registerWebsite,
    required this.logout,
    this.onLogin,
    this.allowReLogin = true,
    this.infoItems = const [],
  });
}

class AccountInfoItem {
  final String title;
  final String Function()? data;
  final void Function()? onTap;
  final WidgetBuilder? builder;

  AccountInfoItem({required this.title, this.data, this.onTap, this.builder});
}

class LoadImageRequest {
  String url;

  Map<String, String> headers;

  LoadImageRequest(this.url, this.headers);
}

class ExplorePageData {
  final String title;

  final ExplorePageType type;

  final ComicListBuilder? loadPage;

  final Future<Res<List<ExplorePagePart>>> Function()? loadMultiPart;

  /// return a `List` contains `List<BaseComic>` or `ExplorePagePart`
  final Future<Res<List<Object>>> Function(int index)? loadMixed;

  final WidgetBuilder? overridePageBuilder;

  ExplorePageData(this.title, this.type, this.loadPage, this.loadMultiPart)
      : loadMixed = null,
        overridePageBuilder = null;

  ExplorePageData.named({
    required this.title,
    required this.type,
    this.loadPage,
    this.loadMultiPart,
    this.loadMixed,
    this.overridePageBuilder,
  });
}

class ExplorePagePart {
  final String title;

  final List<BaseComic> comics;

  /// If this is not null, the [ExplorePagePart] will show a button to jump to new page.
  ///
  /// Value of this field should match the following format:
  ///   - search:keyword
  ///   - category:categoryName
  ///
  /// End with `@`+`param` if the category has a parameter.
  final String? viewMore;

  const ExplorePagePart(this.title, this.comics, this.viewMore);
}

enum ExplorePageType {
  multiPageComicList,
  singlePageWithMultiPart,
  mixed,
  override,
}

typedef SearchFunction = Future<Res<List<BaseComic>>> Function(
    String keyword, int page, List<String> searchOption);

class SearchPageData {
  /// If this is not null, the default value of search options will be first element.
  final List<SearchOptions>? searchOptions;

  final Widget Function(BuildContext, List<String> initialValues, void Function(List<String>))?
      customOptionsBuilder;

  final Widget Function(String keyword, List<String> options)?
      overrideSearchResultBuilder;

  final SearchFunction? loadPage;

  final bool enableLanguageFilter;

  final bool enableTagsSuggestions;

  const SearchPageData(this.searchOptions, this.loadPage)
      : enableLanguageFilter = false,
        customOptionsBuilder = null,
        overrideSearchResultBuilder = null,
        enableTagsSuggestions = false;

  const SearchPageData.named({
    this.searchOptions,
    this.loadPage,
    this.enableLanguageFilter = false,
    this.customOptionsBuilder,
    this.overrideSearchResultBuilder,
    this.enableTagsSuggestions = false,
  });
}

class SearchOptions {
  final LinkedHashMap<String, String> options;

  final String label;

  const SearchOptions(this.options, this.label);

  String get defaultValue => options.keys.first;

  const SearchOptions.named({required this.options, required this.label});
}

class SettingItem {
  final String name;
  final String iconName;
  final SettingType type;
  final List<String>? options;

  const SettingItem(this.name, this.iconName, this.type, this.options);
}

enum SettingType {
  switcher,
  selector,
  input,
}

class ComicInfoData with HistoryMixin {
  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  final String? description;

  final Map<String, List<String>> tags;

  /// id-name
  final Map<String, String>? chapters;

  final List<String>? thumbnails;

  final Future<Res<List<String>>> Function(String id, int page)?
      thumbnailLoader;

  final int thumbnailMaxPage;

  final List<BaseComic>? suggestions;

  final String sourceKey;

  final String comicId;

  final bool? isFavorite;

  final String? subId;

  /// Optional score in stars (0-5), when the source provides one.
  final double? stars;

  /// Optional rating text from the source (e.g. "4.5").
  final String? rating;

  const ComicInfoData(
      this.title,
      this.subTitle,
      this.cover,
      this.description,
      this.tags,
      this.chapters,
      this.thumbnails,
      this.thumbnailLoader,
      this.thumbnailMaxPage,
      this.suggestions,
      this.sourceKey,
      this.comicId,
      {this.isFavorite,
      this.subId,
      this.stars,
      this.rating});

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "subTitle": subTitle,
      "cover": cover,
      "description": description,
      "tags": tags,
      "chapters": chapters,
      "sourceKey": sourceKey,
      "comicId": comicId,
      "isFavorite": isFavorite,
      "subId": subId,
      "stars": stars,
      "rating": rating,
    };
  }

  static Map<String, List<String>> _generateMap(Map<String, dynamic> map) {
    var res = <String, List<String>>{};
    map.forEach((key, value) {
      res[key] = List<String>.from(value);
    });
    return res;
  }

  ComicInfoData.fromJson(Map<String, dynamic> json)
      : title = json["title"],
        subTitle = json["subTitle"],
        cover = json["cover"],
        description = json["description"],
        tags = _generateMap(json["tags"]),
        chapters = Map<String, String>.from(json["chapters"]),
        sourceKey = json["sourceKey"],
        comicId = json["comicId"],
        thumbnails = null,
        thumbnailLoader = null,
        thumbnailMaxPage = 0,
        suggestions = null,
        isFavorite = json["isFavorite"],
        subId = json["subId"],
        stars = (json["stars"] as num?)?.toDouble(),
        rating = json["rating"] as String?;

  @override
  HistoryType get historyType => HistoryType(sourceKey.hashCode);

  @override
  String get target => comicId;
}

typedef CategoryComicsLoader = Future<Res<List<BaseComic>>> Function(
    String category, String? param, List<String> options, int page);

class CategoryComicsData {
  /// options
  final List<CategoryComicsOptions> options;

  /// [category] is the one clicked by the user on the category page.

  /// if [BaseCategoryPart.categoryParams] is not null, [param] will be not null.
  ///
  /// [Res.subData] should be maxPage or null if there is no limit.
  final CategoryComicsLoader load;

  final RankingData? rankingData;

  const CategoryComicsData(this.options, this.load, {this.rankingData});

  const CategoryComicsData.named({
    this.options = const [],
    required this.load,
    this.rankingData,
  });
}

class RankingData {
  final Map<String, String> options;

  final Future<Res<List<BaseComic>>> Function(String option, int page) load;

  const RankingData(this.options, this.load);

  const RankingData.named({
    required this.options,
    required this.load,
  });
}

class CategoryComicsOptions {
  /// Use a [LinkedHashMap] to describe an option list.
  /// key is for loading comics, value is the name displayed on screen.
  /// Default value will be the first of the Map.
  final LinkedHashMap<String, String> options;

  /// If [notShowWhen] contains category's name, the option will not be shown.
  final List<String> notShowWhen;

  final List<String>? showWhen;

  const CategoryComicsOptions(this.options, this.notShowWhen, this.showWhen);

  const CategoryComicsOptions.named({
    required this.options,
    this.notShowWhen = const [],
    this.showWhen,
  });
}

class Comment {
  final String userName;
  final String? avatar;
  final String content;
  final String? time;
  final int? replyCount;
  final String? id;

  const Comment(this.userName, this.avatar, this.content, this.time,
      this.replyCount, this.id);
}
