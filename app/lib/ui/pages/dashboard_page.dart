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

/// 首页（仿 Codex 桌面端首页）：
/// 内容垂直居中——状态标题 + 一个"输入框式"的操作卡片（当前节点 / 出站规则 / TUN / 连接按钮），
/// 卡片下方一行淡色的流量信息。
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final core = context.watch<CoreService>();
    final s = context.watch<Session>();
    final mobile = Platform.isAndroid || Platform.isIOS;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final statusText = switch (core.status) {
      CoreStatus.running => t.connected,
      CoreStatus.starting => t.connecting,
      CoreStatus.stopping => t.disconnecting,
      CoreStatus.stopped => t.notConnected,
    };
    final sub = core.running && core.connectedAt != null
        ? fmtDuration(DateTime.now().difference(core.connectedAt!))
        : t.statusIdleHint;

    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.notices.isNotEmpty) ...[_NoticeBar(notice: s.notices.first), const SizedBox(height: 10)],
      if (s.subscriptionUnavailable) ...[
        _WarnBar(
          text: t.subUnavailable,
          action: Platform.isIOS ? null : t.renewNow,
          onAction: () => context.findAncestorStateOfType<HomeShellState>()?.goTo('store'),
        ),
        const SizedBox(height: 10),
      ],
      SizedBox(height: narrow ? 12 : 28),
      if (narrow) ...[
        Center(child: PowerButton(status: core.status, onTap: () => connectToggle(context), size: 120)),
        const SizedBox(height: 18),
      ],
      Center(
        child: Text(statusText,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: KColors.sub,
              fontSize: KSize.body,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: core.running ? 1 : 0,
            )),
      ),
      const SizedBox(height: 26),
      _Composer(core: core, session: s, showButton: !narrow, showTun: !mobile),
      const SizedBox(height: 12),
      _InfoLine(core: core, session: s),
    ]);

    return RefreshIndicator(
      color: KColors.accent,
      onRefresh: () => s.refresh(),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (c.maxHeight - 40).clamp(0, double.infinity)),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// "输入框式"操作卡片：上半部分是当前节点，下半部分是一排小控件 + 右下角圆形连接按钮
class _Composer extends StatelessWidget {
  const _Composer({required this.core, required this.session, required this.showButton, required this.showTun});
  final CoreService core;
  final Session session;
  final bool showButton, showTun;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final node = core.currentNode;
    final auto = core.selected == 'auto';
    final title = auto
        ? (node == null ? t.autoSelect : '${t.autoSelect} · ${node.plainName}')
        : (node == null ? core.selected : node.plainName);
    final flag = auto ? '⚡' : (node?.flag ?? '🌐');
    final subtitle = auto ? t.autoSelectDesc : (node?.protocolLabel ?? '');

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          onTap: () => context.findAncestorStateOfType<HomeShellState>()?.goTo('nodes'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 14, 10),
            child: Row(children: [
              Text(flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: KSize.small, color: KColors.faint)),
                ]),
              ),
              Text(t.switchNode, style: const TextStyle(fontSize: KSize.small, color: KColors.faint)),
              const Icon(Icons.chevron_right_rounded, size: 18, color: KColors.faint),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                _ModeChip(core: core),
                if (showTun)
                  _ToggleChip(
                    icon: Icons.lan_outlined,
                    label: t.tunMode,
                    tooltip: t.tunModeDesc,
                    value: core.storage.tunMode,
                    onChanged: core.busy ? null : (v) => core.setTunMode(v),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            if (showButton) _SendButton(core: core),
          ]),
        ),
      ]),
    );
  }
}

/// 出站规则下拉（智能分流 / 全局 / 直连）
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    String label(RouteMode m) => switch (m) {
          RouteMode.rule => t.modeRule,
          RouteMode.global => t.modeGlobal,
          RouteMode.direct => t.modeDirect,
        };
    final mode = core.storage.routeMode;
    return PopupMenuButton<RouteMode>(
      tooltip: t.routeModeDesc,
      position: PopupMenuPosition.under,
      onSelected: core.setRouteMode,
      itemBuilder: (_) => [
        for (final m in RouteMode.values)
          PopupMenuItem(
            value: m,
            height: 36,
            child: Row(children: [
              SizedBox(
                width: 22,
                child: m == mode ? const Icon(Icons.check_rounded, size: 15, color: KColors.ink) : null,
              ),
              Text(label(m), style: const TextStyle(fontSize: KSize.body)),
            ]),
          ),
      ],
      child: _ChipBody(icon: Icons.alt_route_rounded, label: label(mode), trailing: Icons.expand_more_rounded),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.icon, required this.label, required this.tooltip, required this.value, required this.onChanged});
  final IconData icon;
  final String label, tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: _ChipBody(icon: value ? Icons.check_rounded : icon, label: label, active: value),
        ),
      );
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.icon, required this.label, this.trailing, this.active = false});
  final IconData icon;
  final String label;
  final IconData? trailing;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? KColors.accentSoft : KColors.field,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? KColors.accent.withValues(alpha: 0.3) : KColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? KColors.accent : KColors.sub),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: KSize.small + 0.5, color: active ? KColors.accent : KColors.ink)),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 15, color: KColors.faint),
          ],
        ]),
      );
}

/// 右下角圆形连接按钮（对应 Codex 输入框的"发送"按钮）
class _SendButton extends StatelessWidget {
  const _SendButton({required this.core});
  final CoreService core;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final on = core.running;
    final busy = core.busy;
    return Tooltip(
      message: on ? t.disconnectNow : t.connectNow,
      child: Material(
        color: on ? KColors.accent : KColors.ink,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : () => connectToggle(context),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                    : const Icon(Icons.power_settings_new_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 7),
                Text(on ? t.disconnectNow : t.connectNow,
                    style: const TextStyle(color: Colors.white, fontSize: KSize.body, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片下方的淡色信息行：速度 / 剩余流量 / 到期
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.core, required this.session});
  final CoreService core;
  final Session session;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final exp = session.expireAt;
    final days = exp == 0
        ? null
        : (DateTime.fromMillisecondsSinceEpoch(exp * 1000).difference(DateTime.now()).inHours / 24).ceil();
    Widget item(IconData i, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: KColors.faint),
          const SizedBox(width: 4),
          Text(v,
              style: const TextStyle(
                  fontSize: KSize.small, color: KColors.sub, fontFeatures: [FontFeature.tabularFigures()])),
        ]);
    return Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 6, children: [
      item(Icons.south_rounded, fmtSpeed(core.downSpeed)),
      item(Icons.north_rounded, fmtSpeed(core.upSpeed)),
      if (session.totalBytes > 0)
        item(Icons.data_usage_rounded, t.trafficLeft(fmtBytes(session.totalBytes - session.usedBytes))),
      if (session.mode == AccountMode.xboard || exp > 0)
        item(Icons.schedule_rounded, days == null ? t.longTerm : t.daysLeft(days < 0 ? 0 : days)),
    ]);
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice});
  final Map<String, dynamic> notice;
  @override
  Widget build(BuildContext context) {
    final title = (notice['title'] ?? '').toString();
    final content = stripHtml((notice['content'] ?? '').toString());
    return Material(
      color: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: KColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: SelectableText(content)),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(context.t.ok))],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            const Icon(Icons.campaign_outlined, size: 16, color: KColors.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: KSize.body)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: KColors.faint),
          ]),
        ),
      ),
    );
  }
}

class _WarnBar extends StatelessWidget {
  const _WarnBar({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: KColors.warnSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KColors.warn.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: KColors.warn),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(fontSize: KSize.small + 0.5))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(color: KColors.warn, fontWeight: FontWeight.w600)),
            ),
        ]),
      );
}
