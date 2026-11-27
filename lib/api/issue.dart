import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// Issue / PR 列表分类筛选类型
enum IssueKindFilter {
  all('全部类型'),
  issue('仅 Issue'),
  pr('仅 PR');

  const IssueKindFilter(this.label);

  final String label;
}

/// 拼接指定仓库 Issues 接口基础路径
String _issuesBase(String owner, String repo) =>
    '${HttpConstants.repos}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}/issues';

/// 拼接指定仓库 Pull Requests 接口基础路径
String _pullsBase(String owner, String repo) =>
    '${HttpConstants.repos}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}/pulls';

/// 匹配形如 `repo:xxx`、`is:pr`、`author:someone` 的 GitHub Search 限定符
final RegExp _searchQualifier = RegExp(r'(^|[\s(])[A-Za-z][A-Za-z0-9_-]*:');

/// 净化仓库标识：去掉空白与冒号，避免污染 `repo:` 限定符
String _cleanRepoPart(String value) =>
    value.trim().replaceAll(RegExp(r'[\s:]+'), '');

/// 转义用户关键词：出现限定符写法时整体加引号，避免越权改写搜索范围
///
/// GitHub Search 把 `repo:`、`is:`、`author:` 等视为过滤器，直接拼接用户输入会被
/// 用来把搜索范围切换到其它仓库或放宽状态过滤，因此这里把含限定符的输入降级为
/// 字面量短语（引号内冒号不再具备过滤语义）。
String _escapeRepoIssueKeyword(String keyword) {
  if (keyword.isEmpty || !_searchQualifier.hasMatch(keyword)) {
    return keyword;
  }
  final escaped = keyword.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

/// 构造在当前仓库范围内搜索全部 Issues / PR 的 GitHub Search 查询串
String buildRepoIssueSearchQuery({
  required String owner,
  required String repo,
  required String keyword,
  String state = 'open',
  IssueKindFilter kind = IssueKindFilter.all,
}) {
  var cleanKeyword = keyword.trim();
  // 支持输入 `#43475` 形式的编号检索，去掉前导 `#` 以提升 GitHub Search 命中率
  if (RegExp(r'^#\d+$').hasMatch(cleanKeyword)) {
    cleanKeyword = cleanKeyword.substring(1);
  }
  // 关键词一律降级为字面量短语，因此状态只能由 UI 的 Open/Closed/All 决定，
  // 不再识别关键词中的 `is:open` / `is:closed`（否则会出现“筛选 Closed 却返回 Open”）
  cleanKeyword = _escapeRepoIssueKeyword(cleanKeyword);

  final parts = <String>[
    'repo:${_cleanRepoPart(owner)}/${_cleanRepoPart(repo)}',
  ];
  if (kind == IssueKindFilter.issue) {
    parts.add('is:issue');
  } else if (kind == IssueKindFilter.pr) {
    parts.add('is:pr');
  }
  if (state == 'open') {
    parts.add('is:open');
  } else if (state == 'closed') {
    parts.add('is:closed');
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
  IssueKindFilter kind = IssueKindFilter.all,
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  void Function(int totalCount)? onTotalCount,
  CancelToken? cancelToken,
}) async {
  final q = buildRepoIssueSearchQuery(
    owner: owner,
    repo: repo,
    keyword: keyword,
    state: state,
    kind: kind,
  );
  final raw = asMap(
    await dioRequest.get(
      HttpConstants.searchIssues,
      params: {'q': q, 'order': 'desc', 'page': page, 'per_page': perPage},
      cancelToken: cancelToken,
    ),
  );
  final totalCount = asInt(raw['total_count']);
  // GitHub Search 最多只能翻到 1000 条，总数与分页能力保持一致
  final cappedTotal = math.min(totalCount, 1000);
  onTotalCount?.call(cappedTotal);
  final items = asList(raw['items'], IssueItem.fromJson);
  final hasMore = page * perPage < cappedTotal && items.isNotEmpty;
  return PageResult<IssueItem>(items: items, page: page, hasMore: hasMore);
}

/// 分页获取仓库 Pull Requests 列表
Future<PageResult<IssueItem>> getRepoPullsAPI(
  String owner,
  String repo, {
  String state = 'open',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    _pullsBase(owner, repo),
    params: {'state': state, 'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<IssueItem>(
    items: asModelList(res.data, IssueItem.fromPullRequestJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取仓库 Issue / PR 列表
Future<PageResult<IssueItem>> getRepoIssuesAPI(
  String owner,
  String repo, {
  String state = 'open',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    _issuesBase(owner, repo),
    params: {'state': state, 'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
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
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    '${_issuesBase(owner, repo)}/$number/comments',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
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

/// 创建新 Issue（需要登录且 Token 含写权限）
Future<IssueItem> createRepoIssueAPI(
  String owner,
  String repo, {
  required String title,
  String body = '',
  List<String> labels = const [],
}) async {
  final payload = <String, dynamic>{'title': title.trim()};
  final trimmedBody = body.trim();
  if (trimmedBody.isNotEmpty) {
    payload['body'] = trimmedBody;
  }
  if (labels.isNotEmpty) {
    payload['labels'] = labels;
  }
  final data = await dioRequest.post(_issuesBase(owner, repo), data: payload);
  return IssueItem.fromJson(asMap(data));
}

/// 修改 Issue/PR 标题、正文或状态（`open` / `closed`）
Future<IssueItem> updateRepoIssueAPI(
  String owner,
  String repo,
  int number, {
  String? title,
  String? body,
  String? state,
}) async {
  final payload = <String, dynamic>{
    if (title != null) 'title': title.trim(),
    'body': ?body,
    'state': ?state,
  };
  final data = await dioRequest.patch(
    '${_issuesBase(owner, repo)}/$number',
    data: payload,
  );
  return IssueItem.fromJson(asMap(data));
}

/// 获取仓库可用标签列表（用于新建 Issue 时快速选择）
Future<List<IssueLabel>> getRepoLabelsAPI(
  String owner,
  String repo, {
  int perPage = 50,
}) async {
  final encodedOwner = Uri.encodeComponent(owner.trim());
  final encodedRepo = Uri.encodeComponent(repo.trim());
  final data = await dioRequest.get(
    '${HttpConstants.repos}/$encodedOwner/$encodedRepo/labels',
    params: {'per_page': perPage},
  );
  return asModelList(data, IssueLabel.fromJson);
}

/// 获取单个 Pull Request 详情（含 head/base 分支、Merge 状态及统计行数）
Future<PullRequestDetail> getPullRequestDetailAPI(
  String owner,
  String repo,
  int number, {
  CancelToken? cancelToken,
}) async {
  final data = await dioRequest.get(
    '${_pullsBase(owner, repo)}/$number',
    cancelToken: cancelToken,
  );
  return PullRequestDetail.fromJson(asMap(data));
}

/// 分页获取 Pull Request 的变更文件与 Patch Diff 列表
Future<PageResult<CommitFileChange>> getPullRequestFilesAPI(
  String owner,
  String repo,
  int number, {
  int page = 1,
  int perPage = 30,
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    '${_pullsBase(owner, repo)}/$number/files',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<CommitFileChange>(
    items: asModelList(res.data, CommitFileChange.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 修改评论正文（需要是本人评论或具备仓库维护权限）
Future<IssueComment> updateIssueCommentAPI(
  String owner,
  String repo,
  int commentId,
  String body,
) async {
  final encodedOwner = Uri.encodeComponent(owner.trim());
  final encodedRepo = Uri.encodeComponent(repo.trim());
  final data = await dioRequest.patch(
    '${HttpConstants.repos}/$encodedOwner/$encodedRepo/issues/comments/$commentId',
    data: {'body': body.trim()},
  );
  return IssueComment.fromJson(asMap(data));
}

/// 删除指定评论
Future<void> deleteIssueCommentAPI(
  String owner,
  String repo,
  int commentId,
) async {
  final encodedOwner = Uri.encodeComponent(owner.trim());
  final encodedRepo = Uri.encodeComponent(repo.trim());
  await dioRequest.delete(
    '${HttpConstants.repos}/$encodedOwner/$encodedRepo/issues/comments/$commentId',
  );
}

/// 为指定 Issue/PR 评论添加 Emoji Reaction（如 `+1` / `heart` / `rocket` / `eyes`）
Future<void> addIssueCommentReactionAPI(
  String owner,
  String repo,
  int commentId,
  String content,
) async {
  final encodedOwner = Uri.encodeComponent(owner.trim());
  final encodedRepo = Uri.encodeComponent(repo.trim());
  await dioRequest.post(
    '${HttpConstants.repos}/$encodedOwner/$encodedRepo/issues/comments/$commentId/reactions',
    data: {'content': content},
  );
}

/// 全量更新 Issue / PR 的标签列表
Future<List<IssueLabel>> setIssueLabelsAPI(
  String owner,
  String repo,
  int number,
  List<String> labels,
) async {
  final data = await dioRequest.put(
    '${_issuesBase(owner, repo)}/$number/labels',
    data: {'labels': labels},
  );
  return asModelList(data, IssueLabel.fromJson);
}

/// 合并指定 Pull Request（`mergeMethod`: `merge` / `squash` / `rebase`）
///
/// `sha` 为调用方审阅过的 head 提交，GitHub 会拒绝与当前 head 不一致的合并请求，
/// 避免用户审完 diff 后分支又被推送新提交、却把未经审阅的代码合入。
Future<({bool merged, String message})> mergePullRequestAPI(
  String owner,
  String repo,
  int number, {
  String mergeMethod = 'merge',
  String commitTitle = '',
  String sha = '',
}) async {
  final data = asMap(
    await dioRequest.put(
      '${_pullsBase(owner, repo)}/$number/merge',
      data: {
        'merge_method': mergeMethod,
        if (commitTitle.trim().isNotEmpty) 'commit_title': commitTitle.trim(),
        if (sha.trim().isNotEmpty) 'sha': sha.trim(),
      },
    ),
  );
  return (merged: asBool(data['merged']), message: asString(data['message']));
}

/// 获取 Pull Request 总体审阅结论列表
///
/// 取 `per_page: 100`（GitHub 单页上限）：审阅结论按人聚合，单个 PR 极少超过
/// 100 条；若仍超限则只展示最近 100 条，避免多页串联带来的额外配额消耗。
Future<List<PullRequestReview>> getPullRequestReviewsAPI(
  String owner,
  String repo,
  int number, {
  CancelToken? cancelToken,
}) async {
  final data = await dioRequest.get(
    '${_pullsBase(owner, repo)}/$number/reviews',
    params: {'per_page': 100},
    cancelToken: cancelToken,
  );
  return asModelList(data, PullRequestReview.fromJson);
}

/// 获取 Pull Request 行内代码评审评论列表
///
/// 与审阅结论一致取 `per_page: 100`，减少大型 PR 上行内批注被截断的概率。
Future<List<PullRequestReviewComment>> getPullRequestReviewCommentsAPI(
  String owner,
  String repo,
  int number, {
  CancelToken? cancelToken,
}) async {
  final data = await dioRequest.get(
    '${_pullsBase(owner, repo)}/$number/comments',
    params: {'per_page': 100},
    cancelToken: cancelToken,
  );
  return asModelList(data, PullRequestReviewComment.fromJson);
}

/// 提交 Pull Request 代码审阅结论（`APPROVE` / `REQUEST_CHANGES` / `COMMENT`）
Future<PullRequestReview> submitPullRequestReviewAPI(
  String owner,
  String repo,
  int number, {
  required String event,
  String body = '',
}) async {
  final payload = <String, dynamic>{
    'event': event,
    if (body.trim().isNotEmpty) 'body': body.trim(),
  };
  final data = await dioRequest.post(
    '${_pullsBase(owner, repo)}/$number/reviews',
    data: payload,
  );
  return PullRequestReview.fromJson(asMap(data));
}
