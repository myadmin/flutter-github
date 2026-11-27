import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/utils/auth_session.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';

class _EtagCacheEntry {
  const _EtagCacheEntry({
    required this.etag,
    required this.data,
    required this.hasNextPage,
  });

  final String etag;
  final dynamic data;
  final bool hasNextPage;
}

/// GitHub API 分页响应载体
class PagedResponse {
  const PagedResponse({required this.data, required this.hasNextPage});

  final dynamic data;
  final bool hasNextPage;
}

/// GitHub 速率限制更新回调签名
typedef RateLimitCallback = void Function({
  required int limit,
  required int remaining,
  DateTime? resetAt,
});

/// 按 GitHub 配额资源域（`core` / `search` 等）上报速率限制的回调签名
typedef ResourceRateLimitCallback = void Function({
  required String resource,
  required int limit,
  required int remaining,
  DateTime? resetAt,
});

/// GitHub REST API v3 网络层封装（参考 hm_shop DioRequest 设计）
class DioRequest {
  static final DioRequest _instance = DioRequest._internal();
  factory DioRequest() => _instance;

  final Dio _dio = Dio();
  final Dio _authDio = Dio();

  /// 暴露底层 Dio 实例，方便测试替换 httpClientAdapter
  Dio get dio => _dio;

  /// 用于 github.com/login/* 设备授权接口的独立 Dio，测试时同样可 mock
  Dio get authDio => _authDio;

  /// 401 登录态失效回调，由 MainPage 注册
  static VoidCallback? onUnauthorized;

  /// 响应头速率限制信息回调（仅 core 配额），由应用入口接线到 RateLimitController
  static RateLimitCallback? onRateLimitUpdate;

  /// 按资源域分类的速率限制信息回调（区分 core / search），防止搜索限流覆盖核心配额
  static ResourceRateLimitCallback? onResourceRateLimitUpdate;

  static const String _extraSkipAuthRedirect = 'skipAuthRedirect';
  static const int _maxEtagCacheEntries = 120;

  final LinkedHashMap<String, _EtagCacheEntry> _etagCache =
      LinkedHashMap<String, _EtagCacheEntry>();

  /// 清空内存中的 ETag 条件缓存（退出登录或测试隔离时调用）
  void clearEtagCache() {
    _etagCache.clear();
  }

  DioRequest._internal() {
    _dio.options
      ..baseUrl = GlobalConstants.apiBaseUrl
      ..connectTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..sendTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..receiveTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..headers = {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': GlobalConstants.apiVersion,
      };

    _authDio.options
      ..connectTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..sendTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..receiveTimeout = const Duration(seconds: GlobalConstants.timeout)
      ..headers = {'Accept': 'application/json'};

    _addInterceptor();
  }

  /// 注册请求与响应拦截器：注入凭证、采集限流配额、统一翻译网络与业务异常
  void _addInterceptor() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          // 允许调用方显式指定临时 Authorization（例如登录前验证 PAT）
          if (!request.headers.containsKey('Authorization')) {
            final token = authTokenReader?.call() ?? '';
            if (token.isNotEmpty) {
              request.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(request);
        },
        onResponse: (response, handler) {
          _captureRateLimit(response.headers, response.requestOptions.path);
          return handler.next(response);
        },
        onError: (error, handler) async {
          final headers = error.response?.headers;
          if (headers != null) {
            _captureRateLimit(headers, error.requestOptions.path);
          }
          // 令牌失效时先完成本地清除，再通知 UI 跳转登录，避免跳转后仍带着旧 token 重试
          final translated = await _translateError(error);
          debugPrint(
            '[DioRequest] ${error.requestOptions.method} '
            '${error.requestOptions.uri} 失败: $translated',
          );
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: translated,
              message: _messageOf(translated) ?? error.message,
              stackTrace: error.stackTrace,
            ),
          );
        },
      ),
    );
  }

  /// 从 GitHub 响应头中解析剩余请求配额与重置时间并按资源域通知状态层
  void _captureRateLimit(Headers headers, String requestPath) {
    final limitStr = headers.value('x-ratelimit-limit');
    final remainingStr = headers.value('x-ratelimit-remaining');
    if (limitStr == null || remainingStr == null) return;
    final limit = int.tryParse(limitStr);
    final remaining = int.tryParse(remainingStr);
    if (limit == null || remaining == null) return;
    final resetEpoch = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
    final resetAt = resetEpoch == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000);
    final headerResource = headers
        .value('x-ratelimit-resource')
        ?.trim()
        .toLowerCase();
    final resource = (headerResource != null && headerResource.isNotEmpty)
        ? headerResource
        : (requestPath.startsWith('/search/') ? 'search' : 'core');

    onResourceRateLimitUpdate?.call(
      resource: resource,
      limit: limit,
      remaining: remaining,
      resetAt: resetAt,
    );
    if (resource == 'core') {
      onRateLimitUpdate?.call(
        limit: limit,
        remaining: remaining,
        resetAt: resetAt,
      );
    }
  }

  /// 将 Dio 底层错误码与异常类型翻译为面向用户的中文业务/网络异常
  Future<Exception> _translateError(DioException error) async {
    if (error.type == DioExceptionType.cancel) {
      return const RequestCancelledException();
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return NetworkException('网络请求超时，请稍后重试');
    }

    final response = error.response;
    final statusCode = response?.statusCode;
    final skipRedirect =
        error.requestOptions.extra[_extraSkipAuthRedirect] == true;

    if (statusCode == 401) {
      if (!skipRedirect) {
        clearEtagCache();
        await authTokenClearer?.call();
        onUnauthorized?.call();
        return NetworkException('GitHub 凭证已失效，请重新登录');
      }
      return ApiException('GitHub Token 无效或已过期', code: '401');
    }

    if (statusCode == 403 || statusCode == 429) {
      final remaining = response?.headers.value('x-ratelimit-remaining');
      if (remaining == '0') {
        final resetEpoch = int.tryParse(
          response?.headers.value('x-ratelimit-reset') ?? '',
        );
        final resetAt = resetEpoch == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000);
        final resetHint = resetAt == null
            ? '请稍后再试'
            : '将于 ${_formatClock(resetAt)} 重置';
        return RateLimitException(
          'GitHub API 请求次数已达上限，$resetHint（登录后配额更高）',
          resetAt: resetAt,
        );
      }
    }

    final data = response?.data;
    if (data is Map && data['message'] != null) {
      final rawMsg = data['message'].toString();
      final lowerMsg = rawMsg.toLowerCase();
      if (statusCode == 405 || statusCode == 409) {
        // 405：PR 不可合并 / 分支保护拦截；409：head 已变更或存在冲突
        final reason = statusCode == 409 ? 'PR 状态已变更' : '该操作暂不被允许';
        return ApiException('$reason，请刷新后重试：$rawMsg', code: '$statusCode');
      }
      if (statusCode == 404) {
        return ApiException('请求的仓库或用户不存在', code: '404');
      }
      if (statusCode == 403) {
        // 次级限流（快速连续请求触发 abuse detection）与配额耗尽不同，稍后重试即可
        if (lowerMsg.contains('secondary rate limit') ||
            lowerMsg.contains('abuse detection')) {
          return ApiException('操作过于频繁，已触发 GitHub 次级限流，请稍后再试', code: '403');
        }
        // contents API 对超过 1 MB 的 blob 直接返回 403，应提示可改用「在浏览器中打开」
        if (lowerMsg.contains('larger than 1 mb') ||
            lowerMsg.contains('up to 1 mb') ||
            lowerMsg.contains('too_large')) {
          return ApiException(
            '文件超过 1 MB，GitHub 接口不支持直接读取，请在浏览器中打开',
            code: '403',
          );
        }
        return ApiException('权限不足：$rawMsg', code: '403');
      }
      return ApiException(rawMsg, code: statusCode?.toString());
    }

    if (error.type == DioExceptionType.badResponse) {
      return NetworkException(
        'GitHub 服务异常${statusCode == null ? '' : '（$statusCode）'}',
      );
    }

    return NetworkException('网络连接异常，请检查网络或代理设置');
  }

  static String _formatClock(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String? _messageOf(Exception error) {
    if (error is ApiException) return error.message;
    if (error is NetworkException) return error.message;
    return null;
  }

  String _etagCacheKey(String kind, String url, Map<String, dynamic>? params) {
    final token = authTokenReader?.call() ?? '';
    final authTag = token.isEmpty
        ? 'anon'
        : '${token.length}:${token.hashCode}';
    if (params == null || params.isEmpty) {
      return '$authTag::$kind::$url';
    }
    final sortedKeys = params.keys.map((k) => k.toString()).toList()..sort();
    final query = sortedKeys.map((k) => '$k=${params[k]}').join('&');
    return '$authTag::$kind::$url?$query';
  }

  bool _canCacheWithEtag(String url, bool skipAuthRedirect, bool useEtagCache) {
    if (!useEtagCache || skipAuthRedirect) return false;
    return !url.startsWith(HttpConstants.rateLimit);
  }

  _EtagCacheEntry? _readEtagEntry(String key) {
    final hit = _etagCache.remove(key);
    if (hit != null) {
      _etagCache[key] = hit;
    }
    return hit;
  }

  void _writeEtagEntry(
    String key,
    Headers responseHeaders, {
    required dynamic data,
    bool hasNextPage = false,
  }) {
    final etag = responseHeaders.value('etag')?.trim() ?? '';
    if (etag.isEmpty) return;
    _etagCache.remove(key);
    _etagCache[key] = _EtagCacheEntry(
      etag: etag,
      data: data,
      hasNextPage: hasNextPage,
    );
    while (_etagCache.length > _maxEtagCacheEntries) {
      _etagCache.remove(_etagCache.keys.first);
    }
  }

  /// 通用 GET 请求（默认支持基于 ETag / If-None-Match 的 304 零配额复用）
  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    bool skipAuthRedirect = false,
    CancelToken? cancelToken,
    bool useEtagCache = true,
  }) async {
    final cacheable = _canCacheWithEtag(url, skipAuthRedirect, useEtagCache);
    final key = cacheable ? _etagCacheKey('json', url, params) : '';
    final cached = cacheable ? _readEtagEntry(key) : null;
    final mergedHeaders = <String, dynamic>{...?headers};
    if (cached != null && !mergedHeaders.containsKey('If-None-Match')) {
      mergedHeaders['If-None-Match'] = cached.etag;
    }

    final res = await _execute(
      () => _dio.get<dynamic>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(
          headers: mergedHeaders.isEmpty ? null : mergedHeaders,
          validateStatus: cached != null
              ? (s) => s != null && ((s >= 200 && s < 300) || s == 304)
              : null,
          extra: {_extraSkipAuthRedirect: skipAuthRedirect},
        ),
      ),
    );
    if (res.statusCode == 304 && cached != null) {
      return cached.data;
    }
    if (cacheable) {
      _writeEtagEntry(key, res.headers, data: res.data);
    }
    return res.data;
  }

  /// 带响应与响应头信息的 GET 请求（用于读取 `X-OAuth-Scopes` 等头字段）
  Future<Response<dynamic>> getFullResponse(
    String url, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    bool skipAuthRedirect = false,
    CancelToken? cancelToken,
  }) {
    return _execute(
      () => _dio.get<dynamic>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          extra: {_extraSkipAuthRedirect: skipAuthRedirect},
        ),
      ),
    );
  }

  /// 面向列表分页的 GET 请求：自动解析 GitHub `Link` 头判定是否有下一页并支持 ETag 304 复用
  Future<PagedResponse> getPaged(
    String url, {
    Map<String, dynamic>? params,
    int perPage = GlobalConstants.defaultPageSize,
    CancelToken? cancelToken,
    bool useEtagCache = true,
  }) async {
    final cacheable = _canCacheWithEtag(url, false, useEtagCache);
    final key = cacheable ? _etagCacheKey('paged', url, params) : '';
    final cached = cacheable ? _readEtagEntry(key) : null;
    final headers = cached != null ? {'If-None-Match': cached.etag} : null;

    final res = await _execute(
      () => _dio.get<dynamic>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: cached != null
            ? Options(
                headers: headers,
                validateStatus: (s) =>
                    s != null && ((s >= 200 && s < 300) || s == 304),
              )
            : null,
      ),
    );
    if (res.statusCode == 304 && cached != null) {
      return PagedResponse(data: cached.data, hasNextPage: cached.hasNextPage);
    }
    final linkHeader = res.headers.value('link');
    final hasLinkNext = parseHasNextPage(linkHeader);
    final data = res.data;
    final hasNext = linkHeader != null
        ? hasLinkNext
        : (data is List && data.length >= perPage);
    if (cacheable) {
      _writeEtagEntry(key, res.headers, data: data, hasNextPage: hasNext);
    }
    return PagedResponse(data: data, hasNextPage: hasNext);
  }

  /// 拉取原始文本内容（README / 源码文件，支持 CancelToken 与 ETag 304 缓存）
  Future<String> getRaw(
    String url, {
    Map<String, dynamic>? params,
    CancelToken? cancelToken,
    bool useEtagCache = true,
  }) async {
    final cacheable = _canCacheWithEtag(url, false, useEtagCache);
    final key = cacheable ? _etagCacheKey('raw', url, params) : '';
    final cached = cacheable ? _readEtagEntry(key) : null;
    final headers = <String, dynamic>{
      'Accept': 'application/vnd.github.raw+json',
      if (cached != null) 'If-None-Match': cached.etag,
    };

    final res = await _execute(
      () => _dio.get<String>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          validateStatus: cached != null
              ? (s) => s != null && ((s >= 200 && s < 300) || s == 304)
              : null,
        ),
      ),
    );
    if (res.statusCode == 304 && cached != null) {
      return cached.data is String ? cached.data as String : '';
    }
    final text = res.data ?? '';
    if (cacheable) {
      _writeEtagEntry(key, res.headers, data: text);
    }
    return text;
  }

  /// 用于检查状态接口（如 `GET /user/starred/{owner}/{repo}`：`204` 为 true，`404` 为 false）
  Future<bool> checkExists(String url, {CancelToken? cancelToken}) async {
    final res = await _execute(
      () => _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          validateStatus: (status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
        ),
      ),
    );
    final code = res.statusCode ?? 404;
    return code >= 200 && code < 300;
  }

  /// 通用 POST 请求
  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final res = await _execute(
      () => _dio.post<dynamic>(
        url,
        data: data,
        options: headers == null ? null : Options(headers: headers),
      ),
    );
    return res.data;
  }

  /// 通用 PUT 请求（点 Star 等无请求体操作传 null）
  Future<dynamic> put(
    String url, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final res = await _execute(
      () => _dio.put<dynamic>(
        url,
        data: data,
        options: headers == null ? null : Options(headers: headers),
      ),
    );
    return res.data;
  }

  /// 通用 PATCH 请求（如标为已读等）
  Future<dynamic> patch(
    String url, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final res = await _execute(
      () => _dio.patch<dynamic>(
        url,
        data: data,
        options: headers == null ? null : Options(headers: headers),
      ),
    );
    return res.data;
  }

  /// 通用 DELETE 请求（取消 Star / Unfollow 等）
  Future<dynamic> delete(String url, {Object? data}) async {
    final res = await _execute(() => _dio.delete<dynamic>(url, data: data));
    return res.data;
  }

  /// 统一执行 Dio 请求并解包拦截器翻译后的异常对象
  Future<Response<T>> _execute<T>(Future<Response<T>> Function() task) async {
    try {
      return await task();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const RequestCancelledException();
      }
      final cause = e.error;
      if (cause is Exception) throw cause;
      throw NetworkException(e.message ?? '网络连接异常，请检查网络');
    }
  }
}

/// 全局网络请求单例
final dioRequest = DioRequest();
