import 'package:dio/dio.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 拼接当前用户操作指定仓库 Star 状态的请求路径
String _repoStarPath(String owner, String repo) =>
    '${HttpConstants.userStarred}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}';

/// 检查当前用户是否已 Star 该仓库（204 为 true，404 为 false）
Future<bool> checkRepoStarredAPI(
  String owner,
  String repo, {
  CancelToken? cancelToken,
}) {
  return dioRequest.checkExists(
    _repoStarPath(owner, repo),
    cancelToken: cancelToken,
  );
}

/// 为仓库点 Star（PUT `/user/starred/{owner}/{repo}`）
Future<void> starRepoAPI(String owner, String repo) async {
  await dioRequest.put(_repoStarPath(owner, repo));
}

/// 取消仓库 Star（DELETE `/user/starred/{owner}/{repo}`）
Future<void> unstarRepoAPI(String owner, String repo) async {
  await dioRequest.delete(_repoStarPath(owner, repo));
}

/// 获取当前登录用户 Star 的仓库列表
Future<PageResult<RepoItem>> getMyStarredReposAPI({
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  String sort = 'created',
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    HttpConstants.userStarred,
    params: {
      'page': page,
      'per_page': perPage,
      'sort': sort,
      'direction': 'desc',
    },
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<RepoItem>(
    items: asModelList(res.data, RepoItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取指定用户 Star 的公开仓库列表
Future<PageResult<RepoItem>> getUserStarredReposAPI(
  String login, {
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  CancelToken? cancelToken,
}) async {
  final encoded = Uri.encodeComponent(login.trim());
  final res = await dioRequest.getPaged(
    '${HttpConstants.users}/$encoded/starred',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<RepoItem>(
    items: asModelList(res.data, RepoItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}
