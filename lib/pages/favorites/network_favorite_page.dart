import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';

class NetworkFavoritePage extends StatelessWidget {
  const NetworkFavoritePage(this.data, {super.key});

  final FavoriteData data;

  @override
  Widget build(BuildContext context) {
    return data.multiFolder
        ? _MultiFolderFavoritesPage(data)
        : _NormalFavoritePage(data);
  }
}

class _NormalFavoritePage extends ComicsPage<BaseComic> {
  const _NormalFavoritePage(this.data);

  final FavoriteData data;

  @override
  Future<Res<List<BaseComic>>> getComics(int i) {
    return data.loadComic(i);
  }

  @override
  String? get tag => "Network Comics Page: ${data.title}";

  @override
  String? get title => null;

  @override
  String get sourceKey => data.key;

  @override
  List<ComicTileMenuOption>? get addonMenuOptions {
    return [
      if (data.addOrDelFavorite != null)
        ComicTileMenuOption(
          "取消收藏".tl,
          Icons.playlist_remove_outlined,
          (id) {
            if (id == null) return;
            var dialog = showLoadingDialog(App.globalContext!);
            data.addOrDelFavorite!(id, "0", false).then((res) {
              dialog.close();
              if (res.error) {
                showToast(message: res.errorMessage!);
              } else {
                refresh();
              }
            });
          },
        )
    ];
  }
}

class _MultiFolderFavoritesPage extends StatefulWidget {
  const _MultiFolderFavoritesPage(this.data);

  final FavoriteData data;

  @override
  State<_MultiFolderFavoritesPage> createState() =>
      _MultiFolderFavoritesPageState();
}

class _MultiFolderFavoritesPageState extends State<_MultiFolderFavoritesPage> {
  bool _loading = true;

  String? _errorMessage;

  Map<String, String>? folders;

  void loadPage() async {
    var res = await widget.data.loadFolders!();
    _loading = false;
    if (res.error) {
      setState(() {
        _errorMessage = res.errorMessage;
      });
    } else {
      setState(() {
        folders = res.data;
      });
    }
  }

  void openFolder(String key, String title) {
    context.to(() => _FavoriteFolder(widget.data, key, title));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      loadPage();
      return const TopInsetPadding(
        child: Center(
          child: MiuixCircularProgressIndicator(),
        ),
      );
    } else if (_errorMessage != null) {
      return TopInsetPadding(
        child: NetworkError(message: _errorMessage!, withAppbar: false,),
      );
    } else {
      var length = folders!.length;
      if (widget.data.allFavoritesId != null) length++;
      final keys = folders!.keys.toList();

      return SmoothCustomScrollView(
        slivers: [
          const TopInsetSliver(),
          SliverGridViewWithFixedItemHeight(
            delegate:
                SliverChildBuilderDelegate(childCount: length, (context, i) {
              if (widget.data.allFavoritesId != null) {
                if (i == 0) {
                  return _FolderTile(
                      name: "全部".tl,
                      onTap: () =>
                          openFolder(widget.data.allFavoritesId!, "全部".tl));
                } else {
                  i--;
                  return _FolderTile(
                    name: folders![keys[i]]!,
                    onTap: () => openFolder(keys[i], folders![keys[i]]!),
                    deleteFolder: widget.data.deleteFolder == null
                        ? null
                        : () => widget.data.deleteFolder!(keys[i]),
                    updateState: () => setState(() {
                      _loading = true;
                    }),
                  );
                }
              } else {
                return _FolderTile(
                  name: folders![keys[i]]!,
                  onTap: () => openFolder(keys[i], folders![keys[i]]!),
                  deleteFolder: widget.data.deleteFolder == null
                      ? null
                      : () => widget.data.deleteFolder!(keys[i]),
                  updateState: () => setState(() {
                    _loading = true;
                  }),
                );
              }
            }),
            maxCrossAxisExtent: 450,
            itemHeight: 64,
          ),
          if (widget.data.addFolder != null)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Center(
                  child: MiuixPressable(
 onPressed: () {
                        showMiuixDialog(
                            context: context,
                            title: "创建收藏夹".tl,
                            contentBuilder: (context, close) {
                              return _CreateFolderDialog(
                                  widget.data,
                                  () => setState(() {
                                        _loading = true;
                                      }));
                            });
                      },
 feedbackType: MiuixPressFeedbackType.sink,
 shape: const StadiumBorder(),
 child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: ShapeDecoration(
                          shape: const StadiumBorder(),
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              "创建收藏夹".tl,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
),
                ),
              ),
            )
        ],
      );
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile(
      {required this.name,
      required this.onTap,
      this.deleteFolder,
      this.updateState});

  final String name;

  final Future<Res<bool>> Function()? deleteFolder;

  final void Function()? updateState;

  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: MiuixPressable(
 onPressed: onTap,
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
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (deleteFolder != null)
                  MiuixIconButton(onPressed: () => onDeleteFolder(context), child: const Icon(Icons.delete_forever_outlined, size: 20))
                else
                  const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
),
    );
  }

  void onDeleteFolder(BuildContext context) {
    showMiuixDialog(
      context: context,
      title: "确认删除".tl,
      summary: "要删除这个收藏夹吗".tl,
      actionsBuilder: (context, close) => [
        MiuixTextButton(onPressed: () => close(), "取消".tl),
        MiuixTextButton(
            onPressed: () async {
              close();
              showToast(message: "正在删除收藏夹".tl);
              var res = await deleteFolder!();
              showToast(
                  message: res.error ? res.errorMessage! : "删除成功".tl);
              if (!res.error) {
                updateState?.call();
              } else {
                showToast(
                    message: res.error ? res.errorMessage! : "删除失败".tl);
              }
            },
            "确认".tl),
      ],
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog(this.data, this.updateState);

  final FavoriteData data;

  final void Function() updateState;

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  var controller = TextEditingController();
  var focusNode = FocusNode();
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    focusNode.requestFocus();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiuixTextField(
          controller: controller,
          focusNode: focusNode,
          label: "名称".tl,
        ),
        const SizedBox(
          width: 200,
          height: 10,
        ),
        if (loading)
          const SizedBox(
            child: Center(
              child: MiuixCircularProgressIndicator(),
            ),
          )
        else
          SizedBox(
              height: 35,
              child: Center(
                child: MiuixTextButton(
                    onPressed: () {
                      setState(() {
                        loading = true;
                      });
                      widget.data.addFolder!(controller.text).then((b) {
                        if (b.error) {
                          showToast(message: b.errorMessage!);
                          setState(() {
                            loading = false;
                          });
                        } else {
                          context.pop();
                          showToast(message: "成功创建".tl);
                          widget.updateState();
                        }
                      });
                    },
                    "提交".tl),
              ))
      ],
    );
  }
}

class _FavoriteFolder extends ComicsPage<BaseComic> {
  const _FavoriteFolder(this.data, this.folderID, this.title);

  final FavoriteData data;

  final String folderID;

  @override
  final String title;

  @override
  Future<Res<List<BaseComic>>> getComics(int i) {
    return data.loadComic(i, folderID);
  }

  @override
  String? get tag => "Favorites Folder $folderID";

  @override
  String get sourceKey => data.key;
}
