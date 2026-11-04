import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// App 自己的请求（登录、刷新订阅、启动配置）走哪条线路。
class NetRoute {
  NetRoute._();

  /// 已连接时是内核本机入口（user:password@127.0.0.1:port），未连接时为 null。
  static String? proxy;
}

/// 已连接时先走当前节点，这样直连被屏蔽也能登录和刷新；走不通再试直连。
class RoutedAdapter implements HttpClientAdapter {
  final _direct = IOHttpClientAdapter();
  IOHttpClientAdapter? _tunnel;
  String? _tunnelProxy;

  IOHttpClientAdapter _tunnelFor(String proxy) {
    if (_tunnelProxy != proxy) {
      _tunnel?.close(force: true);
      _tunnelProxy = proxy;
      _tunnel = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()..findProxy = (_) => 'PROXY $proxy');
    }
    return _tunnel!;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final proxy = NetRoute.proxy;
    if (proxy == null) return _direct.fetch(options, requestStream, cancelFuture);
    // 请求内容只能读一次，先存下来，换线路时才能重发
    final body = requestStream == null ? null : await requestStream.toList();
    Stream<Uint8List>? stream() => body == null ? null : Stream.fromIterable(body);
    try {
      return await _tunnelFor(proxy).fetch(options, stream(), cancelFuture);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
      return _direct.fetch(options, stream(), cancelFuture);
    }
  }

  @override
  void close({bool force = false}) {
    _direct.close(force: force);
    _tunnel?.close(force: force);
  }
}
