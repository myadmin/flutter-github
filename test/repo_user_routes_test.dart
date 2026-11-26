import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/pages/RepoFiles/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoIssues/index.dart';
import 'package:gh_explorer/pages/Unknown/index.dart';
import 'package:gh_explorer/pages/UserDetail/index.dart';
import 'package:gh_explorer/pages/UserFollows/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 仓库详情、代码文件树、Issue 评论、用户主页与路由守卫页面测试
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registerTestControllers();
  });

  testWidgets('RepoDetailPage 加载仓库详情、README、Star 状态并记录浏览足迹', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.path == '/repos/flutter/flutter') {
        return jsonResponse(repoJson(stars: 168000));
      }
      if (options.path == '/repos/flutter/flutter/readme') {
        return rawResponse('# Flutter README\n\nBuild apps for any screen.');
      }
      if (options.path == '/user/starred/flutter/flutter') {
        if (options.method == 'GET') {
          return emptyResponse(statusCode: 404);
        }
        return emptyResponse(statusCode: 204);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(const RepoDetailPage(owner: 'flutter', repoName: 'flutter')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Flutter makes it easy to build beautiful apps.'),
      findsOneWidget,
    );
    expect(find.textContaining('Flutter README'), findsOneWidget);
    expect(find.textContaining('Star · 168k'), findsOneWidget);

    // 验证写入本地足迹
    final footprints = await FootprintStore.load();
    expect(footprints.length, 1);
    expect(footprints.first.fullName, 'flutter/flutter');

    // 点击 Star 切换为 Starred
    await tester.tap(find.textContaining('Star · 168k'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Starred · 168k'), findsOneWidget);
    expect(
      controllers.starSync.snapshotOf('flutter/flutter')?.isStarred,
      isTrue,
    );
  });

  testWidgets('RepoDetailPage 参数缺失直接展示空态，不发请求', (tester) async {
    final mock = installMock((options) => jsonResponse(<String, dynamic>{}));

    await tester.pumpWidget(
      const MaterialApp(
        home: RepoDetailPage(owner: '', repoName: ''),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('项目信息缺失'), findsOneWidget);
    expect(mock.requests, isEmpty);
  });

  testWidgets('RepoFilesPage / RepoFileViewPage / RepoCommitsPage 渲染交互', (
    tester,
  ) async {
    installMock((options) {
      if (options.path.contains('/contents/lib/main.dart')) {
        return rawResponse("void main() => print('hi');");
      }
      if (options.path.contains('/contents')) {
        return jsonResponse([
          repoContentJson(
            name: 'main.dart',
            path: 'lib/main.dart',
            type: 'file',
            size: 120,
          ),
          repoContentJson(name: 'src', path: 'lib/src', type: 'dir'),
        ]);
      }
      if (options.path.contains('/branches')) {
        return jsonResponse([
          branchJson(name: 'main'),
          branchJson(name: 'dev'),
        ]);
      }
      if (options.path.contains('/commits')) {
        return jsonResponse([commitJson()]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(
        const RepoFilesPage(
          owner: 'flutter',
          repoName: 'flutter',
          branch: 'main',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('src'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoFileViewPage), findsOneWidget);
    expect(find.textContaining("void main() => print('hi');"), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: const RepoCommitsPage(owner: 'flutter', repoName: 'flutter'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('feat: initial commit'), findsOneWidget);
    expect(find.text('1234567'), findsOneWidget);
  });

  testWidgets('RepoIssuesPage 与 RepoIssueDetailPage 评论交互', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.path == '/repos/flutter/flutter/issues') {
        return jsonResponse([issueJson()]);
      }
      if (options.path == '/repos/flutter/flutter/issues/42') {
        return jsonResponse(issueJson());
      }
      if (options.path == '/repos/flutter/flutter/issues/42/comments') {
        if (options.method == 'POST') {
          return jsonResponse(commentJson(id: 4002, body: 'New comment text'));
        }
        return jsonResponse([commentJson()]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(const RepoIssuesPage(owner: 'flutter', repoName: 'flutter')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fix layout overflow'), findsOneWidget);

    await tester.tap(find.text('Fix layout overflow'));
    await tester.pumpAndSettle();
    expect(find.byType(RepoIssueDetailPage), findsOneWidget);
    expect(find.textContaining('Looks good to me!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'New comment text');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.textContaining('New comment text'), findsOneWidget);
  });

  testWidgets('UserDetailPage Follow 互动与 UserFollowsPage 渲染', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson(login: 'me')));

    installMock((options) {
      if (options.path == '/users/torvalds') {
        return jsonResponse(
          userJson(login: 'torvalds', name: 'Linus Torvalds'),
        );
      }
      if (options.path == '/user/following/torvalds') {
        if (options.method == 'GET') return emptyResponse(statusCode: 404);
        return emptyResponse(statusCode: 204);
      }
      if (options.path == '/users/torvalds/repos') {
        return jsonResponse([repoJson(owner: 'torvalds', name: 'linux')]);
      }
      if (options.path == '/users/torvalds/followers') {
        return jsonResponse([ownerJson(login: 'fan1', type: 'User')]);
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      buildTestApp(const UserDetailPage(login: 'torvalds')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Linus Torvalds'), findsOneWidget);
    expect(find.text('torvalds/linux'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: const UserFollowsPage(login: 'torvalds', initialTab: 'followers'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fan1'), findsOneWidget);
  });

  testWidgets('路由表、深链拆解、未知路由兜底与字号钳制', (tester) async {
    final routes = buildInitialRoutes(
      AppRoutes.repoDetail('flutter', 'flutter'),
    );
    expect(routes.length, 2);
    expect(routes.first.settings.name, AppRoutes.home);
    expect(
      routes.last.settings.name,
      AppRoutes.repoDetail('flutter', 'flutter'),
    );

    final unknown = buildRoute(const RouteSettings(name: '/not-found'));
    await tester.pumpWidget(
      MaterialApp(onGenerateRoute: (_) => unknown, home: const SizedBox()),
    );
    await tester.pumpWidget(
      const MaterialApp(home: UnknownRoutePage(location: '/not-found')),
    );
    expect(find.text('没有找到这个页面'), findsOneWidget);
    expect(find.text('地址 /not-found'), findsOneWidget);

    // 验证 clampTextScale 把超大字号 3.0 钳制在 1.3
    double? clamped;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: Builder(
          builder: (context) => clampTextScale(
            context,
            Builder(
              builder: (innerContext) {
                clamped = MediaQuery.textScalerOf(innerContext).scale(10);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(clamped, 13.0);
  });
}
