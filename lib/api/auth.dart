import 'package:dio/dio.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/dio_request.dart';

/// PAT / OAuth 登录验证结果
class AuthLoginResult {
  const AuthLoginResult({
    required this.user,
    required this.token,
    required this.scopes,
  });

  final GithubUser user;
  final String token;
  final List<String> scopes;
}

/// OAuth Device Flow 授权码响应
class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> json) {
    return DeviceCodeResponse(
      deviceCode: asString(json['device_code']),
      userCode: asString(json['user_code']),
      verificationUri: asString(
        json['verification_uri'],
        fallback: 'https://github.com/login/device',
      ),
      expiresIn: asInt(json['expires_in'], fallback: 900),
      interval: asInt(json['interval'], fallback: 5),
    );
  }
}

/// OAuth Device Flow 授权码轮询状态枚举
enum DeviceTokenStatus { success, pending, slowDown, expired, denied, error }

/// OAuth Device Flow 单次轮询结果
class DeviceTokenPollResult {
  const DeviceTokenPollResult({
    required this.status,
    this.accessToken = '',
    this.errorMessage = '',
  });

  /// 本次轮询的状态结果
  final DeviceTokenStatus status;

  /// 授权成功时拿到的 OAuth Access Token
  final String accessToken;

  /// 失败或过期时的中文提示信息
  final String errorMessage;
}

/// 解析响应头中的 `X-OAuth-Scopes`
List<String> parseOAuthScopes(String? headerValue) {
  if (headerValue == null || headerValue.trim().isEmpty) {
    return const [];
  }
  return headerValue
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// 使用 Personal Access Token (或已拿到的 OAuth Token) 登录并校验身份
Future<AuthLoginResult> loginWithTokenAPI(String token) async {
  final trimmed = token.trim();
  if (trimmed.isEmpty) {
    throw ApiException('请输入 GitHub Personal Access Token');
  }
  final res = await dioRequest.getFullResponse(
    HttpConstants.user,
    headers: {'Authorization': 'Bearer $trimmed'},
    skipAuthRedirect: true,
  );
  final user = GithubUser.fromJson(asMap(res.data));
  if (!user.isLoggedIn) {
    throw ApiException('未能获取有效的 GitHub 用户信息');
  }
  final scopes = parseOAuthScopes(res.headers.value('x-oauth-scopes'));
  return AuthLoginResult(user: user, token: trimmed, scopes: scopes);
}

/// 发起 GitHub OAuth Device Flow 授权请求
Future<DeviceCodeResponse> requestDeviceCodeAPI(
  String clientId, {
  String scope = 'repo read:user notifications',
}) async {
  final trimmedId = clientId.trim();
  if (trimmedId.isEmpty) {
    throw ApiException('请先配置 GitHub OAuth Client ID');
  }
  final Response<dynamic> res;
  try {
    res = await dioRequest.authDio.post<dynamic>(
      HttpConstants.deviceCodeUrl,
      data: {'client_id': trimmedId, 'scope': scope},
      options: Options(headers: const {'Accept': 'application/json'}),
    );
  } on DioException catch (e) {
    throw NetworkException(e.message ?? '请求 GitHub 设备授权失败，请检查网络或改用 Token 登录');
  }
  final parsed = DeviceCodeResponse.fromJson(asMap(res.data));
  if (parsed.deviceCode.isEmpty || parsed.userCode.isEmpty) {
    throw ApiException('GitHub 未返回有效的设备授权码');
  }
  return parsed;
}

/// 轮询检查 OAuth Device Flow 是否完成授权
Future<DeviceTokenPollResult> pollDeviceAccessTokenAPI({
  required String clientId,
  required String deviceCode,
}) async {
  final Response<dynamic> res;
  try {
    res = await dioRequest.authDio.post<dynamic>(
      HttpConstants.oauthTokenUrl,
      data: {
        'client_id': clientId.trim(),
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
      options: Options(headers: const {'Accept': 'application/json'}),
    );
  } on DioException catch (e) {
    throw NetworkException(e.message ?? '轮询授权状态失败，请稍后重试');
  }
  final map = asMap(res.data);
  final accessToken = asString(map['access_token']);
  if (accessToken.isNotEmpty) {
    return DeviceTokenPollResult(
      status: DeviceTokenStatus.success,
      accessToken: accessToken,
    );
  }
  final errCode = asString(map['error']);
  final errDesc = asString(map['error_description']);
  // 按照 RFC 8628 设备授权流规范分支处理各轮询错误码
  switch (errCode) {
    case 'authorization_pending':
      return const DeviceTokenPollResult(status: DeviceTokenStatus.pending);
    case 'slow_down':
      return const DeviceTokenPollResult(status: DeviceTokenStatus.slowDown);
    case 'expired_token':
      return const DeviceTokenPollResult(
        status: DeviceTokenStatus.expired,
        errorMessage: '授权码已过期，请重新发起授权',
      );
    case 'access_denied':
      return const DeviceTokenPollResult(
        status: DeviceTokenStatus.denied,
        errorMessage: '已取消 GitHub 授权',
      );
    default:
      return DeviceTokenPollResult(
        status: DeviceTokenStatus.error,
        errorMessage: errDesc.isNotEmpty ? errDesc : '授权失败（$errCode）',
      );
  }
}
