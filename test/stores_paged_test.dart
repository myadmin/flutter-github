import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/stores/search_history_store.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 状态与存储单元测试：覆盖 TokenManager、GetX 控制器、本地历史存储及分页状态机
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
  });

  test('TokenManager 持久化读写与清理', () async {
    expect(tokenManager.hasToken, isFalse);
    await tokenManager.setToken('ghp_abc', scopes: ['repo', 'read:user']);
    expect(tokenManager.hasToken, isTrue);
    expect(tokenManager.getScopes(), ['repo', 'read:user']);

    await tokenManager.init();
    expect(tokenManager.getToken(), 'ghp_abc');
    expect(tokenManager.getScopes(), ['repo', 'read:user']);

    await tokenManager.removeToken();
    expect(tokenManager.hasToken, isFalse);
    expect(tokenManager.getScopes(), isEmpty);
  });

  test('UserController / StarSyncController / RateLimitController 状态更新', () {
    final userCtrl = UserController();
    expect(userCtrl.isLoggedIn, isFalse);
    userCtrl.updateUserInfo(
      GithubUser.fromJson(userJson()),
      tokenScopes: ['repo'],
    );
    expect(userCtrl.isLoggedIn, isTrue);
    expect(userCtrl.scopes, ['repo']);
    userCtrl.clearUserInfo();
    expect(userCtrl.isLoggedIn, isFalse);

    final starCtrl = StarSyncController();
    starCtrl.setSnapshot('Flutter/Flutter', isStarred: true, starCount: 100);
    expect(starCtrl.snapshotOf('flutter/flutter')?.isStarred, isTrue);
    expect(starCtrl.snapshotOf('flutter/flutter')?.starCount, 100);
    starCtrl.clearAll();
    expect(starCtrl.snapshotOf('flutter/flutter'), isNull);

    final rateCtrl = RateLimitController();
    rateCtrl.updateFromHeaders(limit: 5000, remaining: 4200);
    expect(rateCtrl.state.value.remaining, 4200);
    rateCtrl.reset();
    expect(rateCtrl.state.value.limit, 60);
  });

  test('FootprintStore 支持去重、上限 50 条与损坏数据降级', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gh_explorer_footprint', 'not-valid-json');
    expect(await FootprintStore.load(), isEmpty);

    for (var i = 0; i < 55; i++) {
      final repo = RepoItem.fromJson(repoJson(id: i, name: 'repo-$i'));
      await FootprintStore.record(
        FootprintItem.fromRepo(repo, now: DateTime(2026, 11, 25, 10, i % 60)),
      );
    }
    final loaded = await FootprintStore.load();
    expect(loaded.length, FootprintStore.maxItems);

    await FootprintStore.clear();
    expect(await FootprintStore.load(), isEmpty);
  });

  test('SearchHistoryStore 支持记录、去重、删除与清空', () async {
    await SearchHistoryStore.record('flutter');
    await SearchHistoryStore.record('dart');
    await SearchHistoryStore.record('Flutter');
    var items = await SearchHistoryStore.load();
    expect(items, ['Flutter', 'dart']);

    items = await SearchHistoryStore.remove('dart');
    expect(items, ['Flutter']);

    await SearchHistoryStore.clear();
    expect(await SearchHistoryStore.load(), isEmpty);
  });

  test('PagedListController 分页加载、加载更多失败保留列表、removeWhere 与清空', () async {
    var failSecondPage = false;
    final ctrl = PagedListController<int>(
      pageSize: 2,
      loader: (page) async {
        if (page == 2 && failSecondPage) {
          throw NetworkException('加载更多网络断开');
        }
        return PageResult<int>(
          items: page == 1 ? [1, 2] : [3],
          page: page,
          hasMore: page == 1,
        );
      },
      onLoadMoreError: (msg) => expect(msg, '加载更多网络断开'),
    );

    await ctrl.refresh();
    expect(ctrl.items, [1, 2]);
    expect(ctrl.hasMore, isTrue);

    failSecondPage = true;
    await ctrl.loadMore();
    expect(ctrl.items, [1, 2]);
    expect(ctrl.loadMoreFailed, isTrue);

    failSecondPage = false;
    ctrl.retryLoadMore();
    await pumpEventQueue();
    expect(ctrl.loadMoreFailed, isFalse);
    expect(ctrl.items, [1, 2, 3]);
    expect(ctrl.hasMore, isFalse);

    ctrl.removeWhere((item) => item == 2);
    expect(ctrl.items, [1, 3]);

    ctrl.clear();
    expect(ctrl.isEmpty, isTrue);
    ctrl.dispose();
  });

  test('PagedListController 刷新期间拒绝 loadMore，避免旧页与新查询混排', () async {
    final firstPage = Completer<void>();
    final requestedPages = <int>[];
    final ctrl = PagedListController<int>(
      pageSize: 2,
      loader: (page) async {
        requestedPages.add(page);
        if (page == 1) await firstPage.future;
        return PageResult<int>(
          items: page == 1 ? [1, 2] : [3],
          page: page,
          hasMore: page == 1,
        );
      },
    );

    final refreshFuture = ctrl.refresh();
    await Future<void>.delayed(Duration.zero);
    // 刷新进行中（列表尚未就绪）时 loadMore 应直接返回
    await ctrl.loadMore();
    expect(requestedPages, [1]);

    firstPage.complete();
    await refreshFuture;
    expect(ctrl.items, [1, 2]);
    ctrl.dispose();
  });

  test('PagedListController clear 与并发 refresh 会作废旧响应', () async {
    final slow = Completer<void>();
    var calls = 0;
    final ctrl = PagedListController<int>(
      pageSize: 2,
      loader: (page) async {
        calls++;
        if (calls == 1) {
          await slow.future;
          return const PageResult<int>(items: [1, 2], page: 1, hasMore: true);
        }
        return const PageResult<int>(items: [3, 4], page: 1, hasMore: true);
      },
    );

    final stale = ctrl.refresh();
    await Future<void>.delayed(Duration.zero);
    ctrl.clear();
    slow.complete();
    await stale;
    expect(ctrl.items, isEmpty, reason: 'clear 之后旧响应不得回填');

    // 新请求先返回，旧请求后完成时不得覆盖新结果
    final slowAgain = Completer<void>();
    var calls2 = 0;
    final ctrl2 = PagedListController<int>(
      pageSize: 2,
      loader: (page) async {
        calls2++;
        if (calls2 == 1) {
          await slowAgain.future;
          return const PageResult<int>(items: [1, 2], page: 1, hasMore: true);
        }
        return const PageResult<int>(items: [3, 4], page: 1, hasMore: true);
      },
    );
    final oldRefresh = ctrl2.refresh();
    await Future<void>.delayed(Duration.zero);
    final newRefresh = ctrl2.refresh();
    await newRefresh;
    slowAgain.complete();
    await oldRefresh;
    expect(ctrl2.items, [3, 4]);
    ctrl.dispose();
    ctrl2.dispose();
  });

  test('PagedListController 加载更多失败后暂停自动重试，可手动重试', () async {
    var failNext = true;
    var loadMoreCalls = 0;
    final ctrl = PagedListController<int>(
      pageSize: 2,
      loader: (page) async {
        if (page == 1) {
          return const PageResult<int>(items: [1, 2], page: 1, hasMore: true);
        }
        loadMoreCalls++;
        if (failNext) {
          throw NetworkException('断网了');
        }
        return const PageResult<int>(items: [3, 4], page: 2, hasMore: false);
      },
    );

    await ctrl.refresh();
    expect(ctrl.items, [1, 2]);

    await ctrl.loadMore();
    expect(ctrl.loadMoreFailed, isTrue);
    expect(ctrl.items, [1, 2], reason: '失败不得清空已有数据');

    // 失败态下继续滚动不应该反复打接口
    await ctrl.loadMore();
    expect(loadMoreCalls, 1);

    failNext = false;
    ctrl.retryLoadMore();
    await pumpEventQueue();
    expect(ctrl.loadMoreFailed, isFalse);
    expect(ctrl.items, [1, 2, 3, 4]);
    ctrl.dispose();
  });

  test('TokenManager 将历史明文令牌迁移到安全存储并清除明文', () async {
    SharedPreferences.setMockInitialValues({
      'gh_explorer_token': 'ghp_legacy',
      'gh_explorer_token_scopes': <String>['repo', 'read:user'],
    });
    final store = _MemorySecretStore();
    final manager = TokenManager(secretStore: store);

    await manager.init();
    expect(manager.getToken(), 'ghp_legacy');
    expect(manager.getScopes(), ['repo', 'read:user']);
    expect(store.data['gh_explorer_token'], 'ghp_legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gh_explorer_token'), isNull);
    expect(prefs.getStringList('gh_explorer_token_scopes'), isNull);

    await manager.removeToken();
    expect(manager.hasToken, isFalse);
    expect(store.data.containsKey('gh_explorer_token'), isFalse);
  });
}

class _MemorySecretStore implements SecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
