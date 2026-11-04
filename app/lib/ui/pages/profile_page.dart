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
import 'import_page.dart';
import 'login_page.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final local = s.mode == AccountMode.local;
    final tg = s.guestConfig?['telegram_discuss_link'] as String?;

    return ListView(padding: EdgeInsets.only(top: wide ? 32 : 12, bottom: 32), children: [
      KPage(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.navProfile, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(t.profileSubtitle, style: const TextStyle(color: KColors.sub)),
          const SizedBox(height: 18),
          _AccountCard(session: s),
          const SizedBox(height: 14),
          if (s.totalBytes > 0 || !local) _TrafficCard(session: s),
          const SizedBox(height: 14),
          _Section(title: t.helpSupport, icon: Icons.headset_mic_outlined, children: [
            if (s.isFileImport)
              _Item(Icons.upload_file_rounded, t.importAgain,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ImportPage())))
            else
              _Item(Icons.refresh_rounded, t.refreshSubscription, onTap: () async {
                final r = await s.refresh();
                if (context.mounted) {
                  toast(context, r == RefreshResult.ok ? t.refreshOk(s.nodes.length) : t.refreshNetworkFail);
                }
              }),
            if (!s.isFileImport)
              _Item(Icons.upload_file_rounded, t.importSubscription,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ImportPage()))),
            if (!local) ...[
              _Item(Icons.receipt_long_outlined, t.orders,
                  onTap: () => openUrl(context, '${AppConfig.websiteUrl}/#/order')),
              _Item(Icons.support_agent_rounded, t.tickets,
                  onTap: () => openUrl(context, '${AppConfig.websiteUrl}/#/ticket')),
            ],
            _Item(Icons.language_rounded, t.website, onTap: () => openUrl(context, AppConfig.websiteUrl)),
            if (tg != null && tg.isNotEmpty)
              _Item(Icons.send_rounded, t.joinGroup, onTap: () => openUrl(context, tg)),
          ]),
          const SizedBox(height: 14),
          _Section(title: t.settings, icon: Icons.tune_rounded, children: [
            _Item(Icons.translate_rounded, t.language,
                trailing: Text(_langName(context, s.storage.localeOverride),
                    style: const TextStyle(color: KColors.sub)),
                onTap: () => _pickLanguage(context, s.storage)),
            _SwitchItem(Icons.flash_on_rounded, t.autoConnect, t.autoConnectDesc,
                value: s.storage.autoConnect, onChanged: (v) async {
              await s.storage.setAutoConnect(v);
              setState(() {});
            }),
            _SwitchItem(Icons.lan_outlined, 'IPv6', t.ipv6Desc, value: s.storage.ipv6, onChanged: (v) async {
              await s.storage.setIpv6(v);
              setState(() {});
              if (core.running) await core.connect();
            }),
            _Item(Icons.feedback_outlined, t.feedback, onTap: () => showFeedback(context)),
            _Item(Icons.article_outlined, t.logs, onTap: () => _showLogs(context, core)),
            ListenableBuilder(
              listenable: Updater.instance,
              builder: (context, _) {
                final u = Updater.instance;
                return _Item(
                  Icons.system_update_alt_rounded,
                  t.checkUpdate,
                  trailing: u.checking
                      ? const BtnSpinner(color: KColors.sub)
                      : Text(
                          u.available != null
                              ? '${t.newVersionBadge} v${u.available!.version}'
                              : 'v${AppConfig.appVersion} · sing-box ${AppConfig.singBoxVersion}',
                          style: TextStyle(
                              color: u.available != null ? KColors.accent : KColors.sub,
                              fontSize: 12,
                              fontWeight: u.available != null ? FontWeight.w600 : FontWeight.w400)),
                  onTap: u.checking
                      ? () {}
                      : () => u.available != null ? showUpdateDialog(context) : checkUpdateManually(context),
                );
              },
            ),
          ]),
          const SizedBox(height: 20),
          if (local) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage(keepConnection: true))),
              icon: const Icon(Icons.login_rounded),
              label: Text(t.switchToAccount),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: KColors.danger),
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: Text(t.logout),
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
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
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
        ]),
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
    return KCard(
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(local ? t.localMode : (session.email ?? '-'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (!local && session.email != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: KColors.faint,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: session.email!));
                    toast(context, t.copied);
                  },
                ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.verified_rounded, size: 16, color: KColors.ok),
              const SizedBox(width: 4),
              Flexible(
                child: Text(local ? t.localModeDesc : (session.planName ?? t.noPlan),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: KColors.ok, fontWeight: FontWeight.w500)),
              ),
            ]),
          ]),
        ),
        if (!local || exp > 0)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(t.expireDate, style: const TextStyle(color: KColors.sub, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(10)),
              child: Text(exp == 0 ? t.longTerm : fmtDate(exp),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
      ]),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final used = session.usedBytes;
    final total = session.totalBytes;
    final ratio = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final reset = session.resetDay;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBox(Icons.data_usage_rounded, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t.usedTraffic,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('${fmtBytes(used)} / ${fmtBytes(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: KColors.field,
            valueColor: AlwaysStoppedAnimation(ratio > 0.9 ? KColors.danger : KColors.lavender),
          ),
        ),
        if (reset != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 14, color: KColors.sub),
            const SizedBox(width: 4),
            Text(t.resetIn(reset), style: const TextStyle(color: KColors.sub, fontSize: 12)),
          ]),
        ],
        if (session.mode == AccountMode.xboard) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () {
              if (Platform.isIOS) {
                openUrl(context, AppConfig.websiteUrl);
              } else {
                context.findAncestorStateOfType<HomeShellState>()?.goTo('store');
              }
            },
            icon: const Icon(Icons.autorenew_rounded),
            label: Text(t.renewPlan),
          ),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => KCard(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              IconBox(icon, size: 36),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 6),
          ...children,
        ]),
      );
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, {required this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: KColors.sub),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: KColors.faint),
        onTap: onTap,
      );
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem(this.icon, this.label, this.desc, {required this.value, required this.onChanged});
  final IconData icon;
  final String label, desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: KColors.sub),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12, color: KColors.faint)),
        trailing: Switch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );
}
