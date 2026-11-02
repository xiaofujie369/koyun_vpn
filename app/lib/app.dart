import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'l10n/gen/app_localizations.dart';
import 'services/reporter.dart';
import 'services/session.dart';
import 'ui/pages/home_shell.dart';
import 'ui/pages/login_page.dart';
import 'ui/theme.dart';
import 'ui/widgets/window_bar.dart';

/// 手动选择的语言（null = 跟随系统）
final localeNotifier = ValueNotifier<Locale?>(null);

const kLanguages = <String, String>{
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'ru': 'Русский',
  'vi': 'Tiếng Việt',
};

Locale? localeFromCode(String code) {
  if (code.isEmpty) return null;
  if (code == 'zh_Hant') return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  return Locale(code);
}

/// 系统语言 → 支持的语言。繁体按 script 或地区（台港澳）判断，其余没有的语言回退英文
Locale resolveLocale(Locale? device) {
  if (device == null) return const Locale('zh');
  if (device.languageCode == 'zh') {
    final hant = device.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(device.countryCode);
    return hant ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant') : const Locale('zh');
  }
  const langs = {'en', 'ja', 'ko', 'ru', 'vi'};
  return langs.contains(device.languageCode) ? Locale(device.languageCode) : const Locale('en');
}

String apiLanguageTag(Locale l) {
  if (l.languageCode == 'zh') return l.scriptCode == 'Hant' ? 'zh-TW' : 'zh-CN';
  return switch (l.languageCode) {
    'ja' => 'ja-JP',
    'ko' => 'ko-KR',
    'vi' => 'vi-VN',
    'ru' => 'ru-RU',
    _ => 'en-US',
  };
}

class KoyunApp extends StatelessWidget {
  const KoyunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: localeNotifier,
      builder: (context, forced, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: forced,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeListResolutionCallback: (locales, supported) {
          final l = forced ?? resolveLocale(locales?.isNotEmpty == true ? locales!.first : null);
          context.read<Session>().api.language = apiLanguageTag(l);
          Reporter.instance.locale = l.toLanguageTag();
          return l;
        },
        // Windows：自绘标题栏放在所有页面上方（登录页、主界面、弹出的页面都有）
        builder: (context, child) => useCustomTitleBar
            ? Column(children: [const WindowBar(), Expanded(child: child!)])
            : child!,
        home: const _Gate(),
      ),
    );
  }
}

/// 根据登录状态切换登录页 / 主界面
class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (!s.loggedIn) {
      return LoginPage(
        key: const ValueKey('login'),
        message: s.lastResult == RefreshResult.unauthorized
            ? AppLocalizations.of(context).sessionExpired
            : null,
      );
    }
    return const HomeShell(key: ValueKey('home'));
  }
}
