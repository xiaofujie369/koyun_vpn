import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_backend.dart';
import '../../core/core_service.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/power_button.dart';
import 'home_shell.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<CoreService>().running) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final core = context.read<CoreService>();
    final s = context.read<Session>();
    final t = context.t;
    if (!core.running && s.nodes.isEmpty) {
      toast(context, s.subscriptionUnavailable ? t.subUnavailable : t.noNodes);
      return;
    }
    await core.toggle();
    if (!mounted) return;
    if (core.needAdmin) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t.needAdminTitle),
          content: Text(t.needAdminBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(c, true),
              child: Text(t.relaunchAsAdmin),
            ),
          ],
        ),
      );
      if (ok == true) {
        await core.relaunchElevated();
      } else {
        await core.setTunMode(false);
      }
    } else if (core.lastError != null && !core.running) {
      _showError(core);
    }
  }

  void _showError(CoreService core) {
    final t = context.t;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.connectFailed),
        content: SingleChildScrollView(
          child: SelectableText(core.lastError ?? '', style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c),
            child: Text(t.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final core = context.watch<CoreService>();
    final s = context.watch<Session>();
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final statusText = switch (core.status) {
      CoreStatus.running => t.connected,
      CoreStatus.starting => t.connecting,
      CoreStatus.stopping => t.disconnecting,
      CoreStatus.stopped => t.notConnected,
    };
    final node = core.currentNode;
    final desktop = !(Platform.isAndroid || Platform.isIOS);

    return RefreshIndicator(
      color: KColors.lavender,
      onRefresh: () => s.refresh(),
      child: ListView(
        padding: EdgeInsets.only(top: wide ? 32 : 16, bottom: 28),
        children: [
          KPage(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.notices.isNotEmpty) _NoticeBar(notice: s.notices.first),
              if (s.subscriptionUnavailable) ...[
                const SizedBox(height: 12),
                _WarnCard(
                  text: t.subUnavailable,
                  action: Platform.isIOS ? null : t.renewNow,
                  onAction: () => context.findAncestorStateOfType<HomeShellState>()?.go(2),
                ),
              ],
              SizedBox(height: wide ? 28 : 20),
              Center(child: PowerButton(status: core.status, onTap: _toggle, size: wide ? 150 : 140)),
              const SizedBox(height: 14),
              Center(
                child: Text(statusText,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  core.running && core.connectedAt != null
                      ? fmtDuration(DateTime.now().difference(core.connectedAt!))
                      : t.tapToConnect,
                  style: const TextStyle(color: KColors.sub, letterSpacing: 1.5, fontSize: 13),
                ),
              ),
              const SizedBox(height: 22),
              _SpeedRow(core: core),
              const SizedBox(height: 22),
              _NodeCard(
                node: node == null
                    ? (core.selected == 'auto' ? t.autoSelect : core.selected)
                    : '${node.flag}  ${node.plainName}',
                sub: core.selected == 'auto' ? t.autoSelectDesc : node?.protocolLabel ?? '',
                onTap: () => context.findAncestorStateOfType<HomeShellState>()?.go(1),
              ),
              const SizedBox(height: 16),
              Flex(
                direction: wide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop) ...[
                    Flexible(fit: wide ? FlexFit.tight : FlexFit.loose, child: _TunCard(core: core)),
                    SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 16),
                  ],
                  Flexible(fit: wide ? FlexFit.tight : FlexFit.loose, child: _ModeCard(core: core)),
                ],
              ),
              const SizedBox(height: 22),
              _Footer(session: s),
            ]),
          ),
        ],
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice});
  final Map<String, dynamic> notice;
  @override
  Widget build(BuildContext context) {
    final title = (notice['title'] ?? '').toString();
    final content = stripHtml((notice['content'] ?? '').toString());
    return KCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(content)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(context.t.ok))],
        ),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        const Icon(Icons.chevron_right_rounded, color: KColors.faint),
      ]),
    );
  }
}

class _WarnCard extends StatelessWidget {
  const _WarnCard({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF4D7B5)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: KColors.warn),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(color: KColors.warn, fontWeight: FontWeight.w700)),
            ),
        ]),
      );
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget item(IconData i, String label, String v, String total) => Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, color: KColors.sub, size: 22),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: KColors.sub, fontSize: 12)),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(total, style: const TextStyle(color: KColors.faint, fontSize: 11)),
            ]),
          ]),
        );
    return Row(children: [
      item(Icons.south_rounded, t.download, fmtSpeed(core.downSpeed), fmtBytes(core.downTotal)),
      item(Icons.north_rounded, t.upload, fmtSpeed(core.upSpeed), fmtBytes(core.upTotal)),
    ]);
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, required this.sub, required this.onTap});
  final String node, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => KCard(
        onTap: onTap,
        child: Row(children: [
          const IconBox(Icons.public_rounded),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t.currentNode, style: const TextStyle(color: KColors.sub, fontSize: 12)),
              const SizedBox(height: 4),
              Text(node, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty)
                Text(sub, style: const TextStyle(color: KColors.faint, fontSize: 12)),
            ]),
          ),
          Text(context.t.switchNode, style: const TextStyle(color: KColors.faint)),
          const Icon(Icons.chevron_right_rounded, color: KColors.faint),
        ]),
      );
}

class _TunCard extends StatelessWidget {
  const _TunCard({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return KCard(
      child: Row(children: [
        const IconBox(Icons.desktop_windows_outlined),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.tunMode, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(t.tunModeDesc, style: const TextStyle(color: KColors.sub, fontSize: 12)),
          ]),
        ),
        Switch(
          value: core.storage.tunMode,
          onChanged: core.busy ? null : (v) => core.setTunMode(v),
        ),
      ]),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mode = core.storage.routeMode;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBox(Icons.alt_route_rounded),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.routeMode, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(t.routeModeDesc, style: const TextStyle(color: KColors.sub, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            for (final m in RouteMode.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => core.setRouteMode(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: mode == m ? KColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: mode == m
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      switch (m) {
                        RouteMode.rule => t.modeRule,
                        RouteMode.global => t.modeGlobal,
                        RouteMode.direct => t.modeDirect,
                      },
                      style: TextStyle(
                        fontWeight: mode == m ? FontWeight.w700 : FontWeight.w500,
                        color: mode == m ? KColors.ink : KColors.sub,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final exp = session.expireAt;
    final days = exp == 0
        ? null
        : (DateTime.fromMillisecondsSinceEpoch(exp * 1000).difference(DateTime.now()).inHours / 24).ceil();
    final remain = session.totalBytes - session.usedBytes;
    final style = const TextStyle(color: KColors.sub, fontSize: 13);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 22,
      runSpacing: 8,
      children: [
        if (session.mode == AccountMode.xboard || exp > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.schedule_rounded, size: 16, color: KColors.sub),
            const SizedBox(width: 6),
            Text(days == null ? t.longTerm : t.daysLeft(days < 0 ? 0 : days), style: style),
          ]),
        if (session.totalBytes > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt_rounded, size: 16, color: KColors.sub),
            const SizedBox(width: 6),
            Text(t.trafficLeft(fmtBytes(remain)), style: style),
          ]),
      ],
    );
  }
}
