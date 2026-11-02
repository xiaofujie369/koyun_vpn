import 'dart:convert';

/// 全局常量配置。改品牌 / 域名只需要改这里。
class AppConfig {
  static const appName = 'Koyun';
  static const appVersion = '1.0.0';

  /// sing-box 内核版本（必须和打包进去的内核一致，订阅接口按它决定输出格式）。
  static const singBoxVersion = '1.14.4';

  /// 域名不写在代码里（仓库是公开的），编译时通过 --dart-define 注入：
  ///   KOYUN_API  = 接口域名列表（逗号分隔，按顺序尝试，被墙自动切下一个）
  ///   KOYUN_WEB  = 官网 / 网页注册地址
  /// 注入值经过混淆（tools/encode_domains.py 生成），安装包里搜不到明文域名。
  /// Android：编译机 /opt/kvbuild/keys/app.env；Windows：GitHub Secrets。
  static const _apiEnc = String.fromEnvironment('KOYUN_API');
  static const _webEnc = String.fromEnvironment('KOYUN_WEB');

  static final List<String> apiHosts = _decode(_apiEnc)
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.startsWith('https://'))
      .toList();

  /// 注册失败时引导客户打开的网页注册地址。
  static final String webRegisterUrl = _decode(_webEnc);

  /// 官网 / 网页版（用户中心里"官方网站"）。
  static String get websiteUrl => webRegisterUrl;

  static String _decode(String enc) {
    if (enc.isEmpty) return '';
    try {
      final raw = base64Url.decode(base64Url.normalize(enc));
      const key = [0x6b, 0x6f, 0x79, 0x75, 0x6e, 0x21, 0x5a, 0x37];
      return utf8.decode([for (var i = 0; i < raw.length; i++) raw[i] ^ key[i % key.length]]);
    } catch (_) {
      return '';
    }
  }

  /// 请求订阅时的 User-Agent：带上 sing-box 版本，Xboard 才会下发
  /// 原生 sing-box 格式（含 AnyTLS REALITY / ECH 等新特性）。
  static String get subscribeUserAgent =>
      'KoyunVPN/$appVersion sing-box/$singBoxVersion';

  static String get apiUserAgent => 'KoyunVPN/$appVersion';

  /// 测速地址
  static const delayTestUrl = 'https://www.gstatic.com/generate_204';

  /// 订阅自动刷新间隔（App 在前台/连接中时）
  static const autoRefreshInterval = Duration(hours: 6);

  /// 本地代理端口（系统代理模式），被占用时自动顺延。
  static const defaultMixedPort = 17890;
}
