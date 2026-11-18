import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_config.dart';
import '../../core/core_service.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../../services/updater.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/update_dialog.dart';
import 'dashboard_page.dart';
import 'nodes_page.dart';
import 'profile_page.dart';
import 'store_page.dart';

/// 主框架：桌面是“顶部标题栏 + 内容 + 底部导航”（一屏放下）；手机是系统底部导航栏
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int index = 0;
  List<String> _keys = [];

  void go(int i) => setState(() => index = i);

  bool _updatePrompted = false;

  @override
  void initState() {
    super.initState();
    Updater.instance.addListener(_onUpdate);
  }

  @override
  void dispose() {
    Updater.instance.removeListener(_onUpdate);
    super.dispose();
  }

  /// 启动后自动检查到新版本：弹窗提醒一次
  void _onUpdate() {
    final u = Updater.instance;
    if (!_updatePrompted && u.available != null && u.progress == null && mounted) {
      _updatePrompted = true;
      showUpdateDialog(context);
    }
  }

  /// 按名称跳转（store / nodes / profile），避免下标随平台变化出错
  void goTo(String key) {
    final i = _keys.indexOf(key);
    if (i >= 0) go(i);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final showStore = s.mode == AccountMode.xboard && !Platform.isIOS;
    final items = <(String, IconData, String, Widget)>[
      ('home', Icons.space_dashboard_outlined, t.navDashboard, const DashboardPage()),
      ('nodes', Icons.public_rounded, t.navNodes, const NodesPage()),
      if (showStore) ('store', Icons.shopping_bag_outlined, t.navStore, const StorePage()),
      ('profile', Icons.person_outline_rounded, t.navProfile, const ProfilePage()),
    ];
    _keys = items.map((e) => e.$1).toList();
    if (index >= items.length) index = 0;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: index, children: items.map((e) => e.$4).toList());

    if (!wide) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: KColors.border))),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: go,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: items
                .map((e) => NavigationDestination(icon: Icon(e.$2, size: 21), label: e.$3))
                .toList(),
          ),
        ),
      );
    }

    // 桌面：顶部标题栏（自己画，可拖动窗口）+ 内容 + 底部导航
    return Scaffold(
      body: Column(children: [
        const _TitleBar(),
        Expanded(child: body),
        _BottomNav(
          items: [for (final e in items) (e.$2, e.$3)],
          index: index,
          onTap: go,
        ),
      ]),
    );
  }
}

/// 顶部标题栏：Logo / 版本 / 公告 / 白色黑色主题 / 窗口按钮。
/// 系统标题栏已隐藏，这一栏负责拖动窗口；macOS 左侧留出红绿灯的位置
class _TitleBar extends StatelessWidget {
  const _TitleBar();
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final theme = context.watch<ThemeController>();
    final mac = Platform.isMacOS;
    return Container(
      height: 52,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.border))),
      child: Stack(children: [
        const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
        Padding(
          padding: EdgeInsets.only(left: mac ? 80 : 18, right: 10),
          child: Row(children: [
            const KLogo(size: 26),
            const SizedBox(width: 10),
            Text(AppConfig.appName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(AppConfig.appVersion,
                style: TextStyle(fontSize: 11.5, color: KColors.sub, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            const _StatusDot(),
            const Spacer(),
            if (s.notices.isNotEmpty) ...[
              _BarButton(
                icon: Icons.campaign_outlined,
                label: t.noticeTitle,
                onTap: () => showNotice(context, s.notices.first),
              ),
              const SizedBox(width: 8),
            ],
            _ThemeSwitch(controller: theme),
            if (!mac) ...[
              Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: KColors.border),
              _WinButton(icon: Icons.remove_rounded, tooltip: t.winMinimize, onTap: () => windowManager.minimize()),
              _WinButton(icon: Icons.close_rounded, tooltip: t.winClose, onTap: () => windowManager.close()),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: KColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8), side: BorderSide(color: KColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: KColors.ink),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      );
}

/// 白色 / 黑色主题切换（选过之后不再跟随系统；默认跟随系统）
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.controller});
  final ThemeController controller;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget seg(IconData icon, String tip, bool on, ThemeMode m) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            selected: on,
            label: tip,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => controller.setMode(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 30,
                height: 26,
                decoration: BoxDecoration(
                  color: on ? KColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)] : null,
                ),
                child: Icon(icon, size: 15, color: on ? KColors.ink : KColors.sub),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(Icons.light_mode_outlined, t.themeLight, !controller.dark, ThemeMode.light),
        const SizedBox(width: 2),
        seg(Icons.dark_mode_outlined, t.themeDark, controller.dark, ThemeMode.dark),
      ]),
    );
  }
}

class _WinButton extends StatelessWidget {
  const _WinButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(minimumSize: const Size(34, 32), foregroundColor: KColors.sub),
      );
}

/// 底部导航：居中的分段按钮条
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.items, required this.index, required this.onTap});
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        decoration: BoxDecoration(border: Border(top: BorderSide(color: KColors.border))),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 42,
                      constraints: const BoxConstraints(minWidth: 92),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: i == index ? KColors.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: i == index
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))]
                            : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(items[i].$1, size: 17, color: i == index ? KColors.ink : KColors.sub),
                        const SizedBox(width: 7),
                        Text(items[i].$2,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                                color: i == index ? KColors.ink : KColors.sub)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) {
    final on = context.watch<CoreService>().running;
    return Tooltip(
      message: on ? context.t.connected : context.t.notConnected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: on ? KColors.ok : KColors.faint, shape: BoxShape.circle),
      ),
    );
  }
}
