/// 网络层与状态层之间的认证凭证钩子。
///
/// `utils/dio_request.dart` 只依赖这里的函数指针，不直接 import `stores/`，
/// 从而打破「工具层 → 状态层」的反向依赖；凭证的真实来源仍由 `TokenManager`
/// 在创建时注册，应用启动即自动生效。
typedef AuthTokenReader = String Function();
typedef AuthTokenClearer = Future<void> Function();

/// 读取当前访问令牌（未登录时返回空字符串）
AuthTokenReader? authTokenReader;

/// 清除本地失效令牌（HTTP 401 时由拦截器调用）
AuthTokenClearer? authTokenClearer;
