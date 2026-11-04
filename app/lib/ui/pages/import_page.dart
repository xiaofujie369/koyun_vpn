import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_config.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

/// 导入本地文件：把转换网站生成的文件拖进来、选择文件，或粘贴文件内容。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  static const _maxFileBytes = 5 * 1024 * 1024;

  final _ctl = TextEditingController();
  bool _loading = false;
  bool _dragging = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // 安卓的文件选择器按扩展名过滤时，部分 .json 文件会选不了，所以不过滤
    final types = Platform.isAndroid
        ? const <XTypeGroup>[]
        : const [XTypeGroup(label: 'JSON', extensions: ['json', 'txt'])];
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: types);
    } catch (_) {
      if (mounted) toast(context, context.t.importFileFail);
      return;
    }
    if (file != null) await _importFile(file);
  }

  Future<void> _importFile(XFile file) async {
    final String text;
    try {
      if (await file.length() > _maxFileBytes) throw const FormatException();
      text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    } catch (_) {
      if (mounted) toast(context, context.t.importFileFail);
      return;
    }
    await _import(text);
  }

  Future<void> _import(String text) async {
    final t = context.t;
    final input = text.trim();
    if (input.isEmpty) return toast(context, t.importHint);
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return toast(context, t.importLinkHint);
    }
    setState(() => _loading = true);
    final r = await context.read<Session>().importLocal(input);
    if (!mounted) return;
    setState(() => _loading = false);
    if (r == RefreshResult.ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      toast(context, t.importNoNodes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final highlight = _dragging ? KColors.lavender : KColors.border;
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
            if (AppConfig.bootConvert.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openUrl(context, AppConfig.bootConvert),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(t.importOpenConverter),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropTarget(
              enable: !_loading,
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (d) {
                setState(() => _dragging = false);
                if (d.files.isNotEmpty) _importFile(d.files.first);
              },
              child: Material(
                color: _dragging ? KColors.lavender.withValues(alpha: 0.1) : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: highlight, width: _dragging ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _loading ? null : _pickFile,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                    child: Column(children: [
                      const Icon(Icons.upload_file_rounded, size: 36, color: KColors.lavender),
                      const SizedBox(height: 10),
                      Text(desktop ? t.importDropTitle : t.importPickTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(t.importDropHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: KColors.sub, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
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
              onPressed: _loading ? null : () => _import(_ctl.text),
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
