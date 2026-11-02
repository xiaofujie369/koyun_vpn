import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../app_config.dart';
import '../../core/core_service.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../../services/updater.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/update_dialog.dart';
import 'home_shell.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    if (s.guestConfig == null) s.loadGuestConfig();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = context.watch<Session>();
    final core = context.watch<CoreService>();
    final local = s.mode == AccountMode.local;
    final tg = s.guestConfig?['telegram_discuss_link'] as String?;
    const gap = SizedBox(height: 22);

    return ListView(padding: const EdgeInsets.only(top: 22, bottom: 32), children: [
      KPage(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(title: t.navProfile, subtitle: t.profileSubtitle),
          _AccountCard(session: s),
          gap,
          KGroup(title: t.account, children: [
            KRow(
              icon: Icons.refresh_rounded,
              title: t.refreshSubscription,
              onTap: () async {
                final r = await s.refresh();
                if (context.mounted) {
                  toast(context, r == RefreshResult.ok ? t.refreshOk(s.nodes.length) : t.refreshNetworkFail);
                }
              },
            ),
            if (!local) ...[
              KRow(
                  icon: Icons.receipt_long_outlined,
                  title: t.orders,
                  onTap: () => openUrl(context, '${AppConfig.websiteUrl}/#/order')),
              KRow(
                  icon: Icons.support_agent_rounded,
                  title: t.tickets,
                  onTap: () => openUrl(context, '${AppConfig.websiteUrl}/#/ticket')),
            ],
            KRow(icon: Icons.language_rounded, title: t.website, onTap: () => openUrl(context, AppConfig.websiteUrl)),
            if (tg != null && tg.isNotEmpty)
              KRow(icon: Icons.send_rounded, title: t.joinGroup, onTap: () => openUrl(context, tg)),
          ]),
          gap,
          KGroup(title: t.general, children: [
            KRow(
              icon: Icons.translate_rounded,
              title: t.language,
              trailing: _Trailing(_langName(context, s.storage.localeOverride)),
              onTap: () => _pickLanguage(context, s.storage),
            ),
            KRow(
              icon: Icons.flash_on_rounded,
              title: t.autoConnect,
              subtitle: t.autoConnectDesc,
              trailing: Switch(
                value: s.storage.autoConnect,
                onChanged: (v) async {
                  await s.storage.setAutoConnect(v);
                  setState(() {});
                },
              ),
            ),
            KRow(
              icon: Icons.lan_outlined,
              title: 'IPv6',
              subtitle: t.ipv6Desc,
              trailing: Switch(
                value: s.storage.ipv6,
                onChanged: (v) async {
                  await s.storage.setIpv6(v);
                  setState(() {});
                  if (core.running) await core.connect();
                },
              ),
            ),
          ]),
          gap,
          KGroup(title: t.about, children: [
            ListenableBuilder(
              listenable: Updater.instance,
              builder: (context, _) {
                final u = Updater.instance;
                return KRow(
                  icon: Icons.system_update_alt_rounded,
                  title: t.checkUpdate,
                  subtitle: 'v${AppConfig.appVersion} · sing-box ${AppConfig.singBoxVersion}',
                  trailing: u.checking
                      ? const BtnSpinner(color: KColors.sub)
                      : u.available != null
                          ? KTag('${t.newVersionBadge} v${u.available!.version}',
                              color: KColors.accent, bg: KColors.accentSoft)
                          : null,
                  onTap: u.checking
                      ? null
                      : () => u.available != null ? showUpdateDialog(context) : checkUpdateManually(context),
                );
              },
            ),
            KRow(icon: Icons.feedback_outlined, title: t.feedback, onTap: () => showFeedback(context)),
            KRow(icon: Icons.article_outlined, title: t.logs, onTap: () => _showLogs(context, core)),
          ]),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: KColors.danger),
              onPressed: () => _logout(context),
              icon: Icon(local ? Icons.login_rounded : Icons.logout_rounded, size: 16),
              label: Text(local ? t.switchToAccount : t.logout),
            ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _logout(BuildContext context) async {
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: KColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.ok),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final core = context.read<CoreService>();
    if (core.running) await core.disconnect();
    if (context.mounted) await context.read<Session>().logout();
  }

  static String _langName(BuildContext context, String code) =>
      code.isEmpty ? context.t.followSystem : (kLanguages[code] ?? code);

  Future<void> _pickLanguage(BuildContext context, Storage storage) async {
    final t = context.t;
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(t.language),
        children: [
          ListTile(
            title: Text(t.followSystem),
            trailing: storage.localeOverride.isEmpty ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(c, ''),
          ),
          for (final e in kLanguages.entries)
            ListTile(
              title: Text(e.value),
              trailing: storage.localeOverride == e.key ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(c, e.key),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await storage.setLocaleOverride(picked);
    localeNotifier.value = localeFromCode(picked);
  }

  void _showLogs(BuildContext context, CoreService core) {
    final logs = core.backend.recentLogs.join('\n');
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.t.logs),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(logs.isEmpty ? '-' : logs,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(
                text: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
                    '${core.lastError ?? ''}\n$logs')),
            child: Text(context.t.copyLink),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(context.t.ok)),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final local = session.mode == AccountMode.local;
    final exp = session.expireAt;
    final name = local ? t.localMode : (session.email ?? '-');
    final used = session.usedBytes;
    final total = session.totalBytes;
    final ratio = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final reset = session.resetDay;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: KColors.accent, shape: BoxShape.circle),
            child: Text(name.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                if (!local && session.email != null)
                  IconButton(
                    iconSize: 14,
                    tooltip: t.copyLink,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: session.email!));
                      toast(context, t.copied);
                    },
                  ),
              ]),
              Text(local ? t.localModeDesc : (session.planName ?? t.noPlan),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: KColors.sub, fontSize: KSize.small)),
            ]),
          ),
          if (!local || exp > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t.expireDate, style: const TextStyle(color: KColors.faint, fontSize: 11)),
              const SizedBox(height: 2),
              Text(exp == 0 ? t.longTerm : fmtDate(exp),
                  style: const TextStyle(fontSize: KSize.body, fontWeight: FontWeight.w600)),
            ]),
        ]),
        if (total > 0 || !local) ...[
          const SizedBox(height: 16),
          Row(children: [
            Text(t.usedTraffic, style: const TextStyle(fontSize: KSize.small, color: KColors.sub)),
            const Spacer(),
            Text('${fmtBytes(used)} / ${fmtBytes(total)}',
                style: const TextStyle(fontSize: KSize.small, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: KColors.field,
              valueColor: AlwaysStoppedAnimation(ratio > 0.9 ? KColors.danger : KColors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            if (reset != null)
              Expanded(
                child: Text(t.resetIn(reset), style: const TextStyle(color: KColors.faint, fontSize: 11.5)),
              )
            else
              const Spacer(),
            if (session.mode == AccountMode.xboard)
              FilledButton(
                onPressed: () {
                  if (Platform.isIOS) {
                    openUrl(context, AppConfig.websiteUrl);
                  } else {
                    context.findAncestorStateOfType<HomeShellState>()?.goTo('store');
                  }
                },
                child: Text(t.renewPlan),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: const TextStyle(color: KColors.sub, fontSize: KSize.small + 0.5)),
        const Icon(Icons.chevron_right_rounded, size: 18, color: KColors.faint),
      ]);
}
