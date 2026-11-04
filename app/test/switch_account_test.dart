import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/api/xboard_api.dart';
import 'package:koyun_vpn/app_config.dart';
import 'package:koyun_vpn/core/config_builder.dart';
import 'package:koyun_vpn/services/net_route.dart';
import 'package:koyun_vpn/services/session.dart';
import 'package:koyun_vpn/services/storage.dart';
import 'package:koyun_vpn/services/sub_parser.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:shared_preferences/shared_preferences.dart';

String subJson(String tag) => jsonEncode({
      'outbounds': [
        {'type': 'anytls', 'tag': tag, 'server': '1.2.3.4', 'server_port': 443, 'password': 'x'}
      ]
    });

/// 模拟 Xboard 面板
class FakePanel {
  late HttpServer server;
  int subStatus = 200;
  int loginStatus = 200;
  String subTag = '账号节点';
  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await r.drain<void>();
      final p = r.uri.path;
      r.response.headers.contentType = ContentType.json;
      if (p.endsWith('/passport/auth/login')) {
        r.response.statusCode = loginStatus;
        r.response.write(jsonEncode(loginStatus == 200
            ? {'data': {'auth_data': 'token', 'token': 't'}}
            : {'message': '密码错误'}));
      } else if (p.endsWith('/user/getSubscribe')) {
        r.response.write(jsonEncode({'data': {'subscribe_url': '$base/s/abc', 'token': 'abc'}}));
      } else if (p == '/s/abc') {
        r.response.statusCode = subStatus;
        r.response.write(subJson(subTag));
      } else {
        r.response.write(jsonEncode({'data': <String, dynamic>{}}));
      }
      await r.response.close();
    });
  }
}

Future<Session> newSession(Directory dir) async {
  final storage = Storage();
  await storage.initForTest(dir);
  return Session(storage, XboardApi(storage));
}

void main() {
  late FakePanel panel;
  late Directory dir;
  late Session s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('kv');
    panel = FakePanel();
    await panel.start();
    AppConfig.bootApi = [panel.base];
    s = await newSession(dir);
  });

  tearDown(() async {
    NetRoute.proxy = null;
    AppConfig.bootApi = [];
    await panel.server.close(force: true);
  });

  group('本地模式切回账号', () {
    test('登录成功：换成账号节点，并且全程没有清空节点', () async {
      await s.importLocal(subJson('本地节点'));
      final seen = <int>[];
      s.addListener(() => seen.add(s.nodes.length));
      await s.login('a@b.com', 'pw');
      expect(s.mode, AccountMode.xboard);
      expect(s.nodes.single.tag, '账号节点');
      expect(seen.contains(0), isFalse, reason: '节点被清空会导致连接断开');
    });

    test('密码错误：还是本地模式，节点不变', () async {
      await s.importLocal(subJson('本地节点'));
      panel.loginStatus = 400;
      await expectLater(s.login('a@b.com', 'bad'), throwsA(isA<ApiError>()));
      expect(s.mode, AccountMode.local);
      expect(s.nodes.single.tag, '本地节点');
    });

    test('套餐到期：退回本地模式，保留本地节点并提示', () async {
      await s.importLocal(subJson('本地节点'));
      panel.subStatus = 403;
      final seen = <int>[];
      s.addListener(() => seen.add(s.nodes.length));
      await s.login('a@b.com', 'pw');
      expect(s.mode, AccountMode.local);
      expect(s.nodes.single.tag, '本地节点');
      expect(s.storage.authData, isNull);
      expect(s.lastResult, RefreshResult.unavailable);
      expect(seen.contains(0), isFalse);
    });

    test('普通账号套餐到期：仍然清空节点（原有行为不变）', () async {
      panel.subStatus = 403;
      await s.login('a@b.com', 'pw');
      expect(s.mode, AccountMode.xboard);
      expect(s.nodes, isEmpty);
    });
  });

  group('本地订阅地址', () {
    test('文件带订阅地址：可以联网刷新', () async {
      final file = jsonEncode({
        'koyun': {'format': 1, 'sub': 'https://sub.example.com/s/abc?flag=sing-box', 'total': 9},
        'outbounds': jsonDecode(subJson('文件节点'))['outbounds'],
      });
      expect(SubParser.parseSubUrl(file), 'https://sub.example.com/s/abc?flag=sing-box');
      await s.importLocal(file);
      expect(s.isFileImport, isFalse);
      expect(s.storage.localSubUrl, 'https://sub.example.com/s/abc?flag=sing-box');
      expect(s.subInfo?.total, 9);
    });

    test('文件里的地址不是 https：不使用', () {
      final file = jsonEncode({'koyun': {'sub': 'http://evil.example.com/'}, 'outbounds': []});
      expect(SubParser.parseSubUrl(file), isNull);
    });

    test('粘贴订阅链接：导入并能刷新', () async {
      expect(await s.importLocal('${panel.base}/s/abc'), RefreshResult.ok);
      expect(s.mode, AccountMode.local);
      expect(s.isFileImport, isFalse);
      panel.subTag = '更新后节点';
      expect(await s.refresh(), RefreshResult.ok);
      expect(s.nodes.single.tag, '更新后节点');
    });

    test('订阅链接打不开：提示网络失败，原有状态不变', () async {
      await s.importLocal(subJson('本地节点'));
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      expect(await s.importLocal('http://127.0.0.1:$port/s/abc'), RefreshResult.networkFail);
      expect(s.nodes.single.tag, '本地节点');
    });

    test('账号登录后、退出后、重启后备用订阅都还在，切回来带着地址', () async {
      await s.login('a@b.com', 'pw');
      await s.logout();
      expect(s.nodes, isEmpty);
      expect(s.backupNodeCount, 1);

      final again = await newSession(dir);
      await again.init();
      addTearDown(again.dispose);
      expect(again.backupNodeCount, 1);
      await again.useBackup();
      while (again.refreshing) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(again.mode, AccountMode.local);
      expect(again.nodes.single.tag, '账号节点');
      expect(again.storage.localSubUrl, contains('/s/abc'));
      expect(again.storage.localSubUrl, contains('flag=sing-box'));
    });

    test('删除备用订阅后不再出现', () async {
      await s.importLocal(subJson('本地节点'));
      await s.logout();
      await s.clearBackup();
      expect(s.backupNodeCount, 0);
      final again = await newSession(dir);
      await again.init();
      addTearDown(again.dispose);
      expect(again.backupNodeCount, 0);
    });
  });

  group('App 请求的线路', () {
    late HttpServer proxy;
    final seen = <String>[];

    setUp(() async {
      seen.clear();
      proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((r) async {
        seen.add('${r.headers.value('proxy-authorization')}|${r.uri}');
        await r.drain<void>();
        r.response.write('走代理');
        await r.response.close();
      });
    });
    tearDown(() => proxy.close(force: true));

    Dio dio() => Dio(BaseOptions(responseType: ResponseType.plain, connectTimeout: const Duration(seconds: 3)))
      ..httpClientAdapter = RoutedAdapter();

    test('未连接：直连', () async {
      final r = await dio().get<String>('${panel.base}/s/abc');
      expect(r.data, contains('账号节点'));
      expect(seen, isEmpty);
    });

    test('已连接：走节点，并带上入口密码', () async {
      NetRoute.proxy = 'app:secret@127.0.0.1:${proxy.port}';
      final r = await dio().get<String>('http://blocked.example.com/login');
      expect(r.data, '走代理');
      expect(seen.single, startsWith('Basic ${base64Encode(utf8.encode('app:secret'))}|'));
    });

    test('节点走不通：自动改直连，POST 内容不丢', () async {
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      NetRoute.proxy = 'app:secret@127.0.0.1:${dead.port}';
      await dead.close();
      final echo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => echo.close(force: true));
      echo.listen((r) async {
        r.response.write(await utf8.decoder.bind(r).join());
        await r.response.close();
      });
      final r = await dio().post<String>('http://127.0.0.1:${echo.port}/', data: '{"email":"a"}');
      expect(r.data, '{"email":"a"}');
    });

    test('线路切换后马上用新的入口', () async {
      final d = dio();
      NetRoute.proxy = 'app:one@127.0.0.1:${proxy.port}';
      await d.get<String>('http://a.example.com/');
      NetRoute.proxy = 'app:two@127.0.0.1:${proxy.port}';
      await d.get<String>('http://a.example.com/');
      expect(seen[1], startsWith('Basic ${base64Encode(utf8.encode('app:two'))}|'));
    });

    test('内核配置：App 账号跟随当前节点选择，测速专用内核没有这个账号', () {
      final nodes = [ProxyNode({'type': 'anytls', 'tag': 'A', 'server': '1.2.3.4', 'server_port': 443, 'password': 'x'})];
      Map<String, dynamic> build({bool tester = false}) => ConfigBuilder.build(CoreOptions(
            nodes: nodes, selected: 'A', ruleSetDir: '/tmp', workDir: '/tmp', clashPort: 1, clashSecret: 's',
            tun: false, mixedPort: 2, routeMode: RouteMode.rule, ipv6: false, testPort: 3, testSecret: 'pw',
            testerOnly: tester));
      bool hasUser(Map<String, dynamic> c) => jsonEncode(c).contains('"username":"app"');
      final cfg = build();
      expect(hasUser(cfg), isTrue);
      final rules = (cfg['route'] as Map)['rules'] as List;
      final i = rules.indexWhere((r) => (r['auth_user'] as List?)?.contains('app') == true);
      expect(rules[i]['outbound'], 'proxy');
      expect(i, lessThan(rules.indexWhere((r) => r['clash_mode'] == 'Direct')), reason: '要排在分流规则前面');
      expect(hasUser(build(tester: true)), isFalse);
    });
  });
}
