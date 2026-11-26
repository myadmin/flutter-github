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

    failSecondPage = false;
    await ctrl.loadMore();
    expect(ctrl.items, [1, 2, 3]);
    expect(ctrl.hasMore, isFalse);

    ctrl.removeWhere((item) => item == 2);
    expect(ctrl.items, [1, 3]);

    ctrl.clear();
    expect(ctrl.isEmpty, isTrue);
    ctrl.dispose();
  });
}
