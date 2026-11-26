/// 全局常量与 GitHub 接口基础配置
class GlobalConstants {
  const GlobalConstants._();

  /// GitHub REST API 根地址
  static const String apiBaseUrl = 'https://api.github.com';

  /// GitHub 网页端根地址
  static const String webBaseUrl = 'https://github.com';

  /// 固定请求的 GitHub REST API 版本号
  static const String apiVersion = '2022-11-28';

  /// 默认请求超时时间（秒）
  static const int timeout = 15;

  /// 分页列表默认每页条数
  static const int defaultPageSize = 20;

  /// 本地存储键名：访问令牌
  static const String tokenKey = 'gh_explorer_token';

  /// 本地存储键名：令牌权限列表
  static const String tokenScopesKey = 'gh_explorer_token_scopes';

  /// 本地存储键名：项目浏览足迹
  static const String footprintKey = 'gh_explorer_footprint';

  /// 本地存储键名：搜索历史关键词
  static const String searchHistoryKey = 'gh_explorer_search_history';

  /// 可通过 `--dart-define=GH_OAUTH_CLIENT_ID=xxx` 注入 GitHub OAuth App Client ID
  static const String oauthClientId = String.fromEnvironment(
    'GH_OAUTH_CLIENT_ID',
  );

  /// 仓库版本检测地址（预留检查更新功能）
  static const String repoOwner = 'flutter';
  static const String repoName = 'flutter';
}

/// GitHub REST API v3 与 OAuth 端点常量
class HttpConstants {
  const HttpConstants._();

  // 用户与鉴权
  static const String user = '/user';
  static const String users = '/users';
  static const String userRepos = '/user/repos';
  static const String userStarred = '/user/starred';
  static const String userFollowing = '/user/following';
  static const String notifications = '/notifications';
  static const String rateLimit = '/rate_limit';

  // 搜索
  static const String searchRepositories = '/search/repositories';
  static const String searchUsers = '/search/users';

  // 仓库资源
  static const String repos = '/repos';

  // OAuth Device Flow（仅原生端可用，Web 端受限于 github.com CORS）
  static const String deviceCodeUrl = 'https://github.com/login/device/code';
  static const String oauthTokenUrl =
      'https://github.com/login/oauth/access_token';

  // 快速生成 PAT 跳转地址
  static const String createPatUrl =
      'https://github.com/settings/tokens/new?description=gh_explorer&scopes=repo,read:user,notifications';
}
