import '../models/node.dart';
import '../services/storage.dart';

class CoreOptions {
  CoreOptions({
    required this.nodes,
    required this.selected,
    required this.ruleSetDir,
    required this.workDir,
    required this.clashPort,
    required this.clashSecret,
    this.tun = false,
    this.mixedPort,
    this.setSystemProxy = false,
    this.routeMode = RouteMode.rule,
    this.ipv6 = false,
    this.mobile = false,
    this.logLevel = 'warn',
  });

  final List<ProxyNode> nodes;

  /// 选中的节点 tag，或 'auto'（自动选择延迟最低）
  final String selected;
  final String ruleSetDir;
  final String workDir;
  final int clashPort;
  final String clashSecret;
  final bool tun;
  final int? mixedPort;
  final bool setSystemProxy;
  final RouteMode routeMode;
  final bool ipv6;
  final bool mobile;
  final String logLevel;
}

/// 生成 sing-box 1.14 配置。
///
/// 设计：
/// * "proxy" 选择器 = [auto, 所有节点]；"auto" 为 urltest 自动选最快。
/// * 规则 / 全局 / 直连 三种模式用 clash_mode 规则实现，
///   切换时调用 Clash API 即可，不需要重启内核、不断线。
/// * 国内域名走阿里 DNS 直连，其余走 1.1.1.1 DoH 经代理，防 DNS 污染。
/// * 分流规则集打包在 App 内（本地 .srs 文件），首次启动不依赖 GitHub，国内也能秒开。
class ConfigBuilder {
  static Map<String, dynamic> build(CoreOptions o) {
    final nodeTags = o.nodes.map((n) => n.tag).toList();
    final selected =
        (o.selected == 'auto' || nodeTags.contains(o.selected)) ? o.selected : 'auto';

    final inbounds = <Map<String, dynamic>>[];
    if (o.tun) {
      inbounds.add({
        'type': 'tun',
        'tag': 'tun-in',
        'address': [
          '172.19.0.1/30',
          if (o.ipv6) 'fdfe:dcba:9876::1/126',
        ],
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        // mixed：TCP 用系统栈（快），UDP 用 gVisor（兼容好）
        // 注意：不要把局域网段排除出 TUN，否则发往路由器的 DNS 查询会绕过劫持导致污染；
        // 局域网流量进入 TUN 后由 ip_is_private 规则直连，效果一样。
        'stack': 'mixed',
      });
    }
    if (o.mixedPort != null) {
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': o.mixedPort,
        if (o.setSystemProxy) 'set_system_proxy': true,
      });
    }

    final strategy = o.ipv6 ? 'prefer_ipv4' : 'ipv4_only';

    return {
      'log': {'level': o.logLevel, 'timestamp': true},
      'dns': {
        'servers': [
          {
            'type': 'https',
            'tag': 'dns-remote',
            'server': '1.1.1.1',
            'detour': 'proxy',
          },
          {'type': 'udp', 'tag': 'dns-direct', 'server': '223.5.5.5'},
        ],
        'rules': [
          {'clash_mode': 'Direct', 'server': 'dns-direct'},
          {'clash_mode': 'Global', 'server': 'dns-remote'},
          {'rule_set': ['geosite-cn'], 'server': 'dns-direct'},
        ],
        'final': 'dns-remote',
        'strategy': strategy,
      },
      'inbounds': inbounds,
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': ['auto', ...nodeTags],
          'default': selected,
          'interrupt_exist_connections': true,
        },
        {
          'type': 'urltest',
          'tag': 'auto',
          'outbounds': nodeTags,
          'url': 'https://www.gstatic.com/generate_204',
          'interval': '10m',
          'tolerance': 80,
          'idle_timeout': '30m',
        },
        ...o.nodes.map((n) => n.outbound),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
          {'clash_mode': 'Direct', 'outbound': 'direct'},
          {'clash_mode': 'Global', 'outbound': 'proxy'},
          {
            'rule_set': ['geosite-cn', 'geoip-cn'],
            'outbound': 'direct',
          },
        ],
        'rule_set': [
          {
            'type': 'local',
            'tag': 'geosite-cn',
            'format': 'binary',
            'path': '${o.ruleSetDir}/geosite-cn.srs',
          },
          {
            'type': 'local',
            'tag': 'geoip-cn',
            'format': 'binary',
            'path': '${o.ruleSetDir}/geoip-cn.srs',
          },
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
        // 解析节点服务器域名用国内 DNS（节点地址本身不能走代理解析）
        'default_domain_resolver': {'server': 'dns-direct', 'strategy': strategy},
      },
      'experimental': {
        'cache_file': {
          'enabled': true,
          'path': '${o.workDir}/cache.db',
          'store_fakeip': false,
        },
        'clash_api': {
          'external_controller': '127.0.0.1:${o.clashPort}',
          'secret': o.clashSecret,
          'default_mode': switch (o.routeMode) {
            RouteMode.rule => 'Rule',
            RouteMode.global => 'Global',
            RouteMode.direct => 'Direct',
          },
        },
      },
    };
  }

  static String clashMode(RouteMode m) => switch (m) {
        RouteMode.rule => 'Rule',
        RouteMode.global => 'Global',
        RouteMode.direct => 'Direct',
      };
}
