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

  /// 本地存储键名：探索首页顶部展示的语言/主题标签列表
  static const String exploreTagsKey = 'gh_explorer_explore_tags';

  /// 本地存储键名：探索首页顶部是否固定展示「全部」标签
  static const String exploreShowAllTagKey = 'gh_explorer_explore_show_all_tag';

  /// 本地存储键名：用户自定义添加的探索顶部标签列表
  static const String exploreCustomTagsKey = 'gh_explorer_explore_custom_tags';

  /// 本地存储键名：上次检查更新的时间戳
  static const String updateLastCheckKey = 'gh_explorer_update_last_check';

  /// 本地存储键名：用户选择跳过的最新 Release 标签
  static const String updateSkipTagKey = 'gh_explorer_update_skip_tag';

  /// 静默自动检查更新的最小间隔（小时），避免频繁消耗未登录 IP 配额
  static const int updateCheckHours = 6;

  /// CI 构建注入的完整发布标签（例如 `v1.0.0-build.4`），本地调试时为空
  static const String appReleaseTag = String.fromEnvironment('GH_RELEASE_TAG');

  /// 可通过 `--dart-define=GH_OAUTH_CLIENT_ID=xxx` 注入 GitHub OAuth App Client ID
  static const String oauthClientId = String.fromEnvironment(
    'GH_OAUTH_CLIENT_ID',
  );

  /// 仓库版本检测地址（对应本应用托管的 GitHub 仓库）
  static const String repoOwner = 'myadmin';
  static const String repoName = 'flutter-github';

  /// Releases 页面地址（非 Android 平台或浏览器兜底下载使用）
  static const String releasesPageUrl =
      '$webBaseUrl/$repoOwner/$repoName/releases/latest';
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
  static const String searchIssues = '/search/issues';

  // 仓库资源
  static const String repos = '/repos';
  static const String latestRelease =
      '/repos/${GlobalConstants.repoOwner}/${GlobalConstants.repoName}/releases/latest';

  // OAuth Device Flow（仅原生端可用，Web 端受限于 github.com CORS）
  static const String deviceCodeUrl = 'https://github.com/login/device/code';
  static const String oauthTokenUrl =
      'https://github.com/login/oauth/access_token';

  // 快速生成 PAT 跳转地址
  static const String createPatUrl =
      'https://github.com/settings/tokens/new?description=gh_explorer&scopes=repo,read:user,notifications';
}
