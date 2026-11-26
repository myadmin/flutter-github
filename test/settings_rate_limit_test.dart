import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/Settings/index.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 首页标签自定义设置与 API 配额分桶同步测试
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    DioRequest.onUnauthorized = null;
    DioRequest.onRateLimitUpdate = null;
    DioRequest.onResourceRateLimitUpdate = null;
    registerTestControllers();
  });

  test('ExploreTagsController 支持勾选、自定义增删、排序、至少保留校验与持久化恢复', () async {
    final ctrl = ExploreTagsController();
    await ctrl.ensureLoaded();
    expect(ctrl.displayTags.first, '全部');
    expect(ctrl.selectedTags, ExploreTagsController.defaultTags);

    // 取消勾选 Python 并持久化
    expect(await ctrl.toggleTag('Python'), isTrue);
    expect(ctrl.selectedTags, isNot(contains('Python')));

    // 添加自定义标签 Zig（已在预设中）与 Solidity（纯自定义）
    final addedPreset = await ctrl.addCustomTag('Zig');
    expect(addedPreset.added, isTrue);
    expect(ctrl.selectedTags, contains('Zig'));

    final addedCustom = await ctrl.addCustomTag('Solidity');
    expect(addedCustom.added, isTrue);
    expect(ctrl.customTags, contains('Solidity'));
    expect(ctrl.selectedTags, contains('Solidity'));

    // 上移排序与拖拽排序
    final solidityIdx = ctrl.selectedTags.indexOf('Solidity');
    expect(await ctrl.moveTag(solidityIdx, -1), isTrue);
    expect(ctrl.selectedTags.indexOf('Solidity'), solidityIdx - 1);
    await ctrl.reorderTag(solidityIdx - 1, 0);
    expect(ctrl.selectedTags.first, 'Solidity');

    // 重新实例读取，验证本地持久化生效
    final reloaded = ExploreTagsController();
    await reloaded.ensureLoaded();
    expect(reloaded.selectedTags, isNot(contains('Python')));
    expect(reloaded.selectedTags, contains('Solidity'));
    expect(reloaded.customTags, contains('Solidity'));

    // 仅剩 1 个标签且关闭「全部」时，拒绝移除最后一个标签
    for (final tag in List<String>.from(reloaded.selectedTags)) {
      if (tag != 'Dart') {
        await reloaded.toggleTag(tag);
      }
    }
    expect(await reloaded.setShowAllTag(false), isTrue);
    expect(reloaded.displayTags, ['Dart']);
    expect(await reloaded.toggleTag('Dart'), isFalse);

    // 恢复默认
    await reloaded.resetDefaults();
    expect(reloaded.showAllTag.value, isTrue);
    expect(reloaded.selectedTags, ExploreTagsController.defaultTags);
    expect(reloaded.customTags, isEmpty);
  });

  testWidgets('我的页「设置」按钮进入设置页调整首页顶部标签，探索页实时同步且移除当前激活标签时自动回退', (tester) async {
    final mock = installMock((options) {
      if (options.path == '/rate_limit') {
        return jsonResponse(
          rateLimitJson(
            limit: 60,
            remaining: 58,
            searchLimit: 10,
            searchRemaining: 9,
          ),
        );
      }
      if (options.path == '/search/users') {
        return jsonResponse(searchUsersJson());
      }
      return jsonResponse(searchReposJson());
    });

    await tester.pumpWidget(
      MaterialApp(routes: getRootRoutes(), onGenerateRoute: buildRoute),
    );
    await tester.pumpAndSettle();

    // 在探索页选中 Dart 标签
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dart'));
    await tester.pumpAndSettle();
    expect(find.text('Dart 精选'), findsOneWidget);

    // 切到「我的」页，打开「设置」
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('已选 10 项'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    // 在设置页取消选中 Dart，并向下滚动新增自定义标签 Solidity
    await tester.tap(find.widgetWithText(FilterChip, 'Dart'));
    await tester.pumpAndSettle();

    final settingsVerticalScroll = find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(TextField),
      200,
      scrollable: settingsVerticalScroll,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Solidity');
    await tester.tap(find.widgetWithText(ElevatedButton, '添加'));
    await tester.pumpAndSettle();
    expect(find.text('Solidity'), findsWidgets);

    // 返回「我的」，可见计数更新；再切回「探索」，Dart 已隐藏、Solidity 出现且自动回退「全部」
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('已选 10 项'), findsOneWidget);

    await tester.tap(find.text('探索'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Dart'), findsNothing);
    final tagsHorizontalScroll = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'Solidity'),
      150,
      scrollable: tagsHorizontalScroll.first,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Solidity'), findsOneWidget);
    expect(find.text('开源精选'), findsOneWidget);

    // 验证移除当前激活的 Dart 后已触发回退全部查询
    expect(
      mock.requests.where((r) => r.path == '/search/repositories').length,
      greaterThanOrEqualTo(3),
    );
  });

  testWidgets('搜索页请求不覆盖核心 API 配额，切回「我的」实时显示准确 Core 与 Search 额度', (
    tester,
  ) async {
    final controllers = registerTestControllers();
    DioRequest.onResourceRateLimitUpdate =
        ({
          required String resource,
          required int limit,
          required int remaining,
          DateTime? resetAt,
        }) {
          controllers.rateLimit.updateFromResource(
            resource: resource,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
          );
        };

    var rateLimitCalls = 0;
    installMock((options) {
      if (options.path == '/search/repositories') {
        return jsonResponse(
          searchReposJson(),
          headers: {
            'x-ratelimit-resource': ['search'],
            'x-ratelimit-limit': ['10'],
            'x-ratelimit-remaining': ['6'],
            'x-ratelimit-reset': ['1795619000'],
          },
        );
      }
      if (options.path == '/search/users') {
        return jsonResponse(
          searchUsersJson(),
          headers: {
            'x-ratelimit-resource': ['search'],
            'x-ratelimit-limit': ['10'],
            'x-ratelimit-remaining': ['6'],
            'x-ratelimit-reset': ['1795619000'],
          },
        );
      }
      if (options.path == '/rate_limit') {
        rateLimitCalls++;
        return jsonResponse(
          rateLimitJson(
            limit: 60,
            remaining: 56,
            searchLimit: 10,
            searchRemaining: 6,
          ),
          headers: {
            'x-ratelimit-resource': ['core'],
            'x-ratelimit-limit': ['60'],
            'x-ratelimit-remaining': ['60'],
            'x-ratelimit-reset': ['1795619000'],
          },
        );
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: const MainPage(),
        routes: Map<String, WidgetBuilder>.from(getRootRoutes())..remove('/'),
        onGenerateRoute: buildRoute,
      ),
    );
    await tester.pumpAndSettle();

    // 先进入「我的」一次，使 MineView 挂载并获取核心配额 56 / 60
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('剩余 56 / 60 次'), findsOneWidget);
    expect(rateLimitCalls, 1);

    // 切到「搜索」执行搜索（响应头带 x-ratelimit-resource: search, 6/10）
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'topic:frontend stars:>200');
    await tester.tap(find.widgetWithText(ElevatedButton, '搜索'));
    await tester.pumpAndSettle();

    // 验证 Search 响应头未污染核心配额
    expect(controllers.rateLimit.state.value.limit, 60);
    expect(controllers.rateLimit.state.value.remaining, 56);
    expect(controllers.rateLimit.searchState.value?.limit, 10);
    expect(controllers.rateLimit.searchState.value?.remaining, 6);

    // 切回「我的」，核心配额依旧准确显示 56 / 60（不再误显 6 / 10），同时单独展示搜索配额 6 / 10
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('剩余 56 / 60 次'), findsOneWidget);
    expect(find.text('剩余 6 / 10 次'), findsNothing);
    expect(find.text('搜索接口：剩余 6 / 10 次'), findsOneWidget);
    expect(rateLimitCalls, 2);
  });
}
