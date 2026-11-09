import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/app_dio.dart';

String? _updateInfo;

const _githubApiLatest =
    "https://api.github.com/repos/Qilaiwing/PicaComic_miuix/releases/latest";
const _githubHtmlLatest =
    "https://github.com/Qilaiwing/PicaComic_miuix/releases/latest";
const _githubAtom =
    "https://github.com/Qilaiwing/PicaComic_miuix/releases.atom";

Dio _updateDio({bool followRedirects = true}) {
  return logDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        "User-Agent": "PicaComic-MIUIX/$appVersion",
        "Accept":
            "application/vnd.github+json, application/atom+xml, text/html, */*",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      followRedirects: followRedirects,
      maxRedirects: followRedirects ? 5 : 0,
      validateStatus: (code) =>
          code != null &&
          ((code >= 200 && code < 300) || code == 301 || code == 302),
      responseType: ResponseType.plain,
    ),
  );
}

({String base, int miuix}) _parseAppTag(String raw) {
  var s = raw.trim();
  if (s.startsWith("v") || s.startsWith("V")) s = s.substring(1);
  final miuixMatch =
      RegExp(r'-miuix(\d*)$', caseSensitive: false).firstMatch(s);
  var miuix = 0;
  if (miuixMatch != null) {
    miuix = int.tryParse(miuixMatch.group(1)!) ?? 0;
    s = s.substring(0, miuixMatch.start);
  }
  s = s.split('-').first;
  return (base: s, miuix: miuix);
}

String _stripV(String tag) =>
    tag.startsWith("v") || tag.startsWith("V") ? tag.substring(1) : tag;

Future<String> getLatestVersion() async {
  final errors = <String>[];

  try {
    final dio = _updateDio();
    final res = await dio.get(
      _githubApiLatest,
      options: Options(
        responseType: ResponseType.json,
        headers: {"Accept": "application/vnd.github+json"},
      ),
    );
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map) {
        _updateInfo = data["body"]?.toString();
        final tag = data["tag_name"]?.toString();
        if (tag != null && tag.isNotEmpty) {
          _latestTag = tag;
          _latestAssets = _parseAssets(data["assets"]);
          LogManager.addLog(
              LogLevel.info, "Update", "latest tag=$tag (api)");
          return _stripV(tag);
        }
      }
    }
    errors.add("api status=${res.statusCode}");
  } catch (e) {
    errors.add("api: $e");
    LogManager.addLog(LogLevel.warning, "Update", "api failed: $e");
  }

  try {
    final dio = _updateDio(followRedirects: false);
    final res = await dio.get(_githubHtmlLatest);
    final loc = res.headers.value("location") ?? "";
    final m = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(loc);
    if (m != null) {
      final tag = Uri.decodeComponent(m.group(1)!);
      _latestTag = tag;
      _latestAssets = null;
      LogManager.addLog(
          LogLevel.info, "Update", "latest tag=$tag (html redirect)");
      if (_updateInfo == null) {
        try {
          await _loadUpdateInfoFromAtom();
        } catch (_) {}
      }
      return _stripV(tag);
    }
    errors.add("html loc=$loc status=${res.statusCode}");
  } catch (e) {
    errors.add("html: $e");
    LogManager.addLog(
        LogLevel.warning, "Update", "html redirect failed: $e");
  }

  try {
    final tag = await _latestTagFromAtom();
    if (tag != null) {
      _latestTag = tag;
      _latestAssets = null;
      LogManager.addLog(
          LogLevel.info, "Update", "latest tag=$tag (atom)");
      return _stripV(tag);
    }
    errors.add("atom: no tag");
  } catch (e) {
    errors.add("atom: $e");
    LogManager.addLog(LogLevel.warning, "Update", "atom failed: $e");
  }

  final msg = "getLatestVersion failed: ${errors.join(' | ')}";
  LogManager.addLog(LogLevel.error, "Update", msg);
  throw StateError(msg);
}

Future<void> _loadUpdateInfoFromAtom() async {
  final dio = _updateDio();
  final res = await dio.get(_githubAtom);
  final body = res.data?.toString() ?? "";
  final entry = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(body);
  if (entry == null) return;
  final content = RegExp(r'<content[^>]*>([\s\S]*?)</content>')
      .firstMatch(entry.group(1)!);
  if (content != null) {
    final text = _htmlToMarkdown(content.group(1)!
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&'));
    if (text.isNotEmpty) _updateInfo = text;
  }
}

/// 把 GitHub atom 里的 release HTML 转成简易 Markdown, 保留标题 / 列表 / 段落。
String _htmlToMarkdown(String html) {
  var s = html;
  s = s.replaceAllMapped(
      RegExp(r'<h([1-6])[^>]*>([\s\S]*?)</h\1>', caseSensitive: false),
      (m) => "\n${'#' * int.parse(m.group(1)!)} ${m.group(2)}\n");
  s = s.replaceAllMapped(RegExp(r'<li[^>]*>', caseSensitive: false), (_) => "\n- ");
  s = s.replaceAllMapped(
      RegExp(r'<(strong|b)>([\s\S]*?)</\1>', caseSensitive: false),
      (m) => "**${m.group(2)}**");
  s = s.replaceAllMapped(
      RegExp(r'<code>([\s\S]*?)</code>', caseSensitive: false),
      (m) => "`${m.group(1)}`");
  s = s.replaceAllMapped(
      RegExp(r'<a [^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>', caseSensitive: false),
      (m) => "[${m.group(2)}](${m.group(1)})");
  s = s.replaceAll(RegExp(r'<br\s*/?>|</p>|</ul>|</ol>|<hr\s*/?>', caseSensitive: false), "\n");
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.split('\n').map((l) => l.trim()).join('\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

Future<String?> _latestTagFromAtom() async {
  final dio = _updateDio();
  final res = await dio.get(_githubAtom);
  final body = res.data?.toString() ?? "";
  final entry = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(body);
  if (entry == null) return null;
  final block = entry.group(1)!;
  final link = RegExp(
          r'href="https://github\.com/[^"]+/releases/tag/([^"]+)"')
      .firstMatch(block);
  if (link != null) {
    await _loadUpdateInfoFromAtom();
    return Uri.decodeComponent(link.group(1)!);
  }
  final titles = RegExp(r'<title>([^<]*)</title>')
      .allMatches(block)
      .map((m) => m.group(1)!.trim())
      .toList();
  for (final t in titles) {
    final vm = RegExp(r'v?\d+\.\d+\.\d+(?:-miuix\d*)?',
            caseSensitive: false)
        .firstMatch(t);
    if (vm != null) {
      await _loadUpdateInfoFromAtom();
      return vm.group(0)!;
    }
  }
  return null;
}

Future<bool?> checkUpdate() async {
  try {
    final local = appVersion;
    final remote = await getLatestVersion();
    _latestVersion = remote;
    LogManager.addLog(
        LogLevel.info, "Update", "compare remote=$remote local=$local");
    return compareSemVer(remote, local);
  } catch (e) {
    LogManager.addLog(LogLevel.error, "Update", "checkUpdate: $e");
    return null;
  }
}

/// 用缓存的待更新信息填充内存态, 以便弹窗内下载仍能工作。
void hydratePendingUpdate({
  required String version,
  String? tag,
  String? notes,
}) {
  _latestVersion = version;
  if (tag != null && tag.isNotEmpty) {
    _latestTag = tag.startsWith("v") || tag.startsWith("V") ? tag : "v$tag";
  } else {
    _latestTag = "v$version";
  }
  if (notes != null && notes.trim().isNotEmpty) {
    _updateInfo = notes;
  }
  _latestAssets = null;
}

/// 清除内存中的最新 release 缓存 (本机已追上或不再有更新时)。
void clearPendingUpdateMemory() {
  _latestVersion = null;
  _latestTag = null;
  _updateInfo = null;
  _latestAssets = null;
}


bool compareSemVer(String ver1, String ver2) {
  final a = _parseAppTag(ver1);
  final b = _parseAppTag(ver2);
  final v1 = a.base.split('.');
  final v2 = b.base.split('.');
  for (var i = 0; i < 3; i++) {
    final num1 = int.tryParse(v1.elementAtOrNull(i) ?? '0') ?? 0;
    final num2 = int.tryParse(v2.elementAtOrNull(i) ?? '0') ?? 0;
    if (num1 > num2) return true;
    if (num1 < num2) return false;
  }
  if (a.miuix != b.miuix) return a.miuix > b.miuix;
  return false;
}

/// 返回最新版本的更新日志 (Markdown), 拿不到时返回 null。
Future<String?> getUpdatesInfo() async {
  if (_updateInfo == null) {
    try {
      await _loadUpdateInfoFromAtom();
    } catch (_) {}
  }
  final text = _updateInfo?.replaceAll('\r\n', '\n').trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

String? _latestVersion;

/// 最近一次检查得到的最新版本号 (不含 v 前缀)。
String? get latestVersion => _latestVersion;

Future<String> getDownloadUrl() async {
  if (_latestTag != null) {
    return "https://github.com/Qilaiwing/PicaComic_miuix/releases/tag/${Uri.encodeComponent(_latestTag!)}";
  }
  return "https://github.com/Qilaiwing/PicaComic_miuix/releases/latest";
}

// ---------------------------------------------------------------------------
// 当前版本更新日志 / 应用内下载安装
// ---------------------------------------------------------------------------

const _repo = "Qilaiwing/PicaComic_miuix";

String? _latestTag;
List<ReleaseAsset>? _latestAssets;

/// 最近一次检查得到的 release tag (含 v 前缀)。
String? get latestTag => _latestTag;

class ReleaseAsset {
  final String name;
  final String url;
  final int size;

  const ReleaseAsset(this.name, this.url, this.size);
}

List<ReleaseAsset>? _parseAssets(dynamic raw) {
  if (raw is! List) return null;
  final res = <ReleaseAsset>[];
  for (final a in raw) {
    if (a is! Map) continue;
    final name = a["name"]?.toString();
    final url = a["browser_download_url"]?.toString();
    if (name == null || url == null) continue;
    res.add(ReleaseAsset(name, url, (a["size"] as num?)?.toInt() ?? 0));
  }
  return res;
}

/// 拉取已安装版本 (appVersion) 对应 release 的更新日志。
/// 返回 (tag, notes)；找不到对应 tag 时 notes 为 null。
Future<({String tag, String? notes, bool found})> getCurrentVersionNotes() async {
  const tag = "v$appVersion";
  final dio = _updateDio();
  try {
    final res = await dio.get(
      "https://api.github.com/repos/$_repo/releases/tags/${Uri.encodeComponent(tag)}",
      options: Options(
        responseType: ResponseType.json,
        headers: {"Accept": "application/vnd.github+json"},
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    if (res.statusCode == 200 && res.data is Map) {
      final body = (res.data as Map)["body"]?.toString().replaceAll('\r\n', '\n').trim();
      return (tag: tag, notes: (body == null || body.isEmpty) ? null : body, found: true);
    }
    if (res.statusCode == 404) {
      return (tag: tag, notes: null, found: false);
    }
  } catch (e) {
    LogManager.addLog(LogLevel.warning, "Update", "current notes api failed: $e");
  }
  // 回退: atom feed 里找同名 tag 的条目
  try {
    final res = await dio.get(_githubAtom);
    final body = res.data?.toString() ?? "";
    for (final m in RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(body)) {
      final block = m.group(1)!;
      final link = RegExp(r'/releases/tag/([^"]+)"').firstMatch(block);
      if (link == null || Uri.decodeComponent(link.group(1)!) != tag) continue;
      final content = RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(block);
      if (content == null) return (tag: tag, notes: null, found: true);
      final text = _htmlToMarkdown(content.group(1)!
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&amp;', '&'));
      return (tag: tag, notes: text.isEmpty ? null : text, found: true);
    }
    return (tag: tag, notes: null, found: false);
  } catch (e) {
    LogManager.addLog(LogLevel.warning, "Update", "current notes atom failed: $e");
    rethrow;
  }
}

String getReleasePageUrl([String? tag]) => tag == null
    ? "https://github.com/$_repo/releases/latest"
    : "https://github.com/$_repo/releases/tag/${Uri.encodeComponent(tag)}";

const _deviceChannel = MethodChannel("com.picacomic_miuix/device");
const _installChannel = MethodChannel("com.picacomic_miuix/installer");

Future<String> _deviceAbi() async {
  try {
    return (await _deviceChannel.invokeMethod<String>("abi")) ?? "arm64-v8a";
  } catch (_) {
    return "arm64-v8a";
  }
}

/// 从 HTML 的 expanded_assets 页面解析 apk (API 限流时的回退)。
Future<List<ReleaseAsset>> _assetsFromHtml(String tag) async {
  final dio = _updateDio();
  final res = await dio.get(
      "https://github.com/$_repo/releases/expanded_assets/${Uri.encodeComponent(tag)}");
  final body = res.data?.toString() ?? "";
  final list = <ReleaseAsset>[];
  for (final m in RegExp(r'href="(/[^"]+/releases/download/[^"]+\.apk)"')
      .allMatches(body)) {
    final path = m.group(1)!;
    list.add(ReleaseAsset(
        Uri.decodeComponent(path.split('/').last), "https://github.com$path", 0));
  }
  return list;
}

/// 为当前设备选择最新 release 的 apk: 优先匹配 ABI, 其次 arm64-v8a, 最后任意 .apk。
Future<ReleaseAsset?> pickLatestApk() async {
  final tag = _latestTag;
  var assets = _latestAssets;
  if ((assets == null || assets.isEmpty) && tag != null) {
    try {
      assets = await _assetsFromHtml(tag);
    } catch (e) {
      LogManager.addLog(LogLevel.warning, "Update", "assets html failed: $e");
    }
  }
  final apks = (assets ?? const <ReleaseAsset>[])
      .where((a) => a.name.toLowerCase().endsWith(".apk"))
      .toList();
  if (apks.isEmpty) return null;
  final abi = (await _deviceAbi()).toLowerCase();
  for (final want in [abi, "arm64-v8a"]) {
    for (final a in apks) {
      if (a.name.toLowerCase().contains(want)) return a;
    }
  }
  final universal = apks.where((a) => a.name.toLowerCase().contains("universal"));
  if (universal.isNotEmpty) return universal.first;
  return apks.first;
}

/// 下载 apk 到应用缓存目录 update/ 下, 返回文件路径。
/// 走 app 的 Dio 适配器, 因此会遵循全局代理设置。
Future<String> downloadApk(
  ReleaseAsset asset, {
  required void Function(int received, int total) onProgress,
  CancelToken? cancelToken,
}) async {
  final dir = Directory("${(await getTemporaryDirectory()).path}/update");
  if (dir.existsSync()) {
    // 清掉旧安装包
    for (final f in dir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
  } else {
    dir.createSync(recursive: true);
  }
  final safeName = asset.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
  final path = "${dir.path}/$safeName";
  final tmp = "$path.part";
  final dio = logDio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    headers: {"User-Agent": "PicaComic-MIUIX/$appVersion"},
    followRedirects: true,
    maxRedirects: 8,
  ));
  try {
    await dio.download(asset.url, tmp,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (r, t) => onProgress(r, t > 0 ? t : asset.size));
  } catch (e) {
    try {
      File(tmp).deleteSync();
    } catch (_) {}
    rethrow;
  }
  final f = File(tmp);
  if (asset.size > 0 && f.lengthSync() != asset.size) {
    f.deleteSync();
    throw StateError("下载不完整");
  }
  f.renameSync(path);
  return path;
}

/// 调起系统安装器。返回 "ok" / "need_permission" / 错误信息。
Future<String> installApk(String path) async {
  try {
    final r = await _installChannel.invokeMethod<String>("install", {"path": path});
    return r ?? "ok";
  } on PlatformException catch (e) {
    return e.code == "need_permission" ? "need_permission" : (e.message ?? e.code);
  }
}

/// 打开「安装未知应用」权限设置页。
Future<void> openInstallPermissionSettings() async {
  try {
    await _installChannel.invokeMethod("permission");
  } catch (_) {}
}