import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/reporter.dart';
import 'config_builder.dart';
import 'core_backend.dart';
import 'sys_proxy.dart';
import 'win_service.dart';

/// 桌面端：以子进程方式运行随 App 打包的 sing-box 可执行文件。
///
/// * 系统代理模式：普通权限即可。
/// * TUN 模式：
///   - Windows：交给安装时注册的后台服务（koyun-service，SYSTEM 身份）启动内核，不弹管理员确认；
///     便携版没有服务，退回“以管理员身份重启”。
///   - macOS：第一次输入一次密码，把内核复制到 /Library/Application Support/Koyun 并设为 root 运行
///     （和 FlClash 的做法一样），以后直接启动；内核版本变了才需要再授权。
class DesktopBackend extends CoreBackend {
  DesktopBackend(this.workDir);
  final String workDir;

  Process? _proc;
  bool _sysProxySet = false;
  // Windows：通过后台服务运行内核
  WinService? _svc;
  Timer? _svcPoll;
  int _svcLogNext = 0;
  final _status = StreamController<CoreStatus>.broadcast();
  final List<String> _logs = [];
  bool _stopping = false;

  String get _pidFile => '$workDir/core.pid';
  String get _macFlag => '$workDir/core.run';
  String get _configPath => '$workDir/config.json';

  static const _macHelperDir = '/Library/Application Support/Koyun';
  static const _macHelper = '$_macHelperDir/sing-box';
  bool? _macHelperOk;

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
    if (networkChange) _reportNetReset(line);
  }

  // 网卡反复变化的电脑（后台见过一台 12 天上报 3746 次）会刷满日志：10 分钟最多报一次，附带省略的次数
  DateTime? _netResetAt;
  int _netResetSkipped = 0;

  void _reportNetReset(String line) {
    final now = DateTime.now();
    if (_netResetAt != null && now.difference(_netResetAt!) < const Duration(minutes: 10)) {
      _netResetSkipped++;
      return;
    }
    Reporter.instance.event('net_reset', {'line': line, if (_netResetSkipped > 0) 'skipped': _netResetSkipped});
    _netResetAt = now;
    _netResetSkipped = 0;
  }

  @override
  List<String> get recentLogs => List.unmodifiable(_logs);

  @override
  Stream<CoreStatus> get externalStatus => _status.stream;

  @override
  Future<bool> isRunning() async => _proc != null || _svc != null;

  @override
  Future<bool> prepare() async => true;

  @override
  Future<bool> tunAvailable() async {
    if (Platform.isWindows) return await WinService.connect() != null || await _isWindowsAdmin();
    return true; // macOS 第一次开 TUN 时弹系统授权
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
    // 旧版 macOS 的 root 守护脚本靠这个标记文件运行，删掉它旧内核就会退出
    final flag = File(_macFlag);
    if (await flag.exists()) await flag.delete();
    // 上次 App 异常退出时服务里的内核可能还在跑（TUN 一直开着），先停掉
    final svc = await WinService.connect();
    if (svc != null) {
      try {
        if ((await svc.status()).$1) await svc.stop();
      } catch (_) {}
    }
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
    await File(_configPath).writeAsString(configJson, flush: true);
    await File('$workDir/port').writeAsString('$mixedPort');

    if (!File(binaryPath).existsSync()) {
      throw CoreStartException('sing-box not found: $binaryPath');
    }
    WinService? svc;
    if (tun && Platform.isWindows) {
      svc = await WinService.connect();
      if (svc == null && !await _isWindowsAdmin()) {
        throw CoreStartException('need admin', needAdmin: true);
      }
    }

    if (svc != null) {
      await _startViaService(svc, configJson);
    } else {
      var bin = binaryPath;
      if (tun && Platform.isMacOS) {
        await _ensureMacHelper();
        bin = _macHelper;
        // 先以普通用户创建：否则文件归 root 所有，之后切回系统代理模式内核打不开缓存
        await File('$workDir/cache.db').create();
      }
      final p = await Process.start(bin, ['run', '-c', _configPath, '-D', workDir],
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

  /// Windows：服务启动内核，每秒取一次日志和状态（内核意外退出时通知上层）
  Future<void> _startViaService(WinService svc, String configJson) async {
    try {
      _svcLogNext = (await svc.logs(1 << 30)).$2; // 只要这次启动之后的日志
    } catch (_) {
      _svcLogNext = 0;
    }
    try {
      await svc.start(configJson);
    } on ServiceStartError catch (e) {
      await _pullServiceLogs(svc);
      throw CoreStartException(e.message.replaceFirst(RegExp(r'^.*?(FATAL|ERROR)\]?\s*'), ''));
    } catch (e) {
      throw CoreStartException('koyun service: $e');
    }
    _svc = svc;
    _addLog('[服务] 内核已由 Koyun 后台服务启动');
    var busy = false;
    _svcPoll = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (busy || _svc != svc) return;
      busy = true;
      try {
        await _pullServiceLogs(svc);
        final (running, _) = await svc.status();
        if (!running && _svc == svc && !_stopping) {
          _svc = null;
          _svcPoll?.cancel();
          _addLog('core exited (service)');
          Reporter.instance.event('core_exit', {'service': true, 'error': _lastError()});
          _status.add(CoreStatus.stopped);
        }
      } catch (_) {
        // 服务暂时没响应（比如正在重启），下一秒再试
      } finally {
        busy = false;
      }
    });
  }

  Future<void> _pullServiceLogs(WinService svc) async {
    final (lines, next) = await svc.logs(_svcLogNext);
    _svcLogNext = next;
    lines.forEach(_onCoreLine);
  }

  /// macOS：确保 /Library/Application Support/Koyun/sing-box 是 root 所有、带 setuid、
  /// 且和 App 里的内核一模一样；否则弹一次系统授权窗口安装它
  Future<void> _ensureMacHelper() async {
    if (_macHelperOk == true || await _macHelperReady()) {
      _macHelperOk = true;
      return;
    }
    final groups = await Process.run('id', ['-Gn']);
    if (!groups.stdout.toString().split(RegExp(r'\s+')).contains('admin')) {
      throw CoreStartException('TUN needs an administrator account', kind: 'macNotAdmin');
    }
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    final tmp = '$_macHelper.tmp';
    final script = 'set -e; mkdir -p ${q(_macHelperDir)}; chown root:wheel ${q(_macHelperDir)}; '
        'chmod 755 ${q(_macHelperDir)}; cp -f ${q(binaryPath)} ${q(tmp)}; '
        'chown root:admin ${q(tmp)}; chmod 4750 ${q(tmp)}; xattr -c ${q(tmp)} || true; '
        'mv -f ${q(tmp)} ${q(_macHelper)}';
    final apple = 'do shell script "${script.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}" '
        'with administrator privileges';
    final r = await Process.run('osascript', ['-e', apple]);
    if (r.exitCode != 0) throw CoreStartException('authorization cancelled');
    _macHelperOk = await _macHelperReady();
    if (_macHelperOk != true) throw CoreStartException('TUN helper install failed');
  }

  Future<bool> _macHelperReady() async {
    try {
      if (!File(_macHelper).existsSync()) return false;
      final st = await Process.run('stat', ['-f', '%Su:%Sg %Sp', _macHelper]);
      final out = st.stdout.toString().trim(); // root:admin -rwsr-x---
      final mode = out.split(' ').last;
      if (!out.startsWith('root:admin ') || mode.length < 10 || mode[3] != 's') return false;
      final a = File(binaryPath), b = File(_macHelper);
      if (a.lengthSync() != b.lengthSync()) return false;
      final sums = await Process.run('shasum', ['-a', '256', binaryPath, _macHelper]);
      final hashes = sums.stdout.toString().trim().split('\n').map((l) => l.split(' ').first).toList();
      return hashes.length == 2 && hashes[0] == hashes[1];
    } catch (_) {
      return false;
    }
  }

  String _lastError() {
    final lines = [..._logs];
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
    final svc = _svc;
    if (svc != null) {
      _svc = null;
      _svcPoll?.cancel();
      try {
        await svc.stop();
      } catch (_) {}
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
}
