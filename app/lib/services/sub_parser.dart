import 'dart:convert';

import '../models/node.dart';

/// 订阅内容解析：支持
/// 1. sing-box JSON（Xboard flag=sing-box 的原生输出，首选，信息最完整）
/// 2. Base64 / 明文的分享链接列表（vless/vmess/trojan/ss/hysteria2/tuic/anytls）
///
/// 纯 Dart 实现、无副作用，方便单元测试。
class SubParser {
  static const proxyTypes = {
    'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'hysteria',
    'tuic', 'anytls', 'socks', 'http', 'wireguard', 'shadowtls', 'ssh',
  };

  /// Xboard 会把"剩余流量 / 套餐到期"等信息伪装成节点塞进订阅，这里过滤掉
  static final _infoNode = RegExp(
      r'剩余流量|套餐到期|距离下次重置|过滤掉\d+条线路|到期时间|Traffic\s*:|Expire\s*:|官网|官方网址',
      caseSensitive: false);

  static List<ProxyNode> parse(String body) {
    final text = body.trim().replaceFirst('﻿', '');
    List<Map<String, dynamic>> outbounds;
    if (text.startsWith('{')) {
      outbounds = _fromSingBox(text);
    } else {
      var content = text;
      if (!content.contains('://')) {
        final decoded = tryBase64(content.replaceAll(RegExp(r'\s'), ''));
        if (decoded != null) content = decoded;
      }
      outbounds = content
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map(parseUri)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    final nodes = <ProxyNode>[];
    final used = <String>{};
    for (final o in outbounds) {
      final tag = (o['tag'] ?? '').toString();
      if (tag.isEmpty || _infoNode.hasMatch(tag)) continue;
      // sing-box 要求 tag 唯一，重名自动加序号
      var t = tag;
      var i = 2;
      while (used.contains(t) || _reserved.contains(t)) {
        t = '$tag ($i)';
        i++;
      }
      used.add(t);
      o['tag'] = t;
      // 订阅里节点自己的 detour / 拨号字段可能引用不存在的出站，去掉更安全
      o.remove('detour');
      nodes.add(ProxyNode(o));
    }
    return nodes;
  }

  /// 读取转换网站写在文件里的流量和到期信息，没有则返回 null
  static SubInfo? parseInfo(String body) {
    final text = body.trim();
    if (!text.startsWith('{')) return null;
    try {
      final k = (jsonDecode(text) as Map)['koyun'];
      if (k is! Map) return null;
      int n(String key) => (k[key] as num?)?.toInt() ?? 0;
      return SubInfo(upload: n('upload'), download: n('download'), total: n('total'), expire: n('expire'));
    } catch (_) {
      return null;
    }
  }

  /// 我们自己生成配置时使用的保留 tag
  static const _reserved = {'proxy', 'auto', 'direct', 'dns-out', 'block'};

  static List<Map<String, dynamic>> _fromSingBox(String text) {
    final j = jsonDecode(text);
    final list = (j is Map ? j['outbounds'] : null) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((o) => proxyTypes.contains(o['type']))
        .toList();
  }

  static String? tryBase64(String s) {
    try {
      var t = s.replaceAll('-', '+').replaceAll('_', '/');
      while (t.length % 4 != 0) {
        t += '=';
      }
      return utf8.decode(base64.decode(t), allowMalformed: false);
    } catch (_) {
      return null;
    }
  }

  static String _name(Uri u, String fallback) {
    if (u.fragment.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(u.fragment);
    } catch (_) {
      return u.fragment;
    }
  }

  static bool _truthy(String? v) => v == '1' || v == 'true';

  static Map<String, dynamic>? parseUri(String line) {
    try {
      final scheme = line.split('://').first.toLowerCase();
      switch (scheme) {
        case 'vmess':
          return _vmess(line);
        case 'vless':
          return _vless(Uri.parse(line));
        case 'trojan':
          return _trojan(Uri.parse(line));
        case 'ss':
          return _ss(line);
        case 'hysteria2':
        case 'hy2':
          return _hy2(Uri.parse(line));
        case 'tuic':
          return _tuic(Uri.parse(line));
        case 'anytls':
          return _anytls(Uri.parse(line));
        case 'socks':
        case 'socks5':
          final u = Uri.parse(line);
          final ui = _userInfo(u);
          return {
            'type': 'socks', 'tag': _name(u, u.host), 'server': u.host,
            'server_port': u.port,
            if (ui.$1.isNotEmpty) 'username': ui.$1,
            if (ui.$2.isNotEmpty) 'password': ui.$2,
          };
      }
    } catch (_) {}
    return null;
  }

  static (String, String) _userInfo(Uri u) {
    var info = Uri.decodeComponent(u.userInfo);
    if (!info.contains(':')) info = tryBase64(info) ?? info;
    final i = info.indexOf(':');
    return i < 0 ? (info, '') : (info.substring(0, i), info.substring(i + 1));
  }

  static Map<String, dynamic> _tls(Map<String, String> q, String host,
      {bool defaultOn = true}) {
    final sec = q['security'] ?? (defaultOn ? 'tls' : 'none');
    if (sec == 'none' || sec.isEmpty) return {};
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': q['sni'] ?? q['peer'] ?? q['host'] ?? host,
      'insecure': _truthy(q['allowInsecure']) || _truthy(q['insecure']) || _truthy(q['allow_insecure']),
    };
    final alpn = q['alpn'];
    if (alpn != null && alpn.isNotEmpty) tls['alpn'] = alpn.split(',');
    final fp = q['fp'];
    if (fp != null && fp.isNotEmpty && fp != 'none') {
      tls['utls'] = {'enabled': true, 'fingerprint': fp};
    }
    if (sec == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': q['pbk'] ?? '',
        'short_id': q['sid'] ?? '',
      };
      tls['utls'] ??= {'enabled': true, 'fingerprint': 'chrome'};
    }
    return {'tls': tls};
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    final type = q['type'] ?? q['net'] ?? 'tcp';
    final host = q['host'];
    final path = q['path'];
    switch (type) {
      case 'ws':
        return {
          'type': 'ws',
          if (path != null && path.isNotEmpty) 'path': path,
          if (host != null && host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        return {'type': 'grpc', 'service_name': q['serviceName'] ?? q['path'] ?? ''};
      case 'http':
      case 'h2':
        return {
          'type': 'http',
          if (path != null && path.isNotEmpty) 'path': path,
          if (host != null && host.isNotEmpty) 'host': host.split(','),
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          if (path != null && path.isNotEmpty) 'path': path,
          if (host != null && host.isNotEmpty) 'host': host,
        };
      default:
        return null;
    }
  }

  static Map<String, dynamic> _vless(Uri u) {
    final q = u.queryParameters;
    final o = <String, dynamic>{
      'type': 'vless',
      'tag': _name(u, u.host),
      'server': u.host,
      'server_port': u.port,
      'uuid': Uri.decodeComponent(u.userInfo),
      if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
      'packet_encoding': 'xudp',
      ..._tls(q, u.host, defaultOn: false),
    };
    final t = _transport(q);
    if (t != null) o['transport'] = t;
    return o;
  }

  static Map<String, dynamic> _trojan(Uri u) {
    final q = u.queryParameters;
    final o = <String, dynamic>{
      'type': 'trojan',
      'tag': _name(u, u.host),
      'server': u.host,
      'server_port': u.port,
      'password': Uri.decodeComponent(u.userInfo),
      ..._tls(q, u.host),
    };
    final t = _transport(q);
    if (t != null) o['transport'] = t;
    return o;
  }

  static Map<String, dynamic> _vmess(String line) {
    final raw = tryBase64(line.substring(8)) ?? '';
    final j = Map<String, dynamic>.from(jsonDecode(raw));
    String s(String k) => (j[k] ?? '').toString();
    final q = <String, String>{
      'type': s('net').isEmpty ? 'tcp' : s('net'),
      'host': s('host'),
      'path': s('path'),
      'serviceName': s('path'),
      'security': s('tls') == 'tls' ? 'tls' : 'none',
      'sni': s('sni').isNotEmpty ? s('sni') : s('host'),
      'alpn': s('alpn'),
      'fp': s('fp'),
      'allowInsecure': s('allowInsecure'),
    }..removeWhere((k, v) => v.isEmpty);
    final o = <String, dynamic>{
      'type': 'vmess',
      'tag': s('ps').isEmpty ? s('add') : s('ps'),
      'server': s('add'),
      'server_port': int.parse(s('port')),
      'uuid': s('id'),
      'security': s('scy').isEmpty ? 'auto' : s('scy'),
      'alter_id': int.tryParse(s('aid')) ?? 0,
      'packet_encoding': 'xudp',
      ..._tls(q, s('add'), defaultOn: false),
    };
    final t = _transport(q);
    if (t != null) o['transport'] = t;
    return o;
  }

  static Map<String, dynamic>? _ss(String line) {
    var body = line.substring(5);
    var name = '';
    final hashAt = body.indexOf('#');
    if (hashAt >= 0) {
      name = Uri.decodeComponent(body.substring(hashAt + 1));
      body = body.substring(0, hashAt);
    }
    String query = '';
    final qAt = body.indexOf('?');
    if (qAt >= 0) {
      query = body.substring(qAt + 1);
      body = body.substring(0, qAt);
    }
    body = body.replaceAll(RegExp(r'/$'), '');
    String method, password, host;
    int port;
    if (body.contains('@')) {
      // SIP002: base64(method:password)@host:port
      final at = body.lastIndexOf('@');
      var cred = Uri.decodeComponent(body.substring(0, at));
      if (!cred.contains(':')) cred = tryBase64(cred) ?? cred;
      final hp = body.substring(at + 1);
      final c = cred.indexOf(':');
      method = cred.substring(0, c);
      password = cred.substring(c + 1);
      final p = hp.lastIndexOf(':');
      host = hp.substring(0, p).replaceAll(RegExp(r'^\[|\]$'), '');
      port = int.parse(hp.substring(p + 1));
    } else {
      final dec = tryBase64(body);
      if (dec == null) return null;
      final at = dec.lastIndexOf('@');
      final cred = dec.substring(0, at);
      final hp = dec.substring(at + 1);
      final c = cred.indexOf(':');
      method = cred.substring(0, c);
      password = cred.substring(c + 1);
      final p = hp.lastIndexOf(':');
      host = hp.substring(0, p);
      port = int.parse(hp.substring(p + 1));
    }
    final o = <String, dynamic>{
      'type': 'shadowsocks',
      'tag': name.isEmpty ? host : name,
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
    };
    final plugin = Uri.splitQueryString(query)['plugin'];
    if (plugin != null && plugin.isNotEmpty) {
      final i = plugin.indexOf(';');
      o['plugin'] = i < 0 ? plugin : plugin.substring(0, i);
      if (i >= 0) o['plugin_opts'] = plugin.substring(i + 1);
    }
    return o;
  }

  static Map<String, dynamic> _hy2(Uri u) {
    final q = u.queryParameters;
    final o = <String, dynamic>{
      'type': 'hysteria2',
      'tag': _name(u, u.host),
      'server': u.host,
      'server_port': u.hasPort ? u.port : 443,
      'password': Uri.decodeComponent(u.userInfo),
      'tls': {
        'enabled': true,
        'server_name': q['sni'] ?? u.host,
        'insecure': _truthy(q['insecure']),
        if ((q['alpn'] ?? '').isNotEmpty) 'alpn': q['alpn']!.split(','),
      },
    };
    if ((q['obfs'] ?? '').isNotEmpty) {
      o['obfs'] = {'type': q['obfs'], 'password': q['obfs-password'] ?? ''};
    }
    final mport = q['mport'];
    if (mport != null && mport.isNotEmpty) {
      o['server_ports'] = mport.split(',').map((p) => p.replaceAll('-', ':')).toList();
    }
    return o;
  }

  static Map<String, dynamic> _tuic(Uri u) {
    final q = u.queryParameters;
    final ui = _userInfo(u);
    return {
      'type': 'tuic',
      'tag': _name(u, u.host),
      'server': u.host,
      'server_port': u.port,
      'uuid': ui.$1,
      'password': ui.$2,
      'congestion_control': q['congestion_control'] ?? 'bbr',
      'udp_relay_mode': q['udp_relay_mode'] ?? 'native',
      'tls': {
        'enabled': true,
        'server_name': q['sni'] ?? u.host,
        'insecure': _truthy(q['allow_insecure']) || _truthy(q['insecure']),
        'alpn': (q['alpn'] ?? 'h3').split(','),
      },
    };
  }

  static Map<String, dynamic> _anytls(Uri u) {
    final q = u.queryParameters;
    return {
      'type': 'anytls',
      'tag': _name(u, u.host),
      'server': u.host,
      'server_port': u.port,
      'password': Uri.decodeComponent(u.userInfo),
      ..._tls({...q, 'security': q['security'] ?? 'tls'}, u.host),
    };
  }
}
