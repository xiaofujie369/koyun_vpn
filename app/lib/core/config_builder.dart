import 'dart:io' show InternetAddress;

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
    this.routeMode = RouteMode.rule,
    this.ipv6 = false,
    this.mobile = false,
    this.logLevel = 'warn',
    this.testPort,
    this.testSecret = '',
    this.testerOnly = false,
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
  final RouteMode routeMode;
  final bool ipv6;
  final bool mobile;
  final String logLevel;

  /// 测速入口端口（不设置就没有测速入口）和密码
  final int? testPort;
  final String testSecret;

  /// 未连接时临时启动的测速内核：不要"自动选择"（否则一启动就把所有节点测一遍，干扰测速）、不用缓存文件
  final bool testerOnly;
}

/// 生成 sing-box 1.14 配置。
///
/// 设计：
/// * "proxy" 选择器 = [auto, 所有节点]；"auto" 为 urltest 自动选最快。
/// * 规则 / 全局 / 直连 三种模式用 clash_mode 规则实现，
///   切换时调用 Clash API 即可，不需要重启内核、不断线。
/// * DNS 参考 Clash Verge：每类域名同时问多个服务器，谁先答用谁，一个服务器不通不影响上网。
///   节点域名和国内域名直连解析；其余域名经代理解析，防 DNS 污染。
/// * 分流规则集打包在 App 内（本地 .srs 文件），首次启动不依赖 GitHub，国内也能秒开。
class ConfigBuilder {
  /// 节点 tag -> 测速入口用户名
  /// App 自己登录、刷新订阅用的账号，跟随当前选择的节点
  static const appUser = 'app';

  /// 内核 1.14 要求写明解析节点域名的服务器，但这样只能用一个服务器。
  /// 不写才能走下面的 DNS 规则同时问多个，因此启动电脑端内核时要带上这个环境变量。
  /// 升级内核前要先确认这个开关还在，不在时内核会启动失败。
  static const coreEnv = {'ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER': 'true'};

  /// 节点地址里的域名（IP 不需要解析）
  static List<String> nodeDomains(List<ProxyNode> nodes) => {
        for (final n in nodes)
          if (n.server.isNotEmpty && InternetAddress.tryParse(n.server) == null) n.server
      }.toList()
        ..sort();

  /// 同时问 [servers] 里的每个服务器，第一个正常回答的胜出。
  /// 没有服务器正常回答时（比如域名不存在），由最后一条规则返回结果。
  static List<Map<String, dynamic>> _race(
    String name,
    Map<String, dynamic> match,
    List<String> servers, {
    Map<String, dynamic> options = const {},
  }) {
    return [
      for (var i = 0; i < servers.length; i++) ...[
        {
          ...match,
          'query_type': ['A', 'AAAA'],
          'action': 'evaluate',
          'server': servers[i],
          'tag': '$name-$i',
          if (i > 0) 'speculative': true,
          'timeout': '3s',
          ...options,
        },
        {'match_response': '$name-$i', 'response_rcode': 'NOERROR', 'action': 'respond', 'race': true},
      ],
      {...match, 'server': servers.first, ...options},
    ];
  }

  static Map<String, String> testUsers(List<ProxyNode> nodes) =>
      {for (var i = 0; i < nodes.length; i++) nodes[i].tag: 'n$i'};

  static Map<String, dynamic> build(CoreOptions o) {
    final nodeTags = o.nodes.map((n) => n.tag).toList();
    final selected = nodeTags.contains(o.selected)
        ? o.selected
        : (o.testerOnly && nodeTags.isNotEmpty ? nodeTags.first : 'auto');
    final testUsers = o.testPort == null ? const <String, String>{} : ConfigBuilder.testUsers(o.nodes);

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
      });
    }

    // 测速入口：只监听本机、带随机密码；用户名决定走哪个节点，不经过选择器，也不影响正在使用的节点
    if (o.testPort != null) {
      inbounds.add({
        'type': 'mixed',
        'tag': 'test-in',
        'listen': '127.0.0.1',
        'listen_port': o.testPort,
        'users': [
          for (final u in testUsers.values) {'username': u, 'password': o.testSecret},
          if (!o.testerOnly) {'username': appUser, 'password': o.testSecret},
        ],
      });
    }

    // 电脑端节点域名由 DNS 规则解析；手机端内核没有 coreEnv，暂时保持单个服务器
    final nodeDomains = o.mobile ? const <String>[] : ConfigBuilder.nodeDomains(o.nodes);
    const direct = ['dns-direct-ali', 'dns-direct-pub', 'dns-direct'];
    const remote = ['dns-remote', 'dns-remote-google'];

    return {
      'log': {'level': o.logLevel, 'timestamp': true},
      'dns': {
        'servers': [
          {'type': 'https', 'tag': 'dns-remote', 'server': '1.1.1.1', 'detour': 'proxy'},
          {'type': 'https', 'tag': 'dns-remote-google', 'server': '8.8.8.8', 'detour': 'proxy'},
          {'type': 'udp', 'tag': 'dns-direct', 'server': '223.5.5.5'},
          {'type': 'udp', 'tag': 'dns-direct-tencent', 'server': '119.29.29.29'},
          {
            'type': 'https',
            'tag': 'dns-direct-ali',
            'server': '223.5.5.5',
            'tls': {'server_name': 'dns.alidns.com'},
          },
          {
            'type': 'https',
            'tag': 'dns-direct-pub',
            'server': '1.12.12.12',
            'tls': {'server_name': 'doh.pub'},
          },
          {'type': 'https', 'tag': 'dns-node-cf', 'server': '1.1.1.1'},
          {'type': 'https', 'tag': 'dns-node-google', 'server': '8.8.8.8'},
          // 系统 DNS：有些网络只放行内网 DNS。TUN 模式下它会被自己劫持，不能用
          if (!o.tun) {'type': 'local', 'tag': 'dns-system'},
        ],
        'rules': [
          if (nodeDomains.isNotEmpty)
            ..._race('node', {'domain': nodeDomains}, [
              'dns-direct',
              'dns-direct-tencent',
              'dns-direct-ali',
              'dns-node-cf',
              'dns-node-google',
              if (!o.tun) 'dns-system',
            ]),
          // 关闭 IPv6 时不返回网站的 IPv6 地址。节点域名在上面已处理，只有 IPv6 地址的节点不受影响
          if (!o.ipv6) {'query_type': ['AAAA'], 'action': 'predefined', 'rcode': 'NOERROR'},
          ..._race('mode-direct', {'clash_mode': 'Direct'}, direct),
          ..._race('mode-global', {'clash_mode': 'Global'}, remote),
          ..._race('cn', {'rule_set': ['geosite-cn']}, direct),
          ..._race('notcn', {'rule_set': ['geosite-geolocation-notcn']}, remote),
          // 不在任何名单里的域名（智能分流模式）：仍用防污染的远程 DNS，但告诉它"用户在中国"，
          // 国内网站会返回国内的服务器 IP，随后被 geoip-cn 判定为直连，不再绕道国外。
          ..._race('other', {'clash_mode': 'Rule'}, remote, options: {'client_subnet': '114.114.114.0/24'}),
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
        // 缓存过期后先用旧结果、后台再更新，DNS 临时不通时不影响新连接
        'optimistic': true,
      },
      'inbounds': inbounds,
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': [if (!o.testerOnly) 'auto', ...nodeTags],
          'default': selected,
          'interrupt_exist_connections': true,
        },
        if (!o.testerOnly)
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
          for (final e in testUsers.entries)
            {'inbound': ['test-in'], 'auth_user': [e.value], 'outbound': e.key},
          if (o.testPort != null && !o.testerOnly)
            {'inbound': ['test-in'], 'auth_user': [appUser], 'outbound': 'proxy'},
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
          {'clash_mode': 'Direct', 'outbound': 'direct'},
          {'clash_mode': 'Global', 'outbound': 'proxy'},
          {'rule_set': ['geosite-cn'], 'outbound': 'direct'},
          // 已知国外网站：直接走代理，不需要先解析域名
          {'rule_set': ['geosite-geolocation-notcn'], 'outbound': 'proxy'},
          // 其余域名先解析出 IP，再判断是不是国内 IP。
          // 修复：以前系统代理模式下连接只有域名没有 IP，geoip-cn 永远匹配不上，
          // 不在名单里的国内网站全部被送去代理，绕道国外导致打开很慢。
          {'action': 'resolve'},
          {'rule_set': ['geoip-cn'], 'outbound': 'direct'},
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
            'tag': 'geosite-geolocation-notcn',
            'format': 'binary',
            'path': '${o.ruleSetDir}/geosite-geolocation-notcn.srs',
          },
          {
            'type': 'local',
            'tag': 'geoip-cn',
            'format': 'binary',
            'path': '${o.ruleSetDir}/geoip-cn.srs',
          },
        ],
        'final': 'proxy',
        // 绑定默认网卡只为防止 TUN 回环。系统代理模式下交给系统路由，
        // 否则 IPv6 走的网卡和默认 IPv4 网卡不同时，IPv6 节点连不上。
        'auto_detect_interface': o.tun || o.mobile,
        // 节点地址本身不能走代理解析。电脑端由上面的 DNS 规则处理（见 coreEnv）
        if (o.mobile) 'default_domain_resolver': {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
      },
      'experimental': {
        'cache_file': o.testerOnly
            ? {'enabled': false} // 不和正式内核抢缓存文件
            : {
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
