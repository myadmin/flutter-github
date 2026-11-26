import 'dart:math' as math;

import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 拼接指定仓库 Issues 接口基础路径
String _issuesBase(String owner, String repo) =>
    '${HttpConstants.repos}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}/issues';

/// 构造在当前仓库范围内搜索全部 Issues / PR 的 GitHub Search 查询串
String buildRepoIssueSearchQuery({
  required String owner,
  required String repo,
  required String keyword,
  String state = 'open',
}) {
  var cleanKeyword = keyword.trim();
  // 支持输入 `#43475` 形式的编号检索，去掉前导 `#` 以提升 GitHub Search 命中率
  if (RegExp(r'^#\d+$').hasMatch(cleanKeyword)) {
    cleanKeyword = cleanKeyword.substring(1);
  }

  final parts = <String>['repo:${owner.trim()}/${repo.trim()}'];
  final lower = cleanKeyword.toLowerCase();
  final hasExplicitState =
      lower.contains('is:open') || lower.contains('is:closed');
  if (!hasExplicitState) {
    if (state == 'open') {
      parts.add('is:open');
    } else if (state == 'closed') {
      parts.add('is:closed');
    }
  }
  if (cleanKeyword.isNotEmpty) {
    parts.add(cleanKeyword);
  }
  return parts.join(' ');
}

/// 在当前仓库的全部 Issues 与 PR 中按关键词或编号搜索（基于 `/search/issues`）
Future<PageResult<IssueItem>> searchRepoIssuesAPI(
  String owner,
  String repo, {
  required String keyword,
  String state = 'open',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  void Function(int totalCount)? onTotalCount,
}) async {
  final q = buildRepoIssueSearchQuery(
    owner: owner,
    repo: repo,
    keyword: keyword,
    state: state,
  );
  final raw = asMap(
    await dioRequest.get(
      HttpConstants.searchIssues,
      params: {'q': q, 'order': 'desc', 'page': page, 'per_page': perPage},
    ),
  );
  final totalCount = asInt(raw['total_count']);
  onTotalCount?.call(totalCount);
  final items = asList(raw['items'], IssueItem.fromJson);
  final cappedTotal = math.min(totalCount, 1000);
  final hasMore = page * perPage < cappedTotal && items.isNotEmpty;
  return PageResult<IssueItem>(items: items, page: page, hasMore: hasMore);
}

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
