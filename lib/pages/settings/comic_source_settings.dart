part of pica_settings;

class ComicSourceSettings extends StatefulWidget {
  const ComicSourceSettings({super.key});

  @override
  State<ComicSourceSettings> createState() => _ComicSourceSettingsState();
}

class _ComicSourceSettingsState extends State<ComicSourceSettings> {

  @override
  Widget build(BuildContext context) {
    final jsList = [
      ...ComicSource.sources.where((e) => !e.isBuiltIn),
      ...ComicSource.disabledJsSources,
    ];
    return Column(
      children: [
        buildCard(context),
        buildSpeedCard(context),
        MiuixSmallTitle("内置漫画源".tl),
        for (final key in builtInSources)
          _SourceExpandCard(
            key: ValueKey("builtin_$key"),
            sourceKey: key,
            latency: _latency[key],
            tested: _latency.containsKey(key),
            testing: _testing,
            onChanged: () {
              if (mounted) setState(() {});
            },
            onCheckUpdate: null,
            onTestNetwork: null,
            onDelete: null,
            onEdit: null,
          ),
        if (jsList.isNotEmpty) MiuixSmallTitle("JS 漫画源".tl),
        for (final source in jsList)
          _SourceExpandCard(
            key: ValueKey("js_${source.key}"),
            source: source,
            latency: _latency[source.key],
            tested: _latency.containsKey(source.key),
            testing: _testing,
            onChanged: () {
              if (mounted) setState(() {});
            },
            onCheckUpdate: () => checkUpdate(source),
            onTestNetwork: () => testNetwork(source),
            onDelete: () => delete(source),
            onEdit: App.isDesktop ? () => edit(source) : null,
          ),
        Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16))
      ],
    );
  }

  // Widget buildCustomSettings() {
  //   return Column(
  //     children: [
  //       ListTile(
  //         title: Text("自定义漫画源".tl),
  //       ),
  //       ListTile(
  //         leading: const Icon(Icons.update_outlined),
  //         title: Text("检查更新".tl),
  //         onTap: () => ComicSourceSettings.checkCustomComicSourceUpdate(true),
  //         trailing: const Icon(Icons.arrow_right),
  //       ),
  //       SwitchSetting(
  //         title: "启动时检查更新".tl,
  //         icon: const Icon(Icons.security_update),
  //         settingsIndex: 80,
  //       )
  //     ],
  //   );
  // }

  /// 检查更新：拉取远程脚本，比较版本，按需替换并重新加载
  Future<void> checkUpdate(ComicSource source) async {
    if (source.url.trim().isEmpty) {
      showToast(message: "暂未配置更新地址".tl);
      return;
    }
    bool cancel = false;
    var controller = showLoadingDialog(App.globalContext!,
        onCancel: () => cancel = true, barrierDismissible: false);
    String code;
    try {
      var res = await logDio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15)))
          .get<String>(source.url,
              options: Options(responseType: ResponseType.plain));
      code = res.data ?? "";
      if (code.isEmpty) throw "Empty response";
    } catch (e) {
      if (cancel) return;
      controller.close();
      showToast(message: "${"检查更新失败".tl}: $e");
      return;
    }
    if (cancel) return;
    controller.close();
    var remote = ComicSource.scriptVersionOf(code);
    if (remote == null) {
      showToast(message: "${"检查更新失败".tl}: version");
      return;
    }
    if (!compareSemVer(remote, source.version)) {
      showToast(message: "已是最新".tl);
      return;
    }
    showConfirmDialog(App.globalContext!, "发现新版本".tl,
        "${source.version} → $remote", () async {
      try {
        await ComicSource.applyScriptUpdate(source, code);
        showToast(message: "更新成功".tl);
      } catch (e) {
        showToast(message: "${"更新失败".tl}: $e");
      }
      _validatePages();
      if (mounted) setState(() {});
    });
  }

  Future<void> testNetwork(ComicSource source) async {
    var controller = showLoadingDialog(App.globalContext!,
        barrierDismissible: false);
    var watch = Stopwatch()..start();
    String msg;
    try {
      if (source.explorePages.isEmpty) throw "此源没有可测试的页面".tl;
      var page = source.explorePages.first;
      dynamic res;
      if (page.loadPage != null) {
        res = await page.loadPage!(1);
      } else if (page.loadMultiPart != null) {
        res = await page.loadMultiPart!();
      } else {
        throw "此源没有可测试的页面".tl;
      }
      if (res.error) throw res.errorMessage ?? "Error";
      msg = "${"连接成功".tl} · ${watch.elapsedMilliseconds} ms";
    } catch (e) {
      msg = "${"连接失败".tl}: ${_readableError(e)}";
    }
    controller.close();
    showToast(message: msg);
  }

  void delete(ComicSource source) {
    showConfirmDialog(App.globalContext!, "删除".tl, "要删除此漫画源吗?".tl, () async {
      await ComicSource.deleteJsSource(source);
      _validatePages();
      if (mounted) setState(() {});
      MyApp.updater?.call();
    });
  }

  void edit(ComicSource source) async {
    try {
      await Process.run("code", [source.filePath], runInShell: true);
      showConfirmDialog(
        App.globalContext!,
        "Reload Configs",
        "Reload configurations?",
        () async {
          await ComicSource.reload();
          MyApp.updater?.call();
        },
      );
    } catch (e) {
      showToast(message: "Failed to launch vscode");
    }
  }


  Widget buildCard(BuildContext context) {
    return MiuixSettingsCard(
      children: [
        MiuixArrowPreference(
          startAction: _mi(MiuixIcons.os4.add),
          title: "添加漫画源".tl,
          summary: "从项目仓库拉取可用漫画源".tl,
          onClick: () => _showRepoDialog(context),
        ),
      ],
    );
  }

  // ---------------- 连通性 / 测速 ----------------
  final Map<String, int?> _latency = {};
  bool _testing = false;
  bool _tested = false;

  static const _knownHosts = <String, String>{
    "picacg": "picaapi.picacomic.com",
    "ehentai": "e-hentai.org",
    "jm": "18comic.vip",
    "hitomi": "hitomi.la",
    "htmanga": "www.wnacg.com",
    "nhentai": "nhentai.net",
    "copy_manga": "api.copy202601.com",
    "baozi": "www.baozimh.com",
    "manhuagui": "www.manhuagui.com",
    "mangadex": "api.mangadex.org",
  };

  String? _hostOf(ComicSource source) {
    if (!source.isBuiltIn) {
      try {
        final data = source.data["settings"];
        if (data is Map) {
          final b = data["base_url"];
          if (b is String && b.trim().isNotEmpty) {
            return b.trim().replaceAll(RegExp(r"^https?://"), "").split("/").first;
          }
        }
      } catch (_) {}
    }
    final known = _knownHosts[source.key];
    if (known != null) return known;
    if (!source.isBuiltIn && source.filePath.isNotEmpty) {
      try {
        final code = File(source.filePath).readAsStringSync();
        final m = RegExp(r"https?://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})").firstMatch(code);
        if (m != null) return m.group(1);
      } catch (_) {}
    }
    return null;
  }

  Future<int?> _ping(String host) async {
    final dio = logDio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      sendTimeout: const Duration(seconds: 6),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ));
    final sw = Stopwatch()..start();
    try {
      await dio.head<String>("https://$host/");
      return sw.elapsedMilliseconds;
    } on DioException catch (e) {
      if (e.response != null) return sw.elapsedMilliseconds;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runSpeedTest() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _latency.clear();
    });
    final list = List<ComicSource>.from(ComicSource.sources);
    await Future.wait(list.map((s) async {
      final host = _hostOf(s);
      final ms = host == null ? null : await _ping(host);
      _latency[s.key] = ms;
      if (mounted) setState(() {});
    }));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _tested = true;
    });
  }

  Widget buildSpeedCard(BuildContext context) {
    final enabledCount = ComicSource.sources.length;
    final ok = _latency.values.where((e) => e != null).length;
    final hasResult = _tested || _testing;
    return MiuixSettingsCard(
      children: [
        MiuixBasicComponent(
          startAction: _mi(MiuixIcons.os4.refresh),
          title: "连通性检测".tl,
          endActions: [
            // 固定尺寸的紧凑按钮：检测中只换内容，不改变大小，卡片不会抖动。
            SizedBox(
              width: 76,
              height: 32,
              child: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                minWidth: 0,
                minHeight: 32,
                insideMargin: EdgeInsets.zero,
                onPressed: _testing ? null : _runSpeedTest,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _testing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MiuixInfiniteProgressIndicator(size: 12),
                          const SizedBox(width: 4),
                          Text("检测中".tl, style: const TextStyle(fontSize: 12)),
                        ],
                      )
                    : Text("检测".tl, style: const TextStyle(fontSize: 13)),
                ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              _StatTile(
                title: "已启用".tl,
                value: "$enabledCount",
                highlight: enabledCount > 0,
              ),
              const SizedBox(width: 10),
              _StatTile(
                title: "可用".tl,
                value: hasResult ? "$ok" : "—",
                highlight: hasResult && ok > 0,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showRepoDialog(BuildContext context) async {
    await showMiuixDialog<void>(
      context: context,
      title: "添加漫画源".tl,
      contentBuilder: (dialogContext, close) => _RepoSourceDialog(
        onAdd: (url) async {
          await handleAddSource(url);
          if (mounted) setState(() {});
        },
      ),
      actionsBuilder: (dialogContext, close) => [
        MiuixButton(
          onPressed: () => close(),
          child: Text("关闭".tl),
        ),
      ],
    );
  }

  Future<void> handleAddSource(String url) async {
    if (url.isEmpty) {
      return;
    }
    var splits = url.split("/");
    splits.removeWhere((element) => element == "");
    var fileName = splits.last;
    bool cancel = false;
    var controller = showLoadingDialog(App.globalContext!,
        onCancel: () => cancel = true, barrierDismissible: false);
    try {
      var res = await logDio()
          .get<String>(url, options: Options(responseType: ResponseType.plain));
      if (cancel) return;
      controller.close();
      await addSource(res.data!, fileName);
    } catch (e) {
      if (cancel) return;
      showToast(message: e.toString());
    }
  }

  Future<void> addSource(String js, String fileName) async {
    var comicSource = await ComicSourceParser().createAndParse(js, fileName);
    ComicSource.sources.add(comicSource);
    _addAllPagesWithComicSource(comicSource);
    appdata.updateSettings();
    MyApp.updater?.call();
  }
}

/// JS 漫画源 `settings` 中声明的单个设置项
class JsSourceSettingTile extends StatefulWidget {
  const JsSourceSettingTile({
    required this.source,
    required this.settingKey,
    required this.config,
    this.onChanged,
  });

  final ComicSource source;
  final String settingKey;
  final Map<String, dynamic> config;
  final VoidCallback? onChanged;

  @override
  State<JsSourceSettingTile> createState() => JsSourceSettingTileState();
}

class JsSourceSettingTileState extends State<JsSourceSettingTile> {
  Map<String, dynamic> get _saved {
    var s = widget.source.data["settings"];
    if (s is Map) return Map<String, dynamic>.from(s);
    return {};
  }

  dynamic get _value =>
      _saved[widget.settingKey] ?? widget.config["default"];

  void _save(dynamic value) {
    var s = _saved;
    s[widget.settingKey] = value;
    widget.source.data["settings"] = s;
    widget.source.saveData();
    setState(() {});
  }

  String get _title => (widget.config["title"] ?? widget.settingKey).toString();

  @override
  Widget build(BuildContext context) {
    switch (widget.config["type"]) {
      case "select":
        var options = (widget.config["options"] as List? ?? [])
            .whereType<Map>()
            .toList();
        var values = options.map((e) => e["value"].toString()).toList();
        var texts = options
            .map((e) => (e["text"] ?? e["value"]).toString().tl)
            .toList();
        var index = values.indexOf(_value?.toString() ?? "");
        return SelectSetting(
          leading: _mi(MiuixIcons.os4.tune),
          title: _title.tl,
          values: texts,
          initialValue: index < 0 ? 0 : index,
          onChanged: (i) => _save(values[i]),
        );
      case "callback":
        return MiuixBasicComponent(
          startAction: _mi(MiuixIcons.os4.forward),
          title: _title.tl,
          endActions: [
            MiuixButton(
              onPressed: _runCallback,
              child: Text(
                  (widget.config["buttonText"] ?? "执行").toString().tl),
            ),
          ],
        );
      case "switch":
        return MiuixSwitchPreference(
          startAction: _mi(MiuixIcons.os4.tune),
          title: _title.tl,
          value: _value == true,
          onChanged: (v) => _save(v),
        );
      default:
        return MiuixArrowPreference(
          startAction: _mi(MiuixIcons.os4.edit),
          title: _title.tl,
          summary: (_value ?? "").toString().isEmpty
              ? (widget.config["placeholder"] ?? "").toString().tl
              : _value.toString(),
          onClick: _edit,
        );
    }
  }

  void _edit() async {
    var controller = TextEditingController(text: (_value ?? "").toString());
    bool submit = false;
    await showMiuixDialog<void>(
      context: App.globalContext!,
      title: _title.tl,
      contentBuilder: (dialogContext, close) => MiuixTextField(
        label: _title.tl,
        controller: controller,
        singleLine: true,
        onSubmitted: (s) {
          submit = true;
          close();
        },
      ),
      actionsBuilder: (dialogContext, close) => [
        MiuixButton(
          child: Text("恢复默认".tl),
          onPressed: () {
            controller.text = (widget.config["default"] ?? "").toString();
          },
        ),
        MiuixButton(
          colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
          child: Text("确认".tl),
          onPressed: () {
            submit = true;
            close();
          },
        ),
      ],
    );
    if (!submit) return;
    var text = controller.text.trim();
    var validator = widget.config["validator"];
    if (validator is String && validator.isNotEmpty) {
      try {
        if (!RegExp(validator).hasMatch(text)) {
          showToast(message: "格式不正确".tl);
          return;
        }
      } catch (_) {}
    }
    _save(text);
    widget.onChanged?.call();
  }

  void _runCallback() async {
    try {
      var res = await JsEngine().runCode(
          "ComicSource.sources.${widget.source.key}.settings[${jsonEncode(widget.settingKey)}].callback()");
      showToast(
          message: res == null || res == "ok" ? "完成".tl : res.toString());
    } catch (e) {
      showToast(message: e.toString());
    }
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }
}

/// JS 源账号区：显示登录状态、凭证校验结果、重新登录与退出登录
class JsAccountSection extends StatefulWidget {
  const JsAccountSection({required this.source});

  final ComicSource source;

  @override
  State<JsAccountSection> createState() => JsAccountSectionState();
}

class JsAccountSectionState extends State<JsAccountSection> {
  bool? valid;
  bool checking = false;
  String? username;

  ComicSource get source => widget.source;

  @override
  void initState() {
    super.initState();
    check();
  }

  bool get _hasCheck => JsEngine().runCode(
          "typeof ComicSource.sources.${source.key}.account.checkStatus === 'function'") ==
      true;

  void check() async {
    if (!source.isLogin) return;
    var acc = source.data["account"];
    username = source.data["username"]?.toString() ??
        (acc is List && acc.isNotEmpty ? acc[0].toString() : null);
    if (!_hasCheck) return;
    setState(() => checking = true);
    try {
      var res = await JsEngine()
          .runCode("ComicSource.sources.${source.key}.account.checkStatus()");
      if (res is Map) {
        valid = res["valid"] == true;
        if (res["username"] != null) username = res["username"].toString();
      }
    } catch (e) {
      valid = null;
    }
    if (mounted) setState(() => checking = false);
  }

  void openLogin() async {
    var acc = source.account!;
    if (acc.onLogin != null) await acc.onLogin!(context);
    if (acc.login != null && mounted) {
      await context.to(() => SourceLoginPage(
            sourceName: source.name,
            login: acc.login!,
            loginWithSlider: acc.loginWithSlider,
            registerWebsite: acc.registerWebsite,
          ));
      source.saveData();
    }
    valid = null;
    if (mounted) setState(() {});
    check();
  }

  void reLogin() async {
    var controller = showLoadingDialog(App.globalContext!,
        barrierDismissible: false);
    var ok = await source.reLogin();
    controller.close();
    showToast(message: ok ? "登录成功".tl : (source.lastReLoginError ?? "登录失败".tl));
    check();
  }

  void logout() {
    showConfirmDialog(App.globalContext!, "退出登录".tl, "要退出登录吗?".tl, () {
      source.data["account"] = null;
      source.account?.logout();
      source.data.remove("username");
      source.saveData();
      valid = null;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = MiuixTheme.of(context).colors;
    if (!source.isLogin) {
      return MiuixArrowPreference(
        startAction: _mi(MiuixIcons.os4.contactsCircle),
        title: "未登录".tl,
        summary: "点击登录".tl,
        onClick: openLogin,
      );
    }
    String state;
    Color color;
    if (checking) {
      state = "检查中".tl;
      color = colors.onSurfaceVariantSummary;
    } else if (valid == true) {
      state = "凭证有效".tl;
      color = Colors.green;
    } else if (valid == false) {
      state = "凭证失效".tl;
      color = colors.error;
    } else {
      state = "未校验".tl;
      color = colors.onSurfaceVariantSummary;
    }
    return Column(
      children: [
        MiuixBasicComponent(
          startAction: _mi(MiuixIcons.os4.contactsCircle),
          title: "已登录".tl,
          content: [
            Text("${username ?? ""} · $state",
                style: TextStyle(color: color, fontSize: 14)),
          ],
          endActions: [
            MiuixPressable(
              onPressed: reLogin,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text("重新登录".tl,
                    style: TextStyle(color: colors.primary)),
              ),
            ),
          ],
          onClick: check,
        ),
        MiuixBasicComponent(
          startAction: _mi(MiuixIcons.os4.back, tint: Colors.red),
          content: [
            Text("退出登录".tl,
                style: const TextStyle(color: Colors.red, fontSize: 16)),
          ],
          onClick: logout,
        ),
      ],
    );
  }
}

/// 单个漫画源可折叠卡片：启用开关 + 账号 + 源设置。
class _SourceExpandCard extends StatefulWidget {
  const _SourceExpandCard({
    super.key,
    this.sourceKey,
    this.source,
    required this.onChanged,
    this.onCheckUpdate,
    this.onTestNetwork,
    this.onDelete,
    this.onEdit,
    this.latency,
    this.tested = false,
    this.testing = false,
  }) : assert(sourceKey != null || source != null);

  final int? latency;
  final bool tested;
  final bool testing;

  final String? sourceKey;
  final ComicSource? source;
  final VoidCallback onChanged;
  final Future<void> Function()? onCheckUpdate;
  final Future<void> Function()? onTestNetwork;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  State<_SourceExpandCard> createState() => _SourceExpandCardState();
}

class _SourceExpandCardState extends State<_SourceExpandCard> {
  bool toggling = false;

  ComicSource get source {
    if (widget.source != null) return widget.source!;
    final key = widget.sourceKey!;
    return ComicSource.builtIn.firstWhere((e) => e.key == key);
  }

  bool get isBuiltIn => source.isBuiltIn;

  bool get enabled {
    if (isBuiltIn) {
      return appdata.appSettings.isComicSourceEnabled(source.key);
    }
    return ComicSource.isJsSourceEnabled(source.key);
  }

  String get summary {
    final parts = <String>[];
    // 启用/停用；仅已登录时追加「 · 已登录」；未登录不显示登录态
    parts.add(enabled ? "启用".tl : "停用".tl);
    if (source.account != null && source.isLogin) {
      parts.add("已登录".tl);
    }
    if (!isBuiltIn && source.version.isNotEmpty) {
      parts.add("v${source.version}");
    }
    return parts.join(" · ");
  }

  Future<void> _setEnabled(bool v) async {
    if (toggling) return;
    setState(() => toggling = true);
    try {
      if (isBuiltIn) {
        appdata.appSettings.setComicSourceEnabled(source.key, v);
        await appdata.updateSettings();
        if (!v) {
          ComicSource.sources.removeWhere((e) => e.key == source.key);
          _validatePages();
        } else {
          var s = ComicSource.builtIn.firstWhere((e) => e.key == source.key);
          if (ComicSource.sources.every((e) => e.key != s.key)) {
            ComicSource.sources.add(s);
          }
          s.loadData();
          _addAllPagesWithComicSource(s);
        }
      } else {
        await ComicSource.setJsSourceEnabled(source, v);
        if (!v) {
          _validatePages();
        } else {
          _addAllPagesWithComicSource(source);
        }
      }
      ComicSource.notifySourcesChanged();
    } finally {
      if (mounted) {
        setState(() => toggling = false);
      }
      widget.onChanged();
    }
  }

  Widget? _builtInSettings() {
    if (!enabled) return null;
    switch (source.key) {
      case "picacg":
        return const PicacgSettings(false, embedded: true);
      case "ehentai":
        return const EhSettings(false, embedded: true);
      case "jm":
        return const JmSettings(false, embedded: true);
      case "hitomi":
        return const HitomiSettings(false, embedded: true);
      case "htmanga":
        return const HtSettings(false, embedded: true);
      case "nhentai":
        return const NhSettings(false, embedded: true);
      default:
        return null;
    }
  }

  List<Widget> _jsSettings() {
    if (isBuiltIn) return const [];
    return [
      for (var entry in source.jsSettings.entries)
        if (entry.value is Map &&
            !(source.account != null &&
                JsAccountRows.deviceKeys.contains(entry.key)))
          JsSourceSettingTile(
            source: source,
            settingKey: entry.key,
            config: Map<String, dynamic>.from(entry.value),
            onChanged: () {
              if (mounted) setState(() {});
              widget.onChanged();
            },
          ),
    ];
  }

  Widget? _latencyCapsule(BuildContext context) {
    if (!widget.tested) {
      if (widget.testing && enabled) {
        return const MiuixInfiniteProgressIndicator(size: 14);
      }
      return null;
    }
    final ms = widget.latency;
    final Color color;
    final String text;
    if (ms == null) {
      color = const Color(0xFFE53935);
      text = "不可用".tl;
    } else {
      text = "${ms}ms";
      color = ms < 300
          ? const Color(0xFF34A853)
          : ms < 800
              ? const Color(0xFFF29900)
              : const Color(0xFFE8710A);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600, height: 1.4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      MiuixSwitchPreference(
        startAction: _mi(MiuixIcons.os4.ok),
        title: "启用".tl,
        value: enabled,
        endActions: toggling
            ? const [MiuixInfiniteProgressIndicator(size: 20)]
            : null,
        onChanged: _setEnabled,
      ),
    ];

    if (source.account != null) {
      if (isBuiltIn) {
        children.add(
          BuiltInAccountRows(
            key: ValueKey("acc_${source.key}_${source.isLogin}"),
            source: source,
            onChanged: () {
              if (mounted) setState(() {});
              widget.onChanged();
            },
          ),
        );
      } else {
        children.add(
          JsAccountRows(
            key: ValueKey("acc_${source.key}_${source.isLogin}"),
            source: source,
            onChanged: () {
              if (mounted) setState(() {});
              widget.onChanged();
            },
          ),
        );
      }
    }

    final builtin = _builtInSettings();
    if (builtin != null) children.add(builtin);
    children.addAll(_jsSettings());

    if (!isBuiltIn) {
      children.add(
        MiuixArrowPreference(
          startAction: _mi(MiuixIcons.os4.update),
          title: "检查更新".tl,
          summary: "当前版本 v@v".tlParams({"v": source.version}),
          onClick: () => widget.onCheckUpdate?.call(),
        ),
      );
      children.add(
        MiuixArrowPreference(
          startAction: _mi(MiuixIcons.os4.link),
          title: "测试网络连通性".tl,
          summary: "实测向源发起一次连接测试".tl,
          onClick: () => widget.onTestNetwork?.call(),
        ),
      );
      if (widget.onEdit != null) {
        children.add(
          MiuixArrowPreference(
            startAction: _mi(MiuixIcons.os4.edit),
            title: "编辑代码".tl,
            onClick: () => widget.onEdit?.call(),
          ),
        );
      }
      children.add(
        MiuixArrowPreference(
          startAction: _mi(MiuixIcons.os4.delete, tint: Colors.red),
          title: "删除漫画源".tl,
          onClick: () => widget.onDelete?.call(),
        ),
      );
    }

    return MiuixSettingsCard(
      children: [
        MiuixExpandable(
          title: source.name.tl,
          summary: summary,
          startAction: _mi(MiuixIcons.os4.book),
          titleTrailing: _latencyCapsule(context),
          children: children,
        ),
      ],
    );
  }
}


void _validatePages() {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;

  var totalExplorePages = ComicSource.sources
      .map((e) => e.explorePages.map((e) => e.title))
      .expand((element) => element)
      .toList();
  var totalCategoryPages = ComicSource.sources
      .map((e) => e.categoryData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();
  var totalNetworkFavorites = ComicSource.sources
      .map((e) => e.favoriteData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();

  for (var page in List.from(explorePages)) {
    if (!totalExplorePages.contains(page)) {
      explorePages.remove(page);
    }
  }
  for (var page in List.from(categoryPages)) {
    if (!totalCategoryPages.contains(page)) {
      categoryPages.remove(page);
    }
  }
  for (var page in List.from(networkFavorites)) {
    if (!totalNetworkFavorites.contains(page)) {
      networkFavorites.remove(page);
    }
  }

  appdata.appSettings.explorePages = explorePages;
  appdata.appSettings.categoryPages = categoryPages;
  appdata.appSettings.networkFavorites = networkFavorites;

  appdata.updateSettings();
}

void _addAllPagesWithComicSource(ComicSource source) {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;

  if (source.explorePages.isNotEmpty) {
    for (var page in source.explorePages) {
      if (!explorePages.contains(page.title)) {
        explorePages.add(page.title);
      }
    }
  }
  if (source.categoryData != null &&
      !categoryPages.contains(source.categoryData!.key)) {
    categoryPages.add(source.categoryData!.key);
  }
  if (source.favoriteData != null &&
      !networkFavorites.contains(source.favoriteData!.key)) {
    networkFavorites.add(source.favoriteData!.key);
  }

  appdata.appSettings.explorePages = explorePages.toSet().toList();
  appdata.appSettings.categoryPages = categoryPages.toSet().toList();
  appdata.appSettings.networkFavorites = networkFavorites.toSet().toList();

  appdata.updateSettings();
}

/// 统一尺寸的 Miuix 矢量图标，保证各行图标对齐。
Widget _mi(MiuixVectorIcon v, {Color? tint}) =>
    SizedBox.square(dimension: 24, child: Center(child: MiuixIcon(vector: v, size: 22, tint: tint)));

/// 「添加漫画源」弹窗：拉取本项目仓库 index.json，每个源一张卡片。
class _RepoSourceDialog extends StatefulWidget {
  const _RepoSourceDialog({required this.onAdd});

  final Future<void> Function(String url) onAdd;

  @override
  State<_RepoSourceDialog> createState() => _RepoSourceDialogState();
}

class _RepoSourceDialogState extends State<_RepoSourceDialog> {
  static const _repoBase =
      "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/assets/comic_sources/";

  List? list;
  String? error;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      list = null;
      error = null;
    });
    try {
      final res = await logDio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15)))
          .get<String>("${_repoBase}index.json",
              options: Options(responseType: ResponseType.plain));
      if (res.statusCode != 200 || res.data == null) {
        throw "HTTP ${res.statusCode}";
      }
      final l = jsonDecode(res.data!) as List;
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted) setState(() => error = "$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text("${"网络错误".tl}: $error",
                style: theme.textStyles.body2
                    .copyWith(color: theme.colors.onSurfaceVariantSummary)),
          ),
          MiuixButton(onPressed: _load, child: Text("重试".tl)),
        ],
      );
    }
    if (list == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: MiuixCircularProgressIndicator()),
      );
    }
    final installed = [...ComicSource.sources, ...ComicSource.disabledJsSources]
        .map((e) => e.key)
        .toSet();
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in list!)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildItem(context, item, installed),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, dynamic item, Set<String> installed) {
    final theme = MiuixTheme.of(context);
    final key = "${item["key"]}";
    final has = installed.contains(key);
    final adding = _adding.contains(key);
    Widget action;
    if (has) {
      action = Text("已添加".tl,
          style: theme.textStyles.body2
              .copyWith(color: theme.colors.onSurfaceVariantSummary));
    } else if (adding) {
      action = const MiuixInfiniteProgressIndicator(size: 20);
    } else {
      action = MiuixButton(
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        onPressed: () async {
          setState(() => _adding.add(key));
          await widget.onAdd("$_repoBase${item["fileName"]}");
          if (mounted) setState(() => _adding.remove(key));
        },
        child: Text("添加".tl),
      );
    }
    return MiuixCard(
      cornerRadius: 16,
      insideMargin: EdgeInsets.zero,
      child: MiuixBasicComponent(
        startAction: _mi(MiuixIcons.os4.book),
        title: "${item["name"]}",
        summary: "v${item["version"]}",
        endActions: [action],
      ),
    );
  }
}


/// 与「我的」页统计磁贴同款：上方小灰字标签，下方主色粗体大数字。
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.highlight,
  });

  final String title;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onCard = MiuixTheme.of(context).colors.onSurface;
    final primary = MiuixTheme.of(context).colors.primary;
    final border = isDark ? const Color(0x0DFFFFFF) : const Color(0x0A000000);
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: border,
          shape: MiuixSquircleBorder(
            cornerRadius: 16,
            side: BorderSide(color: border, width: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: onCard.withOpacity(0.6)),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: highlight ? primary : onCard,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 把异常 / 源返回的错误整理成一句可读文本:
/// 去掉 HTML 标签、JS 堆栈、换行和过长内容, 避免在提示里显示源码。
String _readableError(Object? e) {
  var s = (e ?? "").toString();
  const prefixes = ["Exception: ", "DioException ", "Error: "];
  for (var p in prefixes) {
    if (s.startsWith(p)) s = s.substring(p.length);
  }
  final lower = s.toLowerCase();
  if (lower.contains("timeout") || lower.contains("timed out")) return "连接超时".tl;
  if (lower.contains("socketexception") || lower.contains("failed host lookup")) {
    return "网络错误".tl;
  }
  if (lower.contains("<html") || lower.contains("<!doctype") || lower.contains("<body")) {
    final m = RegExp(r"<title>(.*?)</title>", caseSensitive: false, dotAll: true).firstMatch(s);
    s = m?.group(1)?.trim() ?? "";
    if (s.isEmpty) return "服务器返回了无效内容".tl;
  }
  s = s.replaceAll(RegExp(r"<[^>]*>"), " ");
  s = s.split(RegExp(r"\n\s*at |\n#\d|\n")).first;
  s = s.replaceAll(RegExp(r"\s+"), " ").trim();
  if (s.isEmpty) return "未知错误".tl;
  if (s.length > 80) s = "${s.substring(0, 80)}…";
  return s;
}
