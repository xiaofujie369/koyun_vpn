import 'dart:ffi';
import 'dart:io';

/// 系统代理（桌面端）。由 App 自己设置 / 恢复，而不是交给内核：
/// Windows 上结束子进程是强杀，内核来不及恢复；App 崩溃后下次启动也能自己清理，
/// 避免出现"关了 VPN 却上不了网"。
class SysProxy {
  static const _bypass =
      'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';
  static const _winKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static Future<void> enable(int port) async {
    if (Platform.isWindows) {
      await _reg(['add', _winKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
      await _reg(['add', _winKey, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '127.0.0.1:$port', '/f']);
      await _reg(['add', _winKey, '/v', 'ProxyOverride', '/t', 'REG_SZ', '/d', _bypass, '/f']);
      _winNotify();
    } else if (Platform.isMacOS) {
      for (final s in await _macServices()) {
        await _ns(['-setwebproxy', s, '127.0.0.1', '$port']);
        await _ns(['-setsecurewebproxy', s, '127.0.0.1', '$port']);
        await _ns(['-setsocksfirewallproxy', s, '127.0.0.1', '$port']);
        await _ns(['-setproxybypassdomains', s, 'localhost', '127.0.0.1', '*.local',
          '192.168.0.0/16', '10.0.0.0/8', '172.16.0.0/12']);
      }
    }
  }

  static Future<void> disable() async {
    if (Platform.isWindows) {
      await _reg(['add', _winKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
      _winNotify();
    } else if (Platform.isMacOS) {
      for (final s in await _macServices()) {
        await _ns(['-setwebproxystate', s, 'off']);
        await _ns(['-setsecurewebproxystate', s, 'off']);
        await _ns(['-setsocksfirewallproxystate', s, 'off']);
      }
    }
  }

  /// 当前系统代理是否指向我们的端口（只清理自己设置的，不动用户其它代理软件）
  static Future<bool> isOurs(int port) async {
    if (port <= 0) return false;
    if (Platform.isWindows) {
      final r = await Process.run('reg', ['query', _winKey, '/v', 'ProxyServer']);
      final e = await Process.run('reg', ['query', _winKey, '/v', 'ProxyEnable']);
      return r.stdout.toString().contains('127.0.0.1:$port') &&
          e.stdout.toString().contains('0x1');
    }
    if (Platform.isMacOS) {
      for (final s in await _macServices()) {
        final r = await Process.run('networksetup', ['-getwebproxy', s]);
        final out = r.stdout.toString();
        if (out.contains('Enabled: Yes') && out.contains('Port: $port')) return true;
      }
    }
    return false;
  }

  static Future<void> _reg(List<String> args) async {
    await Process.run('reg', args, runInShell: false);
  }

  /// 通知 WinINet 设置已变化，浏览器立刻生效
  static void _winNotify() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final f = wininet.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('InternetSetOptionW');
      f(0, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
      f(0, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
    } catch (_) {}
  }

  static Future<List<String>> _macServices() async {
    final r = await Process.run('networksetup', ['-listallnetworkservices']);
    return r.stdout
        .toString()
        .split('\n')
        .skip(1) // 第一行是说明文字
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('*'))
        .toList();
  }

  static Future<void> _ns(List<String> args) async {
    await Process.run('networksetup', args);
  }
}
