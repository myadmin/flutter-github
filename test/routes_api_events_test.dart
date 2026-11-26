import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/api/auth.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/models/event.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/Footprint/index.dart';
import 'package:gh_explorer/pages/Login/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/MyRepos/index.dart';
import 'package:gh_explorer/pages/MyStars/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/pages/RepoFiles/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoIssues/index.dart';
import 'package:gh_explorer/pages/UserDetail/index.dart';
import 'package:gh_explorer/pages/UserFollows/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 事件模型、设备流轮询、Markdown 渲染与全量深链路由接线测试
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registerTestControllers();
  });

  test('GithubEvent 解析所有常见动态事件类型', () {
    final cases = <String, Map<String, dynamic>>{
      'ForkEvent': {
        'forkee': {'full_name': 'alice/flutter'},
      },
      'PushEvent': {'ref': 'refs/heads/main', 'size': 3},
      'CreateEvent': {'ref_type': 'branch', 'ref': 'feat/login'},
      'IssuesEvent': {
        'action': 'opened',
        'issue': {'number': 12, 'title': 'Crash'},
      },
      'IssueCommentEvent': {
        'issue': {'number': 12},
        'comment': {'body': 'Fixed in #13'},
      },
      'PullRequestEvent': {
        'action': 'closed',
        'pull_request': {'number': 99, 'title': 'Feat'},
      },
      'ReleaseEvent': {
        'release': {'tag_name': 'v1.0.0', 'name': 'First Release'},
      },
      'PublicEvent': <String, dynamic>{},
      'MemberEvent': <String, dynamic>{},
    };

    for (final entry in cases.entries) {
      final evt = GithubEvent.fromJson({
        'id': '1',
        'type': entry.key,
        'actor': {'login': 'alice', 'avatar_url': ''},
        'repo': {'name': 'flutter/flutter'},
        'payload': entry.value,
        'created_at': '2026-11-25T10:00:00Z',
      });
      expect(evt.actionText, isNotEmpty);
    }
  });

  test('pollDeviceAccessTokenAPI 解析全部轮询状态', () async {
    final responses = [
      ({'access_token': 'gho_123'}, DeviceTokenStatus.success),
      ({'error': 'authorization_pending'}, DeviceTokenStatus.pending),
      ({'error': 'slow_down'}, DeviceTokenStatus.slowDown),
      ({'error': 'expired_token'}, DeviceTokenStatus.expired),
      ({'error': 'access_denied'}, DeviceTokenStatus.denied),
      (
        {'error': 'bad_code', 'error_description': 'invalid'},
        DeviceTokenStatus.error,
      ),
    ];

    for (final (body, expected) in responses) {
      installAuthMock((options) => jsonResponse(body));
      final res = await pollDeviceAccessTokenAPI(
        clientId: 'cid',
        deviceCode: 'dcode',
      );
      expect(res.status, expected);
    }
  });

  testWidgets('GhMarkdownView 渲染标题、代码块、引用、SVG 徽章与图片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GhMarkdownView(
              owner: 'flutter',
              repo: 'flutter',
              branch: 'master',
              data: '''
# Title
> Blockquote line

`inline_code`

```dart
void main() {}
```

![CI](https://img.shields.io/badge/build-passing-green.svg)
![Logo](./assets/logo.png)
''',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('CI'), findsOneWidget);
  });

  testWidgets('AppRoutes 与 getRootRoutes 逐条深链参数解析命中目标页面', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.path.contains('/readme')) {
        return rawResponse('# doc');
      }
      if (options.path.contains('/branches')) {
        return jsonResponse([]);
      }
      if (options.path.contains('/contents/README.md')) {
        return rawResponse('# hi');
      }
      if (options.path.contains('/contents')) {
        return jsonResponse([]);
      }
      if (options.path.contains('/commits')) {
        return jsonResponse([]);
      }
      if (options.path.contains('/comments')) {
        return jsonResponse([]);
      }
      if (options.path.contains('/issues/7')) {
        return jsonResponse(issueJson(number: 7));
      }
      if (options.path.contains('/issues')) {
        return jsonResponse([]);
      }
      if (options.path.startsWith('/repos/')) {
        return jsonResponse(repoJson());
      }
      if (options.path.startsWith('/users/octocat/followers')) {
        return jsonResponse([]);
      }
      if (options.path.startsWith('/users/octocat/repos')) {
        return jsonResponse([]);
      }
      if (options.path.startsWith('/users/')) {
        return jsonResponse(userJson());
      }
      if (options.path == '/user/repos') {
        return jsonResponse([]);
      }
      if (options.path == '/user/starred') {
        return jsonResponse([]);
      }
      if (options.path.startsWith('/user/')) {
        return emptyResponse(statusCode: 404);
      }
      if (options.path == '/notifications') {
        return jsonResponse([]);
      }
      return jsonResponse(searchReposJson());
    });

    final routeExpectations = <(String, Type)>[
      (AppRoutes.home, MainPage),
      (AppRoutes.login, LoginPage),
      (AppRoutes.repoDetailFromFullName('flutter/flutter'), RepoDetailPage),
      (
        AppRoutes.repoFiles('flutter', 'flutter', ref: 'main', path: 'lib'),
        RepoFilesPage,
      ),
      (
        AppRoutes.repoFileView(
          'flutter',
          'flutter',
          path: 'README.md',
          ref: 'main',
        ),
        RepoFileViewPage,
      ),
      (AppRoutes.repoIssues('flutter', 'flutter'), RepoIssuesPage),
      (AppRoutes.repoIssueDetail('flutter', 'flutter', 7), RepoIssueDetailPage),
      (
        AppRoutes.repoCommits('flutter', 'flutter', branch: 'main'),
        RepoCommitsPage,
      ),
      (AppRoutes.userDetail('octocat'), UserDetailPage),
      (AppRoutes.userFollows('octocat', tab: 'following'), UserFollowsPage),
      (AppRoutes.myReposPath, MyReposPage),
      (AppRoutes.myStarsPath, MyStarsPage),
      (AppRoutes.notificationsPath, NotificationsPage),
      (AppRoutes.footprintPath, FootprintPage),
    ];

    for (final (location, expectedType) in routeExpectations) {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          initialRoute: location,
          routes: getRootRoutes(),
          onGenerateRoute: buildRoute,
          onGenerateInitialRoutes: buildInitialRoutes,
          onUnknownRoute: buildUnknownRoute,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(expectedType), findsOneWidget, reason: '路由 $location');
    }
  });
}
