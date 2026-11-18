import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_backend.dart';
import '../../core/core_service.dart';
import '../../core/mobile_backend.dart';
import '../../services/ip_info.dart';
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
    } else if (core.running) {
      await _maybeAskBackground(core);
    }
  }

  /// 安卓：国产系统切到后台不久就会杀掉 VPN。连接成功后请用户允许后台运行；
  /// 只提示一次，被系统杀过之后再提示一次
  Future<void> _maybeAskBackground(CoreService core) async {
    final b = core.backend;
    if (!Platform.isAndroid || b is! MobileBackend) return;
    final storage = core.storage;
    if (storage.bgHintShown && !core.killedBySystem) return;
    final exempt = await b.batteryExempt();
    final brand = await b.brand();
    const strict = ['xiaomi', 'redmi', 'huawei', 'honor', 'oppo', 'oneplus', 'realme', 'vivo', 'iqoo', 'meizu'];
    final strictRom = strict.any(brand.contains);
    if (exempt && !(strictRom && core.killedBySystem)) return;
    core.killedBySystem = false;
    await storage.setBgHintShown(true);
    if (!mounted) return;
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.bgTitle),
        content: Text(exempt ? t.bgBodyRom : (strictRom ? '${t.bgBody}\n\n${t.bgBodyRom}' : t.bgBody),
            style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.later)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.bgAllow),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!exempt) {
      await b.requestBatteryExempt();
    } else {
      await b.openAppSettings();
    }
  }

  void _showError(CoreService core) {
    final t = context.t;
    final friendly = switch (core.errorKind) {
      'nodeUnreachable' => t.errNodeUnreachable,
      'tunAdapter' => t.errTunAdapter,
      'macNotAdmin' => t.errMacNotAdmin,
      _ => null,
    };
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.connectFailed),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (friendly != null) ...[
              Text(friendly, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 12),
              Text(t.errorDetails, style: TextStyle(fontSize: 12, color: KColors.sub)),
              const SizedBox(height: 4),
            ],
            SelectableText(core.lastError ?? '',
                style: TextStyle(fontSize: friendly != null ? 12 : 13, color: friendly != null ? KColors.sub : null)),
          ]),
        ),
        actions: [
          if (core.errorKind == 'nodeUnreachable')
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context.findAncestorStateOfType<HomeShellState>()?.goTo('nodes');
              },
              child: Text(t.changeNode),
            ),
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
      CoreStatus.stopped => core.errorKind == 'nodeUnreachable' ? t.connectFailed : t.notConnected,
    };
    final node = core.currentNode;
    final desktop = !(Platform.isAndroid || Platform.isIOS);
    if (desktop && MediaQuery.sizeOf(context).width >= 680) {
      return _DesktopDashboard(core: core, session: s, statusText: statusText, onToggle: _toggle);
    }

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
                  onAction: () => context.findAncestorStateOfType<HomeShellState>()?.goTo('store'),
                ),
              ],
              if (core.running && core.nodeUnreachable) ...[
                const SizedBox(height: 12),
                _WarnCard(
                  text: t.warnNodeUnreachable,
                  action: t.changeNode,
                  onAction: () => context.findAncestorStateOfType<HomeShellState>()?.goTo('nodes'),
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
                  style: TextStyle(color: KColors.sub, letterSpacing: 1.5, fontSize: 13),
                ),
              ),
              const SizedBox(height: 22),
              _SpeedRow(core: core),
              const SizedBox(height: 22),
              _NodeCard(
                node: node == null
                    ? (core.selected == 'auto' ? t.autoSelect : core.selected)
                    : node.plainName,
                code: node?.countryCode,
                sub: core.selected == 'auto' ? t.autoSelectDesc : node?.protocolLabel ?? '',
                onTap: () => context.findAncestorStateOfType<HomeShellState>()?.goTo('nodes'),
              ),
              const SizedBox(height: 16),
              // 修复：以前这里用 Flex + stretch 放在滚动列表里，宽窗口时报错导致整页空白
              if (wide && desktop)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _TunCard(core: core)),
                    const SizedBox(width: 16),
                    Expanded(child: _ModeCard(core: core)),
                  ]),
                )
              else ...[
                if (desktop) ...[_TunCard(core: core), const SizedBox(height: 16)],
                _ModeCard(core: core),
              ],
              const SizedBox(height: 22),
              const _NetworkPanel(),
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
    return KCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => showNotice(context, notice),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.campaign_rounded, color: KColors.onInk, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Icon(Icons.chevron_right_rounded, color: KColors.faint),
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
          color: KColors.warnSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KColors.warn.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: KColors.warn),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: TextStyle(color: KColors.warn, fontWeight: FontWeight.w700)),
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
              Text(label, style: TextStyle(color: KColors.sub, fontSize: 12)),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(total, style: TextStyle(color: KColors.faint, fontSize: 11)),
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
  const _NodeCard({required this.node, required this.sub, required this.onTap, this.code});
  final String node, sub;
  final String? code; // 地区代码：显示国旗图片
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => KCard(
        onTap: onTap,
        child: Row(children: [
          code != null
              ? Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(8.4)),
                  child: CountryFlag(code, width: 20),
                )
              : const IconBox(Icons.public_rounded),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t.currentNode, style: TextStyle(color: KColors.sub, fontSize: 12)),
              const SizedBox(height: 4),
              Text(node, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty)
                Text(sub, style: TextStyle(color: KColors.faint, fontSize: 12)),
            ]),
          ),
          Text(context.t.switchNode, style: TextStyle(color: KColors.faint)),
          Icon(Icons.chevron_right_rounded, color: KColors.faint),
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
            Text(t.tunModeDesc, style: TextStyle(color: KColors.sub, fontSize: 12)),
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
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.routeMode, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(t.routeModeDesc, style: TextStyle(color: KColors.sub, fontSize: 12)),
            ]),
          ),
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
    final style = TextStyle(color: KColors.sub, fontSize: 13);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 22,
      runSpacing: 8,
      children: [
        if (session.mode == AccountMode.xboard || exp > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_rounded, size: 16, color: KColors.sub),
            const SizedBox(width: 6),
            Text(days == null ? t.longTerm : t.daysLeft(days < 0 ? 0 : days), style: style),
          ]),
        if (session.totalBytes > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_rounded, size: 16, color: KColors.sub),
            const SizedBox(width: 6),
            Text(t.trafficLeft(fmtBytes(remain)), style: style),
          ]),
      ],
    );
  }
}
/// 网络信息：本机 IP 和代理出口 IP 并排（窄屏上下排列）
class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel();
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ip = context.watch<IpService>();
    final core = context.watch<CoreService>();
    final local = _IpCard(
      icon: Icons.computer_rounded,
      title: t.localNetwork,
      info: ip.local,
      loading: ip.loadingLocal,
      failed: ip.localFailed,
      onRefresh: ip.refreshLocal,
    );
    final proxy = _IpCard(
      icon: Icons.shield_outlined,
      title: t.proxyExit,
      info: ip.proxy,
      loading: ip.loadingProxy,
      failed: ip.proxyFailed,
      placeholder: core.running ? null : t.showAfterConnect,
      highlight: core.running && ip.proxy != null,
      onRefresh: ip.refreshProxy,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Row(children: [
          Text(t.networkInfo,
              style: TextStyle(fontSize: KSize.small, color: KColors.faint, fontWeight: FontWeight.w500)),
          const Spacer(),
          Tooltip(
            message: t.showIp,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: ip.toggleShowFull,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(ip.showFull ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 15, color: KColors.faint),
              ),
            ),
          ),
        ]),
      ),
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 500
            ? IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: local),
                  const SizedBox(width: 12),
                  Expanded(child: proxy),
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [local, const SizedBox(height: 10), proxy]),
      ),
    ]);
  }
}

class _IpCard extends StatelessWidget {
  const _IpCard({
    required this.icon,
    required this.title,
    required this.info,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    this.placeholder,
    this.highlight = false,
  });
  final IconData icon;
  final String title;
  final IpInfo? info;
  final bool loading, failed, highlight;
  final String? placeholder;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ip = context.read<IpService>();
    final locale = Localizations.localeOf(context);
    final i = info;

    Widget body;
    if (placeholder != null) {
      body = Text(placeholder!, style: TextStyle(fontSize: KSize.small + 0.5, color: KColors.faint));
    } else if (loading && i == null) {
      body = Align(alignment: Alignment.centerLeft, child: BtnSpinner(color: KColors.faint));
    } else if (i == null) {
      body = InkWell(
        onTap: onRefresh,
        child: Text(failed ? t.ipFetchFailed : '—',
            style: TextStyle(fontSize: KSize.small + 0.5, color: KColors.faint)),
      );
    } else {
      final place = [
        countryName(i, locale.languageCode, hant: locale.scriptCode == 'Hant'),
        if (i.city.isNotEmpty) i.city,
      ].join(' · ');
      final score = i.fraudScore;
      final (riskText, riskColor, riskBg) = score == null
          ? ('', KColors.sub, KColors.field)
          : score <= 30
              ? (t.riskLow, KColors.ok, KColors.okSoft)
              : score <= 70
                  ? (t.riskMid, KColors.warn, KColors.warnSoft)
                  : (t.riskHigh, KColors.danger, KColors.dangerSoft);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (i.countryCode.isNotEmpty) ...[CountryFlag(i.countryCode, width: 20), const SizedBox(width: 8)],
          Flexible(
            child: SelectableText(ip.showFull ? i.ip : i.masked,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
        const SizedBox(height: 3),
        Text(place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: KSize.small + 0.5, color: KColors.sub)),
        const SizedBox(height: 9),
        Wrap(spacing: 5, runSpacing: 5, children: [
          if (i.residential != null)
            i.residential!
                ? KTag(t.residentialIp, color: KColors.ok, bg: KColors.okSoft)
                : KTag(t.datacenterIp),
          if (i.broadcast != null)
            i.broadcast!
                ? KTag(t.broadcastIp, color: KColors.warn, bg: KColors.warnSoft)
                : KTag(t.nativeIp, color: KColors.ok, bg: KColors.okSoft),
          if (score != null) KTag('${t.riskScore(score)} · $riskText', color: riskColor, bg: riskBg),
        ]),
        if (i.org.isNotEmpty || i.asn > 0) ...[
          const SizedBox(height: 7),
          Text([if (i.asn > 0) 'AS${i.asn}', if (i.org.isNotEmpty) i.org].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: KColors.faint)),
        ],
      ]);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 13),
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? KColors.accent.withValues(alpha: 0.35) : KColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 14, color: highlight ? KColors.accent : KColors.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: KSize.small,
                    color: highlight ? KColors.accent : KColors.sub,
                    fontWeight: FontWeight.w500)),
          ),
          if (placeholder == null)
            Tooltip(
              message: t.refresh,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: loading ? null : onRefresh,
                child: SizedBox(
                  width: 24,
                  height: 22,
                  child: Center(
                    child: loading && i != null
                        ? const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5))
                        : Icon(Icons.refresh_rounded, size: 14, color: KColors.faint),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 9),
        body,
      ]),
    );
  }
}

// ───────────────────────── 桌面：一屏三栏（左 节点+套餐，中 连接，右 网速+开关，底部 IP）─────────────────────────

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({required this.core, required this.session, required this.statusText, required this.onToggle});
  final CoreService core;
  final Session session;
  final String statusText;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final shell = context.findAncestorStateOfType<HomeShellState>();
    final warn = session.subscriptionUnavailable
        ? _WarnCard(
            text: t.subUnavailable,
            action: Platform.isIOS ? null : t.renewNow,
            onAction: () => shell?.goTo('store'),
          )
        : core.running && core.nodeUnreachable
            ? _WarnCard(text: t.warnNodeUnreachable, action: t.changeNode, onAction: () => shell?.goTo('nodes'))
            : null;
    return LayoutBuilder(builder: (context, c) {
      final side = (c.maxWidth * 0.27).clamp(200.0, 262.0);
      final content = Column(children: [
        if (warn != null) Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 0), child: warn),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: side,
                child: Column(children: [
                  _NodePanel(core: core, onTap: () => shell?.goTo('nodes')),
                  const SizedBox(height: 12),
                  _PlanPanel(session: session),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(child: _CenterPanel(core: core, statusText: statusText, onToggle: onToggle)),
              const SizedBox(width: 18),
              SizedBox(
                width: side,
                child: Column(children: [
                  _SpeedPanel(core: core),
                  const SizedBox(height: 12),
                  _SwitchPanel(core: core),
                ]),
              ),
            ]),
          ),
        ),
        const _IpStrip(),
      ]);
      // 窗口太矮时整体可滚动，不会被裁掉
      final minH = 404.0 + (warn != null ? 60 : 0);
      if (c.maxHeight >= minH) return content;
      return SingleChildScrollView(child: SizedBox(height: minH, child: content));
    });
  }
}

/// 小卡片：细边框、白底（黑色主题为深灰）
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: KColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KColors.border),
        ),
        child: child,
      );
}

class _NodePanel extends StatelessWidget {
  const _NodePanel({required this.core, required this.onTap});
  final CoreService core;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final node = core.currentNode;
    final auto = core.selected == 'auto';
    final name = node == null ? (auto ? t.autoSelect : core.selected) : node.plainName;
    final delay = node == null ? null : core.delays[node.tag];
    final meta = node == null
        ? (auto ? t.autoSelectDesc : '')
        : [if (auto) t.autoSelect, node.protocolLabel].join(' · ');
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.currentNode, style: TextStyle(fontSize: 12, color: KColors.sub)),
        const SizedBox(height: 10),
        Row(children: [
          if (node?.countryCode != null)
            CountryFlag(node!.countryCode!, width: 26)
          else
            Icon(Icons.public_rounded, size: 22, color: KColors.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: meta),
                  if (delay != null && delay > 0) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                        text: '$delay ms',
                        style: TextStyle(color: delay > 300 ? KColors.warn : KColors.ok, fontWeight: FontWeight.w600)),
                  ],
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: KColors.sub),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34), backgroundColor: KColors.field, side: BorderSide(color: KColors.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t.changeNode, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 17),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total = session.totalBytes;
    final used = session.usedBytes;
    final exp = session.expireAt;
    final remain = (total - used).clamp(0, total);
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(t.dataLeft, style: TextStyle(fontSize: 12, color: KColors.sub)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(exp > 0 ? t.expireOn(fmtDate(exp).split(' ').first) : t.longTerm,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: KColors.sub)),
          ),
        ]),
        const SizedBox(height: 8),
        if (total > 0) ...[
          Text.rich(
            TextSpan(children: [
              TextSpan(text: fmtBytes(remain), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              TextSpan(text: '  / ${fmtBytes(total)}', style: TextStyle(fontSize: 12.5, color: KColors.sub)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: KColors.field,
              color: ratio > 0.9 ? KColors.danger : KColors.accent,
            ),
          ),
        ] else
          Text('—', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: KColors.sub)),
        if (session.planName != null) ...[
          const SizedBox(height: 8),
          Text(session.planName!,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: KColors.sub)),
        ],
      ]),
    );
  }
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({required this.core, required this.statusText, required this.onToggle});
  final CoreService core;
  final String statusText;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final failed = core.status == CoreStatus.stopped && core.errorKind == 'nodeUnreachable';
    final dot = switch (core.status) {
      CoreStatus.running => KColors.ok,
      CoreStatus.stopped => failed ? KColors.danger : KColors.faint,
      _ => KColors.warn,
    };
    return LayoutBuilder(builder: (context, c) {
      final size = (c.maxHeight * 0.44).clamp(110.0, 160.0);
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        PowerButton(status: core.status, onTap: onToggle, size: size),
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(statusText, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text(
          core.running && core.connectedAt != null
              ? fmtDuration(DateTime.now().difference(core.connectedAt!))
              : t.tapToConnect,
          style: TextStyle(color: KColors.sub, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (failed) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: KColors.warnSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(t.errNodeUnreachable,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.45, color: KColors.ink)),
          ),
        ],
      ]);
    });
  }
}

class _SpeedPanel extends StatefulWidget {
  const _SpeedPanel({required this.core});
  final CoreService core;
  @override
  State<_SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends State<_SpeedPanel> {
  // 最近 40 秒的下载速度，画走势线
  final List<int> _hist = [];
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final core = widget.core;
    final now = DateTime.now();
    if (!core.running) {
      _hist.clear();
    } else if (now.difference(_last) >= const Duration(milliseconds: 900)) {
      _last = now;
      _hist.add(core.downSpeed);
      if (_hist.length > 40) _hist.removeAt(0);
    }
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t.download, style: TextStyle(fontSize: 12, color: KColors.sub)),
          const Spacer(),
          Text(fmtSpeed(core.downSpeed),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 30, child: CustomPaint(painter: _SparkPainter(_hist, KColors.accent, KColors.border))),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t.upload, style: TextStyle(fontSize: 12, color: KColors.sub)),
          const Spacer(),
          Text(fmtSpeed(core.upSpeed),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: KColors.border),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.south_rounded, size: 13, color: KColors.sub),
          Text(' ${fmtBytes(core.downTotal)}', style: TextStyle(fontSize: 12, color: KColors.sub)),
          const Spacer(),
          Icon(Icons.north_rounded, size: 13, color: KColors.sub),
          Text(' ${fmtBytes(core.upTotal)}', style: TextStyle(fontSize: 12, color: KColors.sub)),
        ]),
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(List<int> data, this.color, this.base) : data = List.of(data);
  final List<int> data;
  final Color color, base;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = base);
    if (data.length < 2) return;
    final maxV = data.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 62).toDouble();
    final step = size.width / 39;
    final x0 = size.width - step * (data.length - 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final p = Offset(x0 + step * i, size.height - 2 - (size.height - 4) * data[i] / maxV);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

class _SwitchPanel extends StatelessWidget {
  const _SwitchPanel({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mode = core.storage.routeMode;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.tunMode, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              Text(t.tunModeDesc,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: KColors.sub)),
            ]),
          ),
          Switch(value: core.storage.tunMode, onChanged: core.busy ? null : (v) => core.setTunMode(v)),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(9)),
            child: Row(children: [
              for (final m in RouteMode.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: mode == m,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: () => core.setRouteMode(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: mode == m ? KColors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          boxShadow: mode == m ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)] : null,
                        ),
                        child: Text(
                          switch (m) {
                            RouteMode.rule => t.modeRule,
                            RouteMode.global => t.modeGlobal,
                            RouteMode.direct => t.modeDirect,
                          },
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: mode == m ? FontWeight.w600 : FontWeight.w400,
                              color: mode == m ? KColors.ink : KColors.sub),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// 底部一行：节点出口 IP 和你的网络 IP 分开写清楚；点开看完整信息（家宽 / 风险分等）
class _IpStrip extends StatelessWidget {
  const _IpStrip();
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ip = context.watch<IpService>();
    final core = context.watch<CoreService>();
    final locale = Localizations.localeOf(context);
    InlineSpan part(String label, IpInfo? i, String? empty) {
      final where = i == null ? '' : countryName(i, locale.languageCode, hant: locale.scriptCode == 'Hant');
      return TextSpan(children: [
        TextSpan(text: '$label  '),
        TextSpan(
          text: i == null ? (empty ?? '—') : (ip.showFull ? i.ip : i.masked),
          style: TextStyle(color: KColors.ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (where.isNotEmpty) TextSpan(text: '  $where'),
      ]);
    }

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (c) => AlertDialog(
          content: const SizedBox(width: 560, child: SingleChildScrollView(child: _NetworkPanel())),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(t.ok))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text.rich(part(t.proxyExit, core.running ? ip.proxy : null, core.running ? null : t.showAfterConnect),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: KColors.sub)),
          ),
          const SizedBox(width: 26),
          Flexible(
            child: Text.rich(part(t.localNetwork, ip.local, null),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: KColors.sub)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.info_outline_rounded, size: 14, color: KColors.faint),
        ]),
      ),
    );
  }
}
