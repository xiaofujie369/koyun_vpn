import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../app_config.dart';
import 'storage.dart';

/// 数据管理后台对接（统计上报 / 用户反馈 / 远程配置）。
///
/// * 后台地址编译时注入（AppConfig.statsBase）。没配置时所有功能自动关闭，不收集、不发送。
/// * 自动上报只带匿名设备编号，不带账号邮箱；用户主动"反馈问题"时才带邮箱 / 联系方式。
/// * 事件先存本机文件，攒一批（或每 5 分钟）发送一次；发送失败下次再发，最多保留 500 条。
/// * 接口格式见 docs/后台接口说明.md
class Reporter {
  Reporter._();
  static final instance = Reporter._();

  static const _maxQueue = 500;
  static const _batch = 50;

  Storage? _storage;
  String _deviceId = '';
  String locale = '';
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _sending = false;

  bool get enabled => AppConfig.statsEnabled && _storage != null;
  String get deviceId => _deviceId;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    contentType: Headers.jsonContentType,
  ));

  File get _file => File('${_storage!.dataDir.path}/report_queue.json');

  Future<void> init(Storage storage) async {
    _storage = storage;
    var id = storage.deviceId;
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await storage.setDeviceId(id);
    }
    _deviceId = id;
    if (!AppConfig.statsEnabled) return;
    try {
      if (await _file.exists()) {
        final list = jsonDecode(await _file.readAsString()) as List;
        _queue.addAll(list.whereType<Map>().map((e) => e.cast<String, dynamic>()));
      }
    } catch (_) {}
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => flush());
    Future.delayed(const Duration(seconds: 15), flush);
  }

  /// 设备信息（每次发送都带上）
  Map<String, dynamic> get device => {
        'id': _deviceId,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'app_version': AppConfig.appVersion,
        'core_version': AppConfig.singBoxVersion,
        'locale': locale.isEmpty ? Platform.localeName : locale,
      };

  Map<String, String> get _headers => {
        'User-Agent': AppConfig.apiUserAgent,
        'X-Koyun-Key': AppConfig.statsKey,
        'X-Koyun-Device': _deviceId,
      };

  /// 记录一个事件（不会立刻发送）
  void event(String type, [Map<String, dynamic> data = const {}]) {
    if (!enabled) return;
    _queue.add({'type': type, 'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'data': data});
    if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
    unawaited(_save());
    if (_queue.length >= 20) unawaited(flush());
  }

  Future<void> _save() async {
    try {
      await _file.writeAsString(jsonEncode(_queue));
    } catch (_) {}
  }

  /// 发送排队中的事件
  Future<void> flush() async {
    if (!enabled || _sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(_batch).toList();
        final r = await _dio.post(
          '${AppConfig.statsBase}/api/v1/client/events',
          data: {'device': device, 'events': batch},
          options: Options(headers: _headers),
        );
        if ((r.statusCode ?? 0) ~/ 100 != 2) break;
        _queue.removeRange(0, batch.length);
        await _save();
      }
    } catch (_) {
      // 网络不通：下次再发
    } finally {
      _sending = false;
    }
  }

  /// 用户反馈。返回是否发送成功；后台未配置时返回 null（界面改为引导提交工单）
  Future<bool?> feedback({
    required String content,
    String? contact,
    String? email,
    String? logs,
    Map<String, dynamic>? extra,
  }) async {
    if (!enabled) return null;
    try {
      final r = await _dio.post(
        '${AppConfig.statsBase}/api/v1/client/feedback',
        data: {
          'device': device,
          'content': content,
          'contact': contact,
          'email': email,
          'logs': logs,
          'extra': extra,
        },
        options: Options(headers: _headers),
      );
      return (r.statusCode ?? 0) ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  /// 远程配置（最新版本 / 下载地址 / 公告等），失败返回 null
  Future<Map<String, dynamic>?> remoteConfig() async {
    if (!enabled) return null;
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.statsBase}/api/v1/client/config',
        queryParameters: {'platform': Platform.operatingSystem, 'version': AppConfig.appVersion},
        options: Options(headers: _headers),
      );
      return (r.statusCode ?? 0) ~/ 100 == 2 ? r.data : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _timer?.cancel();
}
