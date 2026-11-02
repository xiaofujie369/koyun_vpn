import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:koyun_vpn/ui/pages/home_shell.dart';
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
  return (session, CoreService(storage, session));
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

void main() {

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
