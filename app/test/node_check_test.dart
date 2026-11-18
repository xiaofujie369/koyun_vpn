// 用真实 sing-box 内核验证“连接后检测节点”：被墙的节点必须检测失败，能用的节点检测成功，
// 自动选择要避开被墙的节点。需要内核程序和外网：
//   SINGBOX=/path/to/sing-box flutter test test/node_check_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/app_config.dart';
import 'package:koyun_vpn/core/clash_api.dart';
import 'package:koyun_vpn/core/config_builder.dart';
import 'package:koyun_vpn/models/node.dart';

void main() {
  final bin = Platform.environment['SINGBOX'];
  final skip = bin == null || !File(bin).existsSync();
  final url = 'http://${AppConfig.delayProbeHost}/generate_204';

  late Directory dir;
  final procs = <Process>[];

  Future<Process> run(Map cfg, String name) async {
    final f = File('${dir.path}/$name.json')..writeAsStringSync(jsonEncode(cfg));
    final p = await Process.start(bin!, ['run', '-c', f.path, '-D', dir.path], environment: ConfigBuilder.coreEnv);
    p.stdout.drain<void>();
    p.stderr.drain<void>();
    procs.add(p);
    return p;
  }

  Future<ClashApi> startCore(String selected) async {
    // “能用的节点”：本机再起一个 sing-box 当 socks5 服务器；“被墙的节点”：连不上的地址
    final nodes = [
      ProxyNode({'type': 'socks', 'tag': '[socks]被墙节点', 'server': '127.0.0.1', 'server_port': 9}),
      ProxyNode({'type': 'socks', 'tag': '[socks]正常节点', 'server': '127.0.0.1', 'server_port': 18601}),
    ];
    final cfg = ConfigBuilder.build(CoreOptions(
      nodes: nodes,
      selected: selected,
      ruleSetDir: '${Directory.current.absolute.path}/assets/rules',
      workDir: dir.path,
      clashPort: 18690,
      clashSecret: 's',
      mixedPort: 18691,
    ));
    await run(cfg, 'core-$selected');
    final api = ClashApi(18690, 's');
    var up = false;
    for (var i = 0; i < 40 && !(up = await api.ping()); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(up, isTrue, reason: '内核没有启动');
    return api;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('koyun-check');
    await run({
      'log': {'level': 'error'},
      'inbounds': [
        {'type': 'socks', 'listen': '127.0.0.1', 'listen_port': 18601}
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ],
    }, 'server');
  });

  tearDown(() async {
    for (final p in procs) {
      p.kill(ProcessSignal.sigkill);
      await p.exitCode;
    }
    procs.clear();
    dir.deleteSync(recursive: true);
  });

  test('选中被墙的节点：检测失败（App 会显示连接失败）', skip: skip, () async {
    final api = await startCore('[socks]被墙节点');
    expect(await api.delay('proxy', url, timeoutMs: 4000), -1);
  });

  test('选中能用的节点：检测成功', skip: skip, () async {
    final api = await startCore('[socks]正常节点');
    expect(await api.delay('proxy', url, timeoutMs: 6000), greaterThan(0));
  });

  test('自动选择：测一遍后避开被墙节点，检测成功', skip: skip, () async {
    final api = await startCore('auto');
    final ok = await api.groupDelay('auto', url);
    expect(ok.keys, ['[socks]正常节点']);
    expect(await api.now('auto'), '[socks]正常节点');
    expect(await api.delay('proxy', url, timeoutMs: 6000), greaterThan(0));
  });
}
