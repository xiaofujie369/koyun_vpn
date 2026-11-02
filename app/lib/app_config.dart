/// 全局常量配置。改品牌 / 域名只需要改这里。
class AppConfig {
  static const appName = 'Koyun';
  static const appVersion = '1.0.0';

  /// sing-box 内核版本（必须和打包进去的内核一致，订阅接口按它决定输出格式）。
  static const singBoxVersion = '1.14.4';

  /// Xboard 接口域名，按顺序尝试，第一个能用的会被记住。
  /// 被墙或故障时自动切到下一个。新增备用域名直接往后加。
  static const apiHosts = <String>[
    'https://ss.koyun520.com',
    'https://moli.shy521.com',
  ];

  /// 注册失败时引导客户打开的网页注册地址。
  static const webRegisterUrl = 'https://ss.koyun520.com';

  /// 官网 / 网页版（用户中心里"官方网站"）。
  static const websiteUrl = 'https://ss.koyun520.com';

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
