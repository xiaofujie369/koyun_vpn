import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app_config.dart';
import '../services/storage.dart';

/// 接口错误分类：界面根据类型给出不同提示。
enum ApiErrorKind {
  /// 网络不通 / 超时 / 域名被墙（所有域名都失败）
  network,

  /// 登录失效（401/403），需要重新登录
  unauthorized,

  /// 服务端返回了业务错误（如"密码错误"、"邮箱已被注册"）
  server,

  /// 其它未知错误
  unknown,
}

class ApiError implements Exception {
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  ApiError(this.kind, this.message, {this.statusCode});

  bool get isNetwork => kind == ApiErrorKind.network;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  @override
  String toString() => message;
}

/// Xboard 用户端接口封装。
///
/// 设计要点：
/// * 多域名容灾：按 [AppConfig.apiHosts] 顺序尝试，成功的域名会被记住，下次优先。
/// * 只有"网络类错误"才会换域名重试；业务错误（密码错误等）直接返回，避免重复提交。
/// * 所有请求都带 Referer，避开 Cloudflare 上"无 Referer 拦截 /api"的规则。
class XboardApi {
  XboardApi(this._storage) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
      headers: {'User-Agent': AppConfig.apiUserAgent},
    ));
  }

  final Storage _storage;
  late final Dio _dio;

  /// 当前界面语言，后台据此返回对应语言的错误提示。
  String language = 'zh-CN';

  String? get _authData => _storage.authData;

  List<String> get _hostOrder {
    final preferred = _storage.preferredApiHost;
    final hosts = [...AppConfig.apiHosts];
    if (preferred != null && hosts.remove(preferred)) {
      hosts.insert(0, preferred);
    }
    return hosts;
  }

  String get currentHost => _hostOrder.first;

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    ApiError? lastNetworkError;
    for (final host in _hostOrder) {
      final headers = <String, dynamic>{
        'Referer': '$host/',
        'Content-Language': language,
        'Accept': 'application/json',
      };
      if (auth && _authData != null) headers['Authorization'] = _authData;
      Response res;
      try {
        res = await _dio.request(
          '$host/api/v1/$path',
          queryParameters: query,
          data: body,
          options: Options(method: method, headers: headers),
        );
      } on DioException catch (e) {
        lastNetworkError = ApiError(ApiErrorKind.network, _describeDioError(e));
        continue; // 换下一个域名
      } catch (e) {
        lastNetworkError = ApiError(ApiErrorKind.network, e.toString());
        continue;
      }

      final code = res.statusCode ?? 0;
      final data = res.data;
      // 被 CDN 拦截、返回 HTML 错误页等情况，当作该域名不可用
      if (data is! Map && (code >= 500 || code == 0 || code == 403)) {
        lastNetworkError =
            ApiError(ApiErrorKind.network, 'HTTP $code', statusCode: code);
        continue;
      }
      if (host != _storage.preferredApiHost) {
        await _storage.setPreferredApiHost(host);
      }
      if (code == 401 || (code == 403 && auth && path.startsWith('user/'))) {
        throw ApiError(ApiErrorKind.unauthorized, _messageOf(data) ?? '登录已失效',
            statusCode: code);
      }
      if (code >= 200 && code < 300) {
        if (data is Map && data['status'] == 'fail') {
          throw ApiError(ApiErrorKind.server, _messageOf(data) ?? '请求失败',
              statusCode: code);
        }
        return data is Map && data.containsKey('data') ? data['data'] : data;
      }
      throw ApiError(
        code >= 500 ? ApiErrorKind.unknown : ApiErrorKind.server,
        _messageOf(data) ?? 'HTTP $code',
        statusCode: code,
      );
    }
    throw lastNetworkError ?? ApiError(ApiErrorKind.network, 'network error');
  }

  static String? _messageOf(dynamic data) {
    if (data is! Map) return null;
    // Laravel 表单校验错误：{"message": "...", "errors": {"email": ["..."]}}
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    final m = data['message'];
    return m is String && m.isNotEmpty ? m : null;
  }

  static String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'timeout';
      default:
        final err = e.error;
        if (err is SocketException) return err.message;
        if (err is HandshakeException) return 'TLS handshake failed';
        return e.message ?? e.type.name;
    }
  }

  // ---------------- 公共 ----------------

  Future<Map<String, dynamic>> guestConfig() async =>
      Map<String, dynamic>.from(await _request('GET', 'guest/comm/config', auth: false) ?? {});

  // ---------------- 账号 ----------------

  Future<String> login(String email, String password) async {
    final data = await _request('POST', 'passport/auth/login',
        body: {'email': email, 'password': password}, auth: false);
    return _extractAuth(data);
  }

  Future<String> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    final data = await _request('POST', 'passport/auth/register', auth: false, body: {
      'email': email,
      'password': password,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
    });
    return _extractAuth(data);
  }

  Future<void> sendEmailCode(String email) async {
    await _request('POST', 'passport/comm/sendEmailVerify',
        body: {'email': email}, auth: false);
  }

  Future<void> resetPassword(String email, String code, String password) async {
    await _request('POST', 'passport/auth/forget',
        body: {'email': email, 'email_code': code, 'password': password}, auth: false);
  }

  String _extractAuth(dynamic data) {
    if (data is Map && data['auth_data'] is String) return data['auth_data'];
    if (data is Map && data['token'] is String) return 'Bearer ${data['token']}';
    throw ApiError(ApiErrorKind.unknown, 'bad login response');
  }

  // ---------------- 用户 ----------------

  Future<Map<String, dynamic>> userInfo() async =>
      Map<String, dynamic>.from(await _request('GET', 'user/info'));

  Future<Map<String, dynamic>> getSubscribe() async =>
      Map<String, dynamic>.from(await _request('GET', 'user/getSubscribe'));

  Future<List<Map<String, dynamic>>> notices() async {
    final d = await _request('GET', 'user/notice/fetch', query: {'current': 1, 'pageSize': 5});
    final list = d is Map ? d['data'] : d;
    return list is List ? list.map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> plans() async {
    final d = await _request('GET', 'user/plan/fetch');
    return d is List ? d.map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> orders() async {
    final d = await _request('GET', 'user/order/fetch');
    return d is List ? d.map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<String> createOrder(int planId, String period, {String? coupon}) async {
    final d = await _request('POST', 'user/order/save', body: {
      'plan_id': planId,
      'period': period,
      if (coupon != null && coupon.isNotEmpty) 'coupon_code': coupon,
    });
    return d.toString();
  }

  Future<List<Map<String, dynamic>>> paymentMethods() async {
    final d = await _request('GET', 'user/order/getPaymentMethod');
    return d is List ? d.map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  /// 返回 (type, data)：type=1 跳转链接，type=0 二维码内容，type=-1 已完成（免费）
  Future<(int, dynamic)> checkout(String tradeNo, int method) async {
    final d = await _request('POST', 'user/order/checkout',
        body: {'trade_no': tradeNo, 'method': method});
    if (d is Map) return ((d['type'] as num?)?.toInt() ?? 1, d['data']);
    return (1, d);
  }

  Future<int> orderStatus(String tradeNo) async {
    final d = await _request('GET', 'user/order/check', query: {'trade_no': tradeNo});
    return (d as num?)?.toInt() ?? 0;
  }

  Future<void> cancelOrder(String tradeNo) async {
    await _request('POST', 'user/order/cancel', body: {'trade_no': tradeNo});
  }

  /// 订阅地址被墙时的兜底：直接走接口域名下的订阅接口。
  String fallbackSubscribeUrl(String token) =>
      '$currentHost/api/v1/client/subscribe?token=${Uri.encodeQueryComponent(token)}';
}
