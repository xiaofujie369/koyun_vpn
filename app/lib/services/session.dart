import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/xboard_api.dart';
import '../app_config.dart';
import '../models/node.dart';
import 'net_route.dart';
import 'storage.dart';
import 'sub_parser.dart';

/// 订阅刷新结果
enum RefreshResult { ok, networkFail, unauthorized, unavailable, empty, error }

/// 账号 + 订阅状态。
///
/// 流程（对应需求 2）：
/// * 首次：登录成功 → 保存凭证 → 拉订阅。
/// * 之后每次打开：先用本地缓存的节点立即显示（离线也能连），后台自动刷新订阅；
///   手动刷新随时可点。
/// * 登录失败 / 接口全部不通：可导入文件或订阅链接。连接后再登录账号时不断线，
///   登录请求走当前节点，所以被屏蔽也能切回账号。
/// * 上次可用的节点和订阅地址一直保留，登录不上时可以切回来用。
class Session extends ChangeNotifier {
  Session(this.storage, this.api);

  final Storage storage;
  final XboardApi api;

  AccountMode mode = AccountMode.none;
  Map<String, dynamic>? user; // user/info
  Map<String, dynamic>? subscribe; // user/getSubscribe
  SubInfo? subInfo;
  List<ProxyNode> nodes = [];
  List<Map<String, dynamic>> notices = [];
  Map<String, dynamic>? guestConfig;

  bool refreshing = false;
  RefreshResult? lastResult;
  String? lastError;
  DateTime? lastRefreshAt;

  /// 订阅不可用（过期 / 流量用完 / 无套餐）
  bool get subscriptionUnavailable => lastResult == RefreshResult.unavailable;

  bool get loggedIn => mode != AccountMode.none;

  Timer? _timer;
  Map<String, dynamic>? _backup;
  bool _keepNodesIfUnavailable = false;

  Future<void> init() async {
    mode = storage.mode;
    if (mode == AccountMode.xboard && storage.authData == null) mode = AccountMode.none;
    _backup = await storage.loadLocalBackup();
    final cache = await storage.loadNodeCache();
    if (cache != null) {
      nodes = ((cache['nodes'] as List?) ?? [])
          .map((e) => ProxyNode.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (cache['sub_info'] is Map) {
        subInfo = SubInfo.fromJson(Map<String, dynamic>.from(cache['sub_info']));
      }
      if (cache['user'] is Map) user = Map<String, dynamic>.from(cache['user']);
      if (cache['subscribe'] is Map) {
        subscribe = Map<String, dynamic>.from(cache['subscribe']);
      }
    }
    if (storage.lastRefresh > 0) {
      lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(storage.lastRefresh);
    }
    notifyListeners();
    if (loggedIn) {
      // 第二次及以后打开：自动刷新订阅（不阻塞界面）
      unawaited(refresh());
    }
    _timer = Timer.periodic(const Duration(minutes: 10), (_) {
      final last = lastRefreshAt;
      if (loggedIn &&
          (last == null || DateTime.now().difference(last) > AppConfig.autoRefreshInterval)) {
        unawaited(refresh());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> loadGuestConfig() async {
    try {
      guestConfig = await api.guestConfig();
      notifyListeners();
    } catch (_) {}
    return guestConfig;
  }

  // ---------------- 登录 / 注册 ----------------

  Future<void> login(String email, String password) async {
    final auth = await api.login(email.trim(), password);
    await _onAuthed(auth, email);
  }

  Future<void> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    final auth = await api.register(
        email: email.trim(), password: password, emailCode: emailCode, inviteCode: inviteCode);
    await _onAuthed(auth, email);
  }

  Future<void> _onAuthed(String auth, String email) async {
    final wasLocal = mode == AccountMode.local;
    await storage.setAuthData(auth);
    await storage.setLastEmail(email.trim());
    mode = AccountMode.xboard;
    await storage.setMode(mode);
    notifyListeners();
    _keepNodesIfUnavailable = wasLocal;
    final r = await refresh();
    _keepNodesIfUnavailable = false;
    if (wasLocal && r == RefreshResult.unavailable) {
      // 账号套餐不可用：继续用本地节点，否则客户连续费页面都打不开
      await _enterLocal();
    }
  }

  /// 通过文件或粘贴内容导入、没有订阅地址的节点，不能联网刷新
  bool get isFileImport => mode == AccountMode.local && storage.localSubUrl == null;

  /// 导入文件内容、订阅链接、节点分享链接或 sing-box JSON
  Future<RefreshResult> importLocal(String input) async {
    final text = input.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      final oldInfo = subInfo;
      subInfo = null;
      final r = await _fetchSub(text);
      if (r.$1 != RefreshResult.ok) {
        subInfo = oldInfo;
        return r.$1;
      }
      await storage.setLocalSubUrl(text);
    } else {
      final List<ProxyNode> parsed;
      try {
        parsed = SubParser.parse(text);
      } catch (_) {
        return RefreshResult.empty; // 内容不完整或不是合法 JSON
      }
      if (parsed.isEmpty) return RefreshResult.empty;
      nodes = parsed;
      subInfo = SubParser.parseInfo(text);
      await storage.setLocalSubUrl(SubParser.parseSubUrl(text));
    }
    lastResult = null;
    await _enterLocal();
    return RefreshResult.ok;
  }

  Future<void> _enterLocal() async {
    await storage.setAuthData(null);
    user = null;
    subscribe = null;
    mode = AccountMode.local;
    await storage.setMode(mode);
    await _saveCache();
    if (lastResult != RefreshResult.unavailable) lastResult = RefreshResult.ok;
    lastRefreshAt = DateTime.now();
    await storage.setLastRefresh(lastRefreshAt!.millisecondsSinceEpoch);
    notifyListeners();
  }

  // ---------------- 备用订阅 ----------------

  int get backupNodeCount => (_backup?['nodes'] as List?)?.length ?? 0;

  /// 切回保存的节点和订阅地址，能联网时顺便更新
  Future<void> useBackup() async {
    final b = _backup;
    if (b == null) return;
    nodes = ((b['nodes'] as List?) ?? [])
        .map((e) => ProxyNode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    subInfo = b['sub_info'] is Map ? SubInfo.fromJson(Map<String, dynamic>.from(b['sub_info'])) : null;
    await storage.setLocalSubUrl(b['url'] as String?);
    lastResult = null;
    await _enterLocal();
    if (storage.localSubUrl != null) unawaited(refresh());
  }

  Future<void> clearBackup() async {
    _backup = null;
    await storage.clearLocalBackup();
    notifyListeners();
  }

  Future<void> logout() async {
    await storage.clearAccount();
    mode = AccountMode.none;
    user = null;
    subscribe = null;
    subInfo = null;
    nodes = [];
    notices = [];
    lastResult = null;
    notifyListeners();
  }

  // ---------------- 刷新 ----------------

  Future<RefreshResult> refresh() async {
    if (refreshing) return lastResult ?? RefreshResult.ok;
    refreshing = true;
    lastError = null;
    notifyListeners();
    RefreshResult result;
    try {
      result = switch (mode) {
        AccountMode.xboard => await _refreshXboard(),
        AccountMode.local => await _refreshLocal(),
        AccountMode.none => RefreshResult.ok,
      };
    } catch (e) {
      lastError = e.toString();
      result = RefreshResult.error;
    }
    lastResult = result;
    refreshing = false;
    if (result == RefreshResult.ok) {
      lastRefreshAt = DateTime.now();
      await storage.setLastRefresh(lastRefreshAt!.millisecondsSinceEpoch);
    }
    notifyListeners();
    return result;
  }

  Future<RefreshResult> _refreshLocal() async {
    final url = storage.localSubUrl;
    if (url == null) return RefreshResult.ok; // 手动粘贴的节点，无需刷新
    final r = await _fetchSub(url);
    if (r.$1 == RefreshResult.ok) await _saveCache();
    return r.$1;
  }

  Future<RefreshResult> _refreshXboard() async {
    try {
      subscribe = await api.getSubscribe();
      unawaited(_loadExtras());
    } on ApiError catch (e) {
      lastError = e.message;
      if (e.isUnauthorized) {
        // 登录失效：回到登录页，但保留缓存节点，防止客户"突然没网"
        await storage.setAuthData(null);
        mode = AccountMode.none;
        await storage.setMode(mode);
        return RefreshResult.unauthorized;
      }
      if (e.isNetwork) {
        // 面板接口不通，但订阅域名可能是通的：用上次保存的订阅地址再试
        final saved = storage.subscribeUrl;
        if (saved != null) {
          final r = await _fetchSub(_withFlag(saved));
          if (r.$1 == RefreshResult.ok) {
            await _saveCache();
            return RefreshResult.ok;
          }
        }
        return RefreshResult.networkFail;
      }
      return RefreshResult.error;
    }

    final subUrl = subscribe?['subscribe_url'] as String?;
    final token = subscribe?['token'] as String?;
    await storage.setSubscribeUrl(subUrl);

    // 先用官方订阅域名，不通再用接口域名兜底
    final candidates = <String>[
      if (subUrl != null && subUrl.isNotEmpty) _withFlag(subUrl),
      if (token != null)
        for (final h in api.hostOrder) _withFlag(api.fallbackSubscribeUrl(token, h)),
    ];
    var result = RefreshResult.networkFail;
    for (final u in candidates) {
      final r = await _fetchSub(u);
      result = r.$1;
      if (result == RefreshResult.ok || result == RefreshResult.unavailable) break;
    }
    if (result == RefreshResult.unavailable && !_keepNodesIfUnavailable) {
      nodes = [];
    }
    if (result == RefreshResult.ok || result == RefreshResult.unavailable) {
      await _saveCache();
    }
    return result;
  }

  Future<void> _loadExtras() async {
    try {
      user = await api.userInfo();
      notifyListeners();
    } catch (_) {}
    try {
      notices = await api.notices();
      notifyListeners();
    } catch (_) {}
  }

  static String _withFlag(String url) {
    final u = Uri.parse(url);
    return u.replace(queryParameters: {...u.queryParameters, 'flag': 'sing-box'}).toString();
  }

  final _subDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 25),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
    headers: {'User-Agent': AppConfig.subscribeUserAgent},
  ))
    ..httpClientAdapter = RoutedAdapter();

  Future<(RefreshResult, String?)> _fetchSub(String url) async {
    Response<String> res;
    try {
      res = await _subDio.get<String>(url, options: Options(headers: {'Referer': url}));
    } catch (e) {
      lastError = e.toString();
      return (RefreshResult.networkFail, null);
    }
    final code = res.statusCode ?? 0;
    if (code == 403 || code == 401) {
      // Xboard：套餐过期 / 流量用完 / 被封禁时订阅返回 403，内容是 JSON。
      // Cloudflare 等拦截也是 403，但内容是网页。不能当成套餐不可用，否则节点会被清空、断开连接
      if (_isPanelJson(res.data)) return (RefreshResult.unavailable, null);
      lastError = 'HTTP $code';
      return (RefreshResult.networkFail, null);
    }
    if (code != 200 || res.data == null) {
      lastError = 'HTTP $code';
      return (RefreshResult.networkFail, null);
    }
    final List<ProxyNode> parsed;
    try {
      parsed = SubParser.parse(res.data!);
    } catch (_) {
      return (RefreshResult.empty, null);
    }
    final info = SubInfo.parseHeader(res.headers.value('subscription-userinfo'));
    if (info != null) subInfo = info;
    if (parsed.isEmpty) return (RefreshResult.empty, null);
    nodes = parsed;
    return (RefreshResult.ok, null);
  }

  static bool _isPanelJson(String? body) {
    try {
      return jsonDecode(body ?? '') is Map;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveBackup() async {
    final url = mode == AccountMode.local
        ? storage.localSubUrl
        : (storage.subscribeUrl == null ? null : _withFlag(storage.subscribeUrl!));
    _backup = {
      if (url != null) 'url': url,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      if (subInfo != null) 'sub_info': subInfo!.toJson(),
    };
    await storage.saveLocalBackup(_backup!);
  }

  Future<void> _saveCache() async {
    if (nodes.isNotEmpty) await _saveBackup();
    await storage.saveNodeCache({
      'nodes': nodes.map((n) => n.toJson()).toList(),
      if (subInfo != null) 'sub_info': subInfo!.toJson(),
      if (user != null) 'user': user,
      if (subscribe != null)
        'subscribe': Map.of(subscribe!)..remove('token')..remove('subscribe_url'),
    });
  }

  // ---------------- 展示用 ----------------

  String? get email => subscribe?['email'] as String? ?? user?['email'] as String?;
  String? get planName => (subscribe?['plan'] as Map?)?['name'] as String?;

  int get usedBytes {
    if (subscribe != null) {
      return ((subscribe!['u'] as num?) ?? 0).toInt() + ((subscribe!['d'] as num?) ?? 0).toInt();
    }
    return subInfo?.used ?? 0;
  }

  int get totalBytes =>
      ((subscribe?['transfer_enable'] as num?)?.toInt()) ?? subInfo?.total ?? 0;

  /// 到期时间（秒级时间戳，0 = 长期有效）
  int get expireAt => ((subscribe?['expired_at'] as num?)?.toInt()) ?? subInfo?.expire ?? 0;

  int? get resetDay => (subscribe?['reset_day'] as num?)?.toInt();

  double get balance => (((user?['balance'] as num?) ?? 0) / 100).toDouble();
}
