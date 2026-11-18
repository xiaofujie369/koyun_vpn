import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 通过 sing-box 内置的 Clash API 控制运行中的内核：
/// 切节点、测延迟、切分流模式、读实时网速。四个平台用法完全一样。
class ClashApi {
  ClashApi(this.port, this.secret);
  final int port;
  final String secret;

  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.http('127.0.0.1:$port', path, q);

  Future<dynamic> _send(String method, String path,
      {Map<String, String>? q, Object? body, Duration timeout = const Duration(seconds: 8)}) async {
    final req = await _client.openUrl(method, _u(path, q)).timeout(timeout);
    req.headers.set('Authorization', 'Bearer $secret');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode >= 400) {
      throw HttpException('clash api ${res.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<bool> ping() async {
    try {
      await _send('GET', '/version', timeout: const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> select(String selector, String name) =>
      _send('PUT', '/proxies/${Uri.encodeComponent(selector)}', body: {'name': name});

  /// 当前 "auto" 实际选中的节点
  Future<String?> now(String group) async {
    final j = await _send('GET', '/proxies/${Uri.encodeComponent(group)}');
    return j is Map ? j['now'] as String? : null;
  }

  Future<void> setMode(String mode) => _send('PATCH', '/configs', body: {'mode': mode});

  Future<void> closeAllConnections() => _send('DELETE', '/connections');

  /// 让 urltest 组立即测一遍并按结果重新选节点；返回 节点 -> 毫秒（不通的节点不在里面）
  ///
  /// 内核刚启动时组自己正在测速，这时请求会立即返回空结果（不等它测完）。
  /// 所以“很快返回空”算忙，等一下再问；测了一阵才返回空才算真的都不通
  Future<Map<String, int>> groupDelay(String group, String url, {int timeoutMs = 6000}) async {
    for (var i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      try {
        final j = await _send('GET', '/group/${Uri.encodeComponent(group)}/delay',
            q: {'url': url, 'timeout': '$timeoutMs'},
            timeout: Duration(milliseconds: timeoutMs + 4000));
        final ok = j is Map
            ? {for (final e in j.entries) if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).toInt()}
            : <String, int>{};
        if (ok.isNotEmpty || sw.elapsedMilliseconds >= 1000) return ok;
      } catch (_) {
        return const {};
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return const {};
  }

  /// 测单个节点延迟（毫秒），失败返回 -1
  Future<int> delay(String tag, String url, {int timeoutMs = 10000}) async {
    try {
      final j = await _send('GET', '/proxies/${Uri.encodeComponent(tag)}/delay',
          q: {'url': url, 'timeout': '$timeoutMs'},
          timeout: Duration(milliseconds: timeoutMs + 2000));
      return (j is Map ? (j['delay'] as num?)?.toInt() : null) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// 实时网速流：每秒一条 (上传B/s, 下载B/s)
  Stream<(int, int)> traffic() async* {
    final req = await _client.getUrl(_u('/traffic'));
    req.headers.set('Authorization', 'Bearer $secret');
    final res = await req.close();
    await for (final line
        in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line);
        yield ((j['up'] as num).toInt(), (j['down'] as num).toInt());
      } catch (_) {}
    }
  }

  /// 本次连接累计流量
  Future<(int, int)> totals() async {
    final j = await _send('GET', '/connections');
    if (j is! Map) return (0, 0);
    return ((j['uploadTotal'] as num?)?.toInt() ?? 0, (j['downloadTotal'] as num?)?.toInt() ?? 0);
  }

  void close() => _client.close(force: true);
}
