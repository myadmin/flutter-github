import 'package:flutter/material.dart';
import 'package:gh_explorer/api/search.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/pages/Explore/skeleton.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 探索首页（按语言与时间窗口探索 GitHub 热门开源项目）
class ExploreView extends StatefulWidget {
  const ExploreView({super.key, this.onSearchTap});

  /// 点击顶部搜索栏的回调，由 MainPage 切往搜索 Tab
  final VoidCallback? onSearchTap;

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

  late final PagedListController<RepoItem> _list =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) {
          final query = buildExploreQuery(
            language: _selectedLanguage,
            since: _selectedSince,
          );
          return searchReposAPI(
            query: query,
            sort: 'stars',
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
    _list.refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 滚动距底部不足 200px 时触发上拉加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换编程语言筛选并重新拉取首屏数据
  void _selectLanguage(String language) {
    if (_selectedLanguage == language) return;
    setState(() => _selectedLanguage = language);
    _list.clear();
    _list.refresh();
  }

  /// 切换热门时间跨度并重新拉取首屏数据
  void _selectSince(TrendingSince since) {
    if (_selectedSince == since) return;
    setState(() => _selectedSince = since);
    _list.clear();
    _list.refresh();
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, color: AppColors.brandDark, size: 22),
              const SizedBox(width: 8),
              const Text('探索开源项目', style: AppTextStyles.sectionTitle),
              const Spacer(),
              // 周期切换下拉或胶囊
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
          const SizedBox(height: 10),
          // 顶部搜索入口框
          Semantics(
            button: true,
            label: '搜索 GitHub 仓库或开发者',
            child: InkWell(
              onTap: widget.onSearchTap,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                height: 38,
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
          const SizedBox(height: 10),
          // 语言横滑筛选胶囊
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final selected = lang == _selectedLanguage;
                return ChoiceChip(
                  label: Text(lang),
                  selected: selected,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: AppColors.brandDark,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  backgroundColor: AppColors.inputFill,
                  side: BorderSide.none,
                  onSelected: (_) => _selectLanguage(lang),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_list.isLoading) {
      return const ExploreSkeleton();
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return HmEmptyView(
        icon: Icons.inbox_outlined,
        title: '暂无匹配的热门项目',
        description: '试试切换语言或时间跨度',
        actionText: '重新加载',
        onAction: _list.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: _list.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _list.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _list.length) {
            return HmListFooter(
              loadingMore: _list.loadingMore,
              hasMore: _list.hasMore,
              noMoreText: '已显示全部热门项目',
            );
          }
          final repo = _list[index];
          return GhRepoCard(
            repo: repo,
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.repoDetail(repo.ownerLogin, repo.repoName),
            ),
          );
        },
      ),
    );
  }
}
