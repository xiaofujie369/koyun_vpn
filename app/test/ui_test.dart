import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/api/xboard_api.dart';
import 'package:koyun_vpn/core/core_service.dart';
import 'package:koyun_vpn/l10n/gen/app_localizations.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:koyun_vpn/services/session.dart';
import 'package:koyun_vpn/services/storage.dart';
import 'package:koyun_vpn/ui/pages/home_shell.dart';
import 'package:koyun_vpn/services/updater.dart';
import 'package:koyun_vpn/ui/theme.dart';
import 'package:koyun_vpn/ui/widgets/update_dialog.dart';
import 'package:koyun_vpn/ui/widgets/window_bar.dart';
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
    for (final n in ['🇭🇰香港D01-1X', '🇯🇵日本D13-1X', '🇹🇼台湾A04-1X直连', '🇺🇸美国洛杉矶-2X', '🇸🇬新加坡B02-1X'])
      ProxyNode({'tag': n, 'type': 'anytls', 'server': '1.2.3.4', 'server_port': 443}),
  ];
  return (session, CoreService(storage, session));
}

Widget _app(Session s, CoreService c) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: s),
        ChangeNotifierProvider.value(value: c),
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
        builder: (context, child) => Column(children: [const WindowBar(), Expanded(child: child!)]),
        home: const HomeShell(),
      ),
    );

void main() {
  forceCustomTitleBar = true;

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
      await tester.pumpWidget(_app(s, c));
      await tester.pump(const Duration(milliseconds: 500));

      final shell = tester.state<HomeShellState>(find.byType(HomeShell));
      for (final key in ['home', 'nodes', 'profile']) {
        shell.goTo(key);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '页面 $key 出现布局错误');
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
