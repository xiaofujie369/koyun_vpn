import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import '../app_config.dart';
import 'storage.dart';

/// 启动引导配置（放在 Cloudflare Pages 仓库 koyunoss 的 boot.json）。
///
/// App 启动时读取，拿到"当前可用的接口域名 / 官网"。域名被封时只要更新 boot.json，
/// 客户下次打开 App 自动切换，不需要发新版本。
///
/// * 文件 AES-256-GCM 加密、Ed25519 签名，只认签名正确的文件（防伪造 / 劫持）。
/// * 多个引导地址同时请求，取最新的一份；时间戳比本机缓存旧的不接受（防回滚）。
/// * 成功后缓存在本机；引导地址全都打不开时用缓存，再不行用 App 内置的域名。
/// * 生成工具：tools/bootstrap.py
class Bootstrap {
  Bootstrap._();
  static final instance = Bootstrap._();

  Storage? _storage;
  int _ts = 0; // 当前生效配置的生成时间
  Future<bool>? _refreshing;

  /// 配置里可选的更新信息（格式同后台接口的 latest），检查更新时优先使用
  Map<String, dynamic>? latest;

  bool get hasConfig => _ts > 0;
  bool get enabled => AppConfig.bootUrls.isNotEmpty && AppConfig.bootPub.length == 32 && AppConfig.bootKey.length == 32;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    responseType: ResponseType.plain,
  ));

  /// 读取本机缓存（很快，不联网）
  Future<void> init(Storage storage) async {
    _storage = storage;
    if (!enabled) return;
    final cached = storage.bootDoc;
    if (cached == null) return;
    final cfg = await open(cached);
    if (cfg != null) _apply(cfg);
  }

  /// 联网获取最新配置。返回 true 表示配置有更新（接口域名可能变了）
  Future<bool> refresh() {
    if (!enabled) return Future.value(false);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final results = await Future.wait(AppConfig.bootUrls.map((u) async {
      try {
        final r = await _dio.get<String>(u);
        final body = r.data ?? '';
        final cfg = await open(body);
        return cfg == null ? null : (body, cfg);
      } catch (_) {
        return null;
      }
    }));
    (String, Map<String, dynamic>)? best;
    for (final r in results) {
      if (r == null) continue;
      if (best == null || _tsOf(r.$2) > _tsOf(best.$2)) best = r;
    }
    if (best == null || _tsOf(best.$2) <= _ts) return false;
    _apply(best.$2);
    await _storage?.setBootDoc(best.$1);
    return true;
  }

  static int _tsOf(Map<String, dynamic> c) => (c['ts'] as num?)?.toInt() ?? 0;

  /// 验证签名并解密，失败返回 null
  static Future<Map<String, dynamic>?> open(String text) async {
    try {
      final doc = jsonDecode(text) as Map<String, dynamic>;
      if (doc['v'] != 1) return null;
      final nonce = base64Decode(doc['n'] as String);
      final data = base64Decode(doc['d'] as String);
      final sig = base64Decode(doc['s'] as String);
      final ok = await Ed25519().verify(
        [...nonce, ...data],
        signature: Signature(sig, publicKey: SimplePublicKey(AppConfig.bootPub, type: KeyPairType.ed25519)),
      );
      if (!ok) return null;
      final box = SecretBox.fromConcatenation([...nonce, ...data], nonceLength: 12, macLength: 16);
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(AppConfig.bootKey));
      final cfg = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return cfg;
    } catch (_) {
      return null;
    }
  }

  void _apply(Map<String, dynamic> cfg) {
    final api = ((cfg['api'] as List?) ?? const [])
        .map((e) => e.toString().trim().replaceAll(RegExp(r'/+$'), ''))
        .where((e) => e.startsWith('https://'))
        .toList();
    if (api.isNotEmpty) AppConfig.bootApi = api;
    final web = (cfg['web'] ?? '').toString().trim();
    if (web.startsWith('https://')) AppConfig.bootWeb = web.replaceAll(RegExp(r'/+$'), '');
    latest = cfg['latest'] is Map ? (cfg['latest'] as Map).cast<String, dynamic>() : null;
    // 数据管理后台地址和密钥：{"url":"https://...","key":"..."}
    final st = cfg['stats'];
    if (st is Map) {
      final url = (st['url'] ?? '').toString().trim().replaceAll(RegExp(r'/+$'), '');
      if (url.startsWith('https://')) {
        AppConfig.bootStatsBase = url;
        AppConfig.bootStatsKey = (st['key'] ?? '').toString();
      }
    }
    _ts = _tsOf(cfg);
  }
}
