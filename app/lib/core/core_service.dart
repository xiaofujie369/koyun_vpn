import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../models/node.dart';
import '../services/reporter.dart';
import '../services/session.dart';
import '../services/storage.dart';
import 'clash_api.dart';
import 'config_builder.dart';
import 'core_backend.dart';
import 'desktop_backend.dart';
import 'mobile_backend.dart';

/// 连接控制：生成配置 → 启动内核 → 通过 Clash API 切节点 / 测速 / 读网速。
class CoreService extends ChangeNotifier {
  CoreService(this.storage, this.session) : _workDir = storage.dataDir.path {
    backend = CoreBackend.create(_workDir);
    backend.externalStatus.listen((s) {
      if (s == CoreStatus.stopped && status != CoreStatus.stopped && status != CoreStatus.stopping) {
        _onStopped();
        lastError ??= 'disconnected';
        notifyListeners();
      } else if (s == CoreStatus.running && status != CoreStatus.running) {
        // 移动端：从系统设置 / 快捷开关启动后，App 重新打开时同步状态
        status = CoreStatus.running;
        _afterStart();
      }
    });
    session.addListener(_onSessionChanged);
  }

  final Storage storage;
  final Session session;
  late final CoreBackend backend;

  CoreStatus status = CoreStatus.stopped;
  String? lastError;
  bool needAdmin = false;

  String selected = 'auto';
  String? autoNow; // 自动选择当前实际使用的节点
  final Map<String, int> delays = {}; // tag -> ms（-1 失败）
  bool testing = false;

  int upSpeed = 0, downSpeed = 0;
  int upTotal = 0, downTotal = 0;
  DateTime? connectedAt;
  int? mixedPort; // 电脑端本地代理端口（查询代理出口 IP 用）

  ClashApi? _api;
  StreamSubscription? _trafficSub;
  Timer? _pollTimer;
  String _lastNodesSig = '';
  bool get isMobile => Platform.isAndroid || Platform.isIOS;
  bool get running => status == CoreStatus.running;
  bool get busy => status == CoreStatus.starting || status == CoreStatus.stopping;

  /// 内核工作目录。iOS 上必须放在 App Group 共享目录，VPN 扩展进程才能读到规则文件
  String _workDir;
  String get _ruleDir => '$_workDir/rules';

  Future<void> init() async {
    selected = storage.selectedNode ?? 'auto';
    if (Platform.isIOS) {
      final shared = await (backend as MobileBackend).sharedDir();
      if (shared != null) _workDir = shared;
    }
    await _installRuleSets();
    await backend.cleanupStale();
    _lastNodesSig = _sig(session.nodes);
    if (isMobile && await backend.isRunning()) {
      // App 被系统杀掉但 VPN 还在运行：读回上次的 Clash API 端口
      try {
        final j = jsonDecode(await File('$_workDir/api.json').readAsString());
        _api = ClashApi(j['port'], j['secret']);
        status = CoreStatus.running;
        connectedAt = DateTime.now();
        _afterStart();
      } catch (_) {}
    }
    notifyListeners();
    if (storage.autoConnect && session.loggedIn && session.nodes.isNotEmpty && !running) {
      unawaited(connect());
    }
  }

  /// 把内置的分流规则释放到数据目录（内核需要文件路径）
  Future<void> _installRuleSets() async {
    await Directory(_ruleDir).create(recursive: true);
    for (final name in ['geosite-cn.srs', 'geoip-cn.srs', 'geosite-geolocation-notcn.srs']) {
      final f = File('$_ruleDir/$name');
      final data = await rootBundle.load('assets/rules/$name');
      final bytes = data.buffer.asUint8List();
      if (!await f.exists() || await f.length() != bytes.length) {
        await f.writeAsBytes(bytes, flush: true);
      }
    }
  }

  String _sig(List<ProxyNode> nodes) =>
      nodes.map((n) => jsonEncode(n.outbound)).join('|').hashCode.toString();

  /// 订阅刷新后节点有变化，且正在连接 → 自动热重载，客户无感
  void _onSessionChanged() {
    final sig = _sig(session.nodes);
    if (sig == _lastNodesSig) return;
    _lastNodesSig = sig;
    delays.clear();
    if (running && session.nodes.isNotEmpty) {
      unawaited(connect());
    } else if (running && session.nodes.isEmpty) {
      unawaited(disconnect());
    }
    if (!session.loggedIn && running) unawaited(disconnect());
    notifyListeners();
  }

  static Future<int> _freePort(int from) async {
    for (var p = from; p < from + 200; p++) {
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
        await s.close();
        return p;
      } catch (_) {}
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static String _randomHex(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<void> connect() async {
    if (session.nodes.isEmpty) {
      lastError = 'no nodes';
      notifyListeners();
      return;
    }
    _stopTester();
    final wasRunning = running;
    final t0 = DateTime.now();
    status = CoreStatus.starting;
    lastError = null;
    needAdmin = false;
    notifyListeners();
    try {
      final tun = isMobile || storage.tunMode;
      final clashPort = await _freePort(isMobile ? 29090 : 19090);
      final secret = _randomHex(32);
      final mixedPort = isMobile ? 0 : await _freePort(AppConfig.defaultMixedPort);
      final cfg = ConfigBuilder.build(CoreOptions(
        nodes: session.nodes,
        selected: selected,
        ruleSetDir: _ruleDir,
        workDir: _workDir,
        clashPort: clashPort,
        clashSecret: secret,
        tun: tun,
        mixedPort: isMobile ? null : mixedPort,
        routeMode: storage.routeMode,
        ipv6: storage.ipv6,
        mobile: isMobile,
        logLevel: kDebugMode ? 'info' : 'warn',
      ));
      await _stopWatchers();
      await backend.start(jsonEncode(cfg), tun: tun, mixedPort: mixedPort);
      _api = ClashApi(clashPort, secret);
      await File('$_workDir/api.json').writeAsString(jsonEncode({'port': clashPort, 'secret': secret}));
      // 等内核就绪（最多 15 秒）
      var ok = false;
      for (var i = 0; i < 60; i++) {
        if (await _api!.ping()) {
          ok = true;
          break;
        }
        final b = backend;
        if (b is MobileBackend && b.lastStatus == 'stopped' && b.lastError != null) {
          throw CoreStartException(b.lastError!);
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (!ok) {
        final logs = backend.recentLogs;
        await backend.stop();
        throw CoreStartException(logs.isEmpty ? 'core not responding' : logs.last);
      }
      this.mixedPort = isMobile ? null : mixedPort;
      status = CoreStatus.running;
      if (!wasRunning) connectedAt = DateTime.now();
      Reporter.instance.event('connect_ok', {
        ..._connInfo(),
        'ms': DateTime.now().difference(t0).inMilliseconds,
      });
      await storage.setWasConnected(true);
      _afterStart();
    } on CoreStartException catch (e) {
      needAdmin = e.needAdmin;
      lastError = e.message;
      _onStopped();
      if (!e.needAdmin) Reporter.instance.event('connect_fail', {..._connInfo(), 'error': e.message});
    } catch (e) {
      lastError = e.toString();
      _onStopped();
      Reporter.instance.event('connect_fail', {..._connInfo(), 'error': lastError});
    }
    notifyListeners();
  }

  void _afterStart() {
    final api = _api;
    if (api == null) return;
    // 内核缓存里可能记着旧选择，以 App 为准再同步一次
    unawaited(api.select('proxy', selected).catchError((_) {}));
    unawaited(api.setMode(ConfigBuilder.clashMode(storage.routeMode)).catchError((_) {}));
    _trafficSub?.cancel();
    _trafficSub = api.traffic().listen((t) {
      upSpeed = t.$1;
      downSpeed = t.$2;
      notifyListeners();
    }, onError: (_) {}, cancelOnError: true);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final t = await api.totals();
        upTotal = t.$1;
        downTotal = t.$2;
        autoNow = await api.now('auto');
        notifyListeners();
      } catch (_) {}
    });
    notifyListeners();
  }

  Future<void> _stopWatchers() async {
    await _trafficSub?.cancel();
    _trafficSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _onStopped() {
    status = CoreStatus.stopped;
    mixedPort = null;
    upSpeed = downSpeed = 0;
    connectedAt = null;
    _stopWatchers();
    _api?.close();
    _api = null;
  }

  /// 上报用的连接信息（节点名、协议、模式）
  Map<String, dynamic> _connInfo() {
    final n = currentNode;
    return {
      'node': selected == 'auto' ? 'auto${n == null ? '' : ':${n.tag}'}' : selected,
      'protocol': n?.type,
      'tun': isMobile || storage.tunMode,
      'route': storage.routeMode.name,
    };
  }

  Future<void> disconnect() async {
    _stopTester();
    if (running && connectedAt != null) {
      Reporter.instance.event('disconnect', {
        ..._connInfo(),
        'duration_s': DateTime.now().difference(connectedAt!).inSeconds,
        'up_bytes': upTotal,
        'down_bytes': downTotal,
      });
    }
    status = CoreStatus.stopping;
    notifyListeners();
    await _stopWatchers();
    try {
      await backend.stop();
    } catch (_) {}
    await storage.setWasConnected(false);
    _onStopped();
    notifyListeners();
  }

  Future<void> toggle() => running ? disconnect() : connect();

  Future<void> selectNode(String tag) async {
    selected = tag;
    await storage.setSelectedNode(tag);
    notifyListeners();
    final api = _api;
    if (running && api != null) {
      try {
        await api.select('proxy', tag);
        await api.closeAllConnections();
      } catch (_) {}
    }
  }

  Future<void> setRouteMode(RouteMode m) async {
    await storage.setRouteMode(m);
    notifyListeners();
    final api = _api;
    if (running && api != null) {
      try {
        await api.setMode(ConfigBuilder.clashMode(m));
        await api.closeAllConnections();
      } catch (_) {}
    }
  }

  Future<void> setTunMode(bool v) async {
    await storage.setTunMode(v);
    notifyListeners();
    if (running) await connect();
  }

  /// 测速：已连接时测真实延迟（经代理访问测速地址）；
  /// 未连接时测 TCP 握手延迟（UDP 协议节点无法测，显示"-"）。
  Process? _tester; // 未连接时临时启动的测速内核

  /// 测速。
  /// * 已连接：通过内核测真实延迟（所有协议都支持）。
  /// * 未连接（电脑端）：临时在后台启动一个只用来测速的内核，测完立即关闭。
  ///   这样 Hysteria2 / TUIC 这类基于 UDP 的协议也能测出延迟（以前只能 TCP 测，UDP 协议显示"-"）。
  /// * 未连接（手机端）或临时内核启动失败：退回 TCP 连接测速。
  /// 正在测速的节点（界面上对应节点显示转圈）
  final Set<String> testingTags = {};

  Future<void> testAll() => _test([...session.nodes]);

  /// 单独重测一个节点。正在测速时不忽略，而是排队，当前这轮测完接着测
  final List<ProxyNode> _queue = [];
  Future<void> testOne(ProxyNode n) async {
    if (testingTags.contains(n.tag)) return;
    if (testing) {
      _queue.add(n);
      testingTags.add(n.tag); // 立刻转圈，让用户知道已经点上了
      notifyListeners();
      return;
    }
    await _test([n]);
  }

  Future<void> _test(List<ProxyNode> list) async {
    if (testing || list.isEmpty) return;
    testing = true;
    _queue.removeWhere((q) => list.any((n) => n.tag == q.tag));
    testingTags.addAll(list.map((n) => n.tag));
    notifyListeners();
    ClashApi? api = running ? _api : null;
    var temp = false;
    if (api == null && !isMobile && backend is DesktopBackend) {
      api = await _startTester(list);
      temp = api != null;
    }
    const parallel = 8;
    try {
      for (var i = 0; i < list.length; i += parallel) {
        final batch = list.skip(i).take(parallel);
        await Future.wait(batch.map((n) async {
          final a = api;
          final d = a != null ? await a.delay(n.tag, AppConfig.delayTestUrl) : await _tcpPing(n);
          delays[n.tag] = d;
          testingTags.remove(n.tag);
          notifyListeners();
        }));
        if (temp && _tester == null) break; // 测速中途用户点了连接
      }
    } finally {
      if (temp) {
        api?.close();
        _stopTester();
      }
      testing = false;
      testingTags.removeAll(list.map((n) => n.tag));
      notifyListeners();
    }
    // 测速期间用户又点了别的节点：接着测
    if (_queue.isNotEmpty) {
      final next = [..._queue];
      _queue.clear();
      testingTags.removeAll(next.map((n) => n.tag));
      await _test(next);
    }
  }

  Future<ClashApi?> _startTester(List<ProxyNode> nodes) async {
    try {
      final port = await _freePort(19190);
      final secret = _randomHex(16);
      final cfg = ConfigBuilder.build(CoreOptions(
        nodes: nodes,
        selected: 'auto',
        ruleSetDir: _ruleDir,
        workDir: _workDir,
        clashPort: port,
        clashSecret: secret,
        routeMode: RouteMode.global,
        ipv6: storage.ipv6,
        logLevel: 'error',
      ));
      // 不和正式内核抢缓存文件
      (cfg['experimental'] as Map)['cache_file'] = {'enabled': false};
      final path = '$_workDir/test_config.json';
      await File(path).writeAsString(jsonEncode(cfg));
      final bin = (backend as DesktopBackend).binaryPath;
      if (!File(bin).existsSync()) return null;
      _tester = await Process.start(bin, ['run', '-c', path, '-D', _workDir], workingDirectory: _workDir);
      _tester!.stdout.drain<void>();
      _tester!.stderr.drain<void>();
      final api = ClashApi(port, secret);
      for (var i = 0; i < 40; i++) {
        if (_tester == null) return null;
        if (await api.ping()) return api;
        await Future.delayed(const Duration(milliseconds: 150));
      }
      api.close();
      _stopTester();
    } catch (_) {
      _stopTester();
    }
    return null;
  }

  void _stopTester() {
    _tester?.kill();
    _tester = null;
  }

  static Future<int> _tcpPing(ProxyNode n) async {
    if (n.type == 'hysteria2' || n.type == 'tuic' || n.type == 'hysteria') return -2;
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(n.server, n.port, timeout: const Duration(seconds: 4));
      sw.stop();
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  ProxyNode? get currentNode {
    final tag = selected == 'auto' ? autoNow : selected;
    for (final n in session.nodes) {
      if (n.tag == tag) return n;
    }
    return null;
  }

  Future<void> relaunchElevated() async {
    await storage.setTunMode(true);
    await backend.relaunchElevated();
    exit(0);
  }

  @override
  void dispose() {
    _stopTester();
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
