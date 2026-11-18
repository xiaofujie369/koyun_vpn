import 'dart:io';

/// 开机自动启动（桌面）。带 --autostart 启动：不弹主窗口，直接在托盘里运行
/// （参考 Clash Verge 的“静默启动”）；开了“自动连接”的话会顺带连上。
///
/// * Windows：HKCU\...\Run\Koyun（和安装包勾选“开机启动”写的是同一项）
/// * macOS：~/Library/LaunchAgents/com.koyun.vpn.autostart.plist
class Autostart {
  static const flag = '--autostart';
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _label = 'com.koyun.vpn.autostart';

  static bool get supported => Platform.isWindows || Platform.isMacOS;

  static String get _plist => '${Platform.environment['HOME']}/Library/LaunchAgents/$_label.plist';

  static Future<bool> enabled() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('reg', ['query', _runKey, '/v', 'Koyun']);
        return r.exitCode == 0;
      }
      if (Platform.isMacOS) return File(_plist).existsSync();
    } catch (_) {}
    return false;
  }

  static Future<void> set(bool on) async {
    final exe = Platform.resolvedExecutable;
    if (Platform.isWindows) {
      if (on) {
        await Process.run('reg', ['add', _runKey, '/v', 'Koyun', '/t', 'REG_SZ', '/d', '"$exe" $flag', '/f']);
      } else {
        await Process.run('reg', ['delete', _runKey, '/v', 'Koyun', '/f']);
      }
    } else if (Platform.isMacOS) {
      final f = File(_plist);
      if (on) {
        String x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
        await f.parent.create(recursive: true);
        await f.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$_label</string>
  <key>ProgramArguments</key>
  <array><string>${x(exe)}</string><string>$flag</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''');
      } else if (f.existsSync()) {
        await f.delete();
      }
    }
  }

  /// 旧版（1.1.6 及以前）安装包写的开机启动项没有 --autostart，启动时会弹出主窗口：补上参数
  static Future<void> migrate() async {
    if (!Platform.isWindows) return;
    try {
      final r = await Process.run('reg', ['query', _runKey, '/v', 'Koyun']);
      if (r.exitCode == 0 && !r.stdout.toString().contains(flag)) await set(true);
    } catch (_) {}
  }
}
