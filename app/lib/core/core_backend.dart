import 'dart:async';
import 'dart:io';

import 'desktop_backend.dart';
import 'mobile_backend.dart';

enum CoreStatus { stopped, starting, running, stopping }

class CoreStartException implements Exception {
  CoreStartException(this.message, {this.needAdmin = false, this.needPermission = false});
  final String message;

  /// Windows TUN 模式需要管理员权限
  final bool needAdmin;

  /// Android 用户拒绝了 VPN 授权
  final bool needPermission;
  @override
  String toString() => message;
}

/// 内核后端：桌面端 = 子进程运行 sing-box；移动端 = 原生 VPN 服务内嵌 libbox
abstract class CoreBackend {
  static CoreBackend create(String workDir) {
    if (Platform.isAndroid || Platform.isIOS) return MobileBackend();
    return DesktopBackend(workDir);
  }

  /// 内核状态被外部改变（系统收回 VPN 授权、进程崩溃）时通知
  Stream<CoreStatus> get externalStatus;

  /// 是否真正在运行（App 重启后用于恢复状态）
  Future<bool> isRunning();

  /// 申请必要权限（Android VPN 授权），返回是否已获得
  Future<bool> prepare();

  Future<void> start(String configJson, {required bool tun, required int mixedPort});

  Future<void> stop();

  /// 最近日志（用于排查"连不上"）
  List<String> get recentLogs;

  /// 桌面端：TUN 是否可用（Windows 需管理员）
  Future<bool> tunAvailable() async => true;

  /// 桌面端：以管理员身份重启自身
  Future<void> relaunchElevated() async {}

  /// 启动时清理上次异常退出遗留（残留进程 / 系统代理）
  Future<void> cleanupStale() async {}
}
