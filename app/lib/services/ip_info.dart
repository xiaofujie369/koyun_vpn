import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/core_backend.dart';
import '../core/core_service.dart';

/// IP 信息（接口 https://my.ippure.com/v1/info 只取需要的字段）
class IpInfo {
  IpInfo({
    required this.ip,
    this.countryCode = '',
    this.country = '',
    this.region = '',
    this.city = '',
    this.asn = 0,
    this.org = '',
    this.fraudScore,
    this.residential,
    this.broadcast,
  });

  final String ip, countryCode, country, region, city, org;
  final int asn;
  final int? fraudScore; // 0~100，越高越可能被网站判定为风险
  final bool? residential; // 住宅 IP（否 = 机房）
  final bool? broadcast; // 广播 IP（否 = 原生）

  factory IpInfo.fromJson(Map<String, dynamic> j) => IpInfo(
        ip: (j['ip'] ?? '').toString(),
        countryCode: (j['countryCode'] ?? '').toString().toUpperCase(),
        country: (j['country'] ?? '').toString(),
        region: (j['region'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        asn: (j['asn'] as num?)?.toInt() ?? 0,
        org: (j['asOrganization'] ?? '').toString(),
        fraudScore: (j['fraudScore'] as num?)?.toInt(),
        residential: j['isResidential'] as bool?,
        broadcast: j['isBroadcast'] as bool?,
      );

  /// 读取自己保存的缓存（toJson 的格式）
  factory IpInfo.fromCache(Map<String, dynamic> j) => IpInfo(
        ip: (j['ip'] ?? '').toString(),
        countryCode: (j['country_code'] ?? '').toString(),
        country: (j['country'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        asn: (j['asn'] as num?)?.toInt() ?? 0,
        org: (j['org'] ?? '').toString(),
        fraudScore: (j['fraud_score'] as num?)?.toInt(),
        residential: j['residential'] as bool?,
        broadcast: j['broadcast'] as bool?,
      );

  /// 国内接口 myip.ipip.net 的结果：{"ret":"ok","data":{"ip":"..","location":["中国","上海","上海","","电信"]}}
  /// 只有 IP / 位置 / 运营商，没有风险值等信息
  factory IpInfo.fromIpip(Map<String, dynamic> j) {
    final d = (j['data'] as Map?) ?? const {};
    final loc = ((d['location'] as List?) ?? const []).map((e) => e.toString()).toList();
    String at(int i) => i < loc.length ? loc[i] : '';
    final country = at(0);
    final city = at(2).isNotEmpty ? at(2) : at(1);
    return IpInfo(
      ip: (d['ip'] ?? '').toString(),
      countryCode: _zhCountry.entries.where((e) => e.value == country).map((e) => e.key).firstOrNull ?? '',
      country: country,
      city: city == country ? '' : city,
      org: at(4),
    );
  }

  /// 是否有完整信息（风险值 / 住宅等），国内接口的结果没有
  bool get detailed => fraudScore != null || residential != null;

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'country_code': countryCode,
        'country': country,
        'city': city,
        'asn': asn,
        'org': org,
        'fraud_score': fraudScore,
        'residential': residential,
        'broadcast': broadcast,
      };

  /// 隐藏中间部分：123.45.*.* / 2001:db8:*
  String get masked {
    if (ip.contains('.')) {
      final p = ip.split('.');
      return p.length == 4 ? '${p[0]}.${p[1]}.*.*' : ip;
    }
    final p = ip.split(':');
    return p.length > 2 ? '${p[0]}:${p[1]}:****' : ip;
  }
}

/// 本机 IP / 代理出口 IP。
/// * 本机：未连接时直接请求；连接后（TUN 模式会接管 App 自己的流量）保留连接前的结果。
/// * 代理出口：连接成功、切换节点后，通过内核的本地代理端口请求（电脑端系统代理模式下
///   App 自己的请求默认不走代理，所以要显式指定）；手机端 VPN 会接管所有流量，直接请求即可。
class IpService extends ChangeNotifier {
  IpService(this.core) {
    core.addListener(_onCore);
  }

  static const url = 'https://my.ippure.com/v1/info';

  final CoreService core;
  IpInfo? local, proxy;
  bool loadingLocal = false, loadingProxy = false;
  bool localFailed = false, proxyFailed = false;
  bool showFull = false;
  bool localCached = false; // 当前显示的是上次保存的结果（正在刷新）

  CoreStatus? _lastStatus;
  String? _lastSelected;
  Timer? _debounce;

  void toggleShowFull() {
    showFull = !showFull;
    notifyListeners();
  }

  /// App 启动时调用
  void start() {
    // 先显示上次保存的本机 IP，后台再刷新
    try {
      final c = core.storage.lastLocalIp;
      if (c != null && local == null) {
        local = IpInfo.fromCache((jsonDecode(c) as Map).cast<String, dynamic>());
        localCached = true;
      }
    } catch (_) {}
    _lastStatus = core.status;
    _lastSelected = core.selected;
    refreshLocal();
    if (core.running) _scheduleProxy();
  }

  void _onCore() {
    final st = core.status;
    if (st != _lastStatus) {
      final was = _lastStatus;
      _lastStatus = st;
      if (st == CoreStatus.running) {
        _scheduleProxy();
      } else if (st == CoreStatus.stopped && was != null) {
        proxy = null;
        proxyFailed = false;
        _debounce?.cancel();
        notifyListeners();
        // 断开后系统网络恢复需要一点时间
        Future.delayed(const Duration(milliseconds: 800), refreshLocal);
      }
    }
    if (core.selected != _lastSelected) {
      _lastSelected = core.selected;
      if (core.running) _scheduleProxy();
    }
  }

  void _scheduleProxy() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), refreshProxy);
  }

  int _localRetry = 0;
  Timer? _retryTimer;

  /// 查询本机 IP：同时请求国内接口（快，国内必通）和 ippure（信息全，但国内直连可能慢），
  /// 谁先回来先显示谁；ippure 的完整结果回来后再更新。都失败则自动重试。
  Future<void> refreshLocal() async {
    // TUN 模式 / 手机 VPN 连接中：直接请求也会走代理，测不出本机 IP，保留连接前的结果
    if (core.running && (core.isMobile || core.storage.tunMode)) return;
    if (loadingLocal) return;
    _retryTimer?.cancel();
    loadingLocal = true;
    localFailed = false;
    notifyListeners();

    var gotFull = false;
    var gotAny = false;
    final full = _fetch().then((i) {
      gotFull = gotAny = true;
      _setLocal(i);
    }).catchError((_) {});
    final fast = _fetchIpip().then((i) {
      // ippure 已经先回来了就不用国内接口的简略结果
      if (!gotFull) {
        gotAny = true;
        _setLocal(i);
      }
    }).catchError((_) {});
    await Future.wait([full, fast]);

    loadingLocal = false;
    localFailed = !gotAny;
    if (gotAny) {
      _localRetry = 0;
    } else if (_localRetry < 3) {
      // 网络刚切换 / 接口偶尔不通：5 秒、15 秒、30 秒后再试
      final wait = const [5, 15, 30][_localRetry++];
      _retryTimer = Timer(Duration(seconds: wait), refreshLocal);
    }
    notifyListeners();
  }

  void _setLocal(IpInfo i) {
    // 同一个 IP 已经有完整信息时，不用简略结果覆盖
    if (!i.detailed && local != null && local!.ip == i.ip && local!.detailed) return;
    local = i;
    localCached = false;
    notifyListeners();
    unawaited(core.storage.setLastLocalIp(jsonEncode(i.toJson())));
  }

  Future<void> refreshProxy() async {
    if (!core.running || loadingProxy) return;
    loadingProxy = true;
    proxyFailed = false;
    notifyListeners();
    try {
      final port = core.isMobile ? null : core.mixedPort;
      proxy = await _fetch(proxyPort: port);
    } catch (_) {
      proxyFailed = true;
    }
    loadingProxy = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await Future.wait([refreshLocal(), refreshProxy()]);
  }

  static Future<IpInfo> _fetchIpip() async {
    final dio = _dio(null);
    try {
      final r = await dio.get<Map<String, dynamic>>('https://myip.ipip.net/json');
      final info = IpInfo.fromIpip(r.data!);
      if (info.ip.isEmpty) throw Exception('empty');
      return info;
    } finally {
      dio.close(force: true);
    }
  }

  static Dio _dio(int? proxyPort) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final c = HttpClient();
      // 不走系统代理设置，由我们明确指定
      c.findProxy = (_) => proxyPort == null ? 'DIRECT' : 'PROXY 127.0.0.1:$proxyPort';
      return c;
    });
    return dio;
  }

  static Future<IpInfo> _fetch({int? proxyPort}) async {
    final dio = _dio(proxyPort);
    try {
      final r = await dio.get<Map<String, dynamic>>(url);
      final info = IpInfo.fromJson(r.data!);
      if (info.ip.isEmpty) throw Exception('empty');
      return info;
    } finally {
      dio.close(force: true);
    }
  }

  @override
  void dispose() {
    core.removeListener(_onCore);
    _debounce?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// 国家代码 → 中文名（常用地区；其它地区显示接口返回的英文名）
const _zhCountry = {
  'CN': '中国', 'HK': '香港', 'TW': '台湾', 'MO': '澳门', 'JP': '日本', 'KR': '韩国', 'SG': '新加坡',
  'US': '美国', 'CA': '加拿大', 'GB': '英国', 'DE': '德国', 'FR': '法国', 'NL': '荷兰', 'IT': '意大利',
  'ES': '西班牙', 'RU': '俄罗斯', 'UA': '乌克兰', 'TR': '土耳其', 'IN': '印度', 'TH': '泰国', 'VN': '越南',
  'MY': '马来西亚', 'ID': '印度尼西亚', 'PH': '菲律宾', 'AU': '澳大利亚', 'NZ': '新西兰', 'BR': '巴西',
  'AR': '阿根廷', 'MX': '墨西哥', 'CL': '智利', 'AE': '阿联酋', 'SA': '沙特阿拉伯', 'IL': '以色列',
  'SE': '瑞典', 'NO': '挪威', 'FI': '芬兰', 'DK': '丹麦', 'CH': '瑞士', 'AT': '奥地利', 'BE': '比利时',
  'PL': '波兰', 'CZ': '捷克', 'IE': '爱尔兰', 'PT': '葡萄牙', 'GR': '希腊', 'HU': '匈牙利', 'RO': '罗马尼亚',
  'BG': '保加利亚', 'LU': '卢森堡', 'IS': '冰岛', 'EE': '爱沙尼亚', 'LV': '拉脱维亚', 'LT': '立陶宛',
  'KZ': '哈萨克斯坦', 'MN': '蒙古', 'KH': '柬埔寨', 'LA': '老挝', 'MM': '缅甸', 'BD': '孟加拉国',
  'PK': '巴基斯坦', 'EG': '埃及', 'ZA': '南非', 'NG': '尼日利亚', 'KE': '肯尼亚',
};

/// 简体 → 繁体（只列出上面国家名里用到且写法不同的字）
const _toHant = {
  '国': '國', '湾': '灣', '门': '門', '韩': '韓', '兰': '蘭', '罗': '羅', '乌': '烏', '亚': '亞', '马': '馬',
  '联': '聯', '尔': '爾', '麦': '麥', '爱': '愛', '腊': '臘', '岛': '島', '维': '維', '萨': '薩', '缅': '緬',
  '宾': '賓', '卢': '盧', '脱': '脫', '挝': '撾',
};

/// 按语言显示国家名
String countryName(IpInfo i, String languageCode, {bool hant = false}) {
  if (languageCode != 'zh') {
    final ascii = i.country.codeUnits.every((c) => c < 128);
    return (i.country.isEmpty || !ascii) ? i.countryCode : i.country;
  }
  final zh = _zhCountry[i.countryCode];
  if (zh == null) return i.country.isEmpty ? i.countryCode : i.country;
  if (!hant) return zh;
  return zh.split('').map((c) => _toHant[c] ?? c).join();
}

/// 地区代码 → 显示名（中文界面显示中文；其它语言显示代码，旁边有国旗）
String regionName(String code, String languageCode, {bool hant = false}) {
  if (languageCode != 'zh') return code;
  final zh = _zhCountry[code];
  if (zh == null) return code;
  return hant ? zh.split('').map((c) => _toHant[c] ?? c).join() : zh;
}
