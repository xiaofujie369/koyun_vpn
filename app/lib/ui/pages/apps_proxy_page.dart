import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/core_service.dart';
import '../../core/mobile_backend.dart';
import '../theme.dart';
import '../util.dart';

/// 安卓分应用代理（参考 FlClash）：
/// * 所选应用不走代理：比如银行、支付类 App，避免被风控
/// * 只有所选应用走代理：其它应用全部直连
class AppsProxyPage extends StatefulWidget {
  const AppsProxyPage({super.key});
  @override
  State<AppsProxyPage> createState() => _AppsProxyPageState();
}

/// 国内常用的银行 / 支付 / 购物 / 出行 App，一键加入“不走代理”
const kDomesticApps = <String>{
  'com.eg.android.AlipayGphone', 'com.tencent.mm', 'com.tencent.mobileqq', 'com.unionpay',
  'cmb.pb', 'com.icbc', 'com.chinamworld.main', 'com.android.bankabc', 'com.chinamworld.bocmbci',
  'com.bankcomm.Bankcomm', 'com.ecitic.bank.mobile', 'com.cib.cibmb', 'com.spdb.mobilebank.per',
  'com.taobao.taobao', 'com.tmall.wireless', 'com.jingdong.app.mall', 'com.xunmeng.pinduoduo',
  'com.sankuai.meituan', 'me.ele', 'com.sdu.didi.psnger', 'com.MobileTicket', 'com.autonavi.minimap',
  'com.baidu.BaiduMap', 'com.ss.android.ugc.aweme', 'com.smile.gifmaker', 'com.xingin.xhs',
  'tv.danmaku.bili', 'com.netease.cloudmusic', 'com.baidu.searchbox', 'com.sina.weibo',
};

class _AppsProxyPageState extends State<AppsProxyPage> {
  List<Map<String, dynamic>>? _apps;
  String? _error;
  late String _mode;
  late Set<String> _sel;
  bool _showSystem = false;
  String _q = '';
  bool _dirty = false;
  final _icons = <String, Future<Uint8List?>>{};

  late final CoreService _core = context.read<CoreService>();
  MobileBackend get _backend => _core.backend as MobileBackend;

  @override
  void initState() {
    super.initState();
    final st = _core.storage;
    _mode = st.perAppMode;
    _sel = st.perAppList.toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await _backend.installedApps();
      if (mounted) setState(() => _apps = apps);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    // 离开页面时也会调用（context 可能已失效），所以用提前保存的 _core
    _dirty = false;
    await _core.setPerApp(_mode, _sel.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final apps = (_apps ?? const <Map<String, dynamic>>[]).where((a) {
      if (!_showSystem && a['system'] == true && !_sel.contains(a['pkg'])) return false;
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return (a['name'] as String).toLowerCase().contains(q) || (a['pkg'] as String).toLowerCase().contains(q);
    }).toList()
      // 已选的排在前面
      ..sort((a, b) => (_sel.contains(b['pkg']) ? 1 : 0) - (_sel.contains(a['pkg']) ? 1 : 0));

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty) _save();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(t.perAppTitle)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'off', label: Text(t.perAppOff)),
                ButtonSegment(value: 'bypass', label: Text(t.perAppBypass)),
                ButtonSegment(value: 'only', label: Text(t.perAppOnly)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _dirty = true;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              switch (_mode) {
                'bypass' => t.perAppBypassDesc,
                'only' => t.perAppOnlyDesc,
                _ => t.perAppOffDesc,
              },
              style: TextStyle(fontSize: 12, color: KColors.sub, height: 1.4),
            ),
          ),
          if (_mode != 'off') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                decoration: InputDecoration(hintText: t.searchApps, prefixIcon: const Icon(Icons.search_rounded, size: 18)),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (_mode == 'bypass')
                  TextButton.icon(
                    icon: const Icon(Icons.account_balance_outlined, size: 16),
                    label: Text(t.perAppDomestic),
                    onPressed: _apps == null
                        ? null
                        : () => setState(() {
                              _sel.addAll(_apps!.map((a) => a['pkg'] as String).where(kDomesticApps.contains));
                              _dirty = true;
                            }),
                  ),
                TextButton(
                  onPressed: _sel.isEmpty ? null : () => setState(() {
                    _sel.clear();
                    _dirty = true;
                  }),
                  child: Text(t.perAppClear),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: _showSystem, onChanged: (v) => setState(() => _showSystem = v ?? false)),
                  Text(t.perAppShowSystem, style: const TextStyle(fontSize: 12.5)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(t.perAppSelected(_sel.length), style: TextStyle(fontSize: 12.5, color: KColors.sub)),
                ),
              ]),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: KColors.danger)))
                  : _apps == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: apps.length,
                          itemBuilder: (context, i) {
                            final a = apps[i];
                            final pkg = a['pkg'] as String;
                            return CheckboxListTile(
                              value: _sel.contains(pkg),
                              onChanged: (v) => setState(() {
                                v == true ? _sel.add(pkg) : _sel.remove(pkg);
                                _dirty = true;
                              }),
                              secondary: _AppIcon(_icons.putIfAbsent(pkg, () => _backend.appIcon(pkg))),
                              title: Text(a['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
                              controlAffinity: ListTileControlAffinity.trailing,
                            );
                          },
                        ),
            ),
          ] else
            const Spacer(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: () async {
                    await _save();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(t.perAppSave),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon(this.data);
  final Future<Uint8List?> data;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: FutureBuilder<Uint8List?>(
          future: data,
          builder: (context, s) => s.data == null
              ? Icon(Icons.android_rounded, color: KColors.faint)
              : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(s.data!, gaplessPlayback: true)),
        ),
      );
}
