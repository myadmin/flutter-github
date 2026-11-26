import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 拼接指定仓库 Issues 接口基础路径
String _issuesBase(String owner, String repo) =>
    '${HttpConstants.repos}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}/issues';

/// 获取仓库 Issue / PR 列表
Future<PageResult<IssueItem>> getRepoIssuesAPI(
  String owner,
  String repo, {
  String state = 'open',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final res = await dioRequest.getPaged(
    _issuesBase(owner, repo),
    params: {'state': state, 'page': page, 'per_page': perPage},
    perPage: perPage,
  );
  return PageResult<IssueItem>(
    items: asModelList(res.data, IssueItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取单个 Issue 详情
Future<IssueItem> getRepoIssueDetailAPI(
  String owner,
  String repo,
  int number,
) async {
  final data = await dioRequest.get('${_issuesBase(owner, repo)}/$number');
  return IssueItem.fromJson(asMap(data));
}

/// 获取 Issue 评论列表
Future<PageResult<IssueComment>> getIssueCommentsAPI(
  String owner,
  String repo,
  int number, {
  int page = 1,
  int perPage = 30,
}) async {
  final res = await dioRequest.getPaged(
    '${_issuesBase(owner, repo)}/$number/comments',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
  );
  return PageResult<IssueComment>(
    items: asModelList(res.data, IssueComment.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 在指定 Issue 下发表评论（需要登录且 Token 含 repo/public_repo 权限）
Future<IssueComment> createIssueCommentAPI(
  String owner,
  String repo,
  int number,
  String body,
) async {
  final data = await dioRequest.post(
    '${_issuesBase(owner, repo)}/$number/comments',
    data: {'body': body.trim()},
  );
  return IssueComment.fromJson(asMap(data));
}
