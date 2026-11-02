import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_config.dart';
import '../../core/core_service.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../theme.dart';
import '../util.dart';
import 'dashboard_page.dart';
import 'nodes_page.dart';
import 'profile_page.dart';
import 'store_page.dart';

/// 主框架：宽屏左侧窄边栏（Codex 风格）；窄屏底部导航
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int index = 0;
  List<String> _keys = [];

  void go(int i) => setState(() => index = i);

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
      body: Row(children: [
        Container(
          width: 216,
          decoration: const BoxDecoration(
            color: KColors.sidebar,
            border: Border(right: BorderSide(color: KColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                const KLogo(size: 26),
                const SizedBox(width: 9),
                Text(AppConfig.appName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                const Spacer(),
                const _StatusDot(),
              ]),
            ),
            const SizedBox(height: 22),
            for (var i = 0; i < items.length; i++)
              _SideItem(icon: items[i].$2, label: items[i].$3, selected: index == i, onTap: () => go(i)),
            const Spacer(),
            const _SideUser(),
          ]),
        ),
        Expanded(child: body),
      ]),
    );
  }
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

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? KColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: KColors.hover.withValues(alpha: 0.6),
            onTap: onTap,
            child: SizedBox(
              height: 34,
              child: Row(children: [
                const SizedBox(width: 10),
                Icon(icon, size: 17, color: selected ? KColors.ink : KColors.sub),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        fontSize: KSize.body,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? KColors.ink : KColors.sub)),
              ]),
            ),
          ),
        ),
      );
}

class _SideUser extends StatelessWidget {
  const _SideUser();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final t = context.t;
    final name = s.email ?? t.localMode;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KColors.border),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: KColors.accentSoft, borderRadius: BorderRadius.circular(7)),
          child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(color: KColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
            Text(s.planName ?? t.manageAccount, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: KColors.faint, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}
