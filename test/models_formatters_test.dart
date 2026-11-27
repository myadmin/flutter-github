import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/components/Issue/gh_pr_review_section.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/event.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';

import 'helpers/mock_http.dart';

/// 模型与工具单元测试：覆盖类型解析工具、数字/时间格式化、各业务模型反序列化与足迹分组
void main() {
  test('parsers 安全类型转换工具覆盖正常与异常输入', () {
    expect(asString(null, fallback: 'x'), 'x');
    expect(asString(123), '123');
    expect(asInt(' 42 '), 42);
    expect(asInt(12.8), 12);
    expect(asInt('bad', fallback: -1), -1);
    expect(asBool('TRUE'), isTrue);
    expect(asBool(1), isTrue);
    expect(asBool('0'), isFalse);
    expect(asDateTime('2026-11-25T10:00:00Z')?.year, 2026);
    expect(asDateTime('invalid'), isNull);
    expect(asStringList(['a', null, 1]), ['a', '1']);
    expect(() => asMap(<dynamic>[]), throwsFormatException);
    expect(
      () => asModelList(<String, dynamic>{}, RepoItem.fromJson),
      throwsFormatException,
    );
    expect(asMapOrEmpty('bad'), isEmpty);
    expect(asMapOrNull('bad'), isNull);
  });

  test('formatters 数字缩写、相对时间、Base64 与 README 相对图片路径解析', () {
    expect(formatCompactNumber(950), '950');
    expect(formatCompactNumber(1250), '1.3k');
    expect(formatCompactNumber(125000), '125k');
    expect(formatCompactNumber(1500000), '1.5m');
    // 999999 若直接 floor 到 k 会显示成 '1000k'，必须进位到 m
    expect(formatCompactNumber(999999), '1.0m');
    expect(formatCompactNumber(999499), '999k');
    expect(formatCompactNumber(-1), '0');

    final now = DateTime(2026, 11, 25, 12, 0);
    expect(formatRelativeTime(now, now: now), '刚刚');
    expect(
      formatRelativeTime(now.subtract(const Duration(minutes: 10)), now: now),
      '10 分钟前',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
      '3 小时前',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(days: 5)), now: now),
      '5 天前',
    );

    expect(parseHasNextPage('<url>; rel="next"'), isTrue);
    expect(parseHasNextPage('<url>; rel="prev"'), isFalse);

    expect(
      resolveRepoAssetUrl(
        './docs/banner.png',
        owner: 'flutter',
        repo: 'flutter',
        branch: 'master',
      ),
      'https://raw.githubusercontent.com/flutter/flutter/master/docs/banner.png',
    );
    expect(
      resolveRepoAssetUrl(
        'https://example.com/a.png',
        owner: 'flutter',
        repo: 'flutter',
        branch: 'master',
      ),
      'https://example.com/a.png',
    );
  });

  test('各业务模型正确反序列化并生成足迹分组', () {
    final user = GithubUser.fromJson(userJson(name: ''));
    expect(user.isLoggedIn, isTrue);
    expect(user.displayName, 'octocat');

    final repo = RepoItem.fromJson(repoJson());
    expect(repo.ownerLogin, 'flutter');
    expect(repo.repoName, 'flutter');
    // watch 人数只取 subscribers_count：watchers_count 现等价于星标数，不能回退
    expect(repo.watchCount, 3600);

    final noSubscribers = RepoItem.fromJson(
      repoJson()..remove('subscribers_count'),
    );
    expect(noSubscribers.watchCount, 0, reason: '缺少订阅数时不得把星标数当订阅数');
    expect(repo.license?.displayName, 'BSD-3-Clause');

    final renamed = CommitFileChange.fromJson({
      'filename': 'lib/new.dart',
      'previous_filename': 'lib/old.dart',
      'status': 'Renamed',
    });
    expect(renamed.statusBadge, 'R');
    expect(renamed.displayPath, 'lib/old.dart → lib/new.dart');

    final modified = CommitFileChange.fromJson({
      'filename': 'lib/a.dart',
      'previous_filename': 'lib/b.dart',
      'status': 'modified',
    });
    expect(modified.displayPath, 'lib/a.dart');

    final commit = CommitItem.fromJson(commitJson());
    expect(commit.shortSha, '1234567');
    expect(commit.titleLine, 'feat: initial commit');

    final issue = IssueItem.fromJson(issueJson(isPr: true));
    expect(issue.isPullRequest, isTrue);
    expect(issue.isOpen, isTrue);
    expect(issue.closedAt, isNull);
    final closedAt = DateTime.utc(2026, 11, 26, 9);
    final updated = issue.copyWith(
      state: 'closed',
      closedAt: closedAt,
      updatedAt: closedAt,
    );
    expect(updated.state, 'closed');
    expect(updated.closedAt, closedAt, reason: 'copyWith 需支持状态变更时间');
    expect(updated.updatedAt, closedAt);
    expect(updated.createdAt, issue.createdAt, reason: '未传入的字段保持原值');

    final event = GithubEvent.fromJson(eventJson(type: 'WatchEvent'));
    expect(event.actionText, 'Star 了仓库');

    final notif = NotificationItem.fromJson(notificationJson());
    expect(notif.repoOwner, 'flutter');
    expect(notif.repoName, 'flutter');

    final now = DateTime(2026, 11, 25, 14, 0);
    final groups = groupFootprints([
      FootprintItem.fromRepo(repo, now: now),
      FootprintItem.fromRepo(repo, now: now.subtract(const Duration(days: 1))),
      FootprintItem.fromRepo(repo, now: now.subtract(const Duration(days: 4))),
    ], now: now);
    expect(groups.map((g) => g.title).toList(), ['今天', '昨天', '更早']);

    expect(AppColors.languageColor('Dart'), isNot(AppColors.textSecondary));
    expect(AppColors.languageColor('UnknownLang'), AppColors.textSecondary);
    expect(resolveErrorMessage(const FormatException('bad')), '数据格式异常，请稍后重试');
  });

  test('PR 审阅结论只保留每位审阅者最新的有效结论', () {
    PullRequestReview review(String login, String state, String? at) =>
        PullRequestReview(
          id: 1,
          state: state,
          body: '',
          user: RepoOwner.fromJson({'login': login, 'avatar_url': ''}),
          submittedAt: at == null ? null : DateTime.parse(at),
        );

    // 同一人先 APPROVED 后 COMMENTED：结论仍是「已批准」
    final latest = GhPrSummaryCard.latestDecisiveReviews([
      review('alice', 'APPROVED', '2026-11-27T10:00:00Z'),
      review('alice', 'COMMENTED', '2026-11-27T11:00:00Z'),
    ]);
    expect(latest, hasLength(1));
    expect(latest.single.stateLabel, '已批准');

    // 同一人后续改为 CHANGES_REQUESTED：以最新结论为准
    final changed = GhPrSummaryCard.latestDecisiveReviews([
      review('alice', 'APPROVED', '2026-11-27T10:00:00Z'),
      review('alice', 'CHANGES_REQUESTED', '2026-11-27T12:00:00Z'),
      review('alice', 'PENDING', '2026-11-27T13:00:00Z'),
    ]);
    expect(changed.single.stateLabel, '需修改');

    // 乱序返回时按 submittedAt 取最新；DISMISSED 同样计入
    final unordered = GhPrSummaryCard.latestDecisiveReviews([
      review('bob', 'DISMISSED', '2026-11-27T09:00:00Z'),
      review('bob', 'APPROVED', '2026-11-27T08:00:00Z'),
    ]);
    expect(unordered.single.stateLabel, '已驳回');

    // 无 login 或只有 COMMENTED/PENDING 的条目不参与统计
    expect(
      GhPrSummaryCard.latestDecisiveReviews([
        review('', 'APPROVED', '2026-11-27T10:00:00Z'),
        review('carol', 'COMMENTED', '2026-11-27T10:00:00Z'),
        review('dave', 'PENDING', null),
      ]),
      isEmpty,
    );
  });
}
