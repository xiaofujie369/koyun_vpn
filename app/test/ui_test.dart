import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/api/xboard_api.dart';
import 'package:koyun_vpn/core/core_service.dart';
import 'package:koyun_vpn/l10n/gen/app_localizations.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:koyun_vpn/services/ip_info.dart';
import 'package:koyun_vpn/services/session.dart';
import 'package:koyun_vpn/services/storage.dart';
import 'package:koyun_vpn/app_config.dart';
import 'package:koyun_vpn/ui/pages/home_shell.dart';
import 'package:koyun_vpn/ui/pages/import_page.dart';
import 'package:koyun_vpn/services/updater.dart';
import 'package:koyun_vpn/ui/theme.dart';
import 'package:koyun_vpn/ui/widgets/update_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面冒烟测试：模拟已登录用户，在不同窗口尺寸下打开每个页面，
/// 任何布局错误（会导致正式版页面空白）都会让测试失败。
Future<(Session, CoreService)> _services() async {
  SharedPreferences.setMockInitialValues({'mode': 'xboard'});
  final storage = Storage();
  await storage.initForTest(Directory.systemTemp.createTempSync('kv'));
  final session = Session(storage, XboardApi(storage));
  session.mode = AccountMode.xboard;
  session.subscribe = {
    'email': 'demo@example.com',
    'plan': {'name': '标准套餐'},
    'u': 1 << 30,
    'd': 3 << 30,
    'transfer_enable': 100 << 30,
    'expired_at': DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
    'reset_day': 12,
  };
  session.notices = [
    {'title': '公告：新节点上线', 'content': '<p>香港节点已扩容</p>'}
  ];
  session.nodes = [
    for (final n in [
      '🇭🇰香港D01-1X', '🇭🇰香港D02-1X', '🇭🇰香港D03-1X移动', '🇭🇰香港IEPL-2X', '🇭🇰香港HKT-1X', '🇭🇰香港家宽-3X',
      '🇯🇵日本D13-1X', '🇯🇵日本东京-1X', '🇯🇵日本大阪ISP-2X', '🇯🇵日本D14-1X',
      '🇹🇼台湾A04-1X直连', '🇹🇼台湾Hinet-1X',
      '🇺🇸美国洛杉矶-2X', '🇺🇸美国圣何塞-1X', '🇺🇸美国纽约家宽超长名字测试节点-3X',
      '🇸🇬新加坡B02-1X', '🇸🇬新加坡B03-1X', '🇰🇷韩国首尔-1X', '🇬🇧英国伦敦-2X', '无国旗测试节点'
    ])
      ProxyNode({'tag': n, 'type': 'anytls', 'server': '1.2.3.4', 'server_port': 443}),
  ];
  final core = CoreService(storage, session);
  core.delays[session.nodes[0].tag] = 86;
  core.delays[session.nodes[1].tag] = -1; // 超时
  core.delays[session.nodes[2].tag] = 420;
  core.testingTags.add(session.nodes[3].tag); // 测速中
  return (session, core);
}

IpService _ip(CoreService c) => IpService(c)
  ..local = IpInfo.fromJson({
    'ip': '203.0.113.45', 'asn': 4134, 'asOrganization': 'Chinanet', 'country': 'China', 'countryCode': 'CN',
    'city': 'Shanghai', 'fraudScore': 12, 'isResidential': true, 'isBroadcast': false,
  })
  ..proxy = IpInfo.fromJson({
    'ip': '198.51.100.7', 'asn': 17511, 'asOrganization': 'OPTAGE Inc. Very Long Organization Name For Testing',
    'country': 'Japan', 'countryCode': 'JP', 'city': 'Ōtsu', 'fraudScore': 75, 'isResidential': false, 'isBroadcast': true,
  });

Widget _app(Session s, CoreService c) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: s),
        ChangeNotifierProvider.value(value: c),
        ChangeNotifierProvider.value(value: _ip(c)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      ),
    );

/// 记录"单独测速"调用，不真的去测
class _FakeCore extends CoreService {
  _FakeCore(super.storage, super.session);
  final tested = <String>[];
  @override
  Future<void> testOne(ProxyNode n) async => tested.add(n.tag);
}

void main() {
  group('导入本地文件', () {
    const file = '''
{"koyun":{"format":1,"created_at":1,"upload":1,"download":2,"total":30,"expire":40},
 "outbounds":[{"type":"anytls","tag":"节点A","server":"1.2.3.4","server_port":443,"password":"x"}]}''';

    test('转换网站的文件：导入节点和流量信息，切换为不可联网刷新的本地模式', () async {
      final (s, _) = await _services();
      expect(await s.importLocal(file), RefreshResult.ok);
      expect(s.mode, AccountMode.local);
      expect(s.isFileImport, isTrue);
      expect(s.nodes.map((n) => n.tag), ['节点A']);
      expect(s.subInfo?.total, 30);
      expect(s.subInfo?.expire, 40);
    });

    test('内容不完整、不是配置或订阅链接：提示没有节点，原有节点不变', () async {
      final (s, _) = await _services();
      final before = s.nodes.length;
      for (final bad in ['{"outbounds":[', '{"outbounds":{}}', 'proxies: []', 'https://example.com/s/abc']) {
        expect(await s.importLocal(bad), RefreshResult.empty, reason: bad);
      }
      expect(s.nodes.length, before);
      expect(s.mode, AccountMode.xboard);
    });

    testWidgets('粘贴订阅链接：提示先去转换网站，不会导入', (tester) async {
      final (s, c) = await _services();
      await tester.pumpWidget(_app(s, c));
      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.byType(HomeShell)))
          .push(MaterialPageRoute(builder: (_) => const ImportPage()));
      await tester.pump(); // 页面路由第一帧是隐藏的
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), 'https://example.com/s/abc');
      await tester.tap(find.text('导入并使用'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('这里不能导入订阅链接，请先到转换网站转换成文件'), findsOneWidget);
      expect(s.mode, AccountMode.xboard);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('点击延迟：触控板轻点（手指微动 6 像素）也能触发单独测速，且不会误选节点', (tester) async {
    tester.view.physicalSize = const Size(960, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (s, c0) = await _services();
    final c = _FakeCore(c0.storage, s)..delays.addAll(c0.delays);
    await tester.pumpWidget(_app(s, c));
    tester.state<HomeShellState>(find.byType(HomeShell)).goTo('nodes');
    await tester.pump(const Duration(milliseconds: 500));
    final before = c.selected;
    // 模拟触控板：按下 → 移动 6 像素 → 抬起
    final g = await tester.startGesture(tester.getCenter(find.text('86ms')), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(6, 0));
    await g.up();
    await tester.pump();
    expect(c.tested, [s.nodes[0].tag], reason: '点击延迟应触发单独测速');
    expect(c.selected, before, reason: '点击延迟不应该同时选择节点');
    // 点"测速"（没测过的节点）也能触发
    await tester.tap(find.text('测速').first);
    await tester.pump();
    expect(c.tested.length, 2);
    // 点卡片其它位置 = 选择节点，不测速
    await tester.tap(find.text('香港D01-1X'));
    await tester.pump();
    expect(c.tested.length, 2);
    expect(c.selected, s.nodes[0].tag);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });


  test('IP 显示', () {
    final i = IpInfo.fromJson({'ip': '203.0.113.45', 'countryCode': 'tw', 'country': 'Taiwan'});
    expect(i.masked, '203.0.*.*');
    expect(IpInfo(ip: '2001:db8:1:2::1').masked, '2001:db8:****');
    expect(countryName(i, 'zh'), '台湾');
    expect(countryName(i, 'zh', hant: true), '台灣');
    expect(countryName(i, 'en'), 'Taiwan');
    // 国内接口格式
    final c = IpInfo.fromIpip({
      'ret': 'ok',
      'data': {'ip': '203.0.113.9', 'location': ['中国', '上海', '上海', '', '电信']}
    });
    expect(c.ip, '203.0.113.9');
    expect(c.countryCode, 'CN');
    expect(c.city, '上海');
    expect(c.org, '电信');
    expect(c.detailed, isFalse);
    expect(countryName(c, 'zh'), '中国');
    expect(countryName(c, 'en'), 'CN');
    // 缓存读写
    final back = IpInfo.fromCache(c.toJson());
    expect(back.ip, c.ip);
    expect(back.city, '上海');
  });

  test('版本号比较', () {
    expect(Updater.isNewer('1.0.2', '1.0.1'), isTrue);
    expect(Updater.isNewer('1.0.10', '1.0.9'), isTrue);
    expect(Updater.isNewer('1.1', '1.0.9'), isTrue);
    expect(Updater.isNewer('1.0.1', '1.0.1'), isFalse);
    expect(Updater.isNewer('1.0.0', '1.0.1'), isFalse);
  });

  for (final size in const [Size(960, 640), Size(760, 520), Size(1400, 900), Size(390, 800)]) {
    testWidgets('所有页面无布局错误 ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, c) = await _services();
      AppConfig.bootConvert = 'https://convert.example.com';
      addTearDown(() => AppConfig.bootConvert = '');
      // 出错时打印完整信息（哪个文件哪一行的控件溢出）
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        debugPrint(d.toString());
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      await tester.pumpWidget(_app(s, c));
      await tester.pump(const Duration(milliseconds: 500));

      final shell = tester.state<HomeShellState>(find.byType(HomeShell));
      for (final key in ['home', 'nodes', 'profile']) {
        shell.goTo(key);
        await tester.pump(const Duration(milliseconds: 500));
        final e = tester.takeException();
        expect(e, isNull, reason: '页面 $key 出现布局错误：${e is FlutterError ? e.toStringDeep() : e}');
      }
      // 导入本地文件页
      Navigator.of(tester.element(find.byType(HomeShell)))
          .push(MaterialPageRoute(builder: (_) => const ImportPage()));
      await tester.pump(); // 页面路由第一帧是隐藏的
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('拖拽文件到这里，或点击选择文件'), findsOneWidget);
      expect(find.text('打开转换网站'), findsOneWidget);
      final importError = tester.takeException();
      expect(importError, isNull, reason: '导入页出现布局错误：$importError');
      Navigator.of(tester.element(find.byType(ImportPage))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      // 更新对话框
      Updater.instance.available = UpdateInfo(version: '9.9.9', notes: '修复若干问题\n界面优化', pageUrl: 'https://example.com');
      showUpdateDialog(tester.element(find.byType(HomeShell)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('9.9.9'), findsWidgets);
      expect(tester.takeException(), isNull, reason: '更新对话框出现布局错误');
      Navigator.of(tester.element(find.byType(HomeShell))).pop();
      Updater.instance.available = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
