import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';

/// Issue 标签
class IssueLabel {
  const IssueLabel({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.description,
  });

  final int id;
  final String name;
  final String colorHex;
  final String description;

  factory IssueLabel.fromJson(Map<String, dynamic> json) {
    return IssueLabel(
      id: asInt(json['id']),
      name: asString(json['name']),
      colorHex: asString(json['color'], fallback: '0969da'),
      description: asString(json['description']),
    );
  }
}

/// Issue / Pull Request 列表与详情模型
class IssueItem {
  const IssueItem({
    required this.id,
    required this.number,
    required this.title,
    required this.body,
    required this.state,
    required this.commentsCount,
    required this.isPullRequest,
    this.isMerged = false,
    required this.htmlUrl,
    required this.user,
    required this.labels,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
  });

  final int id;
  final int number;
  final String title;
  final String body;
  final String state;
  final int commentsCount;
  final bool isPullRequest;
  final bool isMerged;
  final String htmlUrl;
  final RepoOwner user;
  final List<IssueLabel> labels;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  bool get isOpen => state.toLowerCase() == 'open';

  IssueItem copyWith({
    String? title,
    String? body,
    String? state,
    int? commentsCount,
    bool? isMerged,
  }) {
    return IssueItem(
      id: id,
      number: number,
      title: title ?? this.title,
      body: body ?? this.body,
      state: state ?? this.state,
      commentsCount: commentsCount ?? this.commentsCount,
      isPullRequest: isPullRequest,
      isMerged: isMerged ?? this.isMerged,
      htmlUrl: htmlUrl,
      user: user,
      labels: labels,
      createdAt: createdAt,
      updatedAt: updatedAt,
      closedAt: closedAt,
    );
  }

  factory IssueItem.fromJson(Map<String, dynamic> json) {
    final prMap = asMapOrNull(json['pull_request']);
    return IssueItem(
      id: asInt(json['id']),
      number: asInt(json['number']),
      title: asString(json['title']),
      body: asString(json['body']),
      state: asString(json['state'], fallback: 'open'),
      commentsCount: asInt(json['comments']),
      isPullRequest: prMap != null,
      isMerged:
          asDateTime(json['merged_at']) != null ||
          asDateTime(prMap?['merged_at']) != null,
      htmlUrl: asString(json['html_url']),
      user: RepoOwner.fromJson(asMapOrEmpty(json['user'])),
      labels: asList(json['labels'], IssueLabel.fromJson),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      closedAt: asDateTime(json['closed_at']),
    );
  }

  /// 从 `/pulls` 列表元素构造条目标记 `isPullRequest = true`
  ///
  /// 评论数口径与 Issue 保持一致，仅统计 issue comments；review comments
  /// 属于代码评审，不并入「评论」，否则与详情页数字不一致。
  factory IssueItem.fromPullRequestJson(Map<String, dynamic> json) {
    return IssueItem(
      id: asInt(json['id']),
      number: asInt(json['number']),
      title: asString(json['title']),
      body: asString(json['body']),
      state: asString(json['state'], fallback: 'open'),
      commentsCount: asInt(json['comments']),
      isPullRequest: true,
      isMerged: asDateTime(json['merged_at']) != null,
      htmlUrl: asString(json['html_url']),
      user: RepoOwner.fromJson(asMapOrEmpty(json['user'])),
      labels: asList(json['labels'], IssueLabel.fromJson),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      closedAt: asDateTime(json['closed_at']),
    );
  }
}

/// Pull Request 专属元数据与统计信息
class PullRequestDetail {
  const PullRequestDetail({
    required this.number,
    required this.title,
    required this.body,
    required this.state,
    required this.merged,
    required this.draft,
    required this.mergeable,
    required this.headRef,
    required this.headSha,
    required this.headRepoFullName,
    required this.baseRef,
    required this.commits,
    required this.additions,
    required this.deletions,
    required this.changedFiles,
    required this.mergedByLogin,
    required this.htmlUrl,
    this.mergedAt,
  });

  final int number;
  final String title;
  final String body;
  final String state;
  final bool merged;
  final bool draft;
  final bool? mergeable;
  final String headRef;
  final String headSha;
  final String headRepoFullName;
  final String baseRef;
  final int commits;
  final int additions;
  final int deletions;
  final int changedFiles;
  final String mergedByLogin;
  final String htmlUrl;
  final DateTime? mergedAt;

  bool get isOpen => state.toLowerCase() == 'open';

  factory PullRequestDetail.fromJson(Map<String, dynamic> json) {
    final head = asMapOrEmpty(json['head']);
    final headRepo = asMapOrNull(head['repo']);
    final base = asMapOrEmpty(json['base']);
    final mergedBy = asMapOrNull(json['merged_by']);
    final rawMergeable = json['mergeable'];
    return PullRequestDetail(
      number: asInt(json['number']),
      title: asString(json['title']),
      body: asString(json['body']),
      state: asString(json['state'], fallback: 'open'),
      merged: asBool(json['merged']) || asDateTime(json['merged_at']) != null,
      draft: asBool(json['draft']),
      mergeable: rawMergeable is bool ? rawMergeable : null,
      headRef: asString(head['ref']),
      headSha: asString(head['sha']),
      headRepoFullName: headRepo == null ? '' : asString(headRepo['full_name']),
      baseRef: asString(base['ref']),
      commits: asInt(json['commits']),
      additions: asInt(json['additions']),
      deletions: asInt(json['deletions']),
      changedFiles: asInt(json['changed_files']),
      mergedByLogin: mergedBy == null ? '' : asString(mergedBy['login']),
      htmlUrl: asString(json['html_url']),
      mergedAt: asDateTime(json['merged_at']),
    );
  }
}

/// Issue / PR 评论模型
class IssueComment {
  const IssueComment({
    required this.id,
    required this.body,
    required this.user,
    required this.htmlUrl,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String body;
  final RepoOwner user;
  final String htmlUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory IssueComment.fromJson(Map<String, dynamic> json) {
    return IssueComment(
      id: asInt(json['id']),
      body: asString(json['body']),
      user: RepoOwner.fromJson(asMapOrEmpty(json['user'])),
      htmlUrl: asString(json['html_url']),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
    );
  }
}
