import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_service.dart';
import '../../models/node.dart';
import '../../services/ip_info.dart';
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
  String _region = ''; // 空 = 全部；'?' = 其他（没有国旗）

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
    final q = _query.toLowerCase();
    // 按地区统计（没有国旗的节点归入"其他"），按数量从多到少
    final counts = <String, int>{};
    for (final n in s.nodes) {
      final c = n.countryCode ?? '?';
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final regions = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (_region.isNotEmpty && !counts.containsKey(_region)) _region = '';
    final nodes = s.nodes
        .where((n) =>
            (_region.isEmpty || (n.countryCode ?? '?') == _region) &&
            (q.isEmpty || n.displayName.toLowerCase().contains(q)))
        .toList();
    final showAuto = q.isEmpty && _region.isEmpty;
    final locale = Localizations.localeOf(context);

    return Column(children: [
      KPage(
        maxWidth: 960,
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
          if (regions.length > 1) ...[
            const SizedBox(height: 10),
            // 地区按钮自动换行（电脑上鼠标不能横向拖动，所以不用横向滚动）
            Wrap(spacing: 6, runSpacing: 6, children: [
                _RegionChip(
                  label: '${t.filterAll} ${s.nodes.length}',
                  selected: _region.isEmpty,
                  onTap: () => setState(() => _region = ''),
                ),
                for (final r in regions)
                  _RegionChip(
                    code: r.key == '?' ? null : r.key,
                    label: '${r.key == '?' ? t.otherRegion : regionName(r.key, locale.languageCode, hant: locale.scriptCode == 'Hant')} ${r.value}',
                    selected: _region == r.key,
                    onTap: () => setState(() => _region = r.key),
                  ),
            ]),
          ],
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
              : LayoutBuilder(builder: (context, c) {
                  // 一行放几个：手机 1 个，普通窗口 2 个，很宽 3 个
                  final w = c.maxWidth.clamp(0.0, 960.0) - 40;
                  final cols = w >= 840 ? 3 : (w >= 480 ? 2 : 1);
                  final hPad = (c.maxWidth - w) / 2;
                  return CustomScrollView(slivers: [
                    if (showAuto)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 8),
                        sliver: SliverToBoxAdapter(
                          child: _NodeTile(
                            flag: '⚡',
                            name: t.autoSelect,
                            sub: core.autoNow == null
                                ? t.autoSelectDesc
                                : '${t.autoSelectDesc} · ${_nameOf(s, core.autoNow!)}',
                            selected: core.selected == 'auto',
                            onTap: () => core.selectNode('auto'),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hPad, showAuto ? 0 : 6, hPad, 24),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisExtent: 56,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          childCount: nodes.length,
                          (c, i) {
                            final n = nodes[i];
                            return _NodeTile(
                              flag: n.flag,
                              code: n.countryCode,
                              name: n.plainName,
                              sub: n.protocolLabel,
                              multiplier: n.multiplier,
                              delay: core.delays[n.tag],
                              selected: core.selected == n.tag,
                              testing: core.testingTags.contains(n.tag),
                              onTap: () => core.selectNode(n.tag),
                              onRetest: core.testing ? null : () => core.testOne(n),
                            );
                          },
                        ),
                      ),
                    ),
                  ]);
                }),
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
    this.testing = false,
    this.onRetest,
  });
  final String flag, name, sub;
  final String? code; // 地区代码，有则显示国旗图片
  final String? multiplier;
  final int? delay;
  final bool selected;
  final bool testing; // 正在测这个节点
  final VoidCallback onTap;
  final VoidCallback? onRetest; // 单独重测

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: selected ? KColors.accentSoft : KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? KColors.lavender : KColors.border, width: selected ? 1.4 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: code != null ? CountryFlag(code, width: 22) : Text(flag, style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Flexible(
                      child: Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: KColors.faint, fontSize: 11)),
                    ),
                    if (multiplier != null) ...[const SizedBox(width: 5), KTag(multiplier!)],
                  ]),
                ]),
              ),
              if (testing)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
                )
              else if (delay != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    delay == -2 ? '-' : (delay! < 0 ? t.timeout : '${delay}ms'),
                    style: TextStyle(color: delayColor(delay), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                // 超时 / 测不出：显示单独重测按钮
                if (delay! < 0 && onRetest != null)
                  Tooltip(
                    message: t.testLatency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onRetest,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.refresh_rounded, size: 15, color: KColors.sub),
                      ),
                    ),
                  ),
              ],
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle_rounded, size: 16, color: KColors.lavender),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// 地区筛选按钮
class _RegionChip extends StatelessWidget {
  const _RegionChip({required this.label, required this.selected, required this.onTap, this.code});
  final String label;
  final String? code;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        child: Material(
          color: selected ? KColors.ink : KColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? KColors.ink : KColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (code != null) ...[CountryFlag(code, width: 16), const SizedBox(width: 6)],
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? Colors.white : KColors.ink)),
              ]),
            ),
          ),
        ),
      );
}
