import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../app_config.dart';

/// 节点延迟测量（算法和 Clash Verge 的「统一延迟」一样）：
/// 经内核的测速入口连到测速地址，在同一条连接上发两次请求，只计第二次的耗时。
/// 第一次包含和节点握手的时间，第二次才是真正一来一回的延迟。
///
/// 不用内核 API 的 /delay 接口：它固定走 HTTPS、把 TLS 握手也算进去，
/// 数字约为实际的两倍，线路稍慢就容易超时（内核还会忽略 http:// 测速地址）。
class DelayProbe {
  DelayProbe({required this.port, required this.password, required this.users, this.log, List<String>? hosts})
      : hosts = hosts ?? const [AppConfig.delayProbeHost, AppConfig.delayProbeFallbackHost];

  /// 节点 tag -> 测速入口的用户名（内核按用户名把连接路由到对应节点）
  final Map<String, String> users;
  final int port;
  final String password;

  /// 测速地址，前一个失败时换下一个再试
  final List<String> hosts;

  /// 失败原因写到哪里（设置 → 日志）
  final void Function(String)? log;

  /// 重试时的超时：节点真的不通时不要等太久
  static const _retryTimeout = Duration(seconds: 6);

  Map<String, dynamic> toJson() => {'testPort': port, 'testSecret': password, 'testUsers': users};

  /// 读回保存的信息；旧版内核配置里没有这些字段时返回 null
  static DelayProbe? fromJson(Map j, {void Function(String)? log}) {
    final port = j['testPort'], secret = j['testSecret'], users = j['testUsers'];
    if (port is! int || secret is! String || users is! Map) return null;
    return DelayProbe(port: port, password: secret, users: users.cast<String, String>(), log: log);
  }

  /// 返回毫秒；失败或超时返回 -1
  Future<int> measure(String tag, {Duration timeout = AppConfig.delayTimeout}) async {
    final user = users[tag];
    if (user == null) return -1;
    for (var i = 0; i < hosts.length; i++) {
      final limit = i == 0 || timeout < _retryTimeout ? timeout : _retryTimeout;
      final sw = Stopwatch()..start();
      try {
        final ms = await _attempt(user, hosts[i], limit);
        if (i > 0) log?.call('[测速] $tag：${hosts[i]} 成功 ${ms}ms（前面的地址失败）');
        return ms;
      } catch (e) {
        log?.call('[测速] $tag：${hosts[i]} 失败，${sw.elapsedMilliseconds}ms，$e');
      }
    }
    return -1;
  }

  Future<int> _attempt(String user, String host, Duration timeout) async {
    Socket? socket;
    try {
      return await () async {
        final s = socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: timeout);
        s.setOption(SocketOption.tcpNoDelay, true);
        unawaited(s.done.then((_) {}, onError: (_) {})); // 节点中途断开时的写入错误由读取那边处理
        final reader = _HeadReader(s);
        final auth = base64.encode(utf8.encode('$user:$password'));
        s.write('CONNECT $host:80 HTTP/1.1\r\nHost: $host:80\r\nProxy-Authorization: Basic $auth\r\n\r\n');
        final status = await reader.next();
        if (!RegExp(r'^HTTP/1\.\d 2\d\d').hasMatch(status)) throw FormatException('测速入口返回 $status');
        final first = await _head(s, reader, host);
        try {
          return await _head(s, reader, host);
        } catch (_) {
          return first; // 服务器不支持复用连接：退回第一次的结果
        }
      }().timeout(timeout);
    } finally {
      socket?.destroy();
    }
  }

  Future<int> _head(Socket s, _HeadReader reader, String host) async {
    final sw = Stopwatch()..start();
    s.write('HEAD /generate_204 HTTP/1.1\r\nHost: $host\r\nConnection: keep-alive\r\n\r\n');
    final status = await reader.next();
    if (!status.startsWith('HTTP/')) throw FormatException('不是 HTTP 响应：$status');
    return math.max(1, sw.elapsedMilliseconds);
  }
}

/// 从连接里一段段读 HTTP 响应头，返回状态行
class _HeadReader {
  _HeadReader(Socket s) : _it = StreamIterator<Uint8List>(s);
  final StreamIterator<Uint8List> _it;
  final _buf = StringBuffer();

  Future<String> next() async {
    while (true) {
      final text = _buf.toString();
      final end = text.indexOf('\r\n\r\n');
      if (end >= 0) {
        _buf
          ..clear()
          ..write(text.substring(end + 4));
        return text.substring(0, text.indexOf('\r\n'));
      }
      if (!await _it.moveNext()) throw const SocketException('connection closed');
      _buf.write(latin1.decode(_it.current));
    }
  }
}
