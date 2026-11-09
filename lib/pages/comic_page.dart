import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/comment.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/select_download_eps.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/foundation/image_loader/stream_image_provider.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/stack.dart' as stack;
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/favorites/local_favorites.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'show_image_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'dart:math' as math;

const double _kActionHeight = 48;
const double _kActionRadius = 16;

class ComicPage extends StatelessWidget {
  const ComicPage({
    super.key,
    required this.sourceKey,
    required this.id,
    this.cover,
  });

  final String sourceKey;

  final String id;

  final String? cover;

  @override
  Widget build(BuildContext context) {
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource?.comicPageBuilder != null) {
      return comicSource!.comicPageBuilder!(context, id, cover);
    }
    return _ComicPageImpl(
      sourceKey: sourceKey,
      id: id,
      comicCover: cover,
    );
  }
}

class _ComicPageImpl extends BaseComicPage<ComicInfoData> {
  const _ComicPageImpl(
      {required this.sourceKey, required this.id, this.comicCover});

  @override
  final String sourceKey;

  @override
  final String id;

  final String? comicCover;

  @override
  String? get cover => comicCover ?? data?.cover;

  @override
  void download() async {
    final downloadId = DownloadManager().generateId(sourceKey, id);
    final eps = data!.chapters?.values.toList();
    for (var i in DownloadManager().downloading) {
      if (i.id == downloadId) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    var downloaded = <int>[];
    if (DownloadManager().isExists(downloadId)) {
      if (eps == null) {
        showToast(message: "已下载".tl);
        return;
      }
      var downloadedComic = await DownloadManager().getComicOrNull(downloadId);
      downloaded.addAll(downloadedComic!.downloadedEps);
    } else {
      if (eps == null) {
        DownloadManager().addCustomDownload(data!, [0]);
        App.globalBack();
        showToast(message: "已加入下载队列".tl);
        return;
      }
    }
    if (UiMode.m1(App.globalContext!)) {
      showMiuixBottomSheet<void>(
          context: App.globalContext!,
          builder: (context, close) {
            return SizedBox(
                height: MediaQuery.of(context).size.height * 9 / 16,
                child: Material(
                    type: MaterialType.transparency,
                    child: SelectDownloadChapter(eps, (selectedEps) {
                      DownloadManager().addCustomDownload(data!, selectedEps);
                      App.globalBack();
                      showToast(message: "已加入下载队列".tl);
                    }, downloaded)));
          });
    } else {
      showSideBar(
          App.globalContext!,
          SelectDownloadChapter(eps, (selectedEps) {
            DownloadManager().addCustomDownload(data!, selectedEps);
            App.globalBack();
            showToast(message: "已加入下载队列".tl);
          }, downloaded),
          useSurfaceTintColor: true);
    }
  }

  @override
  EpsData? get eps {
    if (data!.chapters != null && data!.chapters!.isNotEmpty) {
      return EpsData(
        data!.chapters!.values.toList(),
        (ep) async {
          await History.findOrCreate(data!);
          App.globalTo(
            () => ComicReadingPage(
              CustomReadingData(
                data!.target,
                data!.title,
                ComicSource.find(sourceKey)!,
                data!.chapters,
              ),
              0,
              ep + 1,
            ),
          );
        },
      );
    }
    return null;
  }

  @override
  String? get introduction => data!.description;

  @override
  double? get stars => data?.stars;

  @override
  String? get ratingText => data?.rating;

  ComicSource? get comicSource => ComicSource.find(sourceKey);

  @override
  Future<Res<ComicInfoData>> loadData() async {
    if (comicSource == null) throw "Comic Source Not Found";
    var res = await comicSource!.loadComicInfo!(id);
    return res;
  }

  @override
  Future<bool> loadFavorite(ComicInfoData data) async {
    return data.isFavorite ?? false;
  }

  @override
  int? get pages => null;

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(
      () => ComicReadingPage(
        CustomReadingData(
          data!.target,
          data!.title,
          ComicSource.find(sourceKey)!,
          data!.chapters,
        ),
        history!.page,
        history.ep,
      ),
    );
  }

  @override
  Widget? recommendationBuilder(ComicInfoData data) {
    if (data.suggestions == null) return null;

    return SliverGridComics(comics: data.suggestions!, sourceKey: sourceKey);
  }

  @override
  String get source => comicSource!.name;

  @override
  String get tag => "$key comic page with id: $id";

  @override
  Map<String, List<String>>? get tags => data!.tags;

  @override
  void tapOnTag(String tag, String key) {
    context.to(
      () => SearchResultPage(
        keyword: tag,
        options: const [],
        sourceKey: sourceKey,
      ),
    );
  }

  @override
  ThumbnailsData? get thumbnailsCreator {
    if (data!.thumbnails == null && data!.thumbnailLoader == null) return null;

    return ThumbnailsData(
        data!.thumbnails ?? [],
        (page) =>
            data!.thumbnailLoader?.call(id, page) ??
            Future.value(const Res.error("")),
        data!.thumbnailMaxPage);
  }

  @override
  Widget thumbnailImageBuilder(int index, String imageUrl) {
    return Image(
      image: StreamImageProvider(
          () => ImageManager().getCustomThumbnail(imageUrl, sourceKey),
          imageUrl),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, err, d) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return ColoredBox(
          color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE8E8EC),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 28,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.55),
            ),
          ),
        );
      },
    );
  }

  @override
  String? get title => data?.title;

  @override
  FavoriteItem toLocalFavoriteItem() {
    var tags = <String>[];
    data!.tags.forEach((key, value) => tags.addAll(value));
    return FavoriteItem.fromBaseComic(CustomComic(data!.title,
        data!.subTitle ?? "", data!.cover, id, tags, "", sourceKey));
  }

  @override
  Widget? get uploaderInfo => null;

  @override
  bool? get favoriteOnPlatformInitial => data?.isFavorite;

  ComicPageLogic<ComicInfoData> get logic =>
      StateController.find<ComicPageLogic<ComicInfoData>>(tag: tag);

  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite:
          comicSource!.favoriteData != null && comicSource!.isLogin,
      needLoadFolderData: comicSource!.favoriteData?.multiFolder ?? false,
      folders: {
        if (!(comicSource!.favoriteData?.multiFolder ?? false))
          '0': comicSource!.name
      },
      foldersLoader: comicSource?.favoriteData?.loadFolders == null
          ? null
          : () => comicSource!.favoriteData!.loadFolders!(data!.comicId),
      initialFolder:
          (comicSource!.favoriteData?.multiFolder ?? false) ? null : '0',
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      favoriteOnPlatform: logic.favoriteOnPlatform,
      selectFolderCallback: (folder, type) async {
        if (type == 1) {
          LocalFavoritesManager().addComic(folder, toLocalFavoriteItem());
          return const Res(true);
        } else {
          var res = await comicSource!.favoriteData!.addOrDelFavorite!(
              id, folder, true);
          if (!comicSource!.favoriteData!.multiFolder && res.success) {
            logic.favoriteOnPlatform = true;
            update();
          }
          return res;
        }
      },
      cancelPlatformFavorite: () async {
        var res =
            await comicSource!.favoriteData!.addOrDelFavorite!(id, '0', false);
        if (res.success) {
          logic.favoriteOnPlatform = false;
        }
        return res;
      },
      cancelPlatformFavoriteWithFolder: (folder) {
        return comicSource!.favoriteData!.addOrDelFavorite!(id, folder, false);
      },
    ));
  }

  @override
  ActionFunc? get openComments => comicSource!.commentsLoader != null
      ? () {
          showSideBar(App.globalContext!,
              _CommentsPage(data: data!, source: comicSource!),
              title: "评论".tl);
        }
      : null;

  @override
  String get downloadedId => downloadManager.generateId(comicSource!.key, id);
}

class _CommentsPage extends StatefulWidget {
  const _CommentsPage({required this.data, required this.source, this.replyId});

  final ComicInfoData data;

  final ComicSource source;

  final String? replyId;

  @override
  State<_CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<_CommentsPage> {
  bool _loading = true;
  List<Comment>? _comments;
  String? _error;
  int _page = 1;
  int? maxPage;
  var controller = TextEditingController();
  bool sending = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    firstLoad();
  }

  void firstLoad() async {
    if (_started && _loading == false && _comments != null) return;
    _started = true;
    var res = await widget.source.commentsLoader!(
        widget.data.comicId, widget.data.subId, 1, widget.replyId);
    if (!mounted) return;
    if (res.error) {
      setState(() {
        _error = res.errorMessage;
        _loading = false;
      });
    } else {
      setState(() {
        _comments = res.data;
        _loading = false;
        maxPage = res.subData;
      });
    }
  }

  void loadMore() async {
    var res = await widget.source.commentsLoader!(
        widget.data.comicId, widget.data.subId, _page + 1, widget.replyId);
    if (!mounted) return;
    if (res.error) {
      showToast(message: res.errorMessage ?? "Unknown Error");
    } else {
      setState(() {
        _comments!.addAll(res.data);
        _page++;
        if (maxPage == null && res.data.isEmpty) {
          maxPage = _page;
        }
      });
    }
  }

  bool get _canSend => widget.source.sendCommentFunc != null;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: MiuixInfiniteProgressIndicator(),
      );
    } else if (_error != null) {
      return NetworkError(
        message: _error!,
        retry: () {
          setState(() {
            _loading = true;
            _error = null;
            _comments = null;
            _page = 1;
            maxPage = null;
            _started = false;
          });
          firstLoad();
        },
        withAppbar: false,
      );
    } else {
      final empty = _comments == null || _comments!.isEmpty;
      final bottomReserve = _canSend ? 78.0 : 58.0;
      return Stack(
        children: [
          Positioned.fill(
            child: empty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomReserve),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.45),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "暂无评论".tl,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    primary: false,
                    padding: EdgeInsets.only(top: 4, bottom: bottomReserve),
                    itemCount: _comments!.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _comments!.length) {
                        if (_page < (maxPage ?? _page + 1)) {
                          loadMore();
                          return const ListLoadingIndicator();
                        } else {
                          return const SizedBox(height: 8);
                        }
                      }

                      final c = _comments![index];
                      final enableReply = c.replyCount != null;
                      final replyTitle = "回复 · @name"
                          .tlParams({"name": c.userName});

                      return CommentTile(
                        leading: c.avatar == null
                            ? _avatarPlaceholder(context, c.userName)
                            : Container(
                                width: 40,
                                height: 40,
                                clipBehavior: Clip.antiAlias,
                                decoration: const ShapeDecoration(
                                  shape:
                                      MiuixSquircleBorder(cornerRadius: 12),
                                  color: Color(0x18000000),
                                ),
                                child: AnimatedImage(
                                  image: StreamImageProvider(
                                    () => ImageManager().getCustomThumbnail(
                                      c.avatar!,
                                      widget.data.sourceKey,
                                    ),
                                    c.avatar!,
                                  ),
                                ),
                              ),
                        avatarUrl: null,
                        name: c.userName,
                        time: c.time,
                        content: c.content,
                        comments: c.replyCount,
                        onTap: enableReply
                            ? () {
                                showSideBar(
                                  context,
                                  _CommentsPage(
                                    data: widget.data,
                                    source: widget.source,
                                    replyId: c.id,
                                  ),
                                  title: replyTitle,
                                );
                              }
                            : null,
                      );
                    },
                  ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: buildBottom(context),
          ),
        ],
      );
    }
  }

  Widget _avatarPlaceholder(BuildContext context, String name) {
    final ch = name.trim().isEmpty ? "?" : name.trim().substring(0, 1);
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: const MiuixSquircleBorder(cornerRadius: 12),
        color: primary.withOpacity(0.14),
      ),
      child: Text(
        ch.toUpperCase(),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
    );
  }

  Widget buildBottom(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF5F5F7);
    final shadow = [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];

    if (!_canSend) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          shape: const MiuixSquircleBorder(cornerRadius: 16),
          color: barColor,
          shadows: shadow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            "此源仅支持查看评论".tl,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.75),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const MiuixSquircleBorder(cornerRadius: 18),
        color: barColor,
        shadows: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: MiuixTextField(
                controller: controller,
                label: "评论...".tl,
                useLabelAsPlaceholder: true,
                minLines: 1,
                maxLines: 4,
              ),
            ),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: MiuixInfiniteProgressIndicator(size: 20),
                    ),
                  )
                : MiuixIconButton(
                    minWidth: 36,
                    minHeight: 36,
                    child: MiuixIcon(
                      vector: MiuixIcons.extended.byName('send') ??
                          MiuixIcons.os4.share,
                      size: 19,
                      tint: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () async {
                      if (controller.text.isEmpty) return;
                      setState(() => sending = true);
                      var b = await widget.source.sendCommentFunc!(
                          widget.data.comicId,
                          widget.data.subId,
                          controller.text,
                          widget.replyId);
                      if (!mounted) return;
                      if (!b.error) {
                        controller.text = "";
                        setState(() {
                          sending = false;
                          _loading = true;
                          _comments = null;
                          _page = 1;
                          maxPage = null;
                          _started = false;
                        });
                        firstLoad();
                      } else {
                        showToast(message: b.errorMessage ?? "Error");
                        setState(() => sending = false);
                      }
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class EpsData {
  /// episodes text
  final List<String> eps;

  /// callback when a episode button is tapped
  final void Function(int) onTap;

  /// comic episode data
  const EpsData(this.eps, this.onTap);
}

class ThumbnailsData {
  List<String> thumbnails;
  int current = 1;
  final int maxPage;
  final Future<Res<List<String>>> Function(int page) load;
  bool isGetting = false;

  Future<void> get(void Function() update) async {
    if (current >= maxPage || isGetting == true) {
      return;
    }
    isGetting = true;
    var res = await load(current + 1);
    if (res.success) {
      thumbnails.addAll(res.data);
      current++;
      update();
    } else {
      Log.error("Network", "Failed to load thumbnails: ${res.errorMessage}");
    }
    isGetting = false;
  }

  ThumbnailsData(this.thumbnails, this.load, this.maxPage);
}

class ComicPageLogic<T extends Object> extends StateController {
  bool loading = true;
  T? data;
  String? message;
  bool showAppbarTitle = false;
  ScrollController controller = ScrollController();
  ThumbnailsData? thumbnailsData;
  double? width;
  double? height;
  bool favorite = false;
  History? history;
  bool reverseEpsOrder = false;
  bool showFullEps = false;

  /// Section fold state on the detail page.
  bool sectionIntroExpanded = true;
  bool sectionPreviewExpanded = true;
  bool sectionChaptersExpanded = true;
  bool sectionChaptersDefaultApplied = false;
  bool sectionRecommendExpanded = true;
  int colorIndex = 0;
  bool? favoriteOnPlatform;

  /// Prevents stampeding the comic-info API when the loading builder rebuilds
  /// (route transition / LayoutBuilder). Concurrent TLS handshakes to the same
  /// host often surface as "Connection terminated during handshake".
  bool _fetching = false;

  void get(Future<Res<T>> Function() loadData,
      Future<bool> Function(T) loadFavorite, String Function() getId) async {
    if (_fetching) return;
    _fetching = true;
    try {
      var [res, _] = await Future.wait(
          [loadData(), Future.delayed(const Duration(milliseconds: 300))]);
      if (res.error) {
        message = res.errorMessage;
        if (message == "Exit") {
          loading = false;
          return;
        }
      } else {
        data = res.data;
        favorite = await loadFavorite(res.data);
      }
      loading = false;
      history = await HistoryManager().find(getId());
      update();
    } finally {
      _fetching = false;
    }
  }

  void refresh_() {
    data = null;
    message = null;
    loading = true;
    _fetching = false;
    update();
  }

  updateHistory(History? newHistory) {
    if (newHistory != null) {
      history = newHistory;
      update();
    }
  }
}

abstract class BaseComicPage<T extends Object> extends StatelessWidget {
  /// comic info page, show comic's detailed information,
  /// and allow user to download or read comic.
  const BaseComicPage({super.key});

  ComicPageLogic<T> get _logic =>
      StateController.find<ComicPageLogic<T>>(tag: tag);

  /// title
  String? get title;

  /// tags
  Map<String, List<String>>? get tags;

  /// load comic data
  Future<Res<T>> loadData();

  /// get comic data
  @nonVirtual
  T? get data => _logic.data;

  /// Used by StateController.
  ///
  /// This should be a unique identifier,
  /// to prevent loading same data when user open more than one comic page.
  String get tag;

  /// comic total page
  ///
  /// when not null, it will be display at the end of the title.
  int? get pages;

  /// link to comic cover.
  String? get cover;

  /// callback when user tap on a tag
  void tapOnTag(String tag, String key);

  void read(History? history);

  void download();

  void openFavoritePanel();

  ActionFunc? get openComments => null;

  String? get commentsCount => null;

  ActionFunc? get onLike => null;

  bool get isLiked => false;

  String? get likeCount => null;

  /// display uploader info
  Widget? get uploaderInfo;

  /// episodes information
  EpsData? get eps;

  /// comic introduction
  String? get introduction;

  /// Optional score in stars (0-5). Null = source has none.
  double? get stars => null;

  /// Optional rating label from source. Null = none.
  String? get ratingText => null;

  /// create thumbnails data
  ThumbnailsData? get thumbnailsCreator;

  @nonVirtual
  ThumbnailsData? get thumbnails => _logic.thumbnailsData;

  Widget? recommendationBuilder(T data);

  /// update widget state
  @nonVirtual
  void update() => _logic.update();

  /// get context
  BuildContext get context => App.mainNavigatorKey!.currentContext!;

  /// interface for building more info widget
  Widget? get buildMoreInfo => null;

  /// translation tags to CN
  bool get enableTranslationToCN => false;

  String? get subTitle => null;

  Map<String, String> get headers => {};

  @nonVirtual
  bool get favorite => _logic.favorite;

  @nonVirtual
  set favorite(bool f) => _logic.favorite = f;

  Future<bool> loadFavorite(T data);

  /// used for history
  String get id;

  /// url linked to this comic
  String? get url => null;

  /// callback when a thumbnail is tapped
  void onThumbnailTapped(int index) {}

  ActionFunc? get searchSimilar => null;

  Widget thumbnailImageBuilder(int index, String imageUrl) =>
      _thumbnailImageBuilder(index);

  /// The source of this comic, displayed at the beginning of the [title],
  /// can be translated into the user's language.
  String get source;

  FavoriteItem toLocalFavoriteItem();

  bool? get favoriteOnPlatformInitial => null;

  String get downloadedId;

  String get sourceKey;

  void scrollListener() {
    try {
      var logic = _logic;
      bool temp = logic.showAppbarTitle;
      if (!logic.controller.hasClients) {
        return;
      }
      logic.showAppbarTitle = logic.controller.position.pixels > 136;
      if (temp != logic.showAppbarTitle) {
        logic.update();
      }
    } catch (e) {
      return;
    }
  }

  static stack.Stack<ComicPageLogic> tagsStack = stack.Stack<ComicPageLogic>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return MiuixScaffold(content: (_) => StateBuilder<ComicPageLogic<T>>(
          tag: tag,
          init: ComicPageLogic<T>(),
          initState: (logic) {
            tagsStack.push(_logic);
            _logic.favoriteOnPlatform = favoriteOnPlatformInitial;
          },
          dispose: (logic) {
            tagsStack.pop();
          },
          builder: (logic) {
            _logic.width = constraints.maxWidth;
            _logic.height = constraints.maxHeight;
            if (logic.loading) {
              logic.get(loadData, loadFavorite, () => id);
              return buildLoading(context);
            } else if (logic.message != null) {
              return NetworkError(
                message: logic.message!,
                retry: logic.refresh_,
              );
            } else {
              _logic.thumbnailsData ??= thumbnailsCreator;
              logic.controller.removeListener(scrollListener);
              logic.controller.addListener(scrollListener);
              return Stack(
                children: [
                  SmoothCustomScrollView(
                    controller: logic.controller,
                    slivers: [
                      buildTitle(logic),
                      buildComicInfo(logic, context),
                      buildTags(logic, context),
                      ...buildEpisodeInfo(context),
                      ...buildIntroduction(context),
                      ...buildThumbnails(context),
                      ...buildRecommendation(context),
                      SliverPadding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom),
                      )
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: MiuixVerticalScrollBar(
                      adapter: MiuixScrollBarAdapter(logic.controller),
                    ),
                  ),
                ],
              );
            }
          },
        ),
      );
    });
  }

  Widget buildLoading(BuildContext context) {
    return SingleChildScrollView(
      child: Shimmer(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          colorOpacity: 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MiuixIconButton(
                    onPressed: () => Navigator.maybePop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ).paddingLeft(4),
              SizedBox(
                width: double.infinity,
                child: buildComicInfo(_logic, context, false),
              ),
              MiuixSmallTitle("信息".tl),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  8,
                  (index) => Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Container(
                      width: double.infinity,
                      height: 32,
                      constraints: const BoxConstraints(maxWidth: 400),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              )
            ],
          )).paddingTop(MediaQuery.of(context).padding.top),
    );
  }

  Widget buildTitle(ComicPageLogic<T> logic) {
    return SliverAppbar(
      largeTitle: Text("漫画详情".tl),
      title: Text(title!),
      leftSmallTitle: true,
      actions: [
        MiuixWindowIconDropdownMenu(
          entry: MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: "复制标题".tl,
                icon: const Icon(Icons.copy, size: 18),
                onClick: () {
                  var text = title!;
                  if (url != null) {
                    text += ":$url";
                  }
                  Clipboard.setData(ClipboardData(text: text));
                  showToast(message: "已复制".tl, icon: const Icon(Icons.check));
                },
              ),
              if (url != null)
                MiuixDropdownItem(
                  text: "复制链接".tl,
                  icon: const Icon(Icons.link, size: 18),
                  onClick: () {
                    Clipboard.setData(ClipboardData(text: url!));
                    showToast(message: "已复制".tl, icon: const Icon(Icons.check));
                  },
                ),
              MiuixDropdownItem(
                text: "分享".tl,
                icon: MiuixIcon(vector: MiuixIcons.os4.share, size: 18),
                onClick: () {
                  var text = title!;
                  if (url != null) {
                    text += ":$url";
                  }
                  Share.share(text);
                },
              ),
            ],
          ),
          child: MiuixIcon(
            vector: MiuixIcons.os4.more,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget buildComicInfo(ComicPageLogic<T> logic, BuildContext context,
      [bool sliver = true]) {
    var body = LayoutBuilder(builder: (context, constrains) {
      var width = constrains.maxWidth;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildCover(context, logic, 140, 105),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (context) {
                          final rawTitle = title?.trim() ?? "";
                          final len = rawTitle.length;
                          final double fontSize =
                              len > 36 ? 14.5 : (len > 20 ? 16.0 : 18.0);
                          return SizedBox(
                            width: double.infinity,
                            child: SelectableText(
                              rawTitle,
                              maxLines: null,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.25,
                              ),
                            ),
                          );
                        }),
                        if (stars != null || ratingText != null) ...[
                          const SizedBox(height: 8),
                          _buildRatingChip(context),
                        ],
                        const SizedBox(height: 8),
                        if (subTitle != null)
                          SizedBox(
                            width: double.infinity,
                            child: SelectableText(
                              subTitle!,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        if (subTitle != null) const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: ShapeDecoration(
                                shape: const StadiumBorder(),
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(isDark ? 0.22 : 0.12),
                              ),
                              child: Text(
                                source,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            if (pages != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: ShapeDecoration(
                                  shape: const StadiumBorder(),
                                  color: isDark
                                      ? const Color(0x22FFFFFF)
                                      : const Color(0x14000000),
                                ),
                                child: Text(
                                  "${pages}P",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (width >= 500)
                          buildActions(logic, context, false).paddingTop(12),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          if (width < 500)
            buildActions(logic, context, true).paddingHorizontal(16),
        ],
      );
    });

    if (sliver == true) {
      return SliverToBoxAdapter(
        child: body,
      );
    }

    return body;
  }

  Widget buildCover(
      BuildContext context, ComicPageLogic logic, double height, double width) {
    if (cover == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    if (headers["host"] == null && headers["Host"] == null) {
      headers["host"] = Uri.parse(cover!).host;
    }
    ImageProvider image = StreamImageProvider(
        () => ImageManager().getCustomThumbnail(cover!, sourceKey), cover!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(
          shape: MiuixSquircleBorder(
            cornerRadius: 14,
            side: BorderSide(
              color: isDark ? const Color(0x22FFFFFF) : const Color(0x0E000000),
              width: 0.8,
            ),
          ),
          color: Theme.of(context).colorScheme.primaryContainer,
          shadows: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Hero(
          tag: "image$tag",
          child: Image(
            image: image,
            fit: BoxFit.cover,
          ),
        ),
      ),
      onTap: () =>
          App.globalTo(() => ShowImagePageWithHero(cover!, "image$tag")),
    );
  }

  Widget buildInfoCard(String text, BuildContext context,
      {bool title = false, String key = "key"}) {

    if (text == "") {
      text = "未知".tl;
    }

    List<(String, void Function())> buildPopMenus() {
      return [
        (
          "复制".tl,
          () {
            Clipboard.setData(ClipboardData(text: (text)));
            showToast(message: "已复制".tl);
          }
        ),
        if (!title)
          (
            "屏蔽".tl,
            () {
              appdata.blockingKeyword.add(text);
              appdata.writeData();
            }
          ),
        if (!title)
          (
            "收藏".tl,
            () {
              var res = source.tlEN;
              if (source == "EHentai") {
                res += ":$key";
              }
              if (source == "Nhentai" && key == "Artists") {
                res += ":Artist";
              }
              if (text.contains(" ")) {
                res += ":\"$text\"";
              } else {
                res += ":$text";
              }
              appdata.favoriteTags.add(res);
              appdata.writeHistory();
            }
          ),
      ];
    }

    void showPopMenus(Offset position) {
      final menus = buildPopMenus();
      showMiuixMenu(
        context: App.globalContext!,
        anchorBounds: Rect.fromCenter(center: position, width: 1, height: 1),
        items: [for (var m in menus) m.$1],
      ).then((i) {
        if (i != null) menus[i].$2();
      });
    }

    Widget label(String text) =>
        Text(text, style: const TextStyle(fontSize: 13));

    if (title) {
      _logic.colorIndex++;
    }

    return GestureDetector(
      onLongPressStart: (details) {
        showPopMenus(details.globalPosition);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: GestureDetector(onSecondaryTapDown: (details) { showPopMenus(details.globalPosition); }, child: MiuixPressable(feedbackType: MiuixPressFeedbackType.sink, shape: const MiuixSquircleBorder(cornerRadius: 10), onPressed: title ? null : () => tapOnTag(text, key), child: Material(
            color: Colors.transparent,
            shape: const MiuixSquircleBorder(cornerRadius: 10),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: ShapeDecoration(
                shape: MiuixSquircleBorder(
                  cornerRadius: 10,
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0x18FFFFFF)
                        : const Color(0x0C000000),
                    width: 0.6,
                  ),
                ),
                color: title
                    ? themePalette[_logic.colorIndex % themePalette.length]
                        .withOpacity(0.22)
                    : (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0x18FFFFFF)
                        : const Color(0x0A000000)),
              ),
              padding: const EdgeInsets.fromLTRB(11, 5, 11, 5),
              child: enableTranslationToCN
                  ? (title
                      ? label(text.translateTagsCategoryToCN)
                      : label(TagsTranslation.translationTagWithNamespace(
                          text, key)))
                  : label(text),
            ),
          ))),
      ),
    );
  }

  Widget buildActions(ComicPageLogic logic, BuildContext context, bool center) {
    if (logic.loading) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        height: 72,
        width: double.infinity,
      );
    }

    Widget buildItem(String title, dynamic icon, VoidCallback onTap,
        [VoidCallback? onLongPress]) {
      // Same secondary fill as 下载 / non-primary MiuixButton (no border).
      final colors = MiuixButtonDefaults.buttonColors(context);
      final primary = Theme.of(context).colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: MiuixButton(
            cornerRadius: _kActionRadius,
            minWidth: 0,
            minHeight: _kActionHeight,
            colors: colors,
            insideMargin: EdgeInsets.zero,
            onPressed: onTap,
            child: SizedBox(
              height: _kActionHeight,
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon is MiuixVectorIcon)
                    MiuixIcon(vector: icon, size: 18, tint: primary)
                  else
                    Icon(icon as IconData, size: 18, color: primary),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                      color: colors.contentColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

        final width = MediaQuery.of(context).size.width;

    final actionItems = <Widget>[
      if (logic.history != null && width >= 500)
        buildItem("继续阅读".tl, Icons.menu_book, () => read(logic.history)),
      if (width >= 500 || (width < 500 && logic.history != null))
        buildItem("从头开始".tl, Icons.not_started_outlined, () => read(null)),
      buildItem("分享".tl, MiuixIcons.os4.share, () {
        var text = title!;
        if (url != null) {
          text += ":$url";
        }
        Share.share(text);
      }),
      buildItem(
          favorite ? "已收藏".tl : "收藏".tl,
          favorite
              ? (MiuixIcons.extended.byName('favoritesFill') ??
                  MiuixIcons.os4.favorites)
              : MiuixIcons.os4.favorites,
          openFavoritePanel, () {
        var folder = appdata.settings[51];
        if (LocalFavoritesManager().folderNames.contains(folder)) {
          LocalFavoritesManager().addComic(folder, toLocalFavoriteItem());
          showToast(message: "已收藏".tl);
        }
      }),
      if (width >= 500)
        buildItem("下载".tl,
            MiuixIcons.extended.byName('download') ?? Icons.download, download),
      if (onLike != null)
        buildItem(
            likeCount ?? "喜欢".tl,
            isLiked
                ? (MiuixIcons.extended.byName('favoritesFill') ??
                    MiuixIcons.os4.favorites)
                : MiuixIcons.os4.favorites,
            onLike!),
      if (openComments != null)
        buildItem(
            commentsCount ?? "评论".tl,
            MiuixIcons.extended.byName('messages') ?? Icons.comment_outlined,
            openComments!),
      if (searchSimilar != null)
        buildItem("相似".tl, MiuixIcons.os4.search, searchSimilar!),
      if (downloadManager.isExists(downloadedId))
        buildItem("删除".tl, MiuixIcons.os4.delete, () {
          showMiuixDialog<void>(
            context: context,
            title: "从本地下载中删除?".tl,
            actionsBuilder: (context, close) => [
              MiuixTextButton("取消".tl, onPressed: () => close()),
              MiuixTextButton(
                "删除".tl,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () async {
                  close();
                  await downloadManager.delete([downloadedId]);
                  showToast(message: "已删除".tl);
                  logic.update();
                },
              ),
            ],
          );
        }),
    ];

    Widget buildRowOrScroll() {
      if (width >= 500) {
        return Wrap(
          alignment: center ? WrapAlignment.center : WrapAlignment.start,
          children:
              actionItems.map((w) => SizedBox(width: 58, child: w)).toList(),
        );
      }
      if (actionItems.length <= 5) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: actionItems.map((w) => Expanded(child: w)).toList(),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var w in actionItems)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: SizedBox(width: 52, child: w),
              ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: UiMode.m1(context)
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          buildRowOrScroll(),
          if (width < 500)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: MiuixButton(
                      cornerRadius: _kActionRadius,
                      minHeight: _kActionHeight,
                      onPressed: download,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MiuixIcon(
                            vector: MiuixIcons.extended.byName('download') ??
                                MiuixIcons.os4.download,
                            size: 18,
                            tint: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text("下载".tl),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: MiuixButton(
                      cornerRadius: _kActionRadius,
                      minHeight: _kActionHeight,
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      onPressed: () =>
                          openReadingWithChapterSelect(context, _logic.history),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.menu_book_rounded,
                              size: 18, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            (_logic.history != null ? "继续阅读" : "开始阅读").tl,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void openReadingWithChapterSelect(BuildContext context, History? history) {
    if (eps == null || eps!.eps.length <= 1) {
      read(history);
      return;
    }
    showMiuixBottomSheet<void>(
      context: context,
      title: "选择章节".tl,
      builder: (modalContext, close) => _ChapterSelectModal(
        eps: eps!,
        history: _logic.history,
        onSelect: (index) {
          close();
          eps!.onTap(index);
        },
      ),
    );
  }

  Widget _buildRatingChip(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.onSurfaceVariant;
    final sVal = stars;
    final label = ratingText;
    final scoreText = sVal == null
        ? ""
        : (sVal % 1 == 0 ? sVal.toStringAsFixed(0) : sVal.toStringAsFixed(1));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: ShapeDecoration(
            shape: const MiuixSquircleBorder(cornerRadius: 10),
            color: primary.withOpacity(0.12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 16, color: primary),
              const SizedBox(width: 4),
              Text(
                label ?? scoreText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              if (sVal != null && label != null) ...[
                Text(
                  " · $scoreText",
                  style: TextStyle(fontSize: 12.5, color: outline),
                ),
              ],
              if (sVal != null && label == null)
                Text(
                  " / 5",
                  style: TextStyle(
                      fontSize: 12, color: outline.withOpacity(0.8)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCardTitle(
    String title, {
    Widget? trailing,
    bool? expanded,
    VoidCallback? onToggle,
  }) {
    final chevron = expanded == null
        ? null
        : Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
      child: Row(
        children: [
          Expanded(
            child: onToggle == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : MiuixPressable(
                    onPressed: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: trailing,
            ),
          if (chevron != null)
            MiuixIconButton(
              minWidth: 36,
              minHeight: 36,
              onPressed: onToggle,
              child: chevron,
            ),
        ],
      ),
    );
  }


  Widget buildTags(ComicPageLogic logic, BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: MiuixCard(
          cornerRadius: 16,
          insideMargin: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCardTitle("信息".tl),
              ...buildInfoCards(logic, context),
            ],
          ),
        ),
      ),
    );
  }

  Iterable<Widget> buildInfoCards(
      ComicPageLogic logic, BuildContext context) sync* {
    if (buildMoreInfo != null) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: buildMoreInfo!,
      );
    }

    _logic.colorIndex = 0;

    for (var key in tags!.keys) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Wrap(
          children: [
            buildInfoCard(key, context, title: true),
            for (var tag in tags![key]!) buildInfoCard(tag, context, key: key)
          ],
        ),
      );
    }

    if (uploaderInfo != null) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),
            child: uploaderInfo,
          ),
        ),
      );
    }
  }

  Iterable<Widget> buildEpisodeInfo(BuildContext context) sync* {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = colorScheme.primary;
    if (eps == null || eps!.eps.isEmpty) return;

    if (!_logic.sectionChaptersDefaultApplied) {
      _logic.sectionChaptersDefaultApplied = true;
      _logic.sectionChaptersExpanded = eps!.eps.length <= 16;
    }

    int length = eps!.eps.length;
    if (!_logic.showFullEps) {
      length = math.min(length, 20);
    }

    Widget epCell(int i) {
      if (_logic.reverseEpsOrder) {
        i = eps!.eps.length - i - 1;
      }
      final visited =
          (_logic.history?.readEpisode ?? const {}).contains(i + 1);
      final isCurrent = _logic.history?.ep == i + 1;
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          shape: const MiuixSquircleBorder(cornerRadius: 12),
          onPressed: () => eps!.onTap(i),
          child: Material(
            color: isCurrent
                ? primary.withOpacity(isDark ? 0.28 : 0.14)
                : (isDark
                    ? colorScheme.surface
                    : colorScheme.surfaceContainerHighest),
            shape: MiuixSquircleBorder(
              cornerRadius: 12,
              side: BorderSide(
                color: isCurrent
                    ? primary.withOpacity(0.45)
                    : (isDark
                        ? const Color(0x18FFFFFF)
                        : const Color(0x1F000000)),
                width: isCurrent ? 1.0 : 0.9,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Center(
                child: Text(
                  eps!.eps[i],
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isCurrent
                        ? FontWeight.w600
                        : (visited ? FontWeight.w400 : FontWeight.w500),
                    color: isCurrent
                        ? primary
                        : (visited
                            ? (isDark ? Colors.white38 : Colors.black45)
                            : null),
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    yield SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: MiuixCard(
          cornerRadius: 16,
          insideMargin: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCardTitle(
                "章节目录".tl,
                expanded: _logic.sectionChaptersExpanded,
                onToggle: () {
                  _logic.sectionChaptersExpanded =
                      !_logic.sectionChaptersExpanded;
                  _logic.update();
                },
                trailing: MiuixTooltipBox(
                  tooltip: (context, scope) =>
                      MiuixPlainTooltip(scope: scope, child: Text("排序".tl)),
                  child: MiuixIconButton(
                    child: MiuixIcon(vector: MiuixIcons.os4.sort, size: 20),
                    onPressed: () {
                      _logic.reverseEpsOrder = !_logic.reverseEpsOrder;
                      _logic.update();
                    },
                  ),
                ),
              ),
              if (!_logic.sectionChaptersExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    "共 @count 话，点击展开"
                        .tlParams({"count": "${eps!.eps.length}"}),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                    ),
                  ),
                )
              else ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  itemCount: length,
                  gridDelegate: const SliverGridDelegateWithFixedHeight(
                      maxCrossAxisExtent: 200, itemHeight: 52),
                  itemBuilder: (context, i) => epCell(i),
                ),
                if (eps!.eps.length > 20 && !_logic.showFullEps)
                  Align(
                    alignment: Alignment.center,
                    child: MiuixButton(
                      cornerRadius: 12,
                      onPressed: () {
                        _logic.showFullEps = true;
                        _logic.update();
                      },
                      child: Text("${"显示全部".tl} (${eps!.eps.length})"),
                    ).paddingTop(4).paddingBottom(4),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> buildIntroduction(BuildContext context) {
    final text = introduction?.trim() ?? "";
    final isEmpty = text.isEmpty;
    final outline = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: MiuixCard(
            cornerRadius: 16,
            insideMargin: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionCardTitle(
                  "作品简介".tl,
                  expanded: _logic.sectionIntroExpanded,
                  onToggle: () {
                    _logic.sectionIntroExpanded = !_logic.sectionIntroExpanded;
                    _logic.update();
                  },
                ),
                if (_logic.sectionIntroExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: isEmpty
                        ? Text(
                            "暂无作品简介".tl,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: outline.withOpacity(0.75),
                            ),
                          )
                        : SelectableText(
                            text,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _thumbnailImageBuilder(int index) {
    return Image(
      image:
          CachedImageProvider(thumbnails!.thumbnails[index], headers: headers),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, err, d) => _thumbnailErrorPlaceholder(context),
    );
  }

  Widget _thumbnailErrorPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE8E8EC),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 28,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.55),
        ),
      ),
    );
  }

  List<Widget> buildThumbnails(BuildContext context) {
    if (thumbnails == null ||
        (thumbnails!.thumbnails.isEmpty &&
            !tag.contains("Hitomi") &&
            !tag.contains("Eh"))) return [];
    if (thumbnails!.thumbnails.isEmpty) {
      thumbnails!.get(update);
    }

    final thumbs = thumbnails!.thumbnails;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: MiuixCard(
            cornerRadius: 16,
            insideMargin: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionCardTitle(
                  "预览".tl,
                  expanded: _logic.sectionPreviewExpanded,
                  onToggle: () {
                    _logic.sectionPreviewExpanded =
                        !_logic.sectionPreviewExpanded;
                    _logic.update();
                  },
                ),
                if (_logic.sectionPreviewExpanded) ...[
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                    itemCount: thumbs.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 135,
                      childAspectRatio: 0.74,
                    ),
                    itemBuilder: (context, index) {
                      if (index == thumbs.length - 1) {
                        thumbnails!.get(update);
                      }
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final border = isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0x0C000000);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: MiuixPressable(
                          feedbackType: MiuixPressFeedbackType.sink,
                          shape:
                              const MiuixSquircleBorder(cornerRadius: 12),
                          onPressed: () => onThumbnailTapped(index),
                          child: Material(
                            color: isDark
                                ? const Color(0xFF1E1E22)
                                : Theme.of(context).colorScheme.surface,
                            shape: MiuixSquircleBorder(
                              cornerRadius: 12,
                              side: BorderSide(color: border, width: 0.6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                thumbnailImageBuilder(
                                    index, thumbs[index]),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.62),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${index + 1}",
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (thumbnails!.current < thumbnails!.maxPage)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: ListLoadingIndicator(),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> buildRecommendation(BuildContext context) {
    var recommendation = recommendationBuilder(_logic.data!);
    if (recommendation == null) return [];

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: MiuixCard(
            cornerRadius: 16,
            insideMargin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionCardTitle(
                  "相关推荐".tl,
                  expanded: _logic.sectionRecommendExpanded,
                  onToggle: () {
                    _logic.sectionRecommendExpanded =
                        !_logic.sectionRecommendExpanded;
                    _logic.update();
                  },
                ),
                if (!_logic.sectionRecommendExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      "已折叠相关推荐".tl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.75),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      if (_logic.sectionRecommendExpanded)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          sliver: recommendation,
        ),
    ];
  }

  void favoriteComic(FavoriteComicWidget widget) {
    if (UiMode.m1(context)) {
      showMiuixBottomSheet<void>(
          context: context,
          builder: (context, close) => SizedBox(
              height: MediaQuery.of(context).size.height * 9 / 16,
              child: Material(type: MaterialType.transparency, child: widget)));
    } else {
      showSideBar(
        App.globalContext!,
        widget,
        title: "收藏漫画".tl,
        useSurfaceTintColor: true,
      );
    }
  }
}

class FavoriteComicWidget extends StatefulWidget {
  const FavoriteComicWidget(
      {required this.havePlatformFavorite,
      required this.needLoadFolderData,
      required this.localFavoriteItem,
      this.folders = const {},
      this.foldersLoader,
      this.selectFolderCallback,
      this.initialFolder,
      this.favoriteOnPlatform = false,
      this.cancelPlatformFavorite,
      this.cancelPlatformFavoriteWithFolder,
      required this.setFavorite,
      super.key});

  /// whether this platform has favorites feather
  final bool havePlatformFavorite;

  /// need load folder data before show folders
  final bool needLoadFolderData;

  /// initial folders, default is empty
  ///
  /// key - folder's name, value - folders id(used by callback)
  final Map<String, String> folders;

  /// load folders method
  final Future<Res<Map<String, String>>> Function()? foldersLoader;

  /// callback when user choose a folder
  ///
  /// type=0: platform, type=1:local
  final FutureOr<Res<bool>> Function(String id, int type)? selectFolderCallback;

  /// initial selected folder id
  final String? initialFolder;

  /// whether this comic have been added to platform's favorite folder
  /// if this is null, it is required to send a request to check it
  final bool? favoriteOnPlatform;

  /// identifier for the comic
  final FavoriteItem localFavoriteItem;

  final Future<Res<bool>> Function()? cancelPlatformFavorite;

  final Future<Res<bool>> Function(String folder)?
      cancelPlatformFavoriteWithFolder;

  final void Function(bool favorite) setFavorite;

  @override
  State<FavoriteComicWidget> createState() => _FavoriteComicWidgetState();
}

class _FavoriteComicWidgetState extends State<FavoriteComicWidget> {
  late List<String> selected;
  late int page = 0;
  int _tabIndex = 0;
  final _tabPageController = PageController();

  @override
  void dispose() {
    _tabPageController.dispose();
    super.dispose();
  }

  /// network folders
  late Map<String, String> folders;

  /// network folders that have been added to favorite
  var favoritedFolders = <String>[];
  bool loadedData = false;
  List<String> addedFolders = [];
  bool isAdding = false;

  @override
  void initState() {
    LocalFavoritesManager()
        .find(widget.localFavoriteItem.target, widget.localFavoriteItem.type)
        .then((folder) {
      Future.microtask(() => setState(() => addedFolders = folder));
    });
    selected = widget.initialFolder != null ? [widget.initialFolder!] : [];
    if (!widget.havePlatformFavorite) {
      page = 1;
    }
    folders = widget.folders;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.havePlatformFavorite || page != 0);

    Widget buildFolder(String name, String id, int p) {
      bool isSelected = selected.contains(id);
      return MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        shape: const MiuixSquircleBorder(cornerRadius: 12),
        onPressed: () => setState(() {
          page = p;
          if (isSelected) {
            selected.remove(id);
            return;
          }
          if (p == 0) {
            selected.clear();
            selected.add(id);
          } else {
            selected.add(id);
          }
        }),
        child: SizedBox(
          height: App.isDesktop ? 42 : 48,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.folder : Icons.folder_outlined,
                  size: App.isDesktop ? 24 : 28,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(
                  width: 12,
                ),
                Text(name),
                if ((addedFolders.contains(name) && p == 1) ||
                    (favoritedFolders.contains(id) && p == 0))
                  const SizedBox(
                    width: 12,
                  ),
                if ((addedFolders.contains(name) && p == 1) ||
                    (favoritedFolders.contains(id) && p == 0))
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Center(
                      child: Text("已收藏".tl),
                    ),
                  ),
                const Spacer(),
                if (isSelected) const AnimatedCheckIcon()
              ],
            ),
          ),
        ),
      );
    }

    Widget button = Button.filled(
      isLoading: isAdding,
      child: Text("收藏".tl),
      onPressed: () async {
        if (selected.isNotEmpty) {
          setState(() {
            isAdding = true;
          });
          Res<bool> res = const Res(true);
          for (var id in selected) {
            if (addedFolders.contains(id)) {
              continue;
            }
            res = await widget.selectFolderCallback!.call(id, page);
          }
          if (res.success) {
            widget.setFavorite(true);
            if (context.mounted) {
              context.pop();
            }
            showToast(message: "添加收藏成功".tl);
          } else {
            setState(() {
              isAdding = false;
            });
            showToast(message: res.errorMessage!);
          }
        }
      },
    );

    Widget platform = SingleChildScrollView(
      child: Column(
        children: List.generate(
            folders.length,
            (index) => buildFolder(folders.values.elementAt(index),
                folders.keys.elementAt(index), 0)),
      ),
    );

    if (widget.favoriteOnPlatform == true) {
      platform = Center(
        child: Text("已收藏".tl),
      );
      if (page == 0) {
        button = Button.filled(
          isLoading: isAdding,
          onPressed: () async {
            setState(() {
              isAdding = true;
            });
            var res = await widget.cancelPlatformFavorite!.call();
            if (res.success) {
              if (addedFolders.isEmpty) {
                widget.setFavorite(false);
              }
              showToast(message: "取消收藏成功".tl);
              if (context.mounted) {
                context.pop();
              }
            } else {
              setState(() {
                isAdding = false;
              });
              showToast(message: res.errorMessage!);
            }
          },
          child: Text("取消收藏".tl),
        );
      }
    }

    if (page == 1 &&
        selected.isNotEmpty &&
        selected.every((e) => addedFolders.contains(e))) {
      button = Button.filled(
        onPressed: () {
          context.hideMessages();
          App.globalBack();
          if (addedFolders.length == 1 &&
              widget.favoriteOnPlatform == false &&
              favoritedFolders.isEmpty) {
            widget.setFavorite(false);
          }
          for (var id in selected) {
            LocalFavoritesManager().deleteComic(
              id,
              widget.localFavoriteItem,
            );
          }
          showToast(message: "取消收藏成功".tl);
        },
        child: Text("取消收藏".tl),
      );
    } else if (widget.havePlatformFavorite &&
        widget.needLoadFolderData &&
        !loadedData) {
      widget.foldersLoader!.call().then((res) {
        if (res.error) {
          showToast(message: res.errorMessage ?? "Error");
        } else {
          setState(() {
            loadedData = true;
            folders = res.data;
            favoritedFolders = res.subData ?? [];
          });
        }
      });
      platform = const Center(
        child: MiuixInfiniteProgressIndicator(),
      );
    } else if (page == 0 &&
        selected.length == 1 &&
        favoritedFolders.contains(selected[0])) {
      button = Button.filled(
        onPressed: () async {
          var res = await widget.cancelPlatformFavoriteWithFolder!(selected[0]);
          if (res.success) {
            showToast(message: "取消收藏成功".tl);
            if (context.mounted) {
              context.pop();
            }
          } else {
            showToast(message: res.errorMessage!);
          }
        },
        child: Text("取消收藏".tl),
      );
    }

    Widget local;

    var localFolders = LocalFavoritesManager().folderNames;

    var children = List.generate(localFolders.length,
        (index) => buildFolder(localFolders[index], localFolders[index], 1));
    children.add(SizedBox(
      height: 56,
      width: double.infinity,
      child: Center(
        child: MiuixTextButton(
          "新建".tl,
          onPressed: () => CreateFolderDialog.show(App.globalContext!)
              .then((value) => setState(() {})),
        ),
      ),
    ));
    local = SingleChildScrollView(
      child: Column(
        children: children,
      ),
    );

    final tabNames = [
      if (widget.havePlatformFavorite) "网络".tl,
      "本地".tl,
    ];
    return Column(
      children: [
        MiuixTabRow(
          tabs: tabNames,
          selectedTabIndex: _tabIndex,
          onTabSelected: (i) {
            _tabPageController.animateToPage(i,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut);
            setState(() {
              _tabIndex = i;
              selected.clear();
              if (i == 0 && widget.initialFolder != null) {
                selected.add(widget.initialFolder!);
              }
              page = i;
              if (!widget.havePlatformFavorite) {
                page = 1;
              }
            });
          },
        ).paddingHorizontal(12),
        Expanded(
          child: PageView(
            controller: _tabPageController,
            onPageChanged: (i) => setState(() => _tabIndex = i),
            children: [
              if (widget.havePlatformFavorite) platform,
              local,
            ],
          ),
        ),
        SizedBox(
          height: 60,
          child: Center(
            child: button,
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).padding.bottom,
        )
      ],
    );
  }
}

class _ChapterSelectModal extends StatefulWidget {
  const _ChapterSelectModal({
    required this.eps,
    required this.history,
    required this.onSelect,
  });

  final EpsData eps;
  final History? history;
  final ValueChanged<int> onSelect;

  @override
  State<_ChapterSelectModal> createState() => _ChapterSelectModalState();
}

class _ChapterSelectModalState extends State<_ChapterSelectModal> {
  bool reverseOrder = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final totalEps = widget.eps.eps.length;

    return SizedBox(
      height: maxHeight,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 10),
              child: Row(
                children: [
                  Text(
                    "共 @count 话".tlParams({"count": totalEps.toString()}),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const Spacer(),
                  MiuixTooltipBox(
                    tooltip: (context, scope) =>
                        MiuixPlainTooltip(scope: scope, child: Text("排序".tl)),
                    child: MiuixIconButton(
                      onPressed: () => setState(() {
                        reverseOrder = !reverseOrder;
                      }),
                      child: MiuixIcon(vector: MiuixIcons.os4.sort, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16),
                gridDelegate: const SliverGridDelegateWithFixedHeight(
                  maxCrossAxisExtent: 180,
                  itemHeight: 46,
                ),
                itemCount: totalEps,
                itemBuilder: (context, i) {
                  final epIndex = reverseOrder ? totalEps - 1 - i : i;
                  final visited = (widget.history?.readEpisode ?? const {})
                      .contains(epIndex + 1);
                  final isCurrent = widget.history?.ep == epIndex + 1;
                  return Padding(
                    padding: const EdgeInsets.all(3),
                    child: MiuixCard(
                      cornerRadius: 12,
                      feedbackType: MiuixPressFeedbackType.sink,
                      onPressed: () => widget.onSelect(epIndex),
                      colors: isCurrent
                          ? MiuixCardColors(
                              color: primary.withOpacity(isDark ? 0.28 : 0.16),
                              contentColor: primary)
                          : null,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            widget.eps.eps[epIndex],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : (visited ? FontWeight.w400 : FontWeight.w500),
                              color: isCurrent
                                  ? primary
                                  : (visited
                                      ? (isDark ? Colors.white38 : Colors.black38)
                                      : null),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
