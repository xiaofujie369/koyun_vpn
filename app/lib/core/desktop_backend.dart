import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/reporter.dart';
import 'config_builder.dart';
import 'core_backend.dart';
import 'sys_proxy.dart';

/// 桌面端：以子进程方式运行随 App 打包的 sing-box 可执行文件。
///
/// * 系统代理模式：普通权限即可。
/// * TUN 模式：Windows 需要管理员（引导以管理员重启）；
///   macOS 通过系统授权弹窗以 root 启动内核，用"标记文件"控制停止，免二次输密码。
class DesktopBackend extends CoreBackend {
  DesktopBackend(this.workDir);
  final String workDir;

  Process? _proc;
  int _mixedPort = 0;
  bool _sysProxySet = false;
  bool _macRootMode = false;
  final _status = StreamController<CoreStatus>.broadcast();
  final List<String> _logs = [];
  bool _stopping = false;

  String get _pidFile => '$workDir/core.pid';
  String get _macFlag => '$workDir/core.run';
  String get _configPath => '$workDir/config.json';
  String get _logPath => '$workDir/core.log';

  String get binaryPath {
    final dir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) return '$dir\\sing-box.exe';
    if (Platform.isMacOS) {
      // Koyun.app/Contents/MacOS/Koyun -> Contents/Resources/sing-box
      final res = '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/sing-box';
      if (File(res).existsSync()) return res;
    }
    return '$dir/sing-box';
  }

  void _addLog(String l) {
    _logs.add(l);
    if (_logs.length > 300) _logs.removeAt(0);
  }

  @override
  void addLog(String line) => _addLog(line);

  /// 内核输出的一行。INFO 里全是访问记录，不保留；只留错误和网络变化（排查掉线用）。
  void _onCoreLine(String raw) {
    final line = raw.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    final networkChange = line.contains('default interface') || line.contains('network changed');
    if (line.contains(' INFO ') && !networkChange) return;
    _addLog(line);
    // 默认网卡变化时内核会断开所有连接，这是掉线的一个来源
    if (networkChange) Reporter.instance.event('net_reset', {'line': line});
  }

  @override
  List<String> get recentLogs => List.unmodifiable(_logs);

  @override
  Stream<CoreStatus> get externalStatus => _status.stream;

  @override
  Future<bool> isRunning() async => _proc != null || (_macRootMode && File(_macFlag).existsSync());

  @override
  Future<bool> prepare() async => true;

  @override
  Future<bool> tunAvailable() async {
    if (Platform.isWindows) return _isWindowsAdmin();
    return true; // macOS 启动时弹系统授权
  }

  static Future<bool> _isWindowsAdmin() async {
    try {
      final r = await Process.run('net', ['session']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> relaunchElevated() async {
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    await Process.start('powershell', [
      '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
      "Start-Process -FilePath '$exe' -ArgumentList '--elevated' -Verb RunAs",
    ], mode: ProcessStartMode.detached);
    // 由调用方退出当前进程
  }

  @override
  Future<void> cleanupStale() async {
    // 1. 杀掉上次遗留的内核进程
    final pf = File(_pidFile);
    if (await pf.exists()) {
      final pid = int.tryParse((await pf.readAsString()).trim());
      if (pid != null) {
        if (Platform.isWindows) {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
        } else {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
      }
      await pf.delete().catchError((_) => pf);
    }
    final flag = File(_macFlag);
    if (await flag.exists()) await flag.delete();
    // 2. 恢复系统代理（只在指向我们端口时）
    final ports = <int>{17890};
    try {
      final saved = await File('$workDir/port').readAsString();
      ports.add(int.parse(saved.trim()));
    } catch (_) {}
    for (final p in ports) {
      if (await SysProxy.isOurs(p)) await SysProxy.disable();
    }
  }

  @override
  Future<void> start(String configJson, {required bool tun, required int mixedPort}) async {
    await stop();
    _logs.clear();
    _stopping = false;
    _mixedPort = mixedPort;
    await File(_configPath).writeAsString(configJson, flush: true);
    await File('$workDir/port').writeAsString('$mixedPort');

    if (!File(binaryPath).existsSync()) {
      throw CoreStartException('sing-box not found: $binaryPath');
    }
    if (tun && Platform.isWindows && !await _isWindowsAdmin()) {
      throw CoreStartException('need admin', needAdmin: true);
    }

    if (tun && Platform.isMacOS) {
      await _startMacRoot();
    } else {
      final p = await Process.start(binaryPath, ['run', '-c', _configPath, '-D', workDir],
          workingDirectory: workDir, environment: ConfigBuilder.coreEnv);
      _proc = p;
      await File(_pidFile).writeAsString('${p.pid}');
      // 允许非法字符：解码出错时不能中断日志读取，否则管道写满后内核会被卡住
      for (final out in [p.stdout, p.stderr]) {
        out
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen(_onCoreLine, onError: (_) {});
      }
      unawaited(p.exitCode.then((code) {
        if (_proc == p) {
          _proc = null;
          _addLog('core exited: $code');
          if (!_stopping) {
            Reporter.instance.event('core_exit', {'code': code, 'error': _lastError()});
            _restoreProxy();
            _status.add(CoreStatus.stopped);
          }
        }
      }));
      // 等 1 秒看是否立即退出（配置错误、端口占用）
      final early = await p.exitCode.timeout(const Duration(milliseconds: 1200), onTimeout: () => -999);
      if (early != -999) {
        _proc = null;
        throw CoreStartException(_lastError());
      }
    }

    if (!tun) {
      await SysProxy.enable(mixedPort);
      _sysProxySet = true;
    }
  }

  Future<void> _startMacRoot() async {
    final script = File('$workDir/run-root.sh');
    await script.writeAsString(r'''#!/bin/sh
BIN="$1"; CFG="$2"; DIR="$3"; FLAG="$4"; LOG="$5"; PIDF="$6"
export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true
"$BIN" run -c "$CFG" -D "$DIR" > "$LOG" 2>&1 &
P=$!
echo $P > "$PIDF"
while [ -f "$FLAG" ] && kill -0 $P 2>/dev/null; do sleep 1; done
kill $P 2>/dev/null
sleep 2
kill -9 $P 2>/dev/null
rm -f "$FLAG"
''');
    await File(_macFlag).writeAsString('1');
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    final cmd = '/bin/sh ${q(script.path)} ${q(binaryPath)} ${q(_configPath)} '
        '${q(workDir)} ${q(_macFlag)} ${q(_logPath)} ${q('$workDir/core-root.pid')} '
        '> /dev/null 2>&1 &';
    final apple = 'do shell script "${cmd.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}" '
        'with administrator privileges';
    final r = await Process.run('osascript', ['-e', apple]);
    if (r.exitCode != 0) {
      await File(_macFlag).delete().catchError((_) => File(_macFlag));
      throw CoreStartException('authorization cancelled');
    }
    _macRootMode = true;
  }

  String _lastError() {
    final lines = [..._logs];
    try {
      if (_macRootMode) lines.addAll(File(_logPath).readAsLinesSync());
    } catch (_) {}
    final err = lines.lastWhere((l) => l.contains('FATAL') || l.contains('ERROR'),
        orElse: () => lines.isEmpty ? 'core exited' : lines.last);
    return err.replaceFirst(RegExp(r'^.*?(FATAL|ERROR)\]?\s*'), '');
  }

  Future<void> _restoreProxy() async {
    if (_sysProxySet) {
      _sysProxySet = false;
      await SysProxy.disable();
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    await _restoreProxy();
    if (_macRootMode) {
      _macRootMode = false;
      final f = File(_macFlag);
      if (await f.exists()) await f.delete();
      // 等待 root 守护脚本结束内核
      for (var i = 0; i < 30 && await _portBusy(); i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    final p = _proc;
    if (p != null) {
      _proc = null;
      if (Platform.isWindows) {
        p.kill();
      } else {
        p.kill(ProcessSignal.sigterm);
      }
      await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    final pf = File(_pidFile);
    if (await pf.exists()) await pf.delete().catchError((_) => pf);
  }

  Future<bool> _portBusy() async {
    try {
      final s = await Socket.connect('127.0.0.1', _mixedPort, timeout: const Duration(milliseconds: 200));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
