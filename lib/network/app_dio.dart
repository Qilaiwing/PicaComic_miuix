import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:pica_comic/network/http_client.dart';
import '../base.dart';
import '../foundation/app.dart';

class MyLogInterceptor implements Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    LogManager.addLog(LogLevel.error, "Network",
        "${err.requestOptions.method} ${err.requestOptions.path}\n$err\n${err.response?.data.toString()}");
    switch(err.type) {
      case DioExceptionType.badResponse:
        var statusCode = err.response?.statusCode;
        if(statusCode != null){
          err = err.copyWith(message: "状态码 $statusCode："
              "${_getStatusCodeInfo(statusCode)}");
        }
      case DioExceptionType.connectionTimeout:
        err = err.copyWith(message: "连接超时");
      case DioExceptionType.receiveTimeout:
        err = err.copyWith(message: "接收超时：服务器繁忙，请稍后重试");
      case DioExceptionType.unknown:
        if(err.toString().contains("Connection terminated during handshake")) {
          err = err.copyWith(message: "Connection terminated during handshake: "
              "This may be caused by the firewall blocking the connection "
              "or your requests are too frequent.");
        } else if (err.toString().contains("Connection reset by peer")) {
          err = err.copyWith(message: "Connection reset by peer: "
              "The error is unrelated to app, please check your network.");
        }
      default: {}
    }
    handler.next(err);
  }

  static const errorMessages = <int, String>{
    400: "请求无效",
    401: "未授权，请重新登录",
    403: "无权限访问，请检查账号或网络",
    404: "资源不存在",
    429: "请求过于频繁，请稍后重试",
  };

  String _getStatusCodeInfo(int? statusCode){
    if(statusCode != null && statusCode >= 500) {
      return "服务器错误，请稍后重试";
    } else {
      return errorMessages[statusCode] ?? "";
    }
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    var headers = response.headers.map.map((key, value) => MapEntry(
        key.toLowerCase(), value.length == 1 ? value.first : value.toString()));
    headers.remove("cookie");
    String content;
    if(response.data is List<int>) {
      try {
        content = utf8.decode(response.data, allowMalformed: false);
      }
      catch(e) {
        content = "<Bytes>\nlength:${response.data.length}";
      }
    } else {
      content = response.data.toString();
    }
    LogManager.addLog(
        (response.statusCode != null && response.statusCode! < 400)
            ? LogLevel.info : LogLevel.error,
        "Network",
        "Response ${response.realUri.toString()} ${response.statusCode}\n"
            "headers:\n$headers\n$content");
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.connectTimeout = const Duration(seconds: 15);
    options.receiveTimeout = const Duration(seconds: 15);
    options.sendTimeout = const Duration(seconds: 15);
    handler.next(options);
  }
}

class AppHttpAdapter implements HttpClientAdapter{
  HttpClientAdapter? adapter;

  final bool http2;

  AppHttpAdapter(this.http2);

  static Future<HttpClientAdapter> createAdapter(bool http2) async{
    return http2 ? Http2Adapter(ConnectionManager(
      idleTimeout: const Duration(seconds: 15),
      onClientCreate: (_, config) {
        if (proxyHttpOverrides?.proxyStr != null && appdata.settings[58] != "1") {
          config.proxy = Uri.parse('http://${proxyHttpOverrides?.proxyStr}');
        }
      },
    ),) : IOHttpClientAdapter();
  }

  @override
  void close({bool force = false}) {
    adapter?.close(force: force);
  }


  /// 直接使用ip访问绕过sni
  bool changeHost(RequestOptions options){
    var config = const JsonDecoder().convert(File("${App.dataPath}/rule.json").readAsStringSync());
    if((config["sni"] ?? []).contains(options.uri.host) && (config["rule"] ?? {})[options.uri.host] != null) {
      options.path = options.path.replaceFirst(
          options.uri.host, config["rule"][options.uri.host]!);
      return true;
    }
    return false;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async{
    adapter ??= await createAdapter(http2);
    int retry = 0;
    while(true){
      try{
        var res = await fetchOnce(o, requestStream, cancelFuture);
        return res;
      }
      catch(e){
        if(e is DioException) {
          if(e.response?.statusCode != null) {
            var code = e.response!.statusCode!;
            if(code >= 400 && code < 500) {
              rethrow;
            }
          }
        }
        final errStr = e.toString();
        final isHandshake = errStr.contains("Connection terminated during handshake")
            || errStr.contains("HandshakeException")
            || errStr.contains("Connection reset by peer");
        LogManager.addLog(LogLevel.error, "Network",
            "${o.method} ${o.path}\n$e\nRetrying...");
        retry++;
        // Handshake / reset: recreate client and allow one extra attempt with backoff.
        final maxAttempts = isHandshake ? 3 : 2;
        if(retry >= maxAttempts){
          rethrow;
        }
        if (isHandshake) {
          try {
            adapter?.close(force: true);
          } catch (_) {}
          adapter = await createAdapter(http2);
          await Future.delayed(Duration(milliseconds: 400 * retry));
        } else {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
  }

  Future<ResponseBody> fetchOnce(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async{
    var options = o.copyWith();
    LogManager.addLog(LogLevel.info, "Network",
        "${options.method} ${options.path}\nheaders:\n${options.headers.toString()}\ndata:${options.data}");
    if(appdata.settings[58] == "0"){
      return checkCookie(await adapter!.fetch(options, requestStream, cancelFuture));
    }
    if(!changeHost(options)){
      return checkCookie(await adapter!.fetch(options, requestStream, cancelFuture));
    }
    if(options.headers["host"] == null && options.headers["Host"] == null){
      options.headers["host"] = options.uri.host;
    }
    options.followRedirects = false;
    var res = await adapter!.fetch(options, requestStream, cancelFuture);
    while(res.statusCode < 400 && res.statusCode > 300){
      var location = res.headers["location"]!.first;
      if(location.contains("http") && Uri.tryParse(location) != null){
        if(Uri.parse(location).host != o.uri.host){
          options.path = location;
          changeHost(options);
          res = await adapter!.fetch(options, requestStream, cancelFuture);
        } else {
          location = Uri
              .parse(location)
              .path;
          options.path = options.path.contains("https://")
              ? "https://${options.uri.host}$location"
              : "http://${options.uri.host}$location";
          res = await adapter!.fetch(options, requestStream, cancelFuture);
        }
      } else {
        options.path = options.path.contains("https://")
            ? "https://${options.uri.host}$location"
            : "http://${options.uri.host}$location";
        res = await adapter!.fetch(options, requestStream, cancelFuture);
      }
    }
    return checkCookie(res);
  }

  /// 检查cookie是否合法, 去除无效cookie
  ResponseBody checkCookie(ResponseBody res){
    if(res.headers["set-cookie"] == null){
      return res;
    }

    var cookies = <String>[];

    var invalid = <String>[];

    for(var cookie in res.headers["set-cookie"]!){
      try{
        Cookie.fromSetCookieValue(cookie);
        cookies.add(cookie);
      }
      catch(e){
       invalid.add(cookie);
      }
    }

    if(cookies.isNotEmpty){
      res.headers["set-cookie"] = cookies;
    }
    else{
      res.headers.remove("set-cookie");
    }

    if(invalid.isNotEmpty){
      res.headers["invalid-cookie"] = invalid;
    }

    return res;
  }
}

Dio logDio([BaseOptions? options, bool http2 = false]) {
  var dio = Dio(options)..interceptors.add(MyLogInterceptor());
  dio.httpClientAdapter = AppHttpAdapter(http2);
  return dio;
}


