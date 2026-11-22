import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api/xboard_api.dart';
import 'app.dart';
import 'app_config.dart';
import 'core/core_service.dart';
import 'services/autostart.dart';
import 'services/session.dart';
import 'services/storage.dart';
import 'services/bootstrap.dart';
import 'services/ip_info.dart';
import 'services/reporter.dart';
import 'services/updater.dart';
import 'ui/theme.dart';

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
  // 启动引导配置：先用本机缓存，同时联网取最新。第一次打开（没有缓存）时最多等 6 秒，
  // 保证内置域名被封时也能拿到可用域名再登录。（后台地址也由它下发，所以放在统计上报之前）
  await Bootstrap.instance.init(storage);
  final boot = Bootstrap.instance.refresh();
  if (!Bootstrap.instance.hasConfig) {
    await boot.timeout(const Duration(seconds: 7), onTimeout: () => false);
  }
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
  final theme = ThemeController(
    switch (storage.themeMode) { 'dark' => ThemeMode.dark, 'system' => ThemeMode.system, _ => ThemeMode.light },
    onSave: (m) => storage.setThemeMode(m.name),
  )..init(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    final (size, minSize) = await _windowSize();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        minimumSize: minSize,
        center: true,
        title: AppConfig.appName,
        backgroundColor: KColors.bg,
        // Big Sur：隐藏系统标题栏，侧边栏铺满；Windows 右上角自己画标准的最小化 / 最大化 / 关闭，macOS 保留红绿灯
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS,
      ),
      () async {
        // 开机自启（--autostart）：只在托盘里运行，不弹主窗口
        if (args.contains(Autostart.flag)) return;
        await windowManager.show();
        await windowManager.focus();
      },
    );
    unawaited(Autostart.migrate());
    await windowManager.setPreventClose(true);
  }

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: core),
      ChangeNotifierProvider.value(value: ip),
      ChangeNotifierProvider.value(value: theme),
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
    // macOS 的 Cmd+Q 不经过关闭窗口：要先恢复系统代理，否则退出后上不了网
    if (Platform.isMacOS) {
      AppLifecycleListener(onExitRequested: () async {
        await quit();
        return AppExitResponse.exit;
      });
    }
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/images/tray.ico' : 'assets/images/tray.png',
      isTemplate: false,
    );
    if (!Platform.isLinux) await trayManager.setToolTip(AppConfig.appName);
    core.addListener(_updateMenu);
    core.session.addListener(_updateMenu);
    await _updateMenu();
  }

  String? _menuSig;

  /// 托盘菜单（参考 FlClash / Clash Verge）：连接、分流模式、TUN、选节点都能在托盘里完成
  Future<void> _updateMenu() async {
    final st = core.storage;
    final nodes = core.session.nodes;
    final sig = [
      core.running, core.busy, st.routeMode.name, st.tunMode, core.selected,
      nodes.length, nodes.isEmpty ? '' : nodes.first.tag, nodes.isEmpty ? '' : nodes.last.tag,
    ].join('|');
    if (sig == _menuSig) return;
    _menuSig = sig;
    final zh = Platform.localeName.startsWith('zh');
    String l(String z, String e) => zh ? z : e;
    final mode = st.routeMode;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: l('打开主界面', 'Open')),
      MenuItem.separator(),
      MenuItem(
        key: 'toggle',
        label: core.running ? l('断开连接', 'Disconnect') : l('连接', 'Connect'),
        disabled: core.busy,
      ),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'mode:rule', label: l('智能分流', 'Rule'), checked: mode == RouteMode.rule),
      MenuItem.checkbox(key: 'mode:global', label: l('全局', 'Global'), checked: mode == RouteMode.global),
      MenuItem.checkbox(key: 'mode:direct', label: l('直连', 'Direct'), checked: mode == RouteMode.direct),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'tun', label: l('TUN 模式', 'TUN mode'), checked: st.tunMode, disabled: core.busy),
      if (nodes.isNotEmpty)
        MenuItem.submenu(
          key: 'nodes',
          label: l('节点', 'Servers'),
          submenu: Menu(items: [
            MenuItem.checkbox(key: 'node:auto', label: l('自动选择', 'Auto'), checked: core.selected == 'auto'),
            MenuItem.separator(),
            for (var i = 0; i < nodes.length && i < 80; i++)
              MenuItem.checkbox(key: 'node:$i', label: nodes[i].plainName, checked: core.selected == nodes[i].tag),
          ]),
        ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: l('退出', 'Quit')),
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
      case 'tun':
        await core.setTunMode(!core.storage.tunMode);
      case 'node:auto':
        await core.selectNode('auto');
      default:
        final k = item.key ?? '';
        if (k.startsWith('mode:')) {
          await core.setRouteMode(RouteMode.values.byName(k.substring(5)));
        } else if (k.startsWith('node:')) {
          final i = int.tryParse(k.substring(5));
          final nodes = core.session.nodes;
          if (i != null && i < nodes.length) await core.selectNode(nodes[i].tag);
        }
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

/// 默认窗口 900×600（和 1.1.6 一样）。屏幕可用区域放不下时按比例缩小，
/// 保证在 1366×768 + 125% 缩放这类小屏幕上也能完整显示
Future<(Size, Size)> _windowSize() async {
  const want = Size(900, 600);
  const minWant = Size(760, 500);
  try {
    final d = await screenRetriever.getPrimaryDisplay();
    final avail = d.visibleSize ?? d.size; // 逻辑像素，已去掉任务栏
    final w = (avail.width * 0.94).clamp(560.0, want.width);
    final h = (avail.height * 0.92).clamp(420.0, want.height);
    return (Size(w, h), Size(w < minWant.width ? w : minWant.width, h < minWant.height ? h : minWant.height));
  } catch (_) {
    return (want, minWant);
  }
}
