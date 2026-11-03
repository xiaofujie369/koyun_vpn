import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 账号模式：Xboard 账号登录 / 本地导入订阅
enum AccountMode { none, xboard, local }

/// 分流模式（通过 Clash API 的 mode 实时切换，不用重启内核）
enum RouteMode { rule, global, direct }

/// 本地持久化（轻量设置放 SharedPreferences，节点缓存放文件）
class Storage {
  late SharedPreferences _p;
  late Directory dataDir;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    dataDir = Directory('${(await getApplicationSupportDirectory()).path}/koyun');
    await dataDir.create(recursive: true);
  }

  /// 仅供自动化测试使用：不依赖系统目录
  Future<void> initForTest(Directory dir) async {
    _p = await SharedPreferences.getInstance();
    dataDir = dir;
  }

  /// 匿名设备编号（统计用，随机生成，和账号无关）
  String? get deviceId => _p.getString('device_id');
  Future<void> setDeviceId(String v) => _p.setString('device_id', v);

  /// 上次查到的本机 IP 信息（JSON），启动时先显示
  String? get lastLocalIp => _p.getString('last_local_ip');
  Future<void> setLastLocalIp(String v) => _p.setString('last_local_ip', v);

  /// 上次成功获取的引导配置原文（已签名加密的 boot.json）
  String? get bootDoc => _p.getString('boot_doc');
  Future<void> setBootDoc(String v) => _p.setString('boot_doc', v);

  // ---- 账号 ----
  AccountMode get mode =>
      AccountMode.values.firstWhere((m) => m.name == _p.getString('mode'),
          orElse: () => AccountMode.none);
  Future<void> setMode(AccountMode m) => _p.setString('mode', m.name);

  String? get authData => _p.getString('auth');
  Future<void> setAuthData(String? v) =>
      v == null ? _p.remove('auth') : _p.setString('auth', v);

  String? get lastEmail => _p.getString('last_email');
  Future<void> setLastEmail(String v) => _p.setString('last_email', v);

  String? get preferredApiHost => _p.getString('api_host');
  Future<void> setPreferredApiHost(String v) => _p.setString('api_host', v);

  /// Xboard 订阅 token / 地址（用于被墙时兜底和离线时展示）
  String? get subscribeUrl => _p.getString('sub_url');
  Future<void> setSubscribeUrl(String? v) =>
      v == null ? _p.remove('sub_url') : _p.setString('sub_url', v);
  String? get subscribeToken => _p.getString('sub_token');
  Future<void> setSubscribeToken(String? v) =>
      v == null ? _p.remove('sub_token') : _p.setString('sub_token', v);

  /// 本地导入模式的订阅链接
  String? get localSubUrl => _p.getString('local_sub_url');
  Future<void> setLocalSubUrl(String? v) =>
      v == null ? _p.remove('local_sub_url') : _p.setString('local_sub_url', v);

  // ---- 节点 ----
  String? get selectedNode => _p.getString('selected_node');
  Future<void> setSelectedNode(String? v) =>
      v == null ? _p.remove('selected_node') : _p.setString('selected_node', v);

  int get lastRefresh => _p.getInt('last_refresh') ?? 0;
  Future<void> setLastRefresh(int v) => _p.setInt('last_refresh', v);

  File get _nodesFile => File('${dataDir.path}/nodes.json');

  Future<Map<String, dynamic>?> loadNodeCache() async {
    try {
      if (!await _nodesFile.exists()) return null;
      return jsonDecode(await _nodesFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNodeCache(Map<String, dynamic> v) async {
    final tmp = File('${_nodesFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(v), flush: true);
    await tmp.rename(_nodesFile.path); // 原子替换，防止写一半断电损坏
  }

  Future<void> clearNodeCache() async {
    if (await _nodesFile.exists()) await _nodesFile.delete();
  }

  // ---- 设置 ----
  RouteMode get routeMode =>
      RouteMode.values.firstWhere((m) => m.name == _p.getString('route_mode'),
          orElse: () => RouteMode.rule);
  Future<void> setRouteMode(RouteMode m) => _p.setString('route_mode', m.name);

  /// 桌面端是否启用 TUN（虚拟网卡）模式；移动端始终是 VPN 模式
  bool get tunMode => _p.getBool('tun') ?? false;
  Future<void> setTunMode(bool v) => _p.setBool('tun', v);

  bool get ipv6 => _p.getBool('ipv6') ?? false;
  Future<void> setIpv6(bool v) => _p.setBool('ipv6', v);

  bool get autoConnect => _p.getBool('auto_connect') ?? false;
  Future<void> setAutoConnect(bool v) => _p.setBool('auto_connect', v);

  /// 界面语言："" 表示跟随系统
  String get localeOverride => _p.getString('locale') ?? '';
  Future<void> setLocaleOverride(String v) => _p.setString('locale', v);

  /// 上次是否处于连接状态（用于异常退出后清理系统代理）
  bool get wasConnected => _p.getBool('was_connected') ?? false;
  Future<void> setWasConnected(bool v) => _p.setBool('was_connected', v);

  int get mixedPort => _p.getInt('mixed_port') ?? 0;
  Future<void> setMixedPort(int v) => _p.setInt('mixed_port', v);

  Future<void> clearAccount() async {
    await setAuthData(null);
    await setSubscribeUrl(null);
    await setSubscribeToken(null);
    await setLocalSubUrl(null);
    await setSelectedNode(null);
    await _p.remove('last_refresh');
    await setMode(AccountMode.none);
    await clearNodeCache();
  }
}
