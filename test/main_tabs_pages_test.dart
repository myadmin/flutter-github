import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/Footprint/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/MyRepos/index.dart';
import 'package:gh_explorer/pages/MyStars/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 底部 4 Tab 与个人中心页面测试：覆盖懒加载、探索筛选、用户搜索、动态、通知、我的仓库/Star 及足迹
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    DioRequest.onUnauthorized = null;
    registerTestControllers();
  });

  testWidgets('MainPage 懒加载 4 个底部 Tab，冷启动只请求探索列表并支持切换', (tester) async {
    await tokenManager.setToken('ghp_init_token');

    final mock = installMock((options) {
      if (options.path == '/user') {
        return jsonResponse(userJson(login: 'alice', name: 'Alice'));
      }
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
      }
      if (options.path.contains('/received_events')) {
        return jsonResponse([eventJson()]);
      }
      if (options.path == '/rate_limit') {
        return jsonResponse(rateLimitJson());
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    // 首屏只请求 /user 和 /search/repositories，未触发动态与配额接口
    expect(mock.requests.any((r) => r.path == '/search/repositories'), isTrue);
    expect(
      mock.requests.any((r) => r.path.contains('received_events')),
      isFalse,
    );
    expect(mock.requests.any((r) => r.path == '/rate_limit'), isFalse);
    expect(find.text('flutter/flutter'), findsOneWidget);

    // 切到「搜索」Tab 并执行搜索
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('热门搜索'), findsOneWidget);

    await tester.tap(find.text('dart'));
    await tester.pumpAndSettle();
    expect(find.text('flutter/flutter'), findsWidgets);

    // 清空搜索回到落地页，验证「搜索历史」记录了刚刚的关键词
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('搜索历史'), findsOneWidget);

    // 切到「动态」Tab
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    expect(
      mock.requests.any((r) => r.path.contains('received_events')),
      isTrue,
    );
    expect(find.textContaining('Star 了仓库'), findsOneWidget);

    // 切到「我的」Tab
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(mock.requests.any((r) => r.path == '/rate_limit'), isTrue);
  });

  testWidgets('ExploreView 搜索失败展示重试按钮，重拉后恢复正常', (tester) async {
    var shouldFail = true;
    installMock((options) {
      if (shouldFail) {
        return jsonResponse({'message': 'Server Error'}, statusCode: 500);
      }
      return jsonResponse(searchReposJson());
    });

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    expect(find.text('重新加载'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('flutter/flutter'), findsOneWidget);
  });

  testWidgets('MyStarsPage 展示 Star 列表，取消 Star 后移除条目', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.method == 'GET' && options.path == '/user/starred') {
        return jsonResponse([
          repoJson(id: 1, owner: 'flutter', name: 'flutter', stars: 200),
          repoJson(id: 2, owner: 'dart-lang', name: 'sdk', stars: 90),
        ]);
      }
      if (options.method == 'DELETE') {
        return emptyResponse(statusCode: 204);
      }
      return emptyResponse(statusCode: 204);
    });

    await tester.pumpWidget(buildTestApp(const MyStarsPage()));
    await tester.pumpAndSettle();

    expect(find.text('flutter/flutter'), findsOneWidget);
    expect(find.text('dart-lang/sdk'), findsOneWidget);

    // 点击第一个仓库卡片上的 Star 图标取消 Star
    await tester.tap(find.byIcon(Icons.star).first);
    await tester.pumpAndSettle();

    expect(find.text('flutter/flutter'), findsNothing);
    expect(find.text('dart-lang/sdk'), findsOneWidget);
  });

  testWidgets('MyReposPage 支持筛选与空态处理', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      final visibility = options.queryParameters['visibility'];
      if (visibility == 'private') {
        return jsonResponse(<dynamic>[]);
      }
      return jsonResponse([repoJson(owner: 'octocat', name: 'hello-world')]);
    });

    await tester.pumpWidget(const MaterialApp(home: MyReposPage()));
    await tester.pumpAndSettle();

    expect(find.text('octocat/hello-world'), findsOneWidget);

    await tester.tap(find.text('私有'));
    await tester.pumpAndSettle();
    expect(find.text('暂无仓库'), findsOneWidget);
  });

  testWidgets('NotificationsPage 与 FootprintPage 正常加载和清空', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    installMock((options) {
      if (options.path == '/notifications' && options.method == 'GET') {
        return jsonResponse([notificationJson()]);
      }
      return emptyResponse(statusCode: 205);
    });

    await tester.pumpWidget(buildTestApp(const NotificationsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Release v3.47'), findsOneWidget);

    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();
    expect(find.text('已全部标为已读'), findsOneWidget);

    // 验证 FootprintPage 分组与清空确认弹窗
    await FootprintStore.record(
      FootprintItem.fromRepo(RepoItem.fromJson(repoJson())),
    );
    await tester.pumpWidget(const MaterialApp(home: FootprintPage()));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('flutter/flutter'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();
    expect(find.text('还没有浏览足迹'), findsOneWidget);
  });

  testWidgets('MainPage 收到 401 回调时自动跳转登录页', (tester) async {
    installMock((options) => jsonResponse(searchReposJson()));

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MainPage), findsOneWidget);
    DioRequest.onUnauthorized?.call();
    await tester.pumpAndSettle();
    expect(find.text('登录 GitHub'), findsOneWidget);
  });

  testWidgets('SearchView 支持用户搜索与排序切换，ExploreView 支持语言筛选', (tester) async {
    final mock = installMock((options) {
      if (options.path == '/search/users') {
        return jsonResponse(searchUsersJson());
      }
      return jsonResponse(searchReposJson());
    });

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    // 探索页切换语言为 Dart
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dart'));
    await tester.pumpAndSettle();
    expect(
      mock.requests.any(
        (r) =>
            r.queryParameters['q']?.toString().contains('language:Dart') ==
            true,
      ),
      isTrue,
    );

    // 切到「搜索」并切换到「用户」tab
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'octocat');
    await tester.tap(find.widgetWithText(ElevatedButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('octocat'), findsWidgets);
  });

  testWidgets('MineView 支持配额刷新、快捷入口跳转与二次确认退出登录', (tester) async {
    final controllers = registerTestControllers();
    controllers.user.updateUserInfo(
      GithubUser.fromJson(userJson(login: 'bob', name: 'Bob')),
      tokenScopes: ['repo', 'read:user'],
    );
    await tokenManager.setToken('ghp_bob_token');

    installMock((options) {
      if (options.path == '/user') {
        return jsonResponse(
          userJson(login: 'bob', name: 'Bob'),
          headers: {
            'x-oauth-scopes': ['repo, read:user'],
          },
        );
      }
      if (options.path == '/rate_limit') {
        return jsonResponse(rateLimitJson(limit: 5000, remaining: 4888));
      }
      if (options.path == '/user/repos') return jsonResponse([]);
      return jsonResponse(searchReposJson());
    });

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('剩余 4888 / 5000 次'), findsOneWidget);
    expect(find.text('repo'), findsOneWidget);

    // 点击「刷新」配额
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('配额已刷新'), findsOneWidget);

    // 点击「我的仓库」进入页面再返回
    await tester.tap(find.text('我的仓库'));
    await tester.pumpAndSettle();
    expect(find.byType(MyReposPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 点击「退出」弹出二次确认框并确认
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(find.text('确认退出登录吗？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(controllers.user.isLoggedIn, isFalse);
    expect(tokenManager.hasToken, isFalse);
    expect(find.text('点击登录 GitHub'), findsOneWidget);
  });
}
