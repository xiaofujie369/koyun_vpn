import 'dart:async';

import 'package:flutter/services.dart';

import 'core_backend.dart';

/// Android(VpnService) / iOS(NetworkExtension) 原生层桥接。
/// 原生代码见 android/app/src/main/kotlin/.../vpn 和 ios/PacketTunnel。
class MobileBackend extends CoreBackend {
  static const _ch = MethodChannel('koyun/core');
  static const _ev = EventChannel('koyun/core/events');

  final _status = StreamController<CoreStatus>.broadcast();
  final List<String> _logs = [];

  /// 原生层最近一次上报的状态（用于启动失败时立即返回，而不是傻等）
  String lastStatus = 'stopped';
  String? lastError;

  MobileBackend() {
    _ev.receiveBroadcastStream().listen((e) {
      if (e is Map) {
        final s = e['status'] as String?;
        final err = e['error'] as String?;
        if (s != null) lastStatus = s;
        if (err != null) {
          lastError = err;
          _addLog('ERROR $err');
        }
        switch (s) {
          case 'stopped':
            _status.add(CoreStatus.stopped);
          case 'running':
            _status.add(CoreStatus.running);
          case 'starting':
            _status.add(CoreStatus.starting);
        }
      }
    }, onError: (_) {});
  }

  void _addLog(String l) {
    _logs.add(l);
    if (_logs.length > 200) _logs.removeAt(0);
  }

  /// iOS：App Group 共享目录（Android 返回 null）
  Future<String?> sharedDir() async {
    try {
      return await _ch.invokeMethod<String>('sharedDir');
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<CoreStatus> get externalStatus => _status.stream;

  @override
  void addLog(String line) => _addLog(line);

  @override
  List<String> get recentLogs => List.unmodifiable(_logs);

  @override
  Future<bool> isRunning() async =>
      (await _ch.invokeMethod<String>('status')) == 'running';

  /// 上次的连接没有正常断开就没了（进程崩溃或被系统杀掉）
  Future<bool> wasInterrupted() async {
    try {
      return await _ch.invokeMethod<bool>('interrupted') ?? false;
    } catch (_) {
      return false; // iOS 没有这个方法
    }
  }

  @override
  Future<bool> prepare() async => await _ch.invokeMethod<bool>('prepare') ?? false;

  @override
  Future<void> start(String configJson, {required bool tun, required int mixedPort}) async {
    if (!await prepare()) {
      throw CoreStartException('VPN permission denied', needPermission: true);
    }
    lastError = null;
    lastStatus = 'starting';
    try {
      await _ch.invokeMethod('start', {'config': configJson});
    } on PlatformException catch (e) {
      _addLog('ERROR ${e.message}');
      throw CoreStartException(e.message ?? e.code);
    }
  }

  @override
  Future<void> stop() async {
    await _ch.invokeMethod('stop');
  }
}
