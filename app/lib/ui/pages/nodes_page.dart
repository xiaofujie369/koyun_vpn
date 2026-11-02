import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_service.dart';
import '../../models/node.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final nodes = _query.isEmpty
        ? s.nodes
        : s.nodes.where((n) => n.displayName.toLowerCase().contains(_query.toLowerCase())).toList();

    return Column(children: [
      KPage(
        padding: EdgeInsets.fromLTRB(20, wide ? 32 : 12, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.navNodes, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  s.lastRefreshAt == null
                      ? t.nodesCount(s.nodes.length)
                      : '${t.nodesCount(s.nodes.length)} · ${t.updatedAt(_ago(context, s.lastRefreshAt!))}',
                  style: const TextStyle(color: KColors.sub, fontSize: 13),
                ),
              ]),
            ),
            IconButton.filledTonal(
              tooltip: t.testLatency,
              onPressed: core.testing ? null : core.testAll,
              icon: core.testing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: t.refreshSubscription,
              onPressed: s.refreshing ? null : _refresh,
              icon: s.refreshing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ]),
          const SizedBox(height: 14),
          if (s.nodes.length > 8)
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: t.searchNodes,
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          color: KColors.lavender,
          onRefresh: _refresh,
          child: s.nodes.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  Center(child: Text(s.subscriptionUnavailable ? t.subUnavailable : t.noNodes,
                      style: const TextStyle(color: KColors.sub))),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(160, 46)),
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t.refreshSubscription),
                    ),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24, top: 6),
                  itemCount: nodes.length + (_query.isEmpty ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (_query.isEmpty && i == 0) {
                      return KPage(
                        child: _NodeTile(
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
                    final n = nodes[_query.isEmpty ? i - 1 : i];
                    return KPage(
                      child: _NodeTile(
                        flag: n.flag,
                        code: n.countryCode,
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

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.flag,
    this.code,
    required this.name,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.multiplier,
    this.delay,
  });
  final String flag, name, sub;
  final String? code; // 地区代码，有则显示国旗图片
  final String? multiplier;
  final int? delay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: KColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? KColors.lavender : KColors.border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: KColors.field, shape: BoxShape.circle),
                child: code != null ? CountryFlag(code, width: 22) : Text(flag, style: const TextStyle(fontSize: 21)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Flexible(
                      child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: KColors.faint, fontSize: 12)),
                    ),
                    if (multiplier != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: KColors.field, borderRadius: BorderRadius.circular(6)),
                        child: Text(multiplier!,
                            style: const TextStyle(fontSize: 11, color: KColors.sub)),
                      ),
                    ],
                  ]),
                ]),
              ),
              if (delay != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    delay == -2 ? '-' : (delay! < 0 ? t.timeout : '${delay}ms'),
                    style: TextStyle(color: delayColor(delay), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? KColors.lavender : KColors.faint,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
