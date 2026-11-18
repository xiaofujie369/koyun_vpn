// 安卓模拟器上的真实 VPN 测试（真正启动 KoyunVpnService + libbox 内核）：
//   flutter test integration_test/android_vpn_test.dart -d <模拟器>
// 需要宿主机 127.0.0.1:18611 上有一个 socks5 服务器（模拟器里是 10.0.2.2:18611），当作“正常节点”；
// 10.0.2.2:9 没有服务，当作“被封锁节点”。VPN 授权由测试脚本用 adb appops 提前放行。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:koyun_vpn/api/xboard_api.dart';
import 'package:koyun_vpn/core/core_backend.dart';
import 'package:koyun_vpn/core/core_service.dart';
import 'package:koyun_vpn/core/mobile_backend.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:koyun_vpn/services/session.dart';
import 'package:koyun_vpn/services/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const blocked = '[socks]🇯🇵被封锁节点';
  const good = '[socks]🇭🇰正常节点';
  late CoreService core;
  late Storage storage;

  setUpAll(() async {
    storage = Storage();
    await storage.init();
    final session = Session(storage, XboardApi(storage))..mode = AccountMode.xboard;
    session.nodes = [
      ProxyNode({'tag': blocked, 'type': 'socks', 'server': '10.0.2.2', 'server_port': 9}),
      ProxyNode({'tag': good, 'type': 'socks', 'server': '10.0.2.2', 'server_port': 18611}),
    ];
    core = CoreService(storage, session);
    await core.init();
  });

  tearDownAll(() async {
    await core.disconnect();
  });

  Future<void> waitStatus(CoreStatus s) async {
    for (var i = 0; i < 40 && core.status != s; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  testWidgets('安卓：先连被封锁节点失败，再连正常节点成功', (tester) async {
    await tester.runAsync(() async {
      await core.selectNode(blocked);
      await core.connect();
      expect(core.status, CoreStatus.stopped, reason: '${core.lastError}');
      expect(core.errorKind, 'nodeUnreachable');

      await core.selectNode(good);
      await core.connect();
      expect(core.status, CoreStatus.running, reason: 'lastError=${core.lastError} kind=${core.errorKind}');
    });
  });

  testWidgets('安卓：连接中切到被封锁节点会提示，断开后再连正常节点仍能连上（内核缓存）', (tester) async {
    await tester.runAsync(() async {
      if (!core.running) await core.connect();
      expect(core.status, CoreStatus.running);
      await core.selectNode(blocked);
      for (var i = 0; i < 60 && !core.nodeUnreachable; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      expect(core.nodeUnreachable, isTrue, reason: '切到不通的节点应马上提示');
      await core.disconnect();
      await waitStatus(CoreStatus.stopped);

      await core.selectNode(good);
      await core.connect();
      expect(core.status, CoreStatus.running, reason: 'lastError=${core.lastError} kind=${core.errorKind}');
    });
  });

  testWidgets('安卓：分应用代理写进 VPN 配置（不代理所选 / 只代理所选会带上 Koyun 自己）', (tester) async {
    await tester.runAsync(() async {
      // KoyunVpnService 保存的配置在 App 的 files 目录（getApplicationSupportDirectory 就是它）
      final cfgFile = File('${storage.dataDir.parent.path}/vpn-config.json');
      Map tun() {
        final c = jsonDecode(cfgFile.readAsStringSync()) as Map;
        return (c['inbounds'] as List).cast<Map>().firstWhere((i) => i['type'] == 'tun');
      }

      await core.setPerApp('bypass', ['com.android.chrome']);
      await waitStatus(CoreStatus.running);
      expect(core.status, CoreStatus.running, reason: '${core.lastError}');
      expect(tun()['exclude_package'], ['com.android.chrome']);

      await core.setPerApp('only', ['com.android.chrome']);
      await waitStatus(CoreStatus.running);
      expect(core.status, CoreStatus.running, reason: '${core.lastError}');
      expect(tun()['include_package'], containsAll(['com.android.chrome', 'com.koyun.vpn']));

      await core.setPerApp('off', const []);
      await waitStatus(CoreStatus.running);
      expect(tun().containsKey('include_package') || tun().containsKey('exclude_package'), isFalse);
    });
  });

  testWidgets('安卓：读取已安装应用和图标、后台运行权限接口可用', (tester) async {
    await tester.runAsync(() async {
      final b = core.backend as MobileBackend;
      final apps = await b.installedApps();
      expect(apps, isNotEmpty);
      expect(apps.any((a) => a['pkg'] == 'com.koyun.vpn'), isFalse, reason: '列表里不应该有 Koyun 自己');
      final icon = await b.appIcon(apps.first['pkg'] as String);
      expect(icon, isNotNull);
      expect(icon!.sublist(1, 4), utf8.encode('PNG'));
      await b.batteryExempt(); // 不抛异常即可
      expect(await b.brand(), isNotEmpty);
      // 原生通道不存在的方法要报 notImplemented，确认通道名没写错
      await expectLater(const MethodChannel('koyun/core').invokeMethod('no-such-method'),
          throwsA(anyOf(isA<MissingPluginException>(), isA<PlatformException>())));
    });
  });
}
