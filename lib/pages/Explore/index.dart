import 'package:flutter/material.dart';
import 'package:gh_explorer/api/search.dart';
import 'package:gh_explorer/components/Explore/gh_explore_banner.dart';
import 'package:gh_explorer/components/Explore/gh_featured_owners.dart';
import 'package:gh_explorer/components/Explore/gh_recent_footprints.dart';
import 'package:gh_explorer/components/Explore/gh_topic_grid.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/pages/Explore/explore_config.dart';
import 'package:gh_explorer/pages/Explore/skeleton.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 探索首页（专题轮播 + 领域入口 + 本地继续浏览 + 热门作者条 + 语言/维度项目流）
class ExploreView extends StatefulWidget {
  const ExploreView({
    super.key,
    this.onSearchTap,
    this.onTopicQueryTap,
    this.isActive = true,
  });

  /// 点击顶部搜索栏的回调，由 MainPage 切往搜索 Tab
  final VoidCallback? onSearchTap;

  /// 点击专题轮播或领域宫格后携带预设搜索串跳转搜索 Tab
  final ValueChanged<String>? onTopicQueryTap;

  /// 当前探索 Tab 是否处于前景激活态，用于控制 Banner 自动轮播启停
  final bool isActive;

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  static const List<String> _languages = [
    '全部',
    'Dart',
    'TypeScript',
    'Python',
    'Go',
    'Rust',
    'Swift',
    'Java',
    'Kotlin',
    'Vue',
  ];

  final ScrollController _scrollController = ScrollController();

  String _selectedLanguage = '全部';
  TrendingSince _selectedSince = TrendingSince.week;
  ExploreFeedMode _feedMode = ExploreFeedMode.trending;

  List<FootprintItem> _recentFootprints = const [];
  List<RepoOwner> _featuredOwners = const [];
  bool _hasCompletedInitialLoad = false;
  bool _loadingOwners = false;

  late final PagedListController<RepoItem> _list =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) {
          final query = buildExploreQuery(
            language: _selectedLanguage,
            since: _selectedSince,
            feedMode: _feedMode,
          );
          return searchReposAPI(
            query: query,
            sort: _feedMode.sortField,
            order: 'desc',
            page: page,
          );
        },
        firstPageErrorFallback: '加载热门项目失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadRecentFootprints();
    _loadInitialHomeData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 首屏优先拉取核心项目列表，成功后再补拉次级「热门作者」推荐栏（带 20 分钟缓存）
  Future<void> _loadInitialHomeData({bool forceShowcase = false}) async {
    await _list.refresh();
    if (!mounted) return;
    if (_list.errorMessage.isEmpty || !_list.isEmpty) {
      setState(() {
        _hasCompletedInitialLoad = true;
      });
      await _loadFeaturedOwners(forceRefresh: forceShowcase);
    }
  }

  /// 读取本机浏览足迹用于「继续浏览」横滑栏（0 API 请求）
  Future<void> _loadRecentFootprints() async {
    final items = await FootprintStore.load();
    if (!mounted) return;
    setState(() => _recentFootprints = items);
  }

  /// 拉取高关注开源作者/组织条，默认命中 20 分钟内存缓存以保护未登录 60/hr 配额
  Future<void> _loadFeaturedOwners({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = ExploreShowcaseCache.cachedOwners;
      if (cached != null) {
        if (mounted) setState(() => _featuredOwners = cached);
        return;
      }
    }
    if (_loadingOwners) return;
    _loadingOwners = true;
    try {
      final res = await searchUsersAPI(
        query: 'followers:>10000',
        sort: 'followers',
        perPage: 10,
      );
      final valid = res.items.where((owner) => owner.login.isNotEmpty).toList();
      if (valid.isNotEmpty) {
        ExploreShowcaseCache.saveOwners(valid);
      }
      if (mounted) {
        setState(() => _featuredOwners = valid);
      }
    } catch (_) {
      // 次级推荐栏失败时静默降级，不打断核心项目流浏览
    } finally {
      _loadingOwners = false;
    }
  }

  /// 下拉刷新：清空推荐缓存并同步刷新足迹、作者栏与主项目流
  Future<void> _onRefresh() async {
    ExploreShowcaseCache.clear();
    await _loadRecentFootprints();
    await _loadInitialHomeData(forceShowcase: true);
  }

  /// 滚动距底部不足 200px 时触发上拉加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换编程语言筛选并重新拉取列表
  void _selectLanguage(String language) {
    if (_selectedLanguage == language) return;
    setState(() => _selectedLanguage = language);
    _list.clear();
    _list.refresh();
  }

  /// 切换热门时间跨度（同时回到热门榜单模式）
  void _selectSince(TrendingSince since) {
    if (_selectedSince == since && _feedMode == ExploreFeedMode.trending) {
      return;
    }
    setState(() {
      _selectedSince = since;
      _feedMode = ExploreFeedMode.trending;
    });
    _list.clear();
    _list.refresh();
  }

  /// 切换列表细分维度（热门榜单 / 新手友好 / 近期活跃）
  void _selectFeedMode(ExploreFeedMode mode) {
    if (_feedMode == mode) return;
    setState(() => _feedMode = mode);
    _list.clear();
    _list.refresh();
  }

  /// 响应顶部精选专题 Banner 点击事件
  void _handleBannerTap(ExploreBannerItem item) {
    switch (item.actionType) {
      case ExploreBannerActionType.searchQuery:
        _openTopicSearch(item.query);
      case ExploreBannerActionType.switchSince:
        if (item.since != null) {
          _selectSince(item.since!);
          ToastUtils.showToast(context, '已切换至「${item.since!.label}」');
        }
      case ExploreBannerActionType.switchFeedMode:
        if (item.feedMode != null) {
          _selectFeedMode(item.feedMode!);
          ToastUtils.showToast(context, '已切换至「${item.feedMode!.label}」');
        }
    }
  }

  /// 携带领域关键词切往搜索 Tab，若外层未接管回调则提示切换至搜索页
  void _openTopicSearch(String query) {
    if (widget.onTopicQueryTap != null) {
      widget.onTopicQueryTap!(query);
      return;
    }
    widget.onSearchTap?.call();
  }

  /// 进入仓库详情并在返回时刷新「继续浏览」本地足迹条
  Future<void> _openRepoDetail(String owner, String name) async {
    await Navigator.pushNamed(context, AppRoutes.repoDetail(owner, name));
    if (mounted) {
      await _loadRecentFootprints();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListenableBuilder(
                  listenable: _list,
                  builder: (context, _) => _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, color: AppColors.brandDark, size: 22),
              const SizedBox(width: 8),
              const Text('探索开源项目', style: AppTextStyles.sectionTitle),
              const Spacer(),
              // 热门时间跨度切换胶囊
              PopupMenuButton<TrendingSince>(
                initialValue: _selectedSince,
                onSelected: _selectSince,
                itemBuilder: (context) => [
                  for (final item in TrendingSince.values)
                    PopupMenuItem<TrendingSince>(
                      value: item,
                      child: Text(item.label),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedSince.label,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 顶部搜索入口框
          Semantics(
            button: true,
            label: '搜索 GitHub 仓库或开发者',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onSearchTap,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '搜索 GitHub 仓库、用户或主题...',
                        style: AppTextStyles.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 语言横滑筛选胶囊（height 放宽到 38 并收敛内边距，防止小屏/Web 文字被上下裁切）
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final selected = lang == _selectedLanguage;
                return Center(
                  child: ChoiceChip(
                    label: Text(lang),
                    selected: selected,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    selectedColor: AppColors.brandDark,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    backgroundColor: AppColors.inputFill,
                    side: BorderSide.none,
                    onSelected: (_) => _selectLanguage(lang),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionToolbar() {
    return Row(
      children: [
        const Icon(Icons.explore_outlined, size: 17, color: AppColors.primary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            _selectedLanguage == '全部' ? '开源精选' : '$_selectedLanguage 精选',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyStrong,
          ),
        ),
        for (final mode in ExploreFeedMode.values)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Material(
              color: _feedMode == mode
                  ? AppColors.primarySurface
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                onTap: () => _selectFeedMode(mode),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: _feedMode == mode
                          ? AppColors.primary
                          : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    mode.label,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 11,
                      color: _feedMode == mode
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: _feedMode == mode
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 是否存在穿插展示在精选列表前排之后的次级推荐条（「继续浏览」/「热门作者」）
  bool get _hasInterleavedShowcase =>
      _recentFootprints.isNotEmpty || _featuredOwners.isNotEmpty;

  /// 构建穿插在热门榜单中部（前 2 个热门仓库之后）的「继续浏览」与「热门开发者」区块，
  /// 既保证首屏直达项目卡片，又在自然下滑中丰富探索维度
  Widget _buildInterleavedShowcase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recentFootprints.isNotEmpty) ...[
          const SizedBox(height: 12),
          GhRecentFootprints(
            items: _recentFootprints,
            onItemTap: (item) => _openRepoDetail(item.owner, item.name),
            onViewAllTap: () async {
              await Navigator.pushNamed(context, AppRoutes.footprintPath);
              if (mounted) await _loadRecentFootprints();
            },
          ),
        ],
        if (_featuredOwners.isNotEmpty) ...[
          const SizedBox(height: 12),
          GhFeaturedOwners(
            owners: _featuredOwners,
            onOwnerTap: (owner) =>
                Navigator.pushNamed(context, AppRoutes.userDetail(owner.login)),
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    // 仅首次冷启动加载阶段显示全屏骨架屏；切换筛选时保留上方推荐模块
    if (_list.isLoading && !_hasCompletedInitialLoad) {
      return const ExploreSkeleton();
    }
    if (_list.errorMessage.isNotEmpty &&
        _list.isEmpty &&
        !_hasCompletedInitialLoad) {
      return AppErrorView(
        message: _list.errorMessage,
        onRetry: _loadInitialHomeData,
      );
    }

    // 在前 2 张仓库卡片之后插入本地足迹条与热门开发者横滑栏
    final insertAfterCount = _list.length >= 2 ? 2 : _list.length;
    final hasExtraSlot = _hasInterleavedShowcase && !_list.isEmpty;
    final totalSliverItems = _list.length + (hasExtraSlot ? 1 : 0) + 1;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GhExploreBanner(
                    items: exploreBanners,
                    paused: !widget.isActive,
                    onBannerTap: _handleBannerTap,
                  ),
                  const SizedBox(height: 10),
                  GhTopicGrid(
                    topics: exploreTopics,
                    onTopicTap: (entry) => _openTopicSearch(entry.query),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionToolbar(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (_list.isLoading && _list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_list.errorMessage.isNotEmpty && _list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                child: AppErrorView(
                  message: _list.errorMessage,
                  onRetry: _list.refresh,
                ),
              ),
            )
          else if (_list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                child: Column(
                  children: [
                    HmEmptyView(
                      icon: Icons.inbox_outlined,
                      title: '暂无匹配的热门项目',
                      description: '试试切换语言、维度或时间跨度',
                      actionText: '重新加载',
                      onAction: _list.refresh,
                    ),
                    if (_hasInterleavedShowcase)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildInterleavedShowcase(),
                      ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverList.separated(
                itemCount: totalSliverItems,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == totalSliverItems - 1) {
                    return HmListFooter(
                      loadingMore: _list.loadingMore,
                      hasMore: _list.hasMore,
                      noMoreText: '已显示全部热门项目',
                    );
                  }
                  if (hasExtraSlot && index == insertAfterCount) {
                    return _buildInterleavedShowcase();
                  }
                  final repoIndex = hasExtraSlot && index > insertAfterCount
                      ? index - 1
                      : index;
                  final repo = _list[repoIndex];
                  return GhRepoCard(
                    repo: repo,
                    onTap: () =>
                        _openRepoDetail(repo.ownerLogin, repo.repoName),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
