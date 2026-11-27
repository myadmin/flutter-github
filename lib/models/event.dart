import 'package:gh_explorer/models/parsers.dart';

/// GitHub 用户动态事件模型
class GithubEvent {
  const GithubEvent({
    required this.id,
    required this.type,
    required this.actorLogin,
    required this.actorAvatar,
    required this.repoName,
    required this.actionText,
    required this.detailText,
    this.createdAt,
  });

  final String id;
  final String type;
  final String actorLogin;
  final String actorAvatar;
  final String repoName;
  final String actionText;
  final String detailText;
  final DateTime? createdAt;

  factory GithubEvent.fromJson(Map<String, dynamic> json) {
    final type = asString(json['type']);
    final actor = asMapOrEmpty(json['actor']);
    final repo = asMapOrEmpty(json['repo']);
    final payload = asMapOrEmpty(json['payload']);
    final (actionText, detailText) = _describeEvent(type, payload);

    return GithubEvent(
      id: asString(json['id']),
      type: type,
      actorLogin: asString(actor['login']),
      actorAvatar: asString(actor['avatar_url']),
      repoName: asString(repo['name']),
      actionText: actionText,
      detailText: detailText,
      createdAt: asDateTime(json['created_at']),
    );
  }

  static (String, String) _describeEvent(
    String type,
    Map<String, dynamic> payload,
  ) {
    switch (type) {
      case 'WatchEvent':
        return ('Star 了仓库', '');
      case 'ForkEvent':
        final forkee = asMapOrEmpty(payload['forkee']);
        return ('Fork 了仓库', asString(forkee['full_name']));
      case 'PushEvent':
        final ref = asString(payload['ref']).replaceFirst('refs/heads/', '');
        final size = asInt(payload['size']);
        final detail = ref.isEmpty
            ? ''
            : size > 0
            ? '推送 $size 个提交到 $ref'
            : '推送到分支 $ref';
        return ('推送了代码', detail);
      case 'CreateEvent':
        final refType = asString(payload['ref_type'], fallback: 'repository');
        final ref = asString(payload['ref']);
        return ('创建了 $refType', ref);
      case 'IssuesEvent':
        final action = asString(payload['action'], fallback: '更新了');
        final issue = asMapOrEmpty(payload['issue']);
        final num = asInt(issue['number']);
        final title = asString(issue['title']);
        return ('$action Issue #$num', title);
      case 'IssueCommentEvent':
        final issue = asMapOrEmpty(payload['issue']);
        final comment = asMapOrEmpty(payload['comment']);
        final num = asInt(issue['number']);
        return ('评论了 #$num', asString(comment['body']));
      case 'PullRequestEvent':
        final action = asString(payload['action'], fallback: '更新了');
        final pr = asMapOrEmpty(payload['pull_request']);
        final num = asInt(pr['number']);
        return ('$action Pull Request #$num', asString(pr['title']));
      case 'ReleaseEvent':
        final release = asMapOrEmpty(payload['release']);
        final tag = asString(release['tag_name']);
        final name = asString(release['name']);
        return ('发布了新版本 $tag', name);
      case 'PublicEvent':
        return ('将仓库设为公开', '');
      default:
        return (type.replaceAll('Event', ''), '');
    }
  }
}

/// GitHub 通知条目模型
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.unread,
    required this.reason,
    required this.subjectTitle,
    required this.subjectType,
    required this.subjectUrl,
    required this.repoFullName,
    required this.repoOwnerAvatar,
    this.updatedAt,
  });

  final String id;
  final bool unread;
  final String reason;
  final String subjectTitle;
  final String subjectType;
  final String subjectUrl;
  final String repoFullName;
  final String repoOwnerAvatar;
  final DateTime? updatedAt;

  /// 从 API URL 中解析出 owner/repo（用于跳转）
  String get repoOwner {
    final parts = repoFullName.split('/');
    return parts.isNotEmpty ? parts.first : '';
  }

  String get repoName {
    final parts = repoFullName.split('/');
    return parts.length >= 2 ? parts[1] : '';
  }

  /// Issue / PR 编号与 Commit SHA 的解析正则提升为静态常量，
  /// 避免通知列表每帧重建每个卡片时都重新编译正则
  static final RegExp _issueOrPullPath = RegExp(r'/(?:issues|pulls)/(\d+)$');
  static final RegExp _commitPath = RegExp(r'/commits/([0-9a-fA-F]+)$');

  /// 从 API URL 解析关联 Issue 或 PR 编号（如 `/issues/42` 或 `/pulls/12`）
  int? get subjectNumber {
    final match = _issueOrPullPath.firstMatch(subjectUrl);
    if (match == null) return null;
    final n = int.tryParse(match.group(1) ?? '');
    return (n != null && n > 0) ? n : null;
  }

  /// 从 API URL 解析关联 Commit SHA（如 `/commits/abc1234`）
  String get subjectCommitSha {
    final match = _commitPath.firstMatch(subjectUrl);
    return match?.group(1) ?? '';
  }

  /// 将 GitHub 通知原因翻译为中文标签
  String get reasonLabel {
    switch (reason.toLowerCase()) {
      case 'mention':
        return '提及了你';
      case 'author':
        return '你发起的';
      case 'comment':
        return '新评论';
      case 'assign':
        return '指派给你';
      case 'review_requested':
        return '请求代码审查';
      case 'state_change':
        return '状态变更';
      case 'subscribed':
        return '订阅动态';
      case 'team_mention':
        return '团队提及';
      default:
        return reason;
    }
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final subject = asMapOrEmpty(json['subject']);
    final repo = asMapOrEmpty(json['repository']);
    final owner = asMapOrEmpty(repo['owner']);
    return NotificationItem(
      id: asString(json['id']),
      unread: asBool(json['unread']),
      reason: asString(json['reason']),
      subjectTitle: asString(subject['title']),
      subjectType: asString(subject['type']),
      subjectUrl: asString(subject['url']),
      repoFullName: asString(repo['full_name']),
      repoOwnerAvatar: asString(owner['avatar_url']),
      updatedAt: asDateTime(json['updated_at']),
    );
  }
}
