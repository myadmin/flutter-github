import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/models/event.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/Mine/index.dart';
import 'package:gh_explorer/pages/MyStars/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/pages/RepoCommitDetail/index.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/pages/RepoIssueCreate/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoIssues/index.dart';
import 'package:gh_explorer/pages/RepoPeople/index.dart';
import 'package:gh_explorer/pages/RepoReleases/index.dart';
import 'package:gh_explorer/pages/Settings/index.dart';
import 'package:gh_explorer/services/star_service.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/search_history_store.dart';
import 'package:gh_explorer/constants/explore_config.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DioRequest.onUnauthorized = null;
    registerTestControllers();
  });

  testWidgets('RepoCommitsPage 点击提交进入 RepoCommitDetailPage 展示统计与 Diff', (
    tester,
  ) async {
    installMock((options) {
      if (options.path == '/repos/flutter/flutter/commits') {
        return jsonResponse([commitJson()]);
      }
      if (options.path == '/repos/flutter/flutter/commits/1234567890abcdef') {
        return jsonResponse({
          ...commitJson(),
          'commit': {
            'message': 'feat: initial commit\n\nDetailed commit notes',
            'author': {'name': 'Octocat', 'date': '2026-11-25T10:00:00Z'},
          },
          'parents': [
            {'sha': 'parent12345678'},
          ],
          'stats': {'total': 5, 'additions': 3, 'deletions': 2},
          'files': [
            {
              'filename': 'lib/main.dart',
              'status': 'modified',
              'additions': 3,
              'deletions': 2,
              'changes': 5,
              'patch': '@@ -1,2 +1,3 @@\n-oldLine\n+newLine\n contextLine',
            },
          ],
        });
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(
        const RepoCommitsPage(owner: 'flutter', repoName: 'flutter'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('feat: initial commit'));
    await tester.pumpAndSettle();

    expect(find.byType(RepoCommitDetailPage), findsOneWidget);
    expect(find.textContaining('Detailed commit notes'), findsOneWidget);
    expect(find.text('+3'), findsWidgets);
    expect(find.text('-2'), findsWidgets);
    expect(find.textContaining('父提交 parent1'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.textContaining('+newLine'), findsOneWidget);
  });

  testWidgets('RepoIssuesPage 支持 PR 筛选、PR Diff 审查与合并、Issue 新建和状态变更', (
    tester,
  ) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));
    var merged = false;
    var issueState = 'open';

    installMock((options) {
      if (options.path == '/repos/flutter/flutter/issues' &&
          options.method == 'GET') {
        return jsonResponse([issueJson(number: 42, title: 'Sample Issue')]);
      }
      if (options.path == '/repos/flutter/flutter/issues' &&
          options.method == 'POST') {
        return jsonResponse(issueJson(number: 99, title: 'Created Bug Report'));
      }
      if (options.path == '/repos/flutter/flutter/labels') {
        return jsonResponse([
          {'id': 1, 'name': 'bug', 'color': 'd73a4a', 'description': ''},
        ]);
      }
      if (options.path == '/repos/flutter/flutter/pulls') {
        return jsonResponse([
          {
            ...issueJson(number: 88, title: 'Feat PR review'),
            'head': {'ref': 'feat/pr', 'sha': 'abc999'},
            'base': {'ref': 'main'},
          },
        ]);
      }
      if (options.path == '/repos/flutter/flutter/issues/88') {
        return jsonResponse({
          ...issueJson(
            number: 88,
            title: 'Feat PR review',
            state: merged ? 'closed' : 'open',
          ),
          'pull_request': {
            'url': 'https://api.github.com/repos/flutter/flutter/pulls/88',
            if (merged) 'merged_at': '2026-11-27T10:00:00Z',
          },
        });
      }
      if (options.path == '/repos/flutter/flutter/issues/88/comments') {
        return jsonResponse(<dynamic>[]);
      }
      if (options.path == '/repos/flutter/flutter/pulls/88') {
        return jsonResponse({
          'number': 88,
          'title': 'Feat PR review',
          'body': 'PR body content',
          'state': merged ? 'closed' : 'open',
          'merged': merged,
          'draft': false,
          'mergeable': true,
          'head': {
            'ref': 'feat/pr',
            'sha': 'abc999',
            'repo': {'full_name': 'flutter/flutter'},
          },
          'base': {'ref': 'main'},
          'commits': 2,
          'additions': 10,
          'deletions': 4,
          'changed_files': 1,
          'html_url': 'https://github.com/flutter/flutter/pull/88',
        });
      }
      if (options.path == '/repos/flutter/flutter/pulls/88/files') {
        return jsonResponse([
          {
            'filename': 'lib/pr_file.dart',
            'status': 'added',
            'additions': 10,
            'deletions': 0,
            'changes': 10,
            'patch': '@@ -0,0 +1,1 @@\n+class PrReview {}',
          },
        ]);
      }
      if (options.path == '/repos/flutter/flutter/pulls/88/merge') {
        merged = true;
        return jsonResponse({
          'merged': true,
          'message': 'Pull Request successfully merged',
        });
      }
      if (options.path == '/repos/flutter/flutter/issues/42' &&
          options.method == 'GET') {
        return jsonResponse(
          issueJson(number: 42, title: 'Sample Issue', state: issueState),
        );
      }
      if (options.path == '/repos/flutter/flutter/issues/42' &&
          options.method == 'PATCH') {
        final data = options.data as Map<String, dynamic>;
        issueState = (data['state'] ?? issueState).toString();
        return jsonResponse(
          issueJson(
            number: 42,
            title: (data['title'] ?? 'Sample Issue').toString(),
            state: issueState,
          ),
        );
      }
      if (options.path == '/repos/flutter/flutter/issues/42/comments') {
        return jsonResponse(<dynamic>[]);
      }
      if (options.path == '/search/issues') {
        return jsonResponse({
          'total_count': 1,
          'items': [issueJson(number: 42, title: 'Sample Issue')],
        });
      }
      return jsonResponse(<String, dynamic>{});
    });

    expect(
      buildRepoIssueSearchQuery(
        owner: 'flutter',
        repo: 'flutter',
        keyword: 'fix',
        kind: IssueKindFilter.pr,
      ),
      'repo:flutter/flutter is:pr is:open fix',
    );

    await tester.pumpWidget(
      buildTestApp(const RepoIssuesPage(owner: 'flutter', repoName: 'flutter')),
    );
    await tester.pumpAndSettle();

    // 1. 新建 Issue
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(RepoIssueCreatePage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Created Bug Report');
    await tester.tap(find.text('bug'));
    await tester.pump();
    await tester.tap(find.text('提交 Issue'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoIssuesPage), findsOneWidget);

    // 2. #42 直接跳转横条
    await tester.enterText(find.byType(TextField), '#42');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('直达 #42 详情'), findsOneWidget);

    await tester.tap(find.text('直达 #42 详情'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoIssueDetailPage), findsOneWidget);

    // 关闭 Issue
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    expect(find.text('Closed'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // 3. 切到仅 PR 并审查/合并 PR #88
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅 PR'));
    await tester.pumpAndSettle();
    expect(find.text('Feat PR review'), findsOneWidget);

    await tester.tap(find.text('Feat PR review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('feat/pr → main'), findsOneWidget);

    await tester.tap(find.textContaining('变更文件'));
    await tester.pumpAndSettle();
    expect(find.text('lib/pr_file.dart'), findsOneWidget);
    expect(find.textContaining('+class PrReview {}'), findsOneWidget);

    await tester.tap(find.text('合并 Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认合并'));
    await tester.pumpAndSettle();
    expect(find.text('Merged'), findsOneWidget);
  });

  testWidgets('RepoDetailPage 支持 Clone 复制、Releases、社区页与分支 README 切换', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map<dynamic, dynamic>?)?['text']
                ?.toString();
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    installMock((options) {
      if (options.path == '/repos/flutter/flutter') {
        return jsonResponse(repoJson(stars: 168000, forks: 27000));
      }
      if (options.path == '/repos/flutter/flutter/branches') {
        return jsonResponse([
          branchJson(name: 'main'),
          branchJson(name: 'dev'),
        ]);
      }
      if (options.path == '/repos/flutter/flutter/readme') {
        final ref = options.queryParameters['ref']?.toString() ?? 'main';
        return rawResponse('# README on $ref');
      }
      if (options.path == '/repos/flutter/flutter/releases') {
        return jsonResponse([
          {
            'tag_name': 'v2.0.0',
            'name': 'Release 2.0',
            'body': 'Major highlights',
            'prerelease': true,
            'published_at': '2026-11-26T10:00:00Z',
            'html_url':
                'https://github.com/flutter/flutter/releases/tag/v2.0.0',
            'assets': [
              {
                'name': 'release.zip',
                'browser_download_url': 'https://github.com/flutter/flutter/releases/download/v2.0.0/release.zip',
                'size': 2097152,
              },
            ],
          },
        ]);
      }
      if (options.path == '/repos/flutter/flutter/stargazers') {
        return jsonResponse([userJson(login: 'star_user')]);
      }
      if (options.path == '/repos/flutter/flutter/contributors') {
        return jsonResponse([
          {...userJson(login: 'contrib_user'), 'contributions': 42},
        ]);
      }
      if (options.path == '/repos/flutter/flutter/forks') {
        return jsonResponse([repoJson(owner: 'forker', name: 'flutter')]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(const RepoDetailPage(owner: 'flutter', repoName: 'flutter')),
    );
    await tester.pumpAndSettle();

    // 复制 Clone 地址
    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTPS'));
    await tester.pumpAndSettle();
    expect(clipboardText, 'git clone https://github.com/flutter/flutter.git');

    // 切换 README 分支
    await tester.tap(find.byTooltip('切换展示分支'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dev').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('README on dev'), findsOneWidget);

    // 跳转 Releases
    await tester.scrollUntilVisible(
      find.text('Releases 版本发布'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Releases 版本发布'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoReleasesPage), findsOneWidget);
    expect(find.text('Release 2.0'), findsOneWidget);
    expect(find.text('Pre-release'), findsOneWidget);
    await tester.tap(find.textContaining('构建产物'));
    await tester.pumpAndSettle();
    expect(find.text('release.zip'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // 跳转社区页（Stargazers / 贡献者 / Forks）
    await tester.tap(find.textContaining('社区'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoCommunityPage), findsOneWidget);
    expect(find.text('star_user'), findsOneWidget);

    await tester.tap(find.text('贡献者'));
    await tester.pumpAndSettle();
    expect(find.text('contrib_user'), findsOneWidget);
    expect(find.text('42 次提交'), findsOneWidget);

    await tester.tap(find.text('Forks'));
    await tester.pumpAndSettle();
    expect(find.text('forker/flutter'), findsOneWidget);
  });

  testWidgets('通知精准跳往 Issue 详情，代码编辑器联动暗色主题，Settings 支持清缓存与 Mine 登录续跳', (
    tester,
  ) async {
    final item = NotificationItem.fromJson(notificationJson());
    expect(item.subjectNumber, isNull);
    final issueNotif = NotificationItem.fromJson({
      ...notificationJson(title: 'Bug #77'),
      'reason': 'mention',
      'subject': {
        'title': 'Bug #77',
        'type': 'Issue',
        'url': 'https://api.github.com/repos/flutter/flutter/issues/77',
      },
    });
    expect(issueNotif.subjectNumber, 77);
    expect(issueNotif.reasonLabel, '提及了你');

    final commitNotif = NotificationItem.fromJson({
      ...notificationJson(),
      'subject': {
        'title': 'Commit',
        'type': 'Commit',
        'url': 'https://api.github.com/repos/flutter/flutter/commits/deadbeef',
      },
    });
    expect(commitNotif.subjectCommitSha, 'deadbeef');

    // 设置暗色模式，验证 RepoFileViewPage 默认按暗色打开编辑器
    final controllers = registerTestControllers();
    await controllers.theme.setThemeMode(ThemeMode.dark);
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.path == '/notifications') {
        return jsonResponse([
          {
            ...notificationJson(title: 'Bug #77'),
            'reason': 'mention',
            'subject': {
              'title': 'Bug #77',
              'type': 'Issue',
              'url': 'https://api.github.com/repos/flutter/flutter/issues/77',
            },
          },
        ]);
      }
      if (options.path.contains('/notifications/threads/')) {
        return emptyResponse(statusCode: 205);
      }
      if (options.path == '/repos/flutter/flutter/issues/77') {
        return jsonResponse(issueJson(number: 77, title: 'Bug #77'));
      }
      if (options.path == '/repos/flutter/flutter/issues/77/comments') {
        return jsonResponse(<dynamic>[]);
      }
      if (options.path.contains('/contents/lib/a.dart')) {
        return rawResponse('void main() {}');
      }
      if (options.path == '/user/starred') {
        return jsonResponse(<dynamic>[]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(buildTestApp(const NotificationsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('与我相关'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bug #77'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoIssueDetailPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      buildTestApp(
        const RepoFileViewPage(
          owner: 'flutter',
          repoName: 'flutter',
          path: 'lib/a.dart',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    // 验证 Markdown 内相对链接站内打开
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      buildTestApp(
        const Scaffold(
          body: GhMarkdownView(
            data: '[Guide](doc/guide.md)',
            owner: 'flutter',
            repo: 'flutter',
            branch: 'main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guide'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoFileViewPage), findsOneWidget);

    // 验证 SettingsPage 本地数据与缓存清理
    await FootprintStore.record(
      FootprintItem.fromRepo(RepoItem.fromJson(repoJson())),
    );
    await SearchHistoryStore.record('flutter');
    ExploreShowcaseCache.saveOwners([RepoOwner.fromJson(userJson())]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildTestApp(const SettingsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('清除首页推荐缓存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空浏览足迹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空搜索历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除首页推荐缓存'));
    await tester.pumpAndSettle();

    expect(await FootprintStore.load(), isEmpty);
    expect(await SearchHistoryStore.load(), isEmpty);
    expect(ExploreShowcaseCache.cachedOwners, isNull);

    // 验证 MineView 未登录点我的 Star 登录成功后自动跳转 MyStarsPage
    controllers.user.clearUserInfo();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildTestApp(const Scaffold(body: MineView())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的 Star'));
    await tester.pumpAndSettle();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));
    Navigator.of(tester.element(find.textContaining('连接你的 GitHub 账号'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(MyStarsPage), findsOneWidget);
  });

  test('StarService 切换成功与失败回滚行为准确', () async {
    final controllers = registerTestControllers();
    var shouldFail = false;
    installMock((options) {
      if (shouldFail) {
        return jsonResponse({'message': 'Forbidden'}, statusCode: 403);
      }
      return emptyResponse(statusCode: 204);
    });

    var currentStarred = false;
    var currentCount = 10;
    await StarService.toggleStar(
      owner: 'flutter',
      repoName: 'flutter',
      prevStarred: false,
      prevCount: 10,
      nextStarred: true,
      nextCount: 11,
      starSync: controllers.starSync,
      onStateChanged: (s, c) {
        currentStarred = s;
        currentCount = c;
      },
    );
    expect(currentStarred, isTrue);
    expect(currentCount, 11);
    expect(
      controllers.starSync.snapshotOf('flutter/flutter')?.isStarred,
      isTrue,
    );

    shouldFail = true;
    await expectLater(
      () => StarService.toggleStar(
        owner: 'flutter',
        repoName: 'flutter',
        prevStarred: true,
        prevCount: 11,
        nextStarred: false,
        nextCount: 10,
        starSync: controllers.starSync,
        onStateChanged: (s, c) {
          currentStarred = s;
          currentCount = c;
        },
      ),
      throwsException,
    );
    expect(currentStarred, isTrue);
    expect(currentCount, 11);
    expect(controllers.starSync.snapshotOf('flutter/flutter')?.starCount, 11);
  });
}
