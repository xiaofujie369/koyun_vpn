import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../services/updater.dart';
import '../theme.dart';
import '../util.dart';

/// 手动检查更新（设置页"检查更新"）
Future<void> checkUpdateManually(BuildContext context) async {
  final t = context.t;
  final r = await Updater.instance.check();
  if (!context.mounted) return;
  if (r == null) {
    toast(context, t.checkUpdateFailed);
  } else if (!r) {
    toast(context, t.upToDate);
  } else {
    await showUpdateDialog(context);
  }
}

Future<void> showUpdateDialog(BuildContext context) => showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UpdateDialog(),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final u = Updater.instance;
  bool _working = false;

  Future<void> _go() async {
    setState(() => _working = true);
    final ok = await u.install();
    if (!mounted) return;
    if (!ok) {
      setState(() => _working = false);
      toast(context, context.t.updateFailed);
    } else if (u.progress == null) {
      Navigator.pop(context); // 浏览器下载的平台：关闭对话框
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final info = u.available;
    if (info == null) return const SizedBox();
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final p = u.progress;
        return AlertDialog(
          title: Text(t.newVersionTitle(info.version)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('v${AppConfig.appVersion}  →  v${info.version}',
                  style: const TextStyle(fontSize: KSize.small, color: KColors.faint)),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(stripHtml(info.notes), style: const TextStyle(fontSize: KSize.body, color: KColors.sub)),
                  ),
                ),
              ],
              if (p != null) ...[
                const SizedBox(height: 16),
                Text(p >= 1 ? t.installingUpdate : t.downloadingUpdate,
                    style: const TextStyle(fontSize: KSize.small, color: KColors.sub)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 6,
                    backgroundColor: KColors.field,
                    valueColor: const AlwaysStoppedAnimation(KColors.accent),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            if (!_working) TextButton(onPressed: () => Navigator.pop(context), child: Text(t.later)),
            FilledButton(
              onPressed: _working ? null : _go,
              child: _working ? const BtnSpinner() : Text(t.updateNow),
            ),
          ],
        );
      },
    );
  }
}
