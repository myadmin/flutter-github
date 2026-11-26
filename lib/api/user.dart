import 'package:gh_explorer/api/auth.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 获取当前已登录用户资料与权限范围
Future<({GithubUser user, List<String> scopes})> getCurrentUserAPI() async {
  final res = await dioRequest.getFullResponse(HttpConstants.user);
  final user = GithubUser.fromJson(asMap(res.data));
  final scopes = parseOAuthScopes(res.headers.value('x-oauth-scopes'));
  return (user: user, scopes: scopes);
}

/// 获取指定 GitHub 用户 / 组织详情
Future<GithubUser> getUserDetailAPI(String login) async {
  final encoded = Uri.encodeComponent(login.trim());
  final data = await dioRequest.get('${HttpConstants.users}/$encoded');
  return GithubUser.fromJson(asMap(data));
}

/// 获取当前登录用户的仓库列表（含私有仓库）
Future<PageResult<RepoItem>> getMyReposAPI({
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  String affiliation = 'owner,collaborator,organization_member',
  String visibility = 'all',
  String sort = 'updated',
}) async {
  final res = await dioRequest.getPaged(
    HttpConstants.userRepos,
    params: {
      'page': page,
      'per_page': perPage,
      'affiliation': affiliation,
      'visibility': visibility,
      'sort': sort,
      'direction': 'desc',
    },
    perPage: perPage,
  );
  return PageResult<RepoItem>(
    items: asModelList(res.data, RepoItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取指定用户的公开仓库列表
Future<PageResult<RepoItem>> getUserReposAPI(
  String login, {
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  String sort = 'updated',
}) async {
  final encoded = Uri.encodeComponent(login.trim());
  final res = await dioRequest.getPaged(
    '${HttpConstants.users}/$encoded/repos',
    params: {
      'page': page,
      'per_page': perPage,
      'sort': sort,
      'direction': 'desc',
    },
    perPage: perPage,
  );
  return PageResult<RepoItem>(
    items: asModelList(res.data, RepoItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取用户的 Followers 列表
Future<PageResult<RepoOwner>> getUserFollowersAPI(
  String login, {
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final encoded = Uri.encodeComponent(login.trim());
  final res = await dioRequest.getPaged(
    '${HttpConstants.users}/$encoded/followers',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
  );
  return PageResult<RepoOwner>(
    items: asModelList(res.data, RepoOwner.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取用户的 Following 列表
Future<PageResult<RepoOwner>> getUserFollowingAPI(
  String login, {
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final encoded = Uri.encodeComponent(login.trim());
  final res = await dioRequest.getPaged(
    '${HttpConstants.users}/$encoded/following',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
  );
  return PageResult<RepoOwner>(
    items: asModelList(res.data, RepoOwner.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 检查当前登录用户是否关注了指定用户
Future<bool> checkFollowingUserAPI(String login) async {
  final encoded = Uri.encodeComponent(login.trim());
  return dioRequest.checkExists('${HttpConstants.userFollowing}/$encoded');
}

/// 关注指定用户
Future<void> followUserAPI(String login) async {
  final encoded = Uri.encodeComponent(login.trim());
  await dioRequest.put('${HttpConstants.userFollowing}/$encoded');
}

/// 取消关注指定用户
Future<void> unfollowUserAPI(String login) async {
  final encoded = Uri.encodeComponent(login.trim());
  await dioRequest.delete('${HttpConstants.userFollowing}/$encoded');
}

/// 主动查询当前 API 速率限制状态
Future<RateLimitState> getRateLimitAPI() async {
  final data = asMap(await dioRequest.get(HttpConstants.rateLimit));
  final resources = asMapOrEmpty(data['resources']);
  final core = asMapOrEmpty(resources['core']);
  final resetEpoch = asInt(core['reset']);
  return RateLimitState(
    limit: asInt(core['limit'], fallback: 60),
    remaining: asInt(core['remaining'], fallback: 60),
    resetAt: resetEpoch > 0
        ? DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000)
        : null,
  );
}
