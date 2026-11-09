part of pica_settings;

void findUpdate(BuildContext context) {
  context.showMessage(message: "正在检查更新".tl);
  checkUpdate().then((b) {
    if (!context.mounted) return;
    if (b == null) {
      context.showMessage(message: "网络错误".tl);
    } else if (b) {
      getUpdatesInfo().then((s) async {
        if (!context.mounted) return;
        showUpdateDialog(context,
            version: latestVersion,
            notes: s,
            releaseUrl: await getDownloadUrl());
      });
    } else {
      context.showMessage(message: "已是最新版本".tl);
    }
  });
}


/// 关于页「更新日志」: 显示当前已安装版本 (appVersion) 对应 release 的说明。
Future<void> showLatestChangelog(BuildContext context) async {
  var loading = showLoadingDialog(context,
      allowCancel: true, barrierDismissible: false);
  const tag = "v$appVersion";
  String? notes;
  var found = true;
  var failed = false;
  try {
    final r = await getCurrentVersionNotes();
    notes = r.notes;
    found = r.found;
  } catch (_) {
    failed = true;
  }
  loading.close();
  if (!context.mounted) return;
  final url = getReleasePageUrl(found ? tag : null);
  final String fallbackText = failed
      ? "网络错误, 无法获取当前版本的更新日志".tl
      : (found ? "该版本没有填写更新日志".tl : "未找到当前版本的发布记录 (可能是测试版)".tl);
  showMiuixDialog<void>(
    context: context,
    title: "更新日志".tl,
    summary: "${"当前版本".tl} $tag",
    contentBuilder: (context, close) {
      final colors = MiuixTheme.of(context).colors;
      var maxH = MediaQuery.of(context).size.height * 0.55;
      if (maxH < 160) maxH = 160;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: ShapeDecoration(
              color: colors.secondaryContainer,
              shape: const MiuixSquircleBorder(cornerRadius: 14),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: notes == null
                  ? Text(fallbackText,
                      style: TextStyle(
                          fontSize: 14, color: colors.onSurfaceVariantSummary))
                  : SimpleMarkdown(notes),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: MiuixTextButton("关闭".tl, onPressed: () => close())),
            const SizedBox(width: 12),
            Expanded(
              child: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () {
                  close();
                  launchUrlString(url, mode: LaunchMode.externalApplication);
                },
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text("GitHub", maxLines: 1),
                ),
              ),
            ),
          ]),
        ],
      );
    },
  );
}

class ProxyController extends StateController {
  bool value = appdata.settings[8] == "0";
  late var controller =
      TextEditingController(text: value ? "" : appdata.settings[8]);
}

void setProxy(BuildContext context) {
  showMiuixDialog(
      context: context,
      title: "设置代理".tl,
      contentBuilder: (dialogContext, close) {
        return StateBuilder(
            init: ProxyController(),
            builder: (controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MiuixSwitchPreference(
                    title: "使用系统代理".tl,
                    value: controller.value,
                    onChanged: (value) {
                      if (value == true) {
                        controller.controller.text = "";
                      }
                      controller.value = !controller.value;
                      controller.update();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                    child: MiuixTextField(
                      readOnly: controller.value,
                      controller: controller.controller,
                      singleLine: true,
                      useLabelAsPlaceholder: true,
                      label: controller.value
                          ? "使用系统代理时无法手动设置".tl
                          : "设置代理, 例如127.0.0.1:7890".tl,
                    ),
                  ),
                  if (!controller.value)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 0, 12),
                      child: Row(
                        children: [
                          MiuixIcon(vector: MiuixIcons.os4.info, size: 18),
                          Text("  ${"留空表示禁用网络代理".tl}",
                              style: const TextStyle(fontSize: 13))
                        ],
                      ),
                    ),
                  MiuixButton(
                      colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
                      onPressed: () {
                        if (controller.value) {
                          appdata.settings[8] = "0";
                          appdata.writeData();
                          setNetworkProxy();
                          close();
                        } else {
                          appdata.settings[8] = controller.controller.text;
                          appdata.writeData();
                          setNetworkProxy();
                          close();
                        }
                      },
                      child: Text("确认".tl,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              );
            });
      });
}

Future<void> setDownloadFolder() async {
  if (DownloadManager().downloading.isNotEmpty) {
    showToast(message: "请先完成下载任务".tl);
    return;
  }

  if (App.globalContext == null) return;
  await showMiuixDialog(
    context: App.globalContext!,
    title: "漫画下载目录".tl,
    contentBuilder: (context, close) => const SetDownloadFolderDialog(),
  );
}

class SetDownloadFolderDialog extends StatefulWidget {
  const SetDownloadFolderDialog({super.key});

  @override
  State<SetDownloadFolderDialog> createState() =>
      _SetDownloadFolderDialogState();
}

class _SetDownloadFolderDialogState extends State<SetDownloadFolderDialog> {
  late String current;
  bool transform = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    current = appdata.settings[22];
  }

  bool get _isDefault => current.trim().isEmpty;

  Future<void> _pickFolder() async {
    if (busy) return;
    final picked = await pickStorageDirectory();
    if (picked == null) return;
    if (picked.path == null || picked.path!.trim().isEmpty) {
      showToast(message: "请选择内部存储目录".tl);
      return;
    }
    setState(() => current = picked.path!.trim());
  }

  Future<bool> _ensureWritable(String path) async {
    if (!App.isAndroid) return true;
    if (!_needsManageStorageForPath(path)) return true;
    final have = await const MethodChannel("pica_comic/settings")
            .invokeMethod("files_check") ==
        true;
    if (have) return true;
    showToast(message: "需要所有文件访问权限".tl);
    await const MethodChannel("pica_comic/settings").invokeMethod("files");
    return false;
  }

  void _reset() {
    if (busy) return;
    setState(() => current = "");
  }

  Future<void> _apply() async {
    if (busy) return;
    final next = current.trim();
    if (next == appdata.settings[22].trim()) {
      App.globalBack();
      return;
    }
    if (next.isNotEmpty) {
      final ok = await _ensureWritable(next);
      if (!ok) return;
      try {
        final dir = Directory(next);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (e) {
        showToast(message: "${"目录不可用".tl}: $e");
        return;
      }
    }
    setState(() => busy = true);
    final oldPath = appdata.settings[22];
    appdata.settings[22] = next;
    if (transform) {
      showToast(message: "正在复制文件".tl);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final res =
        await downloadManager.updatePath(next, transform: transform);
    if (!mounted) return;
    setState(() => busy = false);
    if (res == "ok") {
      await appdata.updateSettings();
      App.globalBack();
      showToast(message: "已更新".tl);
    } else {
      appdata.settings[22] = oldPath;
      showToast(message: res);
    }
  }

  Widget _optionCard({
    required bool selected,
    required String title,
    required String summary,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        feedbackType: MiuixPressFeedbackType.sink,
        colors: selected
            ? MiuixCardColors(
                color: scheme.primaryContainer,
                contentColor: scheme.onPrimaryContainer,
              )
            : null,
        onPressed: busy ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _optionCard(
          selected: _isDefault,
          title: "默认".tl,
          summary: "应用私有".tl,
          onTap: () => setState(() => current = ""),
        ),
        _optionCard(
          selected: !_isDefault,
          title: "自定义".tl,
          summary: _isDefault
              ? "选择文件夹".tl
              : friendlyStoragePath(current),
          onTap: _pickFolder,
        ),
        MiuixCheckboxPreference(
          value: transform,
          onChanged: busy
              ? null
              : (b) => setState(() {
                    transform = b;
                  }),
          title: "转移数据".tl,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MiuixTextButton(
                "重置".tl,
                onPressed: busy ? null : _reset,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: busy ? null : _apply,
                child: Text(busy ? "处理中".tl : "确认".tl),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


void setExplorePages(BuildContext context) {
  showPopUpWidget(context, const SetExplorePages());
}

class SetExplorePages extends StatefulWidget {
  const SetExplorePages({Key? key}) : super(key: key);

  @override
  State<SetExplorePages> createState() => _SetExplorePagesState();
}

class _SetExplorePagesState extends State<SetExplorePages> {
  @override
  void dispose() {
    appdata.updateSettings();
    Future.microtask(() {
      MyApp.updater?.call();
    });
    super.dispose();
  }

  Widget buildItem(String i) {
    Widget removeButton = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: MiuixIconButton(onPressed: () {
            setState(() {
              var config = appdata.appSettings.explorePages;
              config.remove(i);
              appdata.appSettings.explorePages = config;
            });
          }, child: _mi(MiuixIcons.os4.delete)),
    );

    return Padding(
      key: ValueKey<String>(i),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: ShapeDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C1C1E)
              : Colors.white,
          shape: const MiuixSquircleBorder(cornerRadius: 14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                i.tl,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            removeButton,
            _mi(MiuixIcons.os4.menu),
          ],
        ),
      ),
    );
  }

  Widget buildNotShowPageSelector(String i, BuildContext context) {
    return MiuixBasicComponent(
      key: Key(i),
      title: i.tl,
      onClick: () {
        App.back(context);
        setState(() {
          appdata.appSettings.explorePages = appdata.appSettings.explorePages
            ..add(i);
        });
      },
    );
  }

  var reorderWidgetKey = UniqueKey();
  var scrollController = ScrollController();
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    var notShowPages = <String>[];
    var allPages = <String>[];
    for (var source in ComicSource.sources) {
      for (var page in source.explorePages) {
        allPages.add(page.title);
      }
    }
    for (var i in allPages) {
      if (!appdata.appSettings.explorePages.contains(i)) {
        notShowPages.add(i);
      }
    }

    var tiles =
        appdata.appSettings.explorePages.map((e) => buildItem(e)).toList();

    var view = ReorderableBuilder(
      key: reorderWidgetKey,
      scrollController: scrollController,
      longPressDelay: App.isDesktop
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 500),
      dragChildBoxDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: MiuixTheme.of(context).colors.surfaceContainer,
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              offset: Offset(0, 2),
              spreadRadius: 2)
        ],
      ),
      onReorder: (reorderFunc) {
        setState(() {
          appdata.appSettings.explorePages =
              List.from(reorderFunc(appdata.appSettings.explorePages));
        });
      },
      children: tiles,
      builder: (children) {
        return GridView(
          key: _key,
          controller: scrollController,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            mainAxisExtent: 48,
          ),
          children: children,
        );
      },
    );
    return PopUpWidgetScaffold(
      title: "探索页面".tl,
      tailing: [
        if (notShowPages.isNotEmpty)
          MiuixIconButton(onPressed: () {
              showMiuixDialog(
                context: context,
                title: "添加".tl,
                contentBuilder: (context, close) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: notShowPages
                      .map((e) => buildNotShowPageSelector(e, context))
                      .toList(),
                ),
              );
            }, child: _mi(MiuixIcons.os4.add))
      ],
      body: view,
    );
  }
}

void clearUserData(BuildContext context) {
  showConfirmDialog(
    context,
    "警告".tl,
    "此操作无法撤销, 是否继续?".tl,
    () async {
      await clearAppdata();
      App.offAll(() => const WelcomePage());
      MyApp.updater?.call();
    },
  );
}

void exportDataSetting(BuildContext context) {
  void export(bool includeDownloads) async {
    var dialog = showLoadingDialog(context, allowCancel: false);
    var res = await runExportData(includeDownloads);
    if (context.mounted) {
      if (res) {
        dialog.close();
        showToast(message: "成功导出".tl);
      } else {
        dialog.close();
        showToast(message: "导出失败".tl);
      }
    }
  }

  showMiuixDialog(
      context: context,
      title: "导出用户数据".tl,
      summary: "将导出设置, 账号, 历史记录, 下载内容, 本地收藏等数据".tl,
      contentBuilder: (context, close) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixButton(
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  onPressed: () {
                    close();
                    export(true);
                  },
                  child: Text("导出所有数据".tl)),
              const SizedBox(height: 12),
              MiuixTextButton(
                  onPressed: () {
                    close();
                    export(false);
                  },
                  "导出不含下载的数据".tl),
              const SizedBox(height: 12),
              MiuixTextButton(onPressed: () => close(), "取消".tl),
            ],
          ));
}

void importDataSetting(BuildContext context) {
  showMiuixDialog(
      context: context,
      title: "导入用户数据".tl,
      summary: "${"将导入设置, 账号, 历史记录, 下载内容, 本地收藏等数据, 现在的所有数据将会被覆盖".tl}"
          "\n${"如果导入的数据中包含下载数据, 则当前的下载数据也将被覆盖".tl}",
      actionsBuilder: (context, close) => [
            MiuixTextButton(onPressed: () => close(), "取消".tl),
            MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () {
                  close();
                  var dialog = showLoadingDialog(App.globalContext!, allowCancel: false);
                  importData().then((v) {
                    dialog.close();
                    if (v) {
                      showToast(message: "成功导入".tl);
                    } else {
                      showToast(message: "导入失败".tl);
                    }
                  });
                },
                child: Text("继续".tl)),
          ]);
}

Future<void> syncDataSettings(BuildContext context) async {
  var configs = ["", "", "", ""];
  if (appdata.settings[45] != "") {
    configs = appdata.settings[45].split(';');
  }
  while (configs.length < 4) {
    configs.add("");
  }
  final urlCtrl = TextEditingController(text: configs[0]);
  final userCtrl = TextEditingController(text: configs[1]);
  final pwdCtrl = TextEditingController(text: configs[2]);
  final pathCtrl = TextEditingController(text: configs[3]);
  int value = 0;
  String joined() =>
      "${urlCtrl.text};${userCtrl.text};${pwdCtrl.text};${pathCtrl.text}";

  await showMiuixDialog(
    context: context,
    title: "Webdav",
    contentBuilder: (context, close) {
      final colors = MiuixTheme.of(context).colors;
      final mq = MediaQuery.of(context);
      // 预留标题/边距与软键盘高度, 内容超出时滚动, 不再溢出
      var maxH =
          mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 200;
      if (maxH < 160) maxH = 160;
      Widget gap() => const SizedBox(height: 10);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixTextField(controller: urlCtrl, label: "URL", singleLine: true),
              gap(),
              MiuixTextField(
                  controller: userCtrl, label: "用户名".tl, singleLine: true),
              gap(),
              MiuixTextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  label: "密码".tl,
                  singleLine: true),
              gap(),
              MiuixTextField(
                  controller: pathCtrl, label: "储存路径".tl, singleLine: true),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text("立即执行".tl,
                    style: TextStyle(
                        fontSize: 13, color: colors.onSurfaceVariantSummary)),
              ),
              StatefulBuilder(builder: (context, stateSetter) {
                Widget option(String title, int v) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => stateSetter(() => value = v),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        child: Row(children: [
                          Expanded(
                              child: Text(title,
                                  style: TextStyle(
                                      fontSize: 15, color: colors.onSurface))),
                          AnimatedOpacity(
                            opacity: value == v ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: MiuixIcon(
                                vector: MiuixIcons.os4.ok,
                                size: 20,
                                tint: colors.primary),
                          ),
                        ]),
                      ),
                    );
                return Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: colors.secondaryContainer,
                    shape: const MiuixSquircleBorder(cornerRadius: 14),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    option("上传数据".tl, 0),
                    option("下载数据".tl, 1),
                  ]),
                );
              }),
              const SizedBox(height: 10),
              Row(
                children: [
                  MiuixIcon(
                      vector: MiuixIcons.os4.info,
                      size: 16,
                      tint: colors.onSurfaceVariantSummary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text("将URL留空以禁用同步".tl,
                        style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariantSummary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: MiuixTextButton("取消".tl, onPressed: () => close()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MiuixButton(
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: Text("提交".tl),
                    onPressed: () async {
                      final cfg = joined();
                      if (urlCtrl.text.trim().isEmpty) {
                        appdata.settings[45] = cfg;
                        appdata.updateSettings();
                        close();
                        return;
                      }
                      var dialog = showLoadingDialog(context,
                          allowCancel: false, barrierDismissible: false);
                      var res = value == 0
                          ? await Webdav.uploadData(cfg)
                          : await Webdav.downloadData(cfg);
                      dialog.close();
                      if (!res) {
                        showToast(message: "同步失败".tl);
                      } else {
                        appdata.settings[45] = cfg;
                        appdata.updateSettings();
                        close();
                      }
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      );
    },
  );
}

void setCacheLimit() {
  int size = appdata.appSettings.cacheLimit;
  const minSize = 16;
  bool isValid = true;
  final FocusNode focusNode = FocusNode();
  final TextEditingController controller = TextEditingController(text: size.toString());
  showMiuixDialog(
    context: App.globalContext!,
    title: "设置缓存限制".tl,
    contentBuilder: (context, close) => StatefulBuilder(
      builder: (context, setState) {
        focusNode.requestFocus();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixTextField(
              focusNode: focusNode,
              controller: controller,
              keyboardType: TextInputType.number,
              label: "MB",
              trailingIcon: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Text("MB"),
              ),
              onChanged: (s) {
                size = int.tryParse(s) ?? 500;
                setState(() {
                  isValid = size < minSize ? false : true;
                });
              },
            ),
            if (!isValid)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  "${"不能小于".tl} $minSize MB",
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            MiuixButton(
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: Text("确认".tl),
              onPressed: () {
                if (size < minSize) {
                  setState(() {
                    isValid = false;
                  });
                  return;
                } else {
                  appdata.appSettings.cacheLimit = size;
                  appdata.writeData();
                  CacheManager().setLimitSize(size);
                  close();
                }
              },
            ),
          ],
        );
      },
    ),
  );
}


String downloadFolderSummary() {
  final custom = appdata.settings[22].trim();
  if (custom.isEmpty) {
    return "默认（应用私有）".tl;
  }
  return friendlyStoragePath(custom);
}

String imageSaveFolderSummary() {
  final custom = appdata.settings[93].trim();
  if (custom.isEmpty) {
    return "默认（系统相册）".tl;
  }
  return friendlyStoragePath(custom);
}

bool _isAppPrivateStoragePath(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  return p.contains('/data/user/') ||
      p.contains('/data/data/') ||
      p.contains('/android/data/');
}

bool _needsManageStorageForPath(String path) {
  if (!App.isAndroid) return false;
  return !_isAppPrivateStoragePath(path);
}

/// 设置页展示用：不泄露应用私有真实路径；自定义目录尽量显示相对内部存储的可读路径。
String friendlyStoragePath(String path) {
  var p = path.trim().replaceAll('\\', '/');
  if (p.isEmpty) return "";
  if (_isAppPrivateStoragePath(p)) {
    return "应用私有".tl;
  }
  const prefixes = <String>[
    '/storage/emulated/0/',
    '/sdcard/',
    'storage/emulated/0/',
  ];
  for (final prefix in prefixes) {
    if (p.toLowerCase().startsWith(prefix)) {
      return p.substring(prefix.length);
    }
  }
  if (p.startsWith('content://')) {
    final decoded = Uri.decodeComponent(p);
    final marker = decoded.contains('%3A') ? '%3A' : ':';
    final idx = decoded.lastIndexOf(marker);
    if (idx >= 0 && idx + marker.length < decoded.length) {
      return decoded.substring(idx + marker.length).replaceAll('+', '/');
    }
    final segs = decoded.split('/');
    return segs.isNotEmpty ? segs.last : "已选目录".tl;
  }
  return p;
}

class DirectoryPickResult {
  const DirectoryPickResult({this.path, this.uri, this.displayName});
  final String? path;
  final String? uri;
  final String? displayName;
}

/// Android：系统文件管理器选目录并持久化 URI 权限；桌面：原生文件夹选择。
Future<DirectoryPickResult?> pickStorageDirectory() async {
  if (App.isAndroid) {
    try {
      final raw = await const MethodChannel("pica_comic/settings")
          .invokeMethod("pick_directory");
      if (raw == null) return null;
      final map = Map<String, dynamic>.from(raw as Map);
      final path = (map['path'] as String?)?.trim();
      final uri = map['uri'] as String?;
      final displayName = map['displayName'] as String?;
      return DirectoryPickResult(
        path: (path != null && path.isNotEmpty) ? path : null,
        uri: uri,
        displayName: displayName,
      );
    } catch (e) {
      showToast(message: "${"选择失败".tl}: $e");
      return null;
    }
  }
  final path = await getDirectoryPath();
  if (path == null || path.trim().isEmpty) return null;
  final cleaned = path.trim();
  final name = cleaned.replaceAll('\\', '/').split('/').last;
  return DirectoryPickResult(path: cleaned, displayName: name);
}

Future<void> setImageSaveFolder() async {
  if (App.globalContext == null) return;
  await showMiuixDialog(
    context: App.globalContext!,
    title: "图片保存目录".tl,
    contentBuilder: (context, close) => const SetImageSaveFolderDialog(),
  );
}

class SetImageSaveFolderDialog extends StatefulWidget {
  const SetImageSaveFolderDialog({super.key});

  @override
  State<SetImageSaveFolderDialog> createState() =>
      _SetImageSaveFolderDialogState();
}

class _SetImageSaveFolderDialogState extends State<SetImageSaveFolderDialog> {
  late String current;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    current = appdata.settings[93];
  }

  bool get _isDefault => current.trim().isEmpty;

  Future<void> _pickFolder() async {
    if (busy) return;
    final picked = await pickStorageDirectory();
    if (picked == null) return;
    if (picked.path == null || picked.path!.trim().isEmpty) {
      showToast(message: "请选择内部存储目录".tl);
      return;
    }
    setState(() => current = picked.path!.trim());
  }

  Future<bool> _ensureWritable(String path) async {
    if (!App.isAndroid) return true;
    if (!_needsManageStorageForPath(path)) return true;
    final have = await const MethodChannel("pica_comic/settings")
            .invokeMethod("files_check") ==
        true;
    if (have) return true;
    showToast(message: "需要所有文件访问权限".tl);
    await const MethodChannel("pica_comic/settings").invokeMethod("files");
    return false;
  }

  void _reset() {
    if (busy) return;
    setState(() => current = "");
  }

  Future<void> _confirm() async {
    if (busy) return;
    final path = current.trim();
    if (path.isNotEmpty) {
      final ok = await _ensureWritable(path);
      if (!ok) return;
      try {
        final dir = Directory(path);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (e) {
        showToast(message: "${"目录不可用".tl}: $e");
        return;
      }
    }
    setState(() => busy = true);
    appdata.settings[93] = path;
    await appdata.updateSettings();
    if (!mounted) return;
    setState(() => busy = false);
    App.globalBack();
    showToast(message: "已更新".tl);
  }

  Widget _optionCard({
    required bool selected,
    required String title,
    required String summary,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        feedbackType: MiuixPressFeedbackType.sink,
        colors: selected
            ? MiuixCardColors(
                color: scheme.primaryContainer,
                contentColor: scheme.onPrimaryContainer,
              )
            : null,
        onPressed: busy ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _optionCard(
          selected: _isDefault,
          title: "默认".tl,
          summary: "系统相册".tl,
          onTap: () => setState(() => current = ""),
        ),
        _optionCard(
          selected: !_isDefault,
          title: "自定义".tl,
          summary: _isDefault
              ? "选择文件夹".tl
              : friendlyStoragePath(current),
          onTap: _pickFolder,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: MiuixTextButton(
                "重置".tl,
                onPressed: busy ? null : _reset,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: busy ? null : _confirm,
                child: Text(busy ? "处理中".tl : "确认".tl),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
