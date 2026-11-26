/// 路由名与带查询串深链构造中心（复用 hm_shop 设计）
///
/// 所有页面参数均编进查询串（如 `/repo?owner=flutter&name=flutter`），
/// 保证 Web 刷新、深链分享与测试路由断言完全一致，且避免循环依赖。
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String repoDetailPath = '/repo';
  static const String repoFilesPath = '/repo/files';
  static const String repoFileViewPath = '/repo/blob';
  static const String repoIssuesPath = '/repo/issues';
  static const String repoIssueDetailPath = '/repo/issue';
  static const String repoCommitsPath = '/repo/commits';
  static const String userDetailPath = '/user';
  static const String userFollowsPath = '/user/follows';
  static const String myReposPath = '/my/repos';
  static const String myStarsPath = '/my/stars';
  static const String notificationsPath = '/notifications';
  static const String footprintPath = '/footprint';

  /// 仓库详情：`/repo?owner=<owner>&name=<repo>`
  static String repoDetail(String owner, String name) =>
      '$repoDetailPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}';

  /// 从 `owner/repo` 构造仓库详情路由
  static String repoDetailFromFullName(String fullName) {
    final parts = fullName.split('/');
    if (parts.length < 2) return repoDetail('', '');
    return repoDetail(parts[0], parts[1]);
  }

  /// 代码文件树：`/repo/files?owner=&name=&ref=&path=`
  static String repoFiles(
    String owner,
    String name, {
    String ref = '',
    String path = '',
  }) =>
      '$repoFilesPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}'
      '${ref.isEmpty ? '' : '&ref=${Uri.encodeQueryComponent(ref)}'}'
      '${path.isEmpty ? '' : '&path=${Uri.encodeQueryComponent(path)}'}';

  /// 单文件源码预览：`/repo/blob?owner=&name=&ref=&path=`
  static String repoFileView(
    String owner,
    String name, {
    required String path,
    String ref = '',
  }) =>
      '$repoFileViewPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}'
      '&path=${Uri.encodeQueryComponent(path)}'
      '${ref.isEmpty ? '' : '&ref=${Uri.encodeQueryComponent(ref)}'}';

  /// Issue / PR 列表：`/repo/issues?owner=&name=`
  static String repoIssues(String owner, String name) =>
      '$repoIssuesPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}';

  /// Issue 详情：`/repo/issue?owner=&name=&number=`
  static String repoIssueDetail(String owner, String name, int number) =>
      '$repoIssueDetailPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}'
      '&number=$number';

  /// Commit 历史：`/repo/commits?owner=&name=&branch=`
  static String repoCommits(String owner, String name, {String branch = ''}) =>
      '$repoCommitsPath?owner=${Uri.encodeQueryComponent(owner)}'
      '&name=${Uri.encodeQueryComponent(name)}'
      '${branch.isEmpty ? '' : '&branch=${Uri.encodeQueryComponent(branch)}'}';

  /// 用户 / 组织详情：`/user?login=<login>`
  static String userDetail(String login) =>
      '$userDetailPath?login=${Uri.encodeQueryComponent(login)}';

  /// 关注 / 粉丝列表：`/user/follows?login=<login>&tab=followers|following`
  static String userFollows(String login, {String tab = 'followers'}) =>
      '$userFollowsPath?login=${Uri.encodeQueryComponent(login)}'
      '&tab=${Uri.encodeQueryComponent(tab)}';
}
