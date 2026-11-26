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
  final String htmlUrl;
  final RepoOwner user;
  final List<IssueLabel> labels;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  bool get isOpen => state.toLowerCase() == 'open';

  factory IssueItem.fromJson(Map<String, dynamic> json) {
    return IssueItem(
      id: asInt(json['id']),
      number: asInt(json['number']),
      title: asString(json['title']),
      body: asString(json['body']),
      state: asString(json['state'], fallback: 'open'),
      commentsCount: asInt(json['comments']),
      isPullRequest: asMapOrNull(json['pull_request']) != null,
      htmlUrl: asString(json['html_url']),
      user: RepoOwner.fromJson(asMapOrEmpty(json['user'])),
      labels: asList(json['labels'], IssueLabel.fromJson),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      closedAt: asDateTime(json['closed_at']),
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
