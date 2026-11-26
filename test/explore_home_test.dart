import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/api/search.dart';
import 'package:gh_explorer/components/Explore/gh_explore_banner.dart';
import 'package:gh_explorer/components/Explore/gh_featured_owners.dart';
import 'package:gh_explorer/components/Explore/gh_recent_footprints.dart';
import 'package:gh_explorer/components/Explore/gh_topic_grid.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/pages/Explore/explore_config.dart';
import 'package:gh_explorer/pages/Explore/index.dart';
import 'package:gh_explorer/pages/Explore/skeleton.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 探索首页多模块展示、交互联动与 20 分钟推荐缓存测试
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    registerTestControllers();
  });

  test('buildExploreQuery 支持热门榜单、新手友好与近期活跃三种模式及缓存读写', () {
    final fixedNow = DateTime(2026, 11, 26);

    final trending = buildExploreQuery(
      language: 'Dart',
      since: TrendingSince.week,
      now: fixedNow,
    );
    expect(trending, 'created:>2026-11-19 stars:>10 language:Dart');

    final beginner = buildExploreQuery(
      language: 'Rust',
      feedMode: ExploreFeedMode.beginner,
      now: fixedNow,
    );
    expect(beginner, 'good-first-issues:>3 stars:>50 language:Rust');

    final active = buildExploreQuery(
      language: '全部',
      feedMode: ExploreFeedMode.recentlyActive,
      now: fixedNow,
    );
    expect(active, 'pushed:>2026-11-23 stars:>200');

    expect(
      buildExploreQuery(language: 'Jupyter Notebook', now: fixedNow),
      contains('language:"Jupyter Notebook"'),
    );
    expect(
      buildExploreQuery(language: 'topic:ai', now: fixedNow),
      endsWith('topic:ai'),
    );

    expect(ExploreShowcaseCache.cachedOwners, isNull);
    ExploreShowcaseCache.saveOwners([RepoOwner.fromJson(ownerJson())]);
    expect(ExploreShowcaseCache.cachedOwners?.length, 1);
    ExploreShowcaseCache.clear();
    expect(ExploreShowcaseCache.cachedOwners, isNull);
  });

  testWidgets('GhRepoCard 展示 Topic 标签、开源协议与 Issue 数', (tester) async {
    final repo = RepoItem.fromJson(
      repoJson(
        openIssues: 12500,
        topics: const ['flutter', 'dart', 'ui', 'cross-platform'],
      ),
    );

    await tester.pumpWidget(
      buildTestApp(
        Scaffold(
          body: SingleChildScrollView(child: GhRepoCard(repo: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 最多展示前 3 个 Topic，并附带协议与 Issue 数
    expect(find.text('flutter'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('ui'), findsOneWidget);
    expect(find.text('cross-platform'), findsNothing);
    expect(find.text('BSD-3-Clause'), findsOneWidget);
    expect(find.text('12.5k'), findsOneWidget);
  });

  testWidgets(
    'ExploreSkeleton、Banner、TopicGrid、Footprints 与 Owners 组件各自正常渲染与回调',
    (tester) async {
      ExploreBannerItem? tappedBanner;
      ExploreTopicEntry? tappedTopic;
      FootprintItem? tappedFootprint;
      var viewAllTapped = false;
      RepoOwner? tappedOwner;

      final footprint = FootprintItem(
        fullName: 'dart-lang/sdk',
        owner: 'dart-lang',
        name: 'sdk',
        avatarUrl: '',
        description: 'The Dart SDK',
        language: 'Dart',
        stargazersCount: 10200,
        viewedAt: DateTime(2026, 11, 26).millisecondsSinceEpoch,
      );
      final owner = RepoOwner.fromJson(
        ownerJson(login: 'google', type: 'Organization'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const ExploreSkeleton(),
                  GhExploreBanner(
                    items: exploreBanners,
                    paused: true,
                    onBannerTap: (item) => tappedBanner = item,
                  ),
                  GhTopicGrid(
                    topics: exploreTopics,
                    onTopicTap: (entry) => tappedTopic = entry,
                  ),
                  GhRecentFootprints(
                    items: [footprint],
                    onItemTap: (item) => tappedFootprint = item,
                    onViewAllTap: () => viewAllTapped = true,
                  ),
                  GhFeaturedOwners(
                    owners: [owner],
                    onOwnerTap: (item) => tappedOwner = item,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('AI 与 Agent 开源浪潮'));
      await tester.tap(find.text('AI 与 Agent 开源浪潮'));
      await tester.pump();
      expect(tappedBanner?.title, 'AI 与 Agent 开源浪潮');

      await tester.ensureVisible(find.text('Flutter'));
      await tester.tap(find.text('Flutter'));
      await tester.pump();
      expect(tappedTopic?.query, contains('topic:flutter'));

      await tester.ensureVisible(find.text('dart-lang/sdk'));
      await tester.tap(find.text('dart-lang/sdk'));
      await tester.pump();
      expect(tappedFootprint?.fullName, 'dart-lang/sdk');

      await tester.tap(find.text('全部足迹'));
      await tester.pump();
      expect(viewAllTapped, isTrue);

      await tester.ensureVisible(find.text('google'));
      await tester.tap(find.text('google'));
      await tester.pump();
      expect(tappedOwner?.login, 'google');
      expect(find.text('组织'), findsOneWidget);
    },
  );

  testWidgets('ExploreView 展示足迹、热门作者缓存及多维度切换，并支持联动跳转搜索', (tester) async {
    await FootprintStore.record(
      FootprintItem.fromRepo(
        RepoItem.fromJson(repoJson(owner: 'vuejs', name: 'core', stars: 47000)),
      ),
    );

    final mock = installMock((options) {
      if (options.path == '/search/users') {
        return jsonResponse(
          searchUsersJson(
            items: [
              ownerJson(login: 'torvalds', type: 'User'),
              ownerJson(login: 'vercel', type: 'Organization'),
            ],
          ),
        );
      }
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
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

    // 首屏渲染 Banner、8 个领域以及精选列表，下滚展示继续浏览足迹及热门作者栏
    expect(find.text('AI 与 Agent 开源浪潮'), findsOneWidget);
    expect(find.text('flutter/flutter'), findsOneWidget);

    final verticalScroll = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.text('torvalds'),
      220,
      scrollable: verticalScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('继续浏览'), findsOneWidget);
    expect(find.text('vuejs/core'), findsOneWidget);
    expect(find.text('热门开发者与开源组织'), findsOneWidget);
    expect(find.text('torvalds'), findsOneWidget);

    final initialUserCalls = mock.requests
        .where((r) => r.path == '/search/users')
        .length;
    expect(initialUserCalls, 1);

    // 滚回顶部后切换列表维度为「新手友好」，热门作者命中 20 分钟缓存不重打 /search/users
    await tester.drag(verticalScroll, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新手友好'));
    await tester.pumpAndSettle();

    expect(
      mock.requests.any(
        (r) =>
            r.path == '/search/repositories' &&
            (r.queryParameters['q']?.toString().contains('good-first-issues') ??
                false),
      ),
      isTrue,
    );
    expect(
      mock.requests.where((r) => r.path == '/search/users').length,
      initialUserCalls,
    );

    // 点击「AI / LLM」快捷入口，自动切往搜索 Tab 并触发 topic:llm 查询
    await tester.tap(find.text('AI / LLM'));
    await tester.pumpAndSettle();

    expect(
      mock.requests.any(
        (r) =>
            r.path == '/search/repositories' &&
            (r.queryParameters['q']?.toString().contains('topic:llm') ?? false),
      ),
      isTrue,
    );
    expect(find.text('仓库'), findsOneWidget);
  });

  testWidgets('GhExploreBanner 触发 Banner 切换时间窗口与自动轮播定时器不泄漏', (tester) async {
    final mock = installMock((options) => jsonResponse(searchReposJson()));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExploreView(onSearchTap: () {})),
      ),
    );
    await tester.pumpAndSettle();

    // 滑动 Banner 到第二张（今日新星 · 高速增长榜）并点击切换周期
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日新星 · 高速增长榜'));
    await tester.pumpAndSettle();

    expect(find.text('今日新星'), findsWidgets);
    expect(mock.requests.length, greaterThanOrEqualTo(2));
  });
}
