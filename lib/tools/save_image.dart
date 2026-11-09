import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/file_type.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:share_plus/share_plus.dart';

import '../foundation/app.dart';

const _settingsChannel = MethodChannel("pica_comic/settings");

/// settings[93]：自定义图片保存目录；空字符串表示走系统相册 / SAF。
String get imageSaveDirectorySetting => appdata.settings[93];

bool get hasCustomImageSaveDirectory =>
    imageSaveDirectorySetting.trim().isNotEmpty;

/// Android API < 29：写入公共目录需要 WRITE_EXTERNAL_STORAGE。
/// API 29+：相册 MediaStore 无需写权限；自定义外部路径仍可能需要「所有文件」权限。
Future<bool> _ensureAndroidWritePermission() async {
  if (!App.isAndroid) return true;
  try {
    final ok =
        await _settingsChannel.invokeMethod<bool>("request_storage") ?? false;
    return ok;
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "Save Image",
        "request_storage failed: $e\n$s");
    return false;
  }
}

Future<bool> _saveViaSaf(File file) async {
  try {
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: file.path),
    );
    return path != null && path.isNotEmpty;
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "Save Image", "SAF failed: $e\n$s");
    return false;
  }
}

Future<void> _saveToGallery(File file) async {
  final imageSaver = ImageGallerySaver();
  try {
    await imageSaver.saveFile(file.path);
    return;
  } catch (e) {
    LogManager.addLog(
        LogLevel.info, "Save Image", "saveFile failed, fallback bytes: $e");
  }
  final data = await file.readAsBytes();
  await imageSaver.saveImage(data);
}

String _uniqueFileName(String originalName, String ext) {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  var base = originalName;
  final dot = base.lastIndexOf('.');
  if (dot > 0) {
    base = base.substring(0, dot);
  }
  base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (base.isEmpty) base = "image";
  final e = ext.startsWith('.') ? ext : (ext.isEmpty ? '' : '.$ext');
  return "${base}_$stamp$e";
}

/// 写入用户自定义目录（settings[93]）。
Future<String> _saveToCustomDirectory(File file) async {
  final dirPath = imageSaveDirectorySetting.trim();
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  var data = await file.readAsBytes();
  var type = detectFileType(data);
  var name = file.name;
  if (!name.contains('.')) {
    name += type.ext;
  }
  final ext = name.contains('.') ? name.split('.').last : type.ext.replaceFirst('.', '');
  var destName = _uniqueFileName(name, ext);
  var dest = File("$dirPath$pathSep$destName");
  var n = 0;
  while (await dest.exists()) {
    n++;
    destName = _uniqueFileName("${name}_$n", ext);
    dest = File("$dirPath$pathSep$destName");
  }
  await dest.writeAsBytes(data, flush: true);
  return dest.path;
}

bool _looksLikeAppPrivatePath(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  return p.contains('/data/user/') ||
      p.contains('/data/data/') ||
      p.contains('/android/data/');
}

/// 保存图片：自定义目录优先；否则系统相册（失败则 SAF）；桌面另存为。
Future<void> saveImage(File file) async {
  try {
    if (!await file.exists()) {
      showToast(message: "文件不存在".tl);
      return;
    }

    if (hasCustomImageSaveDirectory) {
      if (App.isAndroid &&
          !_looksLikeAppPrivatePath(imageSaveDirectorySetting)) {
        final allowed = await _ensureAndroidWritePermission();
        if (!allowed) {
          showToast(message: "需要存储权限才能保存到自定义目录".tl);
          return;
        }
      }
      final saved = await _saveToCustomDirectory(file);
      showToast(message: "${"已保存".tl}\n$saved");
      return;
    }

    if (App.isAndroid || App.isIOS) {
      if (App.isAndroid) {
        final allowed = await _ensureAndroidWritePermission();
        if (!allowed) {
          final saved = await _saveViaSaf(file);
          if (saved) {
            showToast(message: "已保存".tl);
          } else {
            showToast(message: "需要存储权限才能保存到相册".tl);
          }
          return;
        }
      }
      await _saveToGallery(file);
      showToast(message: "已保存".tl);
    } else if (App.isDesktop) {
      var data = await file.readAsBytes();
      var type = detectFileType(data);
      var fileName = file.name;
      if (!fileName.contains('.')) {
        fileName += type.ext;
      }
      try {
        final String? path =
            (await getSaveLocation(suggestedName: fileName))?.path;
        if (path != null) {
          final mimeType = type.mime;
          final XFile xFile =
              XFile.fromData(data, mimeType: mimeType, name: fileName);
          await xFile.saveTo(path);
          showToast(message: "已保存".tl);
        }
      } catch (e, s) {
        LogManager.addLog(LogLevel.error, "Save Image", "$e\n$s");
        showToast(message: "保存失败".tl);
      }
    }
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "Save Image", "$e\n$s");
    if (App.isAndroid && !hasCustomImageSaveDirectory) {
      final saved = await _saveViaSaf(file);
      if (saved) {
        showToast(message: "已保存".tl);
        return;
      }
    }
    showToast(message: "保存失败".tl);
  }
}

Future<String> persistentCurrentImage(File file) async {
  final fileName = file.uri.pathSegments.isNotEmpty
      ? file.uri.pathSegments.last
      : file.path.split(RegExp(r'[/\\]')).last;
  final newFile = File("${App.dataPath}/images/$fileName");
  if (!(await newFile.exists())) {
    await newFile.create(recursive: true);
    await newFile.writeAsBytes(await file.readAsBytes());
  }
  return newFile.path;
}

Future<void> shareImage(File file) async {
  try {
    if (!await file.exists()) {
      showToast(message: "文件不存在".tl);
      return;
    }
    await Share.shareXFiles([XFile(file.path)]);
  } catch (e, s) {
    LogManager.addLog(LogLevel.error, "Share Image", "$e\n$s");
    showToast(message: "分享失败".tl);
  }
}
