import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_config.dart';
import '../../core/core_service.dart';
import '../../services/ip_info.dart';
import '../../services/reporter.dart';
import '../../services/session.dart';
import '../../services/storage.dart';
import '../theme.dart';
import '../util.dart';

/// 用户中心 →"反馈问题"。后台没开通时改为打开工单页面。
Future<void> showFeedback(BuildContext context) async {
  if (!Reporter.instance.enabled) {
    final s = context.read<Session>();
    if (s.mode == AccountMode.xboard && AppConfig.websiteUrl.isNotEmpty) {
      await openUrl(context, '${AppConfig.websiteUrl}/#/ticket');
    } else {
      toast(context, context.t.feedbackFailed);
    }
    return;
  }
  await showDialog(context: context, builder: (_) => const _FeedbackDialog());
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _content = TextEditingController();
  late final _contact = TextEditingController(text: context.read<Session>().email ?? '');
  bool _logs = true;
  bool _sending = false;

  @override
  void dispose() {
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = context.t;
    if (_content.text.trim().isEmpty) {
      toast(context, t.feedbackEmpty);
      return;
    }
    setState(() => _sending = true);
    final core = context.read<CoreService>();
    final s = context.read<Session>();
    final ip = context.read<IpService>();
    final ok = await Reporter.instance.feedback(
      content: _content.text.trim(),
      contact: _contact.text.trim(),
      email: s.email,
      logs: _logs ? '${core.lastError ?? ''}\n${core.backend.recentLogs.join('\n')}'.trim() : null,
      extra: {
        'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'connected': core.running,
        'node': core.selected,
        'tun': core.storage.tunMode,
        'route': core.storage.routeMode.name,
        'nodes_count': s.nodes.length,
        'plan': s.planName,
        'local_ip': ip.local?.toJson(),
        'proxy_ip': ip.proxy?.toJson(),
      },
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok == true) {
      Navigator.pop(context);
      toast(context, t.feedbackSent);
    } else {
      toast(context, t.feedbackFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(t.feedback),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _content,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: InputDecoration(hintText: t.feedbackHint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _contact,
            decoration: InputDecoration(hintText: t.contactOptional),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _logs,
            onChanged: (v) => setState(() => _logs = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(t.attachLogs, style: const TextStyle(fontSize: KSize.body)),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _sending ? null : _send, child: _sending ? const BtnSpinner() : Text(t.send)),
      ],
    );
  }
}
