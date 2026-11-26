import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/pages/Explore/explore_config.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/theme_controller.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/dio_request.dart';

/// 测试用纯内存凭证存储，避免 FlutterSecureStorage 插件通道阻塞 FakeAsync 帧循环
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// 构建测试用 MaterialApp，避免 `home` 与 `getRootRoutes()` 中的 `/` 冲突
Widget buildTestApp(Widget home) {
  final routes = Map<String, WidgetBuilder>.from(getRootRoutes())
    ..remove(AppRoutes.home);
  final themeController = Get.isRegistered<ThemeController>()
      ? Get.find<ThemeController>()
      : Get.put(ThemeController(), permanent: true);
  return Obx(
    () => MaterialApp(
      home: home,
      routes: routes,
      onGenerateRoute: buildRoute,
      onUnknownRoute: buildUnknownRoute,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: themeController.themeMode.value,
    ),
  );
}

/// 测试用 Dio HTTP 适配器：拦截真实网络请求并记录调用轨迹
class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  /// 按 HTTP 方法过滤记录下来的请求列表，方便断言 PUT/DELETE 等交互次数
  List<RequestOptions> requestsWhere(String method) => requests
      .where((option) => option.method.toUpperCase() == method.toUpperCase())
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 构造 JSON 格式 Mock 响应体
ResponseBody jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?headers,
    },
  );
}

/// 构造纯文本 Mock 响应体（用于 README 与源码文件 Raw 接口）
ResponseBody rawResponse(
  String body, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      ...?headers,
    },
  );
}

/// 构造无响应体 Mock 响应（默认 204 No Content，适用于 Star / Follow 检查与写操作）
ResponseBody emptyResponse({
  int statusCode = 204,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    '',
    statusCode,
    headers: headers ?? const <String, List<String>>{},
  );
}

/// 替换主 API Dio 客户端适配器为本地 Mock
MockAdapter installMock(ResponseBody Function(RequestOptions options) handler) {
  final adapter = MockAdapter(handler);
  dioRequest.dio.httpClientAdapter = adapter;
  return adapter;
}

/// 替换 OAuth Device Flow 专用 Dio 客户端适配器为本地 Mock
MockAdapter installAuthMock(
  ResponseBody Function(RequestOptions options) handler,
) {
  final adapter = MockAdapter(handler);
  dioRequest.authDio.httpClientAdapter = adapter;
  return adapter;
}

/// 在每个 Widget / 集成测试前重置并注册 GetX 全局控制器
({
  UserController user,
  StarSyncController starSync,
  RateLimitController rateLimit,
  ExploreTagsController exploreTags,
  ThemeController theme,
})
registerTestControllers() {
  Get.reset();
  ExploreShowcaseCache.clear();
  tokenManager.secretStore = InMemorySecretStore();
  final user = Get.put(UserController(), permanent: true);
  final starSync = Get.put(StarSyncController(), permanent: true);
  final rateLimit = Get.put(RateLimitController(), permanent: true);
  final exploreTags = Get.put(ExploreTagsController(), permanent: true);
  final theme = Get.put(ThemeController(), permanent: true);
  return (
    user: user,
    starSync: starSync,
    rateLimit: rateLimit,
    exploreTags: exploreTags,
    theme: theme,
  );
}

/// 构造测试用 GitHub 用户详情 JSON
Map<String, dynamic> userJson({
  int id = 1001,
  String login = 'octocat',
  String name = 'The Octocat',
  String avatarUrl = '',
  String bio = 'GitHub mascot',
  String company = 'GitHub',
  String location = 'San Francisco',
  String type = 'User',
  int publicRepos = 8,
  int followers = 1200,
  int following = 12,
}) {
  return {
    'id': id,
    'login': login,
    'avatar_url': avatarUrl,
    'html_url': 'https://github.com/$login',
    'name': name,
    'company': company,
    'blog': 'https://github.blog',
    'location': location,
    'email': '',
    'bio': bio,
    'type': type,
    'public_repos': publicRepos,
    'public_gists': 2,
    'followers': followers,
    'following': following,
    'total_private_repos': 3,
    'created_at': '2020-01-01T00:00:00Z',
  };
}

/// 构造测试用仓库所有者/用户简要 JSON
Map<String, dynamic> ownerJson({
  int id = 1001,
  String login = 'flutter',
  String avatarUrl = '',
  String type = 'Organization',
}) {
  return {
    'id': id,
    'login': login,
    'avatar_url': avatarUrl,
    'type': type,
    'html_url': 'https://github.com/$login',
  };
}

/// 构造测试用 GitHub 仓库详情 JSON
Map<String, dynamic> repoJson({
  int id = 2001,
  String owner = 'flutter',
  String name = 'flutter',
  String description = 'Flutter makes it easy to build beautiful apps.',
  String language = 'Dart',
  int stars = 168000,
  int forks = 28000,
  int openIssues = 12000,
  bool isPrivate = false,
  bool isFork = false,
  String defaultBranch = 'master',
  List<String> topics = const ['flutter', 'dart', 'mobile'],
}) {
  return {
    'id': id,
    'name': name,
    'full_name': '$owner/$name',
    'description': description,
    'language': language,
    'stargazers_count': stars,
    'forks_count': forks,
    'watchers_count': stars,
    'subscribers_count': 3600,
    'open_issues_count': openIssues,
    'private': isPrivate,
    'fork': isFork,
    'archived': false,
    'default_branch': defaultBranch,
    'html_url': 'https://github.com/$owner/$name',
    'homepage': 'https://flutter.dev',
    'topics': topics,
    'owner': ownerJson(login: owner),
    'license': {
      'key': 'bsd-3-clause',
      'name': 'BSD 3-Clause',
      'spdx_id': 'BSD-3-Clause',
    },
    'created_at': '2020-01-01T00:00:00Z',
    'updated_at': '2026-11-25T10:00:00Z',
    'pushed_at': '2026-11-25T09:00:00Z',
  };
}

/// 构造仓库搜索分页响应 JSON
Map<String, dynamic> searchReposJson({
  int totalCount = 1,
  List<Map<String, dynamic>>? items,
}) {
  return {
    'total_count': totalCount,
    'incomplete_results': false,
    'items': items ?? [repoJson()],
  };
}

/// 构造用户搜索分页响应 JSON
Map<String, dynamic> searchUsersJson({
  int totalCount = 1,
  List<Map<String, dynamic>>? items,
}) {
  return {
    'total_count': totalCount,
    'incomplete_results': false,
    'items': items ?? [ownerJson(login: 'octocat', type: 'User')],
  };
}

/// 构造仓库目录/文件条目 JSON
Map<String, dynamic> repoContentJson({
  String name = 'lib',
  String path = 'lib',
  String type = 'dir',
  int size = 0,
}) {
  return {
    'name': name,
    'path': path,
    'sha': 'abcdef1234567890',
    'size': size,
    'type': type,
    'html_url': 'https://github.com/flutter/flutter/tree/master/$path',
    'download_url': '',
  };
}

/// 构造仓库分支 JSON
Map<String, dynamic> branchJson({String name = 'main'}) {
  return {
    'name': name,
    'commit': {'sha': 'abcdef1234567890'},
    'protected': false,
  };
}

/// 构造 Commit 提交记录 JSON
Map<String, dynamic> commitJson({
  String sha = '1234567890abcdef',
  String message = 'feat: initial commit',
  String authorLogin = 'octocat',
}) {
  return {
    'sha': sha,
    'html_url': 'https://github.com/flutter/flutter/commit/$sha',
    'commit': {
      'message': message,
      'author': {'name': 'Octocat', 'date': '2026-11-25T08:00:00Z'},
    },
    'author': {'login': authorLogin, 'avatar_url': ''},
  };
}

/// 构造 Issue / PR 条目 JSON
Map<String, dynamic> issueJson({
  int id = 3001,
  int number = 42,
  String title = 'Fix layout overflow',
  String body = 'Detailed issue description.',
  String state = 'open',
  int comments = 2,
  bool isPr = false,
}) {
  return {
    'id': id,
    'number': number,
    'title': title,
    'body': body,
    'state': state,
    'comments': comments,
    'html_url': 'https://github.com/flutter/flutter/issues/$number',
    'user': ownerJson(login: 'octocat', type: 'User'),
    'labels': [
      {'id': 1, 'name': 'bug', 'color': 'd73a4a', 'description': ''},
    ],
    if (isPr) 'pull_request': {'url': 'https://api.github.com/...'},
    'created_at': '2026-11-24T10:00:00Z',
    'updated_at': '2026-11-25T10:00:00Z',
  };
}

/// 构造 Issue 评论 JSON
Map<String, dynamic> commentJson({
  int id = 4001,
  String body = 'Looks good to me!',
  String login = 'reviewer',
}) {
  return {
    'id': id,
    'body': body,
    'user': ownerJson(login: login, type: 'User'),
    'html_url': 'https://github.com/flutter/flutter/issues/42#issuecomment-$id',
    'created_at': '2026-11-25T09:00:00Z',
    'updated_at': '2026-11-25T09:00:00Z',
  };
}

/// 构造用户动态事件 JSON
Map<String, dynamic> eventJson({
  String id = 'evt-1',
  String type = 'WatchEvent',
  String actorLogin = 'octocat',
  String repoName = 'flutter/flutter',
}) {
  return {
    'id': id,
    'type': type,
    'actor': {'login': actorLogin, 'avatar_url': ''},
    'repo': {'name': repoName},
    'payload': <String, dynamic>{},
    'created_at': '2026-11-25T09:00:00Z',
  };
}

/// 构造 GitHub 通知条目 JSON
Map<String, dynamic> notificationJson({
  String id = 'notif-1',
  bool unread = true,
  String title = 'Release v3.47',
  String repoFullName = 'flutter/flutter',
}) {
  return {
    'id': id,
    'unread': unread,
    'reason': 'subscribed',
    'subject': {
      'title': title,
      'type': 'Release',
      'url': 'https://api.github.com/repos/$repoFullName/releases/1',
    },
    'repository': {
      'full_name': repoFullName,
      'owner': {'avatar_url': ''},
    },
    'updated_at': '2026-11-25T09:30:00Z',
  };
}

/// 构造 GitHub API 速率限制响应 JSON
Map<String, dynamic> rateLimitJson({
  int limit = 5000,
  int remaining = 4990,
  int reset = 1795619000,
  int? searchLimit,
  int? searchRemaining,
  int? searchReset,
}) {
  return {
    'resources': {
      'core': {'limit': limit, 'remaining': remaining, 'reset': reset},
      if (searchLimit != null && searchRemaining != null)
        'search': {
          'limit': searchLimit,
          'remaining': searchRemaining,
          'reset': searchReset ?? reset,
        },
    },
  };
}
