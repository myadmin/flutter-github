import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化 GitHub 访问令牌（PAT / OAuth Token）及权限范围
class TokenManager {
  Future<SharedPreferences> _getInstance() async {
    return SharedPreferences.getInstance();
  }

  String _token = '';
  List<String> _scopes = const [];

  /// 启动时从本地读取 token 与 scopes
  Future<void> init() async {
    final prefs = await _getInstance();
    _token = prefs.getString(GlobalConstants.tokenKey) ?? '';
    _scopes = prefs.getStringList(GlobalConstants.tokenScopesKey) ?? const [];
  }

  /// 保存 token（可选保存从 `X-OAuth-Scopes` 解析的权限列表）
  Future<void> setToken(String token, {List<String>? scopes}) async {
    final prefs = await _getInstance();
    _token = token;
    await prefs.setString(GlobalConstants.tokenKey, token);
    if (scopes != null) {
      _scopes = List<String>.unmodifiable(scopes);
      await prefs.setStringList(GlobalConstants.tokenScopesKey, _scopes);
    }
  }

  /// 更新已存权限列表
  Future<void> setScopes(List<String> scopes) async {
    final prefs = await _getInstance();
    _scopes = List<String>.unmodifiable(scopes);
    await prefs.setStringList(GlobalConstants.tokenScopesKey, _scopes);
  }

  String getToken() => _token;

  List<String> getScopes() => _scopes;

  /// 是否已登录（本地存在非空 token）
  bool get hasToken => _token.isNotEmpty;

  /// 清除本地 token 与权限信息
  Future<void> removeToken() async {
    final prefs = await _getInstance();
    _token = '';
    _scopes = const [];
    await prefs.remove(GlobalConstants.tokenKey);
    await prefs.remove(GlobalConstants.tokenScopesKey);
  }
}

final tokenManager = TokenManager();
