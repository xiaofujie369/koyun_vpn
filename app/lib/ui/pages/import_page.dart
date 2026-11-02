import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

/// 本地导入订阅模式：面板接口不通 / 登录失败时使用。
/// 支持：订阅链接、节点分享链接（可多行）、sing-box JSON。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _ctl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tryClipboard();
  }

  /// 剪贴板里如果是订阅链接，自动填入
  Future<void> _tryClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final text = d?.text?.trim() ?? '';
    if (text.startsWith('http') || text.contains('://')) {
      setState(() => _ctl.text = text);
    }
  }

  Future<void> _import() async {
    final t = context.t;
    if (_ctl.text.trim().isEmpty) return toast(context, t.importHint);
    setState(() => _loading = true);
    final r = await context.read<Session>().importLocal(_ctl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (r) {
      case RefreshResult.ok:
        Navigator.of(context).popUntil((r) => r.isFirst);
      case RefreshResult.unavailable:
        toast(context, t.subUnavailable);
      case RefreshResult.empty:
        toast(context, t.importNoNodes);
      default:
        toast(context, t.importNetworkFail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.importSubscription)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        child: KPage(
          maxWidth: 560,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KCard(
              child: Row(children: [
                const IconBox(Icons.info_outline_rounded, color: KColors.lavender),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(t.importDesc,
                        style: const TextStyle(color: KColors.sub, height: 1.5))),
              ]),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _ctl,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: t.importHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: KColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: KColors.lavender)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) setState(() => _ctl.text = d!.text!);
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(t.pasteFromClipboard),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _import,
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(t.importButton),
            ),
          ]),
        ),
      ),
    );
  }
}
