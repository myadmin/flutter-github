import 'package:gh_explorer/models/parsers.dart';

/// 仓库所有者 / 提交者简要信息
class RepoOwner {
  const RepoOwner({
    required this.id,
    required this.login,
    required this.avatarUrl,
    required this.type,
    required this.htmlUrl,
  });

  final int id;
  final String login;
  final String avatarUrl;
  final String type;
  final String htmlUrl;

  factory RepoOwner.fromJson(Map<String, dynamic> json) {
    return RepoOwner(
      id: asInt(json['id']),
      login: asString(json['login']),
      avatarUrl: asString(json['avatar_url']),
      type: asString(json['type'], fallback: 'User'),
      htmlUrl: asString(json['html_url']),
    );
  }
}

/// 开源协议信息
class RepoLicense {
  const RepoLicense({
    required this.key,
    required this.name,
    required this.spdxId,
  });

  final String key;
  final String name;
  final String spdxId;

  bool get isEmpty => name.isEmpty && spdxId.isEmpty;

  String get displayName =>
      spdxId.isNotEmpty && spdxId != 'NOASSERTION' ? spdxId : name;

  factory RepoLicense.fromJson(Map<String, dynamic> json) {
    return RepoLicense(
      key: asString(json['key']),
      name: asString(json['name']),
      spdxId: asString(json['spdx_id']),
    );
  }
}

/// GitHub 仓库列表项与详情模型
class RepoItem {
  const RepoItem({
    required this.id,
    required this.name,
    required this.fullName,
    required this.description,
    required this.language,
    required this.stargazersCount,
    required this.forksCount,
    required this.watchersCount,
    required this.subscribersCount,
    required this.openIssuesCount,
    required this.isPrivate,
    required this.isFork,
    required this.isArchived,
    required this.defaultBranch,
    required this.htmlUrl,
    required this.homepage,
    required this.topics,
    required this.owner,
    this.license,
    this.parentFullName = '',
    this.cloneUrl = '',
    this.sshUrl = '',
    this.createdAt,
    this.updatedAt,
    this.pushedAt,
  });

  final int id;
  final String name;
  final String fullName;
  final String description;
  final String language;
  final int stargazersCount;
  final int forksCount;
  final int watchersCount;
  final int subscribersCount;
  final int openIssuesCount;
  final bool isPrivate;
  final bool isFork;
  final bool isArchived;
  final String defaultBranch;
  final String htmlUrl;
  final String homepage;
  final List<String> topics;
  final RepoOwner owner;
  final RepoLicense? license;
  final String parentFullName;
  final String cloneUrl;
  final String sshUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? pushedAt;

  /// 从 fullName 或 owner 中安全提取仓库所属者用户名
  String get ownerLogin {
    if (owner.login.isNotEmpty) return owner.login;
    final parts = fullName.split('/');
    return parts.isNotEmpty ? parts.first : '';
  }

  /// 从 fullName 或 name 中安全提取仓库短名称
  String get repoName {
    if (name.isNotEmpty) return name;
    final parts = fullName.split('/');
    return parts.length >= 2 ? parts[1] : '';
  }

  /// HTTPS Clone 地址（字段缺失时按 owner/repo 兜底拼接）
  String get effectiveCloneUrl {
    if (cloneUrl.isNotEmpty) return cloneUrl;
    if (ownerLogin.isNotEmpty && repoName.isNotEmpty) {
      return 'https://github.com/$ownerLogin/$repoName.git';
    }
    return '';
  }

  /// SSH Clone 地址（字段缺失时按 owner/repo 兜底拼接）
  String get effectiveSshUrl {
    if (sshUrl.isNotEmpty) return sshUrl;
    if (ownerLogin.isNotEmpty && repoName.isNotEmpty) {
      return 'git@github.com:$ownerLogin/$repoName.git';
    }
    return '';
  }

  /// 详情页优先展示 subscribersCount（实际 Watch 数），缺失时回退 watchersCount
  int get watchCount => subscribersCount > 0 ? subscribersCount : watchersCount;

  /// 从 GitHub 仓库接口响应反序列化
  factory RepoItem.fromJson(Map<String, dynamic> json) {
    final licenseJson = asMapOrNull(json['license']);
    final parentJson = asMapOrNull(json['parent']);
    return RepoItem(
      id: asInt(json['id']),
      name: asString(json['name']),
      fullName: asString(json['full_name']),
      description: asString(json['description']),
      language: asString(json['language']),
      stargazersCount: asInt(json['stargazers_count']),
      forksCount: asInt(json['forks_count']),
      watchersCount: asInt(json['watchers_count']),
      subscribersCount: asInt(json['subscribers_count']),
      openIssuesCount: asInt(json['open_issues_count']),
      isPrivate: asBool(json['private']),
      isFork: asBool(json['fork']),
      isArchived: asBool(json['archived']),
      defaultBranch: asString(json['default_branch'], fallback: 'main'),
      htmlUrl: asString(json['html_url']),
      homepage: asString(json['homepage']),
      topics: asStringList(json['topics']),
      owner: RepoOwner.fromJson(asMapOrEmpty(json['owner'])),
      license: licenseJson == null ? null : RepoLicense.fromJson(licenseJson),
      parentFullName: parentJson == null
          ? ''
          : asString(parentJson['full_name']),
      cloneUrl: asString(json['clone_url']),
      sshUrl: asString(json['ssh_url']),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      pushedAt: asDateTime(json['pushed_at']),
    );
  }
}

/// 仓库搜索分页响应
class RepoSearchResult {
  const RepoSearchResult({
    required this.totalCount,
    required this.incompleteResults,
    required this.items,
  });

  final int totalCount;
  final bool incompleteResults;
  final List<RepoItem> items;

  factory RepoSearchResult.fromJson(Map<String, dynamic> json) {
    return RepoSearchResult(
      totalCount: asInt(json['total_count']),
      incompleteResults: asBool(json['incomplete_results']),
      items: asList(json['items'], RepoItem.fromJson),
    );
  }
}

/// 仓库文件或目录条目
class RepoContentItem {
  const RepoContentItem({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.type,
    required this.htmlUrl,
    required this.downloadUrl,
    required this.content,
    required this.encoding,
  });

  final String name;
  final String path;
  final String sha;
  final int size;
  final String type;
  final String htmlUrl;
  final String downloadUrl;
  final String content;
  final String encoding;

  bool get isDir => type == 'dir';
  bool get isSubmodule => type == 'submodule';

  factory RepoContentItem.fromJson(Map<String, dynamic> json) {
    return RepoContentItem(
      name: asString(json['name']),
      path: asString(json['path']),
      sha: asString(json['sha']),
      size: asInt(json['size']),
      type: asString(json['type'], fallback: 'file'),
      htmlUrl: asString(json['html_url']),
      downloadUrl: asString(json['download_url']),
      content: asString(json['content']),
      encoding: asString(json['encoding']),
    );
  }
}

/// 仓库分支
class RepoBranch {
  const RepoBranch({
    required this.name,
    required this.commitSha,
    required this.isProtected,
  });

  final String name;
  final String commitSha;
  final bool isProtected;

  factory RepoBranch.fromJson(Map<String, dynamic> json) {
    final commitMap = asMapOrEmpty(json['commit']);
    return RepoBranch(
      name: asString(json['name']),
      commitSha: asString(commitMap['sha']),
      isProtected: asBool(json['protected']),
    );
  }
}

/// Commit 提交记录
class CommitItem {
  const CommitItem({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.authorLogin,
    required this.authorAvatar,
    required this.htmlUrl,
    this.committedAt,
  });

  final String sha;
  final String message;
  final String authorName;
  final String authorLogin;
  final String authorAvatar;
  final String htmlUrl;
  final DateTime? committedAt;

  /// 提交 SHA 短码（取前 7 位用于卡片展示）
  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  /// 提取提交信息首行作为摘要标题
  String get titleLine {
    final idx = message.indexOf('\n');
    return idx == -1 ? message : message.substring(0, idx).trim();
  }

  /// 优先展示关联 GitHub 账号名，未关联时回退提交者署名
  String get displayAuthor => authorLogin.isNotEmpty ? authorLogin : authorName;

  /// 从 GitHub `/commits` 接口元素反序列化
  factory CommitItem.fromJson(Map<String, dynamic> json) {
    final commit = asMapOrEmpty(json['commit']);
    final commitAuthor = asMapOrEmpty(commit['author']);
    final ghAuthor = asMapOrNull(json['author']);
    return CommitItem(
      sha: asString(json['sha']),
      message: asString(commit['message']),
      authorName: asString(commitAuthor['name'], fallback: 'Unknown'),
      authorLogin: ghAuthor == null ? '' : asString(ghAuthor['login']),
      authorAvatar: ghAuthor == null ? '' : asString(ghAuthor['avatar_url']),
      htmlUrl: asString(json['html_url']),
      committedAt: asDateTime(commitAuthor['date']),
    );
  }
}

/// Commit 或 Pull Request 中单个文件的变更明细与 Diff Patch
class CommitFileChange {
  const CommitFileChange({
    required this.filename,
    required this.previousFilename,
    required this.status,
    required this.additions,
    required this.deletions,
    required this.changes,
    required this.patch,
  });

  final String filename;
  final String previousFilename;
  final String status;
  final int additions;
  final int deletions;
  final int changes;
  final String patch;

  /// 文件状态短标识（A 新增 / D 删除 / R 重命名 / M 修改）
  String get statusBadge {
    switch (status.toLowerCase()) {
      case 'added':
        return 'A';
      case 'removed':
        return 'D';
      case 'renamed':
        return 'R';
      default:
        return 'M';
    }
  }

  /// 兼容重命名路径展示
  String get displayPath => previousFilename.isNotEmpty && status == 'renamed'
      ? '$previousFilename → $filename'
      : filename;

  factory CommitFileChange.fromJson(Map<String, dynamic> json) {
    return CommitFileChange(
      filename: asString(json['filename']),
      previousFilename: asString(json['previous_filename']),
      status: asString(json['status'], fallback: 'modified'),
      additions: asInt(json['additions']),
      deletions: asInt(json['deletions']),
      changes: asInt(json['changes']),
      patch: asString(json['patch']),
    );
  }
}

/// Commit 变更行数统计
class CommitStats {
  const CommitStats({
    required this.total,
    required this.additions,
    required this.deletions,
  });

  final int total;
  final int additions;
  final int deletions;

  factory CommitStats.fromJson(Map<String, dynamic> json) {
    return CommitStats(
      total: asInt(json['total']),
      additions: asInt(json['additions']),
      deletions: asInt(json['deletions']),
    );
  }
}

/// 单个 Commit 完整详情（含父节点 SHA、变更汇总与逐文件 Diff）
class CommitDetail {
  const CommitDetail({
    required this.commit,
    required this.parents,
    required this.stats,
    required this.files,
  });

  final CommitItem commit;
  final List<String> parents;
  final CommitStats stats;
  final List<CommitFileChange> files;

  factory CommitDetail.fromJson(Map<String, dynamic> json) {
    final parentItems = json['parents'];
    final parentShas = <String>[];
    if (parentItems is List) {
      for (final item in parentItems) {
        final sha = asString(asMapOrEmpty(item)['sha']);
        if (sha.isNotEmpty) parentShas.add(sha);
      }
    }
    return CommitDetail(
      commit: CommitItem.fromJson(json),
      parents: List<String>.unmodifiable(parentShas),
      stats: CommitStats.fromJson(asMapOrEmpty(json['stats'])),
      files: asList(json['files'], CommitFileChange.fromJson),
    );
  }
}

/// 仓库贡献者信息（含贡献提交次数）
class RepoContributor {
  const RepoContributor({required this.owner, required this.contributions});

  final RepoOwner owner;
  final int contributions;

  factory RepoContributor.fromJson(Map<String, dynamic> json) {
    return RepoContributor(
      owner: RepoOwner.fromJson(json),
      contributions: asInt(json['contributions']),
    );
  }
}
