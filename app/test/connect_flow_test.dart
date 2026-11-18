// 用真实 sing-box 跑 App 的连接流程（CoreService），复现 / 防止回归：
// “先连一个被封锁的节点，之后再连正常节点也一直显示连接失败”。
//   SINGBOX=/path/sing-box flutter test test/connect_flow_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/api/xboard_api.dart';
import 'package:koyun_vpn/core/core_backend.dart';
import 'package:koyun_vpn/core/core_service.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:koyun_vpn/services/session.dart';
import 'package:koyun_vpn/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final bin = Platform.environment['SINGBOX'];
  final skip = bin == null || Platform.environment['KOYUN_SINGBOX'] != bin;
  const blocked = '[socks]🇯🇵被封锁节点';
  const good = '[socks]🇭🇰正常节点';
  late Directory dir;
  late Process server;
  late CoreService core;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('koyun-flow');
    // “正常节点”：本机另起一个 sing-box 当 socks5 服务器；“被封锁节点”：连不上的端口
    final sc = File('${dir.path}/server.json')
      ..writeAsStringSync(jsonEncode({
        'log': {'level': 'error'},
        'inbounds': [
          {'type': 'socks', 'listen': '127.0.0.1', 'listen_port': 18611}
        ],
        'outbounds': [
          {'type': 'direct'}
        ],
      }));
    server = await Process.start(bin!, ['run', '-c', sc.path]);
    server.stdout.drain<void>();
    server.stderr.drain<void>();

    SharedPreferences.setMockInitialValues({'mode': 'xboard'});
    final storage = Storage();
    await storage.initForTest(Directory('${dir.path}/data')..createSync());
    final session = Session(storage, XboardApi(storage))..mode = AccountMode.xboard;
    session.nodes = [
      ProxyNode({'tag': blocked, 'type': 'socks', 'server': '127.0.0.1', 'server_port': 9}),
      ProxyNode({'tag': good, 'type': 'socks', 'server': '127.0.0.1', 'server_port': 18611}),
    ];
    // 内核需要的分流规则文件（正式 App 启动时从安装包释放）
    final rules = Directory('${storage.dataDir.path}/rules')..createSync(recursive: true);
    for (final f in Directory('assets/rules').listSync().whereType<File>()) {
      f.copySync('${rules.path}/${f.uri.pathSegments.last}');
    }
    core = CoreService(storage, session);
  });

  tearDown(() async {
    await core.disconnect();
    server.kill(ProcessSignal.sigkill);
    await server.exitCode;
    dir.deleteSync(recursive: true);
  });

  Future<void> pick(String tag) => core.selectNode(tag);

  test('先连被封锁的节点（失败），再选正常节点：要能连上', skip: skip, () async {
    await pick(blocked);
    await core.connect();
    expect(core.status, CoreStatus.stopped);
    expect(core.errorKind, 'nodeUnreachable');

    await pick(good);
    await core.connect();
    expect(core.status, CoreStatus.running, reason: 'lastError=${core.lastError} kind=${core.errorKind}');
  });

  test('连着正常节点时切到被封锁节点，断开后再选正常节点：要能连上（内核缓存记着被封锁节点）', skip: skip, () async {
    await pick(good);
    await core.connect();
    expect(core.status, CoreStatus.running, reason: '${core.lastError}');
    await pick(blocked); // 连接中切换：内核把选择存进缓存
    await core.disconnect();

    await pick(good);
    await core.connect();
    expect(core.status, CoreStatus.running, reason: 'lastError=${core.lastError} kind=${core.errorKind}');
  });

  test('被封锁节点连续失败多次后，正常节点仍然能连上', skip: skip, () async {
    for (var i = 0; i < 3; i++) {
      await pick(blocked);
      await core.connect();
      expect(core.status, CoreStatus.stopped);
    }
    await pick(good);
    await core.connect();
    expect(core.status, CoreStatus.running, reason: 'lastError=${core.lastError} kind=${core.errorKind}');
  });

  test('连接中切到被封锁节点：马上提示“节点连不上”；切回正常节点提示消失', skip: skip, () async {
    await pick(good);
    await core.connect();
    expect(core.status, CoreStatus.running);
    await pick(blocked);
    for (var i = 0; i < 40 && !core.nodeUnreachable; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(core.nodeUnreachable, isTrue);
    await pick(good);
    for (var i = 0; i < 40 && core.nodeUnreachable; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(core.nodeUnreachable, isFalse);
  });
}
