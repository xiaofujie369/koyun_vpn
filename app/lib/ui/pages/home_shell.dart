import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_config.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../theme.dart';
import '../util.dart';
import 'dashboard_page.dart';
import 'nodes_page.dart';
import 'profile_page.dart';
import 'store_page.dart';

/// 主框架：宽屏（电脑 / 平板横屏）左侧边栏；窄屏（手机）底部导航
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int index = 0;

  void go(int i) => setState(() => index = i);

  /// iOS 上不展示 App 内购买（避免审核风险），引导去官网
  bool get _showStore =>
      context.read<Session>().mode == AccountMode.xboard && !Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    context.watch<Session>();
    final items = <(IconData, IconData, String, Widget)>[
      (Icons.home_outlined, Icons.home_rounded, t.navDashboard, const DashboardPage()),
      (Icons.public_outlined, Icons.public_rounded, t.navNodes, const NodesPage()),
      if (_showStore)
        (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, t.navStore, const StorePage()),
      (Icons.person_outline_rounded, Icons.person_rounded, t.navProfile, const ProfilePage()),
    ];
    if (index >= items.length) index = 0;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = IndexedStack(index: index, children: items.map((e) => e.$4).toList());

    if (!wide) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: NavigationBar(
          backgroundColor: KColors.surface,
          indicatorColor: KColors.field,
          surfaceTintColor: Colors.transparent,
          selectedIndex: index,
          onDestinationSelected: go,
          destinations: items
              .map((e) => NavigationDestination(icon: Icon(e.$1), selectedIcon: Icon(e.$2), label: e.$3))
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(children: [
        Container(
          width: 248,
          decoration: const BoxDecoration(
            color: KColors.surface,
            border: Border(right: BorderSide(color: KColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 34, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const KLogo(size: 46),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(AppConfig.appName,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                Text(t.appTagline, style: const TextStyle(fontSize: 11, color: KColors.sub)),
              ]),
            ]),
            const SizedBox(height: 36),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SideItem(
                  icon: index == i ? items[i].$2 : items[i].$1,
                  label: items[i].$3,
                  selected: index == i,
                  onTap: () => go(i),
                ),
              ),
            const Spacer(),
            _SideUser(onTap: () => go(items.length - 1)),
          ]),
        ),
        Expanded(child: body),
      ]),
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
  Widget build(BuildContext context) => Material(
        color: selected ? KColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 21, color: selected ? Colors.white : KColors.sub),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : KColors.sub)),
            ]),
          ),
        ),
      );
}

class _SideUser extends StatelessWidget {
  const _SideUser({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final t = context.t;
    return Material(
      color: KColors.bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: KColors.ink,
              child: Icon(Icons.person_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.email ?? t.localMode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(s.planName ?? t.manageAccount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: KColors.sub, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
