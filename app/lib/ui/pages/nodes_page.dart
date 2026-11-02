import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_service.dart';
import '../../models/node.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

/// 节点页（Codex 风格列表：无卡片、整行悬停高亮、右侧显示延迟）
class NodesPage extends StatefulWidget {
  const NodesPage({super.key});
  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  String _query = '';

  Future<void> _refresh() async {
    final s = context.read<Session>();
    final t = context.t;
    final r = await s.refresh();
    if (!mounted) return;
    toast(context, switch (r) {
      RefreshResult.ok => t.refreshOk(s.nodes.length),
      RefreshResult.networkFail => t.refreshNetworkFail,
      RefreshResult.unavailable => t.subUnavailable,
      RefreshResult.unauthorized => t.sessionExpired,
      RefreshResult.empty => t.importNoNodes,
      RefreshResult.error => s.lastError ?? t.refreshNetworkFail,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final core = context.watch<CoreService>();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final q = _query.toLowerCase();
    final nodes = q.isEmpty ? s.nodes : s.nodes.where((n) => n.displayName.toLowerCase().contains(q)).toList();
    final subtitle = s.lastRefreshAt == null
        ? t.nodesCount(s.nodes.length)
        : '${t.nodesCount(s.nodes.length)} · ${t.updatedAt(_ago(context, s.lastRefreshAt!))}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KPage(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(
            title: t.navNodes,
            subtitle: subtitle,
            actions: [
              _Action(
                compact: compact,
                icon: Icons.speed_rounded,
                label: t.testLatency,
                busy: core.testing,
                onTap: core.testAll,
              ),
              const SizedBox(width: 8),
              _Action(
                compact: compact,
                icon: Icons.refresh_rounded,
                label: t.refreshSubscription,
                busy: s.refreshing,
                onTap: _refresh,
              ),
            ],
          ),
          if (s.nodes.length > 8)
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: t.searchNodes,
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
              ),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          color: KColors.accent,
          onRefresh: _refresh,
          child: s.nodes.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(s.subscriptionUnavailable ? t.subUnavailable : t.noNodes,
                        style: const TextStyle(color: KColors.sub)),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: nodes.length + (q.isEmpty ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (q.isEmpty && i == 0) {
                      return KPage(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _NodeRow(
                          flag: '⚡',
                          name: t.autoSelect,
                          sub: core.autoNow == null
                              ? t.autoSelectDesc
                              : '${t.autoSelectDesc} · ${_nameOf(s, core.autoNow!)}',
                          selected: core.selected == 'auto',
                          onTap: () => core.selectNode('auto'),
                        ),
                      );
                    }
                    final n = nodes[q.isEmpty ? i - 1 : i];
                    return KPage(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _NodeRow(
                        flag: n.flag,
                        name: n.plainName,
                        sub: n.protocolLabel,
                        multiplier: n.multiplier,
                        delay: core.delays[n.tag],
                        selected: core.selected == n.tag,
                        onTap: () => core.selectNode(n.tag),
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }

  static String _nameOf(Session s, String tag) {
    for (final ProxyNode n in s.nodes) {
      if (n.tag == tag) return n.displayName;
    }
    return tag;
  }

  static String _ago(BuildContext context, DateTime d) {
    final diff = DateTime.now().difference(d);
    final t = context.t;
    if (diff.inMinutes < 1) return t.justNow;
    if (diff.inHours < 1) return t.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return t.hoursAgo(diff.inHours);
    return t.daysAgo(diff.inDays);
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.flag,
    required this.name,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.multiplier,
    this.delay,
  });
  final String flag, name, sub;
  final String? multiplier;
  final int? delay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? KColors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: KColors.hover.withValues(alpha: 0.55),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              SizedBox(width: 26, child: Text(flag, style: const TextStyle(fontSize: 17))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: KSize.body, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                    ),
                    if (multiplier != null) ...[const SizedBox(width: 6), KTag(multiplier!)],
                  ]),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: KColors.faint, fontSize: 11.5)),
                ]),
              ),
              if (delay != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    delay == -2 ? '-' : (delay! < 0 ? t.timeout : '$delay ms'),
                    style: TextStyle(
                        color: delayColor(delay), fontSize: KSize.small, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              SizedBox(
                width: 28,
                child: selected ? const Icon(Icons.check_rounded, size: 16, color: KColors.accent) : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 页头按钮：宽屏显示"图标 + 文字"，手机只显示图标
class _Action extends StatelessWidget {
  const _Action({required this.compact, required this.icon, required this.label, required this.busy, required this.onTap});
  final bool compact, busy;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final i = busy ? const BtnSpinner(color: KColors.sub) : Icon(icon, size: 15);
    if (compact) {
      return IconButton.outlined(tooltip: label, onPressed: busy ? null : onTap, icon: i);
    }
    return OutlinedButton.icon(onPressed: busy ? null : onTap, icon: i, label: Text(label));
  }
}
