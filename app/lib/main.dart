import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api/xboard_api.dart';
import 'app.dart';
import 'app_config.dart';
import 'core/core_service.dart';
import 'services/session.dart';
import 'services/storage.dart';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop && !await _singleInstance(elevated: args.contains('--elevated'))) {
    exit(0);
  }

  final storage = Storage();
  await storage.init();
  localeNotifier.value = localeFromCode(storage.localeOverride);
  final api = XboardApi(storage);
  final session = Session(storage, api);
  final core = CoreService(storage, session);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 780),
        minimumSize: Size(420, 640),
        center: true,
        title: AppConfig.appName,
        backgroundColor: Color(0xFFF7F3EA),
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
    ],
    child: const KoyunApp(),
  ));

  await session.init();
  await core.init();
  if (isDesktop) DesktopShell(core).install();
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
