import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
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
import 'package:koyun_vpn/ui/theme.dart';
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

/// 截图（仅开发时查看效果用，平时自动跳过）：
///   SHOTS=1 flutter test test/screenshot_test.dart --update-goldens
Future<void> _loadFonts() async {
  final f = FontLoader('HarmonyOS Sans');
  for (final n in ['Regular', 'Medium', 'Bold']) {
    final file = File('assets/fonts/HarmonyOS_Sans_SC_$n.ttf');
    if (file.existsSync()) f.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await f.load();
  final icons = FontLoader('MaterialIcons');
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/kvbuild/flutter';
  icons.addFont(Future.value(ByteData.sublistView(
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  setUpAll(_loadFonts);
  testWidgets('截图 导入本地文件', skip: !Platform.environment.containsKey('SHOTS'), (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppConfig.bootConvert = 'https://convert.example.com';
    addTearDown(() => AppConfig.bootConvert = '');
    final (s, c) = await _services();
    await tester.runAsync(() async {
      await s.importLocal('{"outbounds":[{"type":"anytls","tag":"A","server":"1.2.3.4","server_port":443,"password":"x"}]}');
      await s.logout();
    });
    await tester.pumpWidget(RepaintBoundary(child: _app(s, c)));
    await tester.pump(const Duration(milliseconds: 300));
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const ImportPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('shots/import.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
  for (final page in ['home', 'nodes', 'profile']) {
    testWidgets('截图 $page', skip: !Platform.environment.containsKey('SHOTS'), (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, c) = await _services();
      await tester.pumpWidget(RepaintBoundary(child: _app(s, c)));
      c.selected = s.nodes.first.tag;
      tester.state<HomeShellState>(find.byType(HomeShell)).goTo(page);
      await tester.pump(const Duration(milliseconds: 600));
      // 等图片（国旗）真正解码完成
      for (var k = 0; k < 3; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('shots/$page.png'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
