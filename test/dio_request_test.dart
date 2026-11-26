import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 网络层单元测试：验证 GitHub 鉴权头注入、Link 分页、204/404 语义、401 与限流异常处理
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    DioRequest.onUnauthorized = null;
    DioRequest.onRateLimitUpdate = null;
  });

  test('请求自动注入 GitHub API 头与 Bearer Token，并上报 RateLimit', () async {
    await tokenManager.setToken('ghp_test_token_123');
    int? capturedLimit;
    int? capturedRemaining;
    DioRequest.onRateLimitUpdate =
        ({required int limit, required int remaining, DateTime? resetAt}) {
          capturedLimit = limit;
          capturedRemaining = remaining;
        };

    final mock = installMock((options) {
      return jsonResponse(
        {'ok': true},
        headers: {
          'x-ratelimit-limit': ['5000'],
          'x-ratelimit-remaining': ['4999'],
          'x-ratelimit-reset': ['1795619000'],
        },
      );
    });

    final res = await dioRequest.get('/user');
    expect(res, {'ok': true});
    final sent = mock.requests.single;
    expect(sent.headers['Authorization'], 'Bearer ghp_test_token_123');
    expect(sent.headers['Accept'], 'application/vnd.github+json');
    expect(sent.headers['X-GitHub-Api-Version'], '2022-11-28');
    expect(capturedLimit, 5000);
    expect(capturedRemaining, 4999);
  });

  test('getPaged 解析 Link 响应头判断是否有下一页', () async {
    installMock((options) {
      return jsonResponse(
        [
          {'id': 1},
        ],
        headers: {
          'link': [
            '<https://api.github.com/user/starred?page=2>; rel="next", '
                '<https://api.github.com/user/starred?page=5>; rel="last"',
          ],
        },
      );
    });
    final page1 = await dioRequest.getPaged('/user/starred');
    expect(page1.hasNextPage, isTrue);

    installMock((options) {
      return jsonResponse(
        [
          {'id': 2},
        ],
        headers: {
          'link': ['<https://api.github.com/user/starred?page=1>; rel="prev"'],
        },
      );
    });
    final lastPage = await dioRequest.getPaged('/user/starred');
    expect(lastPage.hasNextPage, isFalse);
  });

  test('checkExists 将 204 视为 true、404 视为 false 且不抛错', () async {
    installMock((options) => emptyResponse(statusCode: 204));
    expect(await dioRequest.checkExists('/user/starred/a/b'), isTrue);

    installMock((options) => emptyResponse(statusCode: 404));
    expect(await dioRequest.checkExists('/user/starred/a/b'), isFalse);
  });

  test('getRaw 获取纯文本内容', () async {
    final mock = installMock((options) => rawResponse('# Hello README'));
    final text = await dioRequest.getRaw('/repos/a/b/readme');
    expect(text, '# Hello README');
    expect(
      mock.requests.single.headers['Accept'],
      'application/vnd.github.raw+json',
    );
  });

  test('401 清理本地 token 并触发 onUnauthorized，skipAuthRedirect 可跳过', () async {
    await tokenManager.setToken('ghp_expired');
    var unauthorizedCalled = 0;
    DioRequest.onUnauthorized = () => unauthorizedCalled++;

    installMock(
      (options) =>
          jsonResponse({'message': 'Bad credentials'}, statusCode: 401),
    );

    await expectLater(
      () => dioRequest.get('/user', skipAuthRedirect: true),
      throwsA(isA<ApiException>()),
    );
    expect(unauthorizedCalled, 0);
    expect(tokenManager.getToken(), 'ghp_expired');

    await expectLater(
      () => dioRequest.get('/user'),
      throwsA(isA<NetworkException>()),
    );
    expect(unauthorizedCalled, 1);
    expect(tokenManager.getToken(), isEmpty);
  });

  test('403 限流返回 RateLimitException 并提示恢复时间', () async {
    installMock((options) {
      return jsonResponse(
        {'message': 'API rate limit exceeded'},
        statusCode: 403,
        headers: {
          'x-ratelimit-limit': ['60'],
          'x-ratelimit-remaining': ['0'],
          'x-ratelimit-reset': ['1795619000'],
        },
      );
    });

    await expectLater(
      () => dioRequest.get('/search/repositories'),
      throwsA(
        isA<RateLimitException>().having(
          (e) => e.message,
          'message',
          contains('上限'),
        ),
      ),
    );
  });

  test('超时异常被翻译为 NetworkException', () async {
    installMock((options) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    });

    await expectLater(
      () => dioRequest.get('/repos/flutter/flutter'),
      throwsA(isA<NetworkException>()),
    );
  });
}
