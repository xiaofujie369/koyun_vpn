import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import 'bootstrap.dart';
import 'reporter.dart';

class UpdateInfo {
  UpdateInfo({required this.version, required this.notes, required this.pageUrl, this.assetUrl});
  final String version;
  final String notes;
  final String pageUrl; // Release 网页
  final String? assetUrl; // 本平台的安装包
}

/// 检查更新：读取 GitHub 上最新的正式 Release（草稿 / 预发布不算）。
/// Windows：下载安装包后静默安装并自动重启；其它平台：用浏览器下载。
class Updater extends ChangeNotifier {
  Updater._();
  static final instance = Updater._();

  UpdateInfo? available;
  bool checking = false;
  double? progress; // 下载进度 0~1；null = 没在下载

  /// 安装前调用：断开连接、恢复系统代理、退出 App（由 main.dart 设置）
  Future<void> Function()? beforeInstall;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/vnd.github+json'},
  ));

  /// 返回 null 表示检查失败（网络问题），否则返回是否有新版本
  Future<bool?> check() async {
    if (checking) return available != null;
    checking = true;
    notifyListeners();
    // 1) 优先问自家后台（国内访问快）；没配置 / 失败再查 GitHub
    final fromServer = await _checkServer();
    if (fromServer != null) {
      checking = false;
      notifyListeners();
      return fromServer;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/${AppConfig.updateRepo}/releases/latest',
        options: Options(headers: {'User-Agent': AppConfig.apiUserAgent}),
      );
      final j = res.data!;
      final tag = (j['tag_name'] ?? '').toString();
      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '').split('-').first;
      if (!isNewer(latest, AppConfig.appVersion)) {
        available = null;
        return false;
      }
      String? asset;
      final assets = <String, String?>{
        for (final a in (j['assets'] as List? ?? const []))
          (a['name'] ?? '').toString().toLowerCase(): a['browser_download_url'] as String?,
      };
      if (Platform.isAndroid) {
        final name = pickApk(assets.keys, await _androidAbis());
        asset = name == null ? null : assets[name];
      } else {
        for (final e in assets.entries) {
          if (_matchesPlatform(e.key)) {
            asset = e.value;
            break;
          }
        }
      }
      available = UpdateInfo(
        version: latest,
        notes: (j['body'] ?? '').toString().trim(),
        pageUrl: (j['html_url'] ?? 'https://github.com/${AppConfig.updateRepo}/releases').toString(),
        assetUrl: asset,
      );
      return true;
    } on DioException catch (e) {
      // 404 = 仓库里还没有正式发布的版本，当作"已是最新"
      if (e.response?.statusCode == 404) {
        available = null;
        return false;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// 后台 /api/v1/client/config 返回的 latest 字段：
  /// {"version":"1.0.3","notes":"...","page":"https://...","downloads":{"windows":"...","android":"...","macos":"..."}}
  Future<bool?> _checkServer() async {
    // 先看启动引导配置（Cloudflare Pages）里有没有版本信息，再问数据后台
    await Bootstrap.instance.refresh();
    final latest = Bootstrap.instance.latest ?? (await Reporter.instance.remoteConfig())?['latest'];
    if (latest is! Map) return null;
    final v = (latest['version'] ?? '').toString();
    if (v.isEmpty) return null;
    if (!isNewer(v, AppConfig.appVersion)) {
      available = null;
      return false;
    }
    final dl = latest['downloads'] is Map ? latest['downloads'] as Map : const {};
    available = UpdateInfo(
      version: v,
      notes: (latest['notes'] ?? '').toString(),
      pageUrl: (latest['page'] ?? 'https://github.com/${AppConfig.updateRepo}/releases').toString(),
      assetUrl: dl[Platform.operatingSystem] as String?,
    );
    return true;
  }

  static bool _matchesPlatform(String name) {
    if (Platform.isWindows) return name.endsWith('-setup.exe');
    if (Platform.isMacOS) return name.endsWith('.dmg');
    return false;
  }

  /// 按手机支持的架构选安装包（优先级从高到低），装错架构的包会安装失败。
  /// 没有合适的包时返回 null，界面会打开发布页让用户自己选。
  static String? pickApk(Iterable<String> names, List<String> abis) {
    for (final abi in abis) {
      for (final name in names) {
        if (name.endsWith('-${abi.toLowerCase()}.apk')) return name;
      }
    }
    for (final name in names) {
      if (name.endsWith('-universal.apk')) return name;
    }
    return null;
  }

  static Future<List<String>> _androidAbis() async {
    try {
      final abis = await const MethodChannel('koyun/core').invokeListMethod<String>('abis');
      return abis ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 版本比较：1.0.10 > 1.0.9
  static bool isNewer(String a, String b) {
    List<int> p(String v) => v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final m = i < x.length ? x[i] : 0, n = i < y.length ? y[i] : 0;
      if (m != n) return m > n;
    }
    return false;
  }

  /// 开始更新。返回 false 表示失败。
  Future<bool> install() async {
    final info = available;
    if (info == null) return false;
    if (!Platform.isWindows || info.assetUrl == null) {
      return launchUrl(Uri.parse(info.assetUrl ?? info.pageUrl), mode: LaunchMode.externalApplication)
          .catchError((_) => false);
    }
    try {
      progress = 0;
      notifyListeners();
      final file = '${Directory.systemTemp.path}\\Koyun-${info.version}-setup.exe';
      await _dio.download(
        info.assetUrl!,
        file,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (r, t) {
          if (t > 0) {
            progress = r / t;
            notifyListeners();
          }
        },
      );
      // /SILENT 显示安装进度但不需要点"下一步"；安装完成后安装包会自动重新打开 App
      await Process.start(file, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
          mode: ProcessStartMode.detached);
      await beforeInstall?.call();
      return true;
    } catch (_) {
      progress = null;
      notifyListeners();
      return false;
    }
  }
}
