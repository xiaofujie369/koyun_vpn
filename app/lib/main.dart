import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api/xboard_api.dart';
import 'app.dart';
import 'app_config.dart';
import 'core/core_service.dart';
import 'services/session.dart';
import 'services/storage.dart';
import 'services/ip_info.dart';
import 'services/reporter.dart';
import 'services/updater.dart';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop && !await _singleInstance(elevated: args.contains('--elevated'))) {
    exit(0);
  }

  try {
    AppConfig.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}

  final storage = Storage();
  await storage.init();
  await Reporter.instance.init(storage);
  Reporter.instance.event('app_start');
  // 崩溃 / 未处理的错误：记录下来上报（后台开启时）
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    Reporter.instance.event('crash', {'error': d.exceptionAsString(), 'stack': _short(d.stack)});
    prevOnError?.call(d);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    Reporter.instance.event('crash', {'error': e.toString(), 'stack': _short(st)});
    return false;
  };
  localeNotifier.value = localeFromCode(storage.localeOverride);
  final api = XboardApi(storage);
  final session = Session(storage, api);
  final core = CoreService(storage, session);
  final ip = IpService(core);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        // 默认窗口大小参考 Codex 桌面端，适中不占满屏幕
        size: const Size(900, 600),
        minimumSize: const Size(760, 500),
        center: true,
        title: AppConfig.appName,
        backgroundColor: const Color(0xFFFAF8F4),
        // Windows 隐藏系统标题栏，改用 App 自己画的（保留窗口边框和拖动缩放）
        titleBarStyle: Platform.isWindows ? TitleBarStyle.hidden : TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
  }

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: core),
      ChangeNotifierProvider.value(value: ip),
    ],
    child: const KoyunApp(),
  ));

  await session.init();
  await core.init();
  ip.start();
  if (isDesktop) {
    final shell = DesktopShell(core);
    await shell.install();
    Updater.instance.beforeInstall = shell.quit;
  }
  // 启动 5 秒后静默检查更新（有新版本时侧边栏显示提示，首页弹窗提醒一次）
  Future.delayed(const Duration(seconds: 5), Updater.instance.check);
}

String? _short(StackTrace? st) {
  if (st == null) return null;
  final s = st.toString();
  return s.length > 4000 ? s.substring(0, 4000) : s;
}

ServerSocket? _instanceLock;

/// 单实例：已经开着就把旧窗口叫到前台。以管理员重启时等待旧进程退出。
Future<bool> _singleInstance({required bool elevated}) async {
  const port = 47391;
  for (var i = 0; i < (elevated ? 25 : 1); i++) {
    try {
      _instanceLock = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _instanceLock!.listen((sock) {
        sock.listen((data) {
          if (utf8.decode(data).contains('show')) {
            windowManager.show();
            windowManager.focus();
          }
        });
      });
      return true;
    } catch (_) {
      if (elevated) await Future.delayed(const Duration(milliseconds: 200));
    }
  }
  try {
    final s = await Socket.connect(InternetAddress.loopbackIPv4, port,
        timeout: const Duration(seconds: 1));
    s.write('show');
    await s.flush();
    await s.close();
  } catch (_) {}
  return false;
}

/// 桌面端托盘 + 关闭窗口行为
class DesktopShell with TrayListener, WindowListener {
  DesktopShell(this.core);
  final CoreService core;

  Future<void> install() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/images/tray.ico' : 'assets/images/tray.png',
      isTemplate: false,
    );
    if (!Platform.isLinux) await trayManager.setToolTip(AppConfig.appName);
    core.addListener(_updateMenu);
    await _updateMenu();
  }

  bool? _lastRunning;
  Future<void> _updateMenu() async {
    if (_lastRunning == core.running) return;
    _lastRunning = core.running;
    final zh = Platform.localeName.startsWith('zh');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: zh ? '打开主界面' : 'Open'),
      MenuItem.separator(),
      MenuItem(
        key: 'toggle',
        label: core.running ? (zh ? '断开连接' : 'Disconnect') : (zh ? '连接' : 'Connect'),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: zh ? '退出' : 'Quit'),
    ]));
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'toggle':
        await core.toggle();
      case 'quit':
        await quit();
    }
  }

  /// 点关闭按钮：最小化到托盘，VPN 继续工作
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  Future<void> quit() async {
    // 退出前务必断开并恢复系统代理，避免客户"关了软件上不了网"
    try {
      await core.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }
}
