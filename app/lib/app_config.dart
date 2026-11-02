import 'dart:convert';

/// 全局常量配置。改品牌 / 域名只需要改这里。
class AppConfig {
  static const appName = 'Koyun';
  /// 版本号启动时从安装包读取（来源 pubspec.yaml 的 version），只需要改 pubspec 一处。
  static String appVersion = '0.0.0';

  /// 检查更新用的 GitHub 仓库（只读取公开的正式 Release，草稿不会被检测到）
  static const updateRepo = 'xiaofujie369/koyun_vpn';

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

  /// 数据管理后台（统计 / 反馈 / 远程配置）地址和密钥，同样编译时注入：
  ///   KOYUN_STATS      = 后台地址，例如 https://admin.example.com（不填 = 关闭上报，App 不会发送任何统计）
  ///   KOYUN_STATS_KEY  = 客户端密钥（后台用来识别是自家 App 发来的请求）
  /// 接口说明见 docs/后台接口说明.md
  static const _statsEnc = String.fromEnvironment('KOYUN_STATS');
  static const _statsKeyEnc = String.fromEnvironment('KOYUN_STATS_KEY');
  static final String statsBase = _decode(_statsEnc).replaceAll(RegExp(r'/+$'), '');
  static final String statsKey = _decode(_statsKeyEnc);
  static bool get statsEnabled => statsBase.startsWith('https://');

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

  /// 订阅自动刷新间隔（App 运行中时）。后台新增国家 / 节点，最晚这么久客户端就能拿到
  static const autoRefreshInterval = Duration(hours: 1);

  /// 本地代理端口（系统代理模式），被占用时自动顺延。
  static const defaultMixedPort = 17890;
}
