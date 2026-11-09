import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:crypto/crypto.dart';
import 'package:pica_comic/foundation/log.dart';

/// 转换自 https://github.com/tonquer/JMComic-qt/blob/main/src/tools/tool.py
int _getSegmentationNum(String epsId, String scrambleID, String pictureName) {
  int scrambleId = int.parse(scrambleID);
  int epsID = int.parse(epsId);
  int num = 0;

  if (epsID < scrambleId) {
    num = 0;
  } else if (epsID < 268850) {
    num = 10;
  } else if (epsID > 421926) {
    String string = epsID.toString() + pictureName;
    List<int> bytes = utf8.encode(string);
    String hash = md5.convert(bytes).toString();
    int charCode = hash.codeUnitAt(hash.length - 1);
    int remainder = charCode % 8;
    num = remainder * 2 + 2;
  } else {
    String string = epsID.toString() + pictureName;
    List<int> bytes = utf8.encode(string);
    String hash = md5.convert(bytes).toString();
    int charCode = hash.codeUnitAt(hash.length - 1);
    int remainder = charCode % 10;
    num = remainder * 2 + 2;
  }

  return num;
}

/// 转换自 https://github.com/tonquer/JMComic-qt/blob/main/src/tools/tool.py
Future<Uint8List> _segmentationPicture(_RecombinationTask data) async {
  int num = _getSegmentationNum(data.epsId, data.scrambleId, data.bookId);

  if (num <= 1) {
    return data.imgData;
  }
  image.Image srcImg;
  try {
    srcImg = image.decodeImage(data.imgData)!;
  }
  catch(e){
    throw Exception("Failed to decode image: Data length is ${data.imgData.length} bytes");
  }

  int blockSize = (srcImg.height / num).floor();
  int remainder = srcImg.height % num;

  List<Map<String, int>> blocks = [];

  for (int i = 0; i < num; i++) {
    int start = i * blockSize;
    int end = start + blockSize + ((i != num - 1) ? 0 : remainder);
    blocks.add({'start': start, 'end': end});
  }

  image.Image desImg = image.Image(width: srcImg.width, height: srcImg.height);

  int y = 0;
  for (int i = blocks.length - 1; i >= 0; i--) {
    var block = blocks[i];
    int currBlockHeight = block['end']! - block['start']!;
    var range = srcImg.getRange(0, block['start']!, srcImg.width, currBlockHeight);
    var desRange = desImg.getRange(0, y, srcImg.width, currBlockHeight);
    while(range.moveNext() && desRange.moveNext()){
      desRange.current.r = range.current.r;
      desRange.current.g = range.current.g;
      desRange.current.b = range.current.b;
      desRange.current.a = range.current.a;
    }
    y += currBlockHeight;
  }

    // Lossless re-encode (PNG). Previous encodeJpg was lossy even at q=100.
  // Tradeoff: PNG cache files are larger on disk/memory than JPEG.
  return image.encodePng(desImg);
}

Future<Uint8List> _recombineImageAndWriteFile(_RecombinationTask data) async {
  var bytes = await _segmentationPicture(data);
  var file = File(data.savePath!);
  if (file.existsSync()) {
    file.deleteSync();
  }
  file.writeAsBytesSync(bytes);
  return bytes;
}


class _RecombinationTask {
  Uint8List imgData;
  String epsId;
  String scrambleId;
  String bookId;
  String? savePath;
  Completer<Uint8List>? completer;

  _RecombinationTask removeCompleter(){
    return _RecombinationTask(imgData, epsId, scrambleId, bookId, null, savePath);
  }

  _RecombinationTask(this.imgData, this.epsId, this.scrambleId, this.bookId, this.completer,
      [this.savePath]);
}

class _JmWorker {
  Isolate? isolate;
  ReceivePort? receivePort;
  ReceivePort? errorPort;
  SendPort? sendPort;
  _RecombinationTask? current;
  bool starting = false;
}

/// JM recombine pool (2 isolates) so consecutive pages can descramble in parallel.
class JmRecombine {
  static const int poolSize = 2;
  static final List<_JmWorker> _workers = [];
  static final List<_RecombinationTask> _tasks = [];

  static Future<Uint8List> recombineImage(Uint8List imgData, String epsId,
      String scrambleId, String bookId, String savePath) async {
    Completer<Uint8List> completer = Completer();
    _RecombinationTask task =
        _RecombinationTask(imgData, epsId, scrambleId, bookId, completer, savePath);
    _tasks.add(task);
    await _ensurePool();
    _dispatch();
    return completer.future;
  }

  static Future<void> _ensurePool() async {
    while (_workers.length < poolSize) {
      final w = _JmWorker();
      _workers.add(w);
      await _startWorker(w);
    }
  }

  static Future<void> _startWorker(_JmWorker w) async {
    if (w.starting) return;
    w.starting = true;
    w.receivePort = ReceivePort();
    w.errorPort = ReceivePort();
    w.isolate = await Isolate.spawn(_run, w.receivePort!.sendPort,
        onError: w.errorPort!.sendPort, debugName: "JmRecombine");
    w.starting = false;
    _listenWorker(w);
  }

  static void _dispatch() {
    for (final w in _workers) {
      if (w.sendPort != null && w.current == null && _tasks.isNotEmpty) {
        w.current = _tasks.removeAt(0);
        w.sendPort!.send(w.current!.removeCompleter());
      }
    }
  }

  static void _listenWorker(_JmWorker w) {
    w.receivePort!.listen((message) {
      if (message is SendPort) {
        w.sendPort = message;
        _dispatch();
      } else if (message is Uint8List) {
        w.current?.completer?.complete(message);
        w.current = null;
        _dispatch();
      } else if (message is Exception) {
        w.current?.completer?.completeError(message);
        w.current = null;
        _dispatch();
      }
    });

    w.errorPort!.listen((message) {
      log("Receive error from Isolate#JmRecombine:\n$message", "Image",
          LogLevel.error);
      _handleWorkerError(w);
    });
  }

  static Future<void> _handleWorkerError(_JmWorker w) async {
    w.receivePort?.close();
    w.errorPort?.close();
    w.isolate = null;
    w.sendPort = null;
    if (w.current != null) {
      _tasks.insert(0, w.current!);
      w.current = null;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    await _startWorker(w);
    _dispatch();
  }

  static void _run(SendPort port) {
    final rp = ReceivePort();
    rp.listen((message) async {
      if (message is _RecombinationTask) {
        try {
          Uint8List bytes = await _recombineImageAndWriteFile(message);
          port.send(bytes);
        } catch (e) {
          port.send(Exception(e.toString()));
        }
      }
    });
    port.send(rp.sendPort);
  }
}

///启动一个新的线程转换图片并且写入文件
Future<Uint8List> startRecombineAndWriteImage(Uint8List imgData, String epsId,
    String scrambleId, String bookId, String savePath) {
  return JmRecombine.recombineImage(imgData, epsId, scrambleId, bookId, savePath);
}
