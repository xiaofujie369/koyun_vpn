import 'dart:convert';
import 'dart:io';

/// Windows 后台服务（koyun-service.exe，安装包以管理员身份注册，以 SYSTEM 运行）的客户端。
/// 有服务时 TUN 模式由它启动内核，不再需要管理员权限。
///
/// 连接信息在 安装目录\service-data\service.json，只有服务和安装 Koyun 的用户能读。
/// 便携版（压缩包）没有服务，读不到时退回原来的“以管理员身份重启”。
class WinService {
  WinService._(this.port, this.token);

  /// 测试用：直接指定端口和令牌
  WinService.at(this.port, this.token);
  final int port;
  final String token;

  static String get stateFile =>
      '${File(Platform.resolvedExecutable).parent.path}\\service-data\\service.json';

  /// 服务可用时返回客户端，否则 null
  static Future<WinService?> connect() async {
    if (!Platform.isWindows) return null;
    try {
      final j = jsonDecode(await File(stateFile).readAsString());
      final s = WinService._(j['port'] as int, j['token'] as String);
      await s._send('GET', '/v1/version', timeout: const Duration(seconds: 2));
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<(int, Map<String, dynamic>)> _send(String method, String path,
      {String? body, Duration timeout = const Duration(seconds: 5)}) async {
    final c = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final req = await c.openUrl(method, Uri.parse('http://127.0.0.1:$port$path')).timeout(timeout);
      req.headers.set('X-Koyun-Token', token);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode == 403) throw const HttpException('koyun service: forbidden');
      final j = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      return (res.statusCode, j);
    } finally {
      c.close(force: true);
    }
  }

  /// 启动内核；启动失败时抛出内核给出的错误
  Future<void> start(String configJson) async {
    final (code, j) = await _send('POST', '/v1/start', body: configJson, timeout: const Duration(seconds: 20));
    if (code != 200) throw ServiceStartError((j['error'] ?? 'koyun service: HTTP $code').toString());
  }

  Future<void> stop() async {
    await _send('POST', '/v1/stop', timeout: const Duration(seconds: 10));
  }

  /// (是否运行中, 退出时的错误)
  Future<(bool, String?)> status() async {
    final (_, j) = await _send('GET', '/v1/status');
    return (j['running'] == true, j['error'] as String?);
  }

  /// 读取序号 since 之后的内核日志，返回 (日志行, 下次的序号)
  Future<(List<String>, int)> logs(int since) async {
    final (_, j) = await _send('GET', '/v1/logs?since=$since');
    return ((j['lines'] as List? ?? const []).cast<String>(), (j['next'] as num?)?.toInt() ?? since);
  }
}

class ServiceStartError implements Exception {
  ServiceStartError(this.message);
  final String message;
  @override
  String toString() => message;
}
