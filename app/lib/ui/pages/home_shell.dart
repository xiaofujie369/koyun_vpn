import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_backend.dart';
import '../../core/core_service.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../../services/updater.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/update_dialog.dart';
import '../widgets/window_bar.dart';
import 'dashboard_page.dart';
import 'nodes_page.dart';
import 'profile_page.dart';
import 'store_page.dart';

/// 主框架。
/// 宽屏：仿 Codex 桌面端——左侧浅灰侧边栏（快捷操作 + 导航 + 节点列表 + 账户），右侧白色内容区。
/// 窄屏（手机）：底部导航。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int index = 0;
  List<String> _keys = [];
  bool _updatePrompted = false;

  void go(int i) => setState(() => index = i);

  /// 按名称跳转（home / nodes / store / profile），避免下标随平台变化出错
  void goTo(String key) {
    final i = _keys.indexOf(key);
    if (i >= 0) go(i);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => shellActive.value = true);
    Updater.instance.addListener(_onUpdate);
  }

  @override
  void dispose() {
    Updater.instance.removeListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => shellActive.value = false);
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final showStore = s.mode == AccountMode.xboard && !Platform.isIOS;
    final items = <(String, IconData, String, Widget)>[
      ('home', Icons.space_dashboard_outlined, t.navDashboard, const DashboardPage()),
      ('nodes', Icons.public_rounded, t.navNodes, const NodesPage()),
      if (showStore) ('store', Icons.shopping_bag_outlined, t.navStore, const StorePage()),
      ('profile', Icons.settings_outlined, t.navProfile, const ProfilePage()),
    ];
    _keys = items.map((e) => e.$1).toList();
    if (index >= items.length) index = 0;
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final body = IndexedStack(index: index, children: items.map((e) => e.$4).toList());

    if (!wide) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: KColors.border))),
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

    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: kSidebarWidth,
          decoration: const BoxDecoration(
            color: KColors.sidebar,
            border: Border(right: BorderSide(color: KColors.border)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 没有自绘标题栏（macOS / Linux）时，在侧边栏顶部显示 Logo
            if (!useCustomTitleBar)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  KLogo(size: 22),
                  SizedBox(width: 8),
                  Text('Koyun', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
            const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 6), child: _QuickConnect()),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _SideItem(
                    icon: items[i].$2, label: items[i].$3, selected: index == i, onTap: () => go(i)),
              ),
            const SizedBox(height: 14),
            Expanded(child: _SideNodes(onViewAll: () => goTo('nodes'))),
            const _UpdateBadge(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: _SideUser(onTap: () => goTo('profile')),
            ),
          ]),
        ),
        Expanded(child: ColoredBox(color: KColors.bg, child: body)),
      ]),
    );
  }
}

/// 侧边栏顶部的"连接 / 断开"快捷按钮（对应 Codex 的"新建对话"位置）
class _QuickConnect extends StatelessWidget {
  const _QuickConnect();
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final core = context.watch<CoreService>();
    final on = core.running;
    final label = switch (core.status) {
      CoreStatus.running => t.connected,
      CoreStatus.starting => t.connecting,
      CoreStatus.stopping => t.disconnecting,
      CoreStatus.stopped => t.notConnected,
    };
    return Material(
      color: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: KColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: core.busy ? null : () => connectToggle(context),
        child: SizedBox(
          height: 36,
          child: Row(children: [
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? KColors.ok : (core.busy ? KColors.warn : KColors.faint),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: KSize.body, fontWeight: FontWeight.w500)),
            ),
            Text(on ? t.disconnectNow : t.connectNow,
                style: TextStyle(
                    fontSize: KSize.small, color: on ? KColors.sub : KColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Material(
          color: selected ? KColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            hoverColor: KColors.hover.withValues(alpha: 0.6),
            onTap: onTap,
            child: SizedBox(
              height: 32,
              child: Row(children: [
                const SizedBox(width: 10),
                Icon(icon, size: 16, color: selected ? KColors.ink : KColors.sub),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        fontSize: KSize.body,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected ? KColors.ink : KColors.sub)),
              ]),
            ),
          ),
        ),
      );
}

/// 侧边栏中部：节点列表（对应 Codex 的对话列表），点一下直接切换
class _SideNodes extends StatelessWidget {
  const _SideNodes({required this.onViewAll});
  final VoidCallback onViewAll;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final core = context.watch<CoreService>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 10, 4),
        child: Row(children: [
          Expanded(
            child: Text(t.navNodes,
                style: const TextStyle(fontSize: KSize.small, color: KColors.faint, fontWeight: FontWeight.w500)),
          ),
          _TinyIcon(
            icon: Icons.speed_rounded,
            tooltip: t.testLatency,
            busy: core.testing,
            onTap: core.testAll,
          ),
          _TinyIcon(
            icon: Icons.refresh_rounded,
            tooltip: t.refreshSubscription,
            busy: s.refreshing,
            onTap: () => s.refresh(),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            _SideNode(
              flag: '⚡',
              name: t.autoSelect,
              selected: core.selected == 'auto',
              onTap: () => core.selectNode('auto'),
            ),
            for (final n in s.nodes)
              _SideNode(
                flag: n.flag,
                name: n.plainName,
                delay: core.delays[n.tag],
                selected: core.selected == n.tag,
                onTap: () => core.selectNode(n.tag),
              ),
          ],
        ),
      ),
    ]);
  }
}

class _TinyIcon extends StatelessWidget {
  const _TinyIcon({required this.icon, required this.tooltip, required this.onTap, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: busy
                  ? const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : Icon(icon, size: 14, color: KColors.faint),
            ),
          ),
        ),
      );
}

class _SideNode extends StatelessWidget {
  const _SideNode({required this.flag, required this.name, required this.selected, required this.onTap, this.delay});
  final String flag, name;
  final bool selected;
  final VoidCallback onTap;
  final int? delay;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? KColors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          hoverColor: KColors.hover.withValues(alpha: 0.6),
          onTap: onTap,
          child: SizedBox(
            height: 30,
            child: Row(children: [
              const SizedBox(width: 10),
              SizedBox(width: 18, child: Text(flag, style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: KSize.small + 0.5,
                        color: selected ? KColors.ink : KColors.sub,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
              ),
              if (delay != null && delay != -2)
                Text(delay! < 0 ? '—' : '$delay',
                    style: TextStyle(fontSize: 11, color: delayColor(delay))),
              const SizedBox(width: 10),
            ]),
          ),
        ),
      );
}

/// 有新版本时，在侧边栏底部显示一条提示（Codex 风格的更新提醒）
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Updater.instance,
        builder: (context, _) {
          final info = Updater.instance.available;
          if (info == null) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Material(
              color: KColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showUpdateDialog(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.arrow_circle_up_rounded, size: 16, color: KColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${context.t.newVersionBadge} v${info.version}',
                          style: const TextStyle(fontSize: KSize.small, color: KColors.accent, fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 16, color: KColors.accent),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

class _SideUser extends StatelessWidget {
  const _SideUser({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final t = context.t;
    final name = s.email ?? t.localMode;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: KColors.hover.withValues(alpha: 0.6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: KColors.accent, shape: BoxShape.circle),
              child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(s.planName ?? t.manageAccount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: KColors.faint, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 连接 / 断开（侧边栏和首页共用）：处理"没有节点""需要管理员""连接失败"等情况
Future<void> connectToggle(BuildContext context) async {
  final core = context.read<CoreService>();
  final s = context.read<Session>();
  final t = context.t;
  if (!core.running && s.nodes.isEmpty) {
    toast(context, s.subscriptionUnavailable ? t.subUnavailable : t.noNodes);
    return;
  }
  await core.toggle();
  if (!context.mounted) return;
  if (core.needAdmin) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.needAdminTitle),
        content: Text(t.needAdminBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.relaunchAsAdmin)),
        ],
      ),
    );
    if (ok == true) {
      await core.relaunchElevated();
    } else {
      await core.setTunMode(false);
    }
  } else if (core.lastError != null && !core.running) {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.connectFailed),
        content: SingleChildScrollView(
          child: SelectableText(core.lastError ?? '', style: const TextStyle(fontSize: 12.5)),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t.ok))],
      ),
    );
  }
}
