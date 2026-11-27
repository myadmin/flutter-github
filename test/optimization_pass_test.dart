import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/Footprint/index.dart';
import 'package:gh_explorer/pages/Login/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/MyRepos/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFiles/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoPeople/index.dart';
import 'package:gh_explorer/pages/Search/index.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/notification_badge_store.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DioRequest.onUnauthorized = null;
    registerTestControllers();
  });

  test('ETag 304 缓存命中与账号切换隔离、CancelToken 中止校验', () async {
    var reqCount = 0;
    final mock = installMock((options) {
      reqCount++;
      if (options.path == '/repos/flutter/flutter') {
        if (options.headers['If-None-Match'] == '"etag-1"') {
          return emptyResponse(statusCode: 304);
        }
        return jsonResponse(
          repoJson(),
          headers: {
            'etag': ['"etag-1"'],
          },
        );
      }
      if (options.path == '/repos/flutter/flutter/commits') {
        if (options.headers['If-None-Match'] == '"etag-page"') {
          return emptyResponse(statusCode: 304);
        }
        return jsonResponse(
          [commitJson()],
          headers: {
            'etag': ['"etag-page"'],
          },
        );
      }
      if (options.path.contains('/contents/lib/a.dart')) {
        if (options.headers['If-None-Match'] == '"etag-raw"') {
          return emptyResponse(statusCode: 304);
        }
        return rawResponse(
          'void main() {}',
          headers: {
            'etag': ['"etag-raw"'],
          },
        );
      }
      return jsonResponse(<String, dynamic>{});
    });

    final first = await getRepoDetailAPI('flutter', 'flutter');
    final second = await getRepoDetailAPI('flutter', 'flutter');
    expect(first.fullName, 'flutter/flutter');
    expect(second.fullName, 'flutter/flutter');
    expect(mock.requests[1].headers['If-None-Match'], '"etag-1"');

    final page1 = await getRepoCommitsAPI('flutter', 'flutter');
    final page2 = await getRepoCommitsAPI('flutter', 'flutter');
    expect(page1.items.length, 1);
    expect(page2.items.length, 1);
    expect(
      mock.requests
          .where((r) => r.path == '/repos/flutter/flutter/commits')
          .last
          .headers['If-None-Match'],
      '"etag-page"',
    );

    final raw1 = await getRepoFileRawAPI(
      'flutter',
      'flutter',
      path: 'lib/a.dart',
    );
    final raw2 = await getRepoFileRawAPI(
      'flutter',
      'flutter',
      path: 'lib/a.dart',
    );
    expect(raw1, 'void main() {}');
    expect(raw2, 'void main() {}');

    // 切换 Token 后不应命中旧用户的 ETag 缓存
    await tokenManager.setToken('ghp_another_token');
    await getRepoDetailAPI('flutter', 'flutter');
    expect(mock.requests.last.headers['If-None-Match'], isNull);

    // Pre-cancelled CancelToken 直接抛出 RequestCancelledException
    final cancelled = CancelToken()..cancel('user aborted');
    await expectLater(
      dioRequest.getRaw(
        '/repos/flutter/flutter/readme',
        cancelToken: cancelled,
      ),
      throwsA(isA<RequestCancelledException>()),
    );
    await expectLater(
      dioRequest.checkExists(
        '/user/starred/flutter/flutter',
        cancelToken: cancelled,
      ),
      throwsA(isA<RequestCancelledException>()),
    );
    expect(reqCount, greaterThanOrEqualTo(6));
  });

  testWidgets('PR 冲突禁合/409自动刷新、Review 审阅批注、标签修改与评论编辑删除回应', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(
      GithubUser.fromJson(userJson(login: 'octocat')),
    );

    var mergeable = false;
    var trigger409Once = false;
    String? sentMergeSha;

    installMock((options) {
      final path = options.path;
      if (path == '/repos/flutter/flutter/issues/88') {
        if (options.method == 'PATCH') {
          return jsonResponse(
            issueJson(number: 88, title: 'PR #88', isPr: true),
          );
        }
        return jsonResponse(issueJson(number: 88, title: 'PR #88', isPr: true));
      }
      if (path == '/repos/flutter/flutter/pulls/88') {
        return jsonResponse({
          'number': 88,
          'title': 'PR #88',
          'body': 'PR body',
          'state': 'open',
          'merged': false,
          'draft': false,
          'mergeable': mergeable,
          'head': {
            'ref': 'feat/safe',
            'sha': 'headsha1234',
            'repo': {'full_name': 'octocat/flutter'},
          },
          'base': {'ref': 'main'},
          'commits': 2,
          'additions': 5,
          'deletions': 1,
          'changed_files': 1,
          'html_url': 'https://github.com/flutter/flutter/pull/88',
        });
      }
      if (path == '/repos/flutter/flutter/pulls/88/reviews') {
        if (options.method == 'POST') {
          return jsonResponse({
            'id': 901,
            'state': 'APPROVED',
            'body': 'LGTM',
            'user': ownerJson(login: 'octocat', type: 'User'),
            'submitted_at': '2026-11-27T10:00:00Z',
          });
        }
        return jsonResponse(<dynamic>[]);
      }
      if (path == '/repos/flutter/flutter/pulls/88/comments') {
        return jsonResponse([
          {
            'id': 501,
            'path': 'lib/app.dart',
            'line': 42,
            'diff_hunk': '@@ -40,2 +40,3 @@\n+final ok = true;',
            'body': 'Nice guard!',
            'user': ownerJson(login: 'reviewer', type: 'User'),
            'html_url': 'https://github.com/flutter/flutter/pull/88#r501',
            'created_at': '2026-11-27T09:00:00Z',
          },
        ]);
      }
      if (path == '/repos/flutter/flutter/pulls/88/files') {
        return jsonResponse([
          {
            'filename': 'lib/app.dart',
            'status': 'modified',
            'additions': 1,
            'deletions': 0,
            'changes': 1,
            'patch': '@@ -40,1 +40,2 @@\n+final ok = true;',
          },
        ]);
      }
      if (path == '/repos/flutter/flutter/pulls/88/merge') {
        sentMergeSha = (options.data as Map?)?['sha']?.toString();
        if (trigger409Once) {
          trigger409Once = false;
          return jsonResponse({
            'message': 'Head branch was modified',
          }, statusCode: 409);
        }
        return jsonResponse({'merged': true, 'message': 'Merged'});
      }
      if (path == '/repos/flutter/flutter/issues/88/comments') {
        return jsonResponse([
          commentJson(id: 4001, login: 'octocat', body: 'Initial note'),
        ]);
      }
      if (path == '/repos/flutter/flutter/issues/comments/4001' &&
          options.method == 'PATCH') {
        return jsonResponse(
          commentJson(id: 4001, login: 'octocat', body: 'Edited note'),
        );
      }
      if (path == '/repos/flutter/flutter/issues/comments/4001' &&
          options.method == 'DELETE') {
        return emptyResponse(statusCode: 204);
      }
      if (path.endsWith('/reactions')) {
        return jsonResponse({'id': 1}, statusCode: 201);
      }
      if (path == '/repos/flutter/flutter/labels') {
        return jsonResponse([
          {
            'id': 1,
            'name': 'enhancement',
            'color': '0969da',
            'description': '',
          },
        ]);
      }
      if (path == '/repos/flutter/flutter/issues/88/labels') {
        return jsonResponse([
          {'id': 1, 'name': 'bug', 'color': 'd73a4a', 'description': ''},
          {
            'id': 2,
            'name': 'enhancement',
            'color': '0969da',
            'description': '',
          },
        ]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(
        const RepoIssueDetailPage(
          owner: 'flutter',
          repoName: 'flutter',
          number: 88,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 冲突 PR 时禁合提示可见
    expect(find.textContaining('当前分支与基线存在冲突'), findsOneWidget);

    // 提交 PR 审阅（批准）
    await tester.tap(find.text('提交审查'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交审阅'));
    await tester.pumpAndSettle();
    expect(find.textContaining('octocat: 已批准'), findsOneWidget);

    // 切到变更文件页签展示行内审阅批注
    await tester.tap(find.textContaining('变更文件'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('行内代码评审批注'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('行内代码评审批注'), findsOneWidget);
    expect(find.text('lib/app.dart:42'), findsOneWidget);
    expect(find.text('Nice guard!'), findsOneWidget);

    // 切回讨论页签，测试评论 Emoji Reaction、引用回复、编辑、删除与标签编辑
    await tester.tap(find.textContaining('讨论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(find.text('已添加回应'), findsOneWidget);

    await tester.tap(find.byTooltip('评论操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用回复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('> Initial note'), findsOneWidget);

    await tester.tap(find.byTooltip('评论操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑评论'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Edited note',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Edited note', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('评论操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('暂无评论'), findsOneWidget);

    // 编辑标签
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('enhancement'));
    await tester.tap(find.text('保存标签'));
    await tester.pumpAndSettle();
    expect(find.text('enhancement'), findsOneWidget);

    // 解锁 mergeable 并先回到顶部再下拉刷新重拉详情，然后触发 409 冲突刷新，验证带上 headSha
    mergeable = true;
    trigger409Once = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('当前分支与基线存在冲突'), findsNothing);
    await tester.tap(find.text('合并 Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认合并'));
    await tester.pumpAndSettle();
    expect(sentMergeSha, 'headsha1234');
    expect(find.textContaining('已刷新'), findsOneWidget);
  });

  testWidgets(
    'RepoDetail 订阅Watch/Fork/Topic直达、Files 面包屑、Commits 切分支与 Badge 兼容',
    (tester) async {
      final controllers = registerTestControllers();
      controllers.user.updateUserInfo(
        GithubUser.fromJson(userJson(login: 'alice')),
      );

      installMock((options) {
        if (options.path == '/repos/flutter/flutter') {
          return jsonResponse(repoJson(topics: ['flutter', 'ui']));
        }
        if (options.path == '/repos/flutter/flutter/subscription') {
          if (options.method == 'PUT') {
            return jsonResponse({'subscribed': true});
          }
          return jsonResponse({'subscribed': false}, statusCode: 404);
        }
        if (options.path == '/repos/flutter/flutter/forks' &&
            options.method == 'POST') {
          return jsonResponse(repoJson(owner: 'alice', name: 'flutter'));
        }
        if (options.path == '/repos/flutter/flutter/forks') {
          return jsonResponse([repoJson(owner: 'forker', name: 'flutter')]);
        }
        if (options.path == '/repos/flutter/flutter/branches') {
          return jsonResponse([
            branchJson(name: 'main'),
            branchJson(name: 'dev'),
          ]);
        }
        if (options.path == '/repos/flutter/flutter/readme') {
          return rawResponse(
            '# Hi\n![CI](https://img.shields.io/badge/build-passing-brightgreen)',
          );
        }
        if (options.path == '/search/repositories') {
          return jsonResponse(searchReposJson());
        }
        if (options.path.contains('/contents/lib/pages')) {
          return jsonResponse([
            repoContentJson(
              name: 'home.dart',
              path: 'lib/pages/home.dart',
              type: 'file',
            ),
          ]);
        }
        if (options.path == '/repos/flutter/flutter/contents') {
          return jsonResponse([
            repoContentJson(name: 'lib', path: 'lib', type: 'dir'),
          ]);
        }
        if (options.path == '/repos/flutter/flutter/commits') {
          return jsonResponse([commitJson()]);
        }
        return jsonResponse(<String, dynamic>{});
      });

      expect(isSvgImageUrl('https://img.shields.io/badge/a-b-green'), isTrue);
      expect(isSvgImageUrl('https://example.com/a.png'), isFalse);

      await tester.pumpWidget(
        buildTestApp(
          const RepoDetailPage(owner: 'flutter', repoName: 'flutter'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CI'), findsOneWidget);

      // Watch 订阅切换
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();
      expect(find.text('已订阅'), findsOneWidget);

      // 点击 Fork 统计跳往社区页 Forks
      await tester.tap(find.textContaining('Fork '));
      await tester.pumpAndSettle();
      expect(find.byType(RepoCommunityPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 点击 Topic 标签跳往 SearchPage 携带 topic:ui
      await tester.ensureVisible(find.text('ui'));
      await tester.tap(find.text('ui'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // RepoFilesPage 面包屑导航
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        buildTestApp(
          const RepoFilesPage(
            owner: 'flutter',
            repoName: 'flutter',
            path: 'lib/pages',
            branch: 'main',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('pages'), findsOneWidget);
      await tester.tap(find.text('flutter'));
      await tester.pumpAndSettle();
      expect(find.text('lib'), findsOneWidget);

      // RepoCommitsPage 分支切换
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        buildTestApp(
          const RepoCommitsPage(
            owner: 'flutter',
            repoName: 'flutter',
            branch: 'main',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dev').last);
      await tester.pumpAndSettle();
      expect(find.text('提交历史 (dev)'), findsOneWidget);

      // Markdown SVG 徽章与图片占位验证
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        buildTestApp(
          const Scaffold(
            body: Column(
              children: [
                AppNetworkImage(
                  url: 'https://example.com/icon.svg',
                  width: 24,
                  height: 24,
                ),
                GhMarkdownView(
                  data:
                      '![](https://img.shields.io/badge/cov-86%25-brightgreen)',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('cov 86%'), findsOneWidget);
    },
  );

  testWidgets('未读通知角标、足迹单条删滤、MyRepos/Search 多维筛选与 DeviceFlow 状态分支', (
    tester,
  ) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(
      GithubUser.fromJson(userJson(login: 'alice')),
    );

    await FootprintStore.record(
      FootprintItem.fromRepo(
        RepoItem.fromJson(repoJson(owner: 'a', name: 'one', language: 'Dart')),
      ),
    );
    await FootprintStore.record(
      FootprintItem.fromRepo(
        RepoItem.fromJson(repoJson(owner: 'b', name: 'two', language: 'Rust')),
      ),
    );

    var allNotificationsRead = false;
    final mock = installMock((options) {
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
      }
      if (options.path == '/notifications') {
        if (options.method == 'PUT') {
          allNotificationsRead = true;
          return emptyResponse(statusCode: 205);
        }
        if (allNotificationsRead) return jsonResponse(<dynamic>[]);
        return jsonResponse([notificationJson()]);
      }
      if (options.path == '/user/repos') {
        return jsonResponse([repoJson()]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    // MainPage -> 动态 Tab 检测未读通知红点 -> NotificationsPage 全部已读清空红点
    await tester.pumpWidget(buildTestApp(const MainPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    expect(NotificationBadgeStore.hasUnread.value, isTrue);

    await tester.tap(find.byTooltip('消息通知'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsPage), findsOneWidget);
    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();
    expect(NotificationBadgeStore.hasUnread.value, isFalse);

    // FootprintPage 筛选与删除单条
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildTestApp(const FootprintPage()));
    await tester.pumpAndSettle();
    expect(find.text('a/one'), findsOneWidget);
    expect(find.text('b/two'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rust');
    await tester.pumpAndSettle();
    expect(find.text('a/one'), findsNothing);
    expect(find.text('b/two'), findsOneWidget);

    await tester.tap(find.byTooltip('删除足迹'));
    await tester.pumpAndSettle();
    expect(await FootprintStore.load(), hasLength(1));

    // MyReposPage 归属与排序切换
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildTestApp(const MyReposPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有归属'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我创建的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名称排序'));
    await tester.pumpAndSettle();
    expect(
      mock.requests.any(
        (r) =>
            r.path == '/user/repos' &&
            r.queryParameters['affiliation'] == 'owner' &&
            r.queryParameters['sort'] == 'full_name',
      ),
      isTrue,
    );

    // SearchView 语言筛选与不含 Fork 开关
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      buildTestApp(const SearchPage(initialQuery: 'flutter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dart').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不含 Fork'));
    await tester.pumpAndSettle();
    expect(
      mock.requests.any(
        (r) =>
            r.path == '/search/repositories' &&
            (r.queryParameters['q']?.toString().contains(
                  'language:Dart fork:false',
                ) ??
                false),
      ),
      isTrue,
    );

    // LoginPage Device Flow slow_down 与 access_denied 轮询覆盖
    var pollStep = 0;
    installAuthMock((options) {
      if (options.path.contains('device/code')) {
        return jsonResponse({
          'device_code': 'dev-code-2',
          'user_code': 'WXYZ-9999',
          'verification_uri': 'https://github.com/login/device',
          'expires_in': 60,
          'interval': 5,
        });
      }
      pollStep++;
      if (pollStep == 1) return jsonResponse({'error': 'slow_down'});
      return jsonResponse({'error': 'access_denied'});
    });

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildTestApp(const LoginPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置 Client ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'client-id-2');
    await tester.tap(find.text('使用 GitHub 网页设备授权'));
    await tester.pumpAndSettle();
    expect(find.text('WXYZ-9999'), findsOneWidget);
    // 推进 6 秒触发第一次 slow_down，再推进 11 秒触发 access_denied 自动结束
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('WXYZ-9999'), findsNothing);
  });
}
