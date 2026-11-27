/// 业务/API 异常：GitHub 接口返回了非预期的业务错误（如 422 校验失败、404 资源不存在等）。
class ApiException implements Exception {
  ApiException(this.message, {this.code});

  /// 面向用户的中文提示
  final String message;

  /// 状态码或 GitHub 错误标识
  final String? code;

  @override
  String toString() => 'ApiException(code: $code, message: $message)';
}

/// GitHub API 速率限制异常（HTTP 403 / 429 且 remaining == 0）。
class RateLimitException extends ApiException {
  RateLimitException(super.message, {this.resetAt}) : super(code: '403');

  /// 限流重置时间（本地时间）
  final DateTime? resetAt;
}

/// 网络异常：超时、断网、DNS 失败或认证失效。
class NetworkException implements Exception {
  NetworkException(this.message);

  final String message;

  @override
  String toString() => 'NetworkException(message: $message)';
}

/// 请求被主动取消：页面销毁、刷新或切换筛选时放弃在途请求，不应提示用户。
class RequestCancelledException implements Exception {
  const RequestCancelledException([this.message = '请求已取消']);

  final String message;

  @override
  String toString() => 'RequestCancelledException(message: $message)';
}

/// 从任意异常中提取面向用户的中文提示文案。
String resolveErrorMessage(Object error, {String? fallback}) {
  if (error is ApiException) return error.message;
  if (error is NetworkException) return error.message;
  if (error is RequestCancelledException) return error.message;
  if (error is FormatException) return '数据格式异常，请稍后重试';
  return fallback ?? '网络或服务异常，请稍后重试';
}
