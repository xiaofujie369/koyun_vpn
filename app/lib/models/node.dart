/// 一个代理节点 = 一个 sing-box outbound（原样保存，生成配置时直接放进 outbounds）
class ProxyNode {
  ProxyNode(this.outbound);

  final Map<String, dynamic> outbound;

  String get tag => outbound['tag'] as String;
  String get type => outbound['type'] as String;
  String get server => (outbound['server'] ?? '').toString();
  int get port => (outbound['server_port'] as num?)?.toInt() ?? 0;

  /// 去掉 "[anytls]"、"[Hy2]" 之类的协议前缀，界面更干净
  String get displayName => tag.replaceFirst(RegExp(r'^\[[^\]]{1,12}\]\s*'), '');

  /// 从名称开头的国旗 emoji 推导地区代码（🇯🇵 -> JP）
  String? get countryCode {
    final runes = displayName.runes.toList();
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      return String.fromCharCodes([runes[0] - 0x1F1E6 + 65, runes[1] - 0x1F1E6 + 65]);
    }
    return null;
  }

  /// 不含国旗的名字
  String get plainName {
    final cc = countryCode;
    if (cc == null) return displayName;
    return String.fromCharCodes(displayName.runes.skip(2)).trim();
  }

  String get flag {
    final cc = countryCode;
    if (cc == null) return '🌐';
    return String.fromCharCodes(displayName.runes.take(2));
  }

  /// 节点倍率（名称里的 "2X"、"0.5X"）
  String? get multiplier {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*[xX倍]').firstMatch(displayName);
    return m == null ? null : '${m.group(1)}x';
  }

  String get protocolLabel => switch (type) {
        'hysteria2' => 'Hy2',
        'anytls' => 'AnyTLS',
        'vless' => 'VLESS',
        'vmess' => 'VMess',
        'trojan' => 'Trojan',
        'shadowsocks' => 'SS',
        'tuic' => 'TUIC',
        'socks' => 'SOCKS',
        'http' => 'HTTP',
        _ => type.toUpperCase(),
      };

  Map<String, dynamic> toJson() => outbound;
  factory ProxyNode.fromJson(Map<String, dynamic> j) => ProxyNode(j);
}

/// 订阅附带的流量 / 到期信息（来自 subscription-userinfo 响应头）
class SubInfo {
  SubInfo({this.upload = 0, this.download = 0, this.total = 0, this.expire = 0});
  final int upload, download, total, expire;

  int get used => upload + download;
  int get remain => total > used ? total - used : 0;

  static SubInfo? parseHeader(String? h) {
    if (h == null || h.isEmpty) return null;
    final m = <String, int>{};
    for (final part in h.split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) m[kv[0].trim()] = int.tryParse(kv[1].trim()) ?? 0;
    }
    return SubInfo(
        upload: m['upload'] ?? 0,
        download: m['download'] ?? 0,
        total: m['total'] ?? 0,
        expire: m['expire'] ?? 0);
  }

  Map<String, dynamic> toJson() =>
      {'upload': upload, 'download': download, 'total': total, 'expire': expire};
  factory SubInfo.fromJson(Map<String, dynamic> j) => SubInfo(
      upload: j['upload'] ?? 0,
      download: j['download'] ?? 0,
      total: j['total'] ?? 0,
      expire: j['expire'] ?? 0);
}
