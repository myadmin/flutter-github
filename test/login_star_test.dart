import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/components/common/gh_star_button.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/pages/Login/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 登录与 Star 互动集成测试：覆盖 PAT / Device Flow 登录、未登录拦截与 Star 乐观更新回滚
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    DioRequest.onUnauthorized = null;
    registerTestControllers();
  });

  testWidgets('LoginPage 表单校验、无效 Token 提示与成功 PAT 登录', (tester) async {
    var unauthorizedTriggered = false;
    DioRequest.onUnauthorized = () => unauthorizedTriggered = true;

    final mock = installMock((options) {
      final auth = options.headers['Authorization']?.toString() ?? '';
      if (auth == 'Bearer ghp_valid_token_123456') {
        return jsonResponse(
          userJson(login: 'dev_user', name: 'Dev User'),
          headers: {
            'x-oauth-scopes': ['repo, read:user'],
          },
        );
      }
      return jsonResponse({'message': 'Bad credentials'}, statusCode: 401);
    });

    final controllers = registerTestControllers();
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
              child: const Text('去登录'),
            ),
          ),
          AppRoutes.login: (_) => const LoginPage(),
        },
      ),
    );

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    // 空提交触发校验
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 GitHub Personal Access Token'), findsOneWidget);

    // 长度不足校验
    await tester.enterText(find.byType(TextFormField), 'short');
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();
    expect(find.text('Token 长度过短，请确认完整复制'), findsOneWidget);

    // 无效 token 返回 401 时提示错误，不触发全局 redirect
    await tester.enterText(find.byType(TextFormField), 'ghp_wrong_token_12345');
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub Token 无效或已过期'), findsOneWidget);
    expect(unauthorizedTriggered, isFalse);

    // 正确 token 登录成功，写盘并自动返回上一页
    await tester.enterText(
      find.byType(TextFormField),
      'ghp_valid_token_123456',
    );
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();

    expect(mock.requests.length, 2);
    expect(tokenManager.getToken(), 'ghp_valid_token_123456');
    expect(controllers.user.isLoggedIn, isTrue);
    expect(controllers.user.user.value.login, 'dev_user');
    expect(controllers.user.scopes, ['repo', 'read:user']);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('LoginPage 支持 OAuth Device Flow 授权码申请与取消', (tester) async {
    installAuthMock((options) {
      if (options.path.contains('device/code')) {
        return jsonResponse({
          'device_code': 'dev-code-1',
          'user_code': 'ABCD-1234',
          'verification_uri': 'https://github.com/login/device',
          'expires_in': 60,
          'interval': 5,
        });
      }
      return jsonResponse({'error': 'authorization_pending'});
    });

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    // 展开配置 Client ID
    await tester.tap(find.text('配置 Client ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'client-id-demo');

    await tester.tap(find.text('使用 GitHub 网页设备授权'));
    await tester.pumpAndSettle();

    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.text('复制并前往授权'), findsOneWidget);

    await tester.ensureVisible(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('ABCD-1234'), findsNothing);
  });

  testWidgets('GhStarButton 未登录拦截跳登录，已登录乐观切换并在失败时回滚', (tester) async {
    final controllers = registerTestControllers();
    var shouldFailStar = false;

    final mock = installMock((options) {
      if (shouldFailStar) {
        return jsonResponse({'message': 'Forbidden'}, statusCode: 403);
      }
      return emptyResponse(statusCode: 204);
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (_) => const Scaffold(
            body: Center(
              child: GhStarButton(
                owner: 'flutter',
                repoName: 'flutter',
                initialCount: 100,
              ),
            ),
          ),
          AppRoutes.login: (_) => const LoginPage(),
        },
      ),
    );

    // 未登录点击跳转到登录页
    await tester.tap(find.textContaining('Star · 100'));
    await tester.pumpAndSettle();
    expect(find.text('登录 GitHub'), findsOneWidget);

    // 返回并模拟登录
    await tester.pageBack();
    await tester.pumpAndSettle();
    controllers.user.updateUserInfo(GithubUser.fromJson(userJson()));

    // 成功点 Star：计数 +1 且发 PUT 请求
    await tester.tap(find.textContaining('Star · 100'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Starred · 101'), findsOneWidget);
    expect(mock.requestsWhere('PUT').length, 1);
    expect(
      controllers.starSync.snapshotOf('flutter/flutter')?.isStarred,
      isTrue,
    );

    // 取消 Star 失败时回滚回 Starred · 101
    shouldFailStar = true;
    await tester.tap(find.textContaining('Starred · 101'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Starred · 101'), findsOneWidget);
    expect(mock.requestsWhere('DELETE').length, 1);
  });
}
