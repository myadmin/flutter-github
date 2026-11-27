import 'package:flutter/material.dart';
import 'package:gh_explorer/api/search.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/search_history_store.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 搜索目标类型：仓库或用户
enum _SearchTarget { repos, users }

/// 搜索页面（支持仓库 / 用户搜索、排序、语言过滤与本地历史）
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.presetQuery = '', this.queryTicket = 0});

  /// 由探索首页快捷入口传入的预设查询串
  final String presetQuery;

  /// 查询递增序号，保证多次点击同一领域也能触发搜索刷新
  final int queryTicket;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  static const List<String> _hotKeywords = [
    'flutter',
    'dart',
    'typescript',
    'deepseek',
    'rust',
    'langchain',
    'nextjs',
  ];

  static const List<(String, String)> _repoSorts = [
    ('best_match', '最佳匹配'),
    ('stars', 'Star 最多'),
    ('forks', 'Fork 最多'),
    ('updated', '最近更新'),
  ];

  static const List<(String, String)> _userSorts = [
    ('best_match', '最佳匹配'),
    ('followers', '粉丝最多'),
    ('repositories', '仓库最多'),
  ];

  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _SearchTarget _target = _SearchTarget.repos;
  String _repoSort = 'stars';
  String _userSort = 'followers';
  String _activeQuery = '';
  List<String> _history = const [];

  late final PagedListController<RepoItem> _repoList =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) =>
            searchReposAPI(query: _activeQuery, sort: _repoSort, page: page),
        firstPageErrorFallback: '搜索仓库失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  late final PagedListController<RepoOwner> _userList =
      PagedListController<RepoOwner>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) =>
            searchUsersAPI(query: _activeQuery, sort: _userSort, page: page),
        firstPageErrorFallback: '搜索用户失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory();
    if (widget.queryTicket > 0 && widget.presetQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPresetQuery(widget.presetQuery);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queryTicket != oldWidget.queryTicket &&
        widget.presetQuery.trim().isNotEmpty) {
      _applyPresetQuery(widget.presetQuery);
    }
  }

  /// 应用首页专题/领域传入的检索表达式并切回仓库搜索视图
  void _applyPresetQuery(String query) {
    if (_target != _SearchTarget.repos) {
      setState(() => _target = _SearchTarget.repos);
    }
    _submitSearch(query);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _keywordController.dispose();
    _repoList.dispose();
    _userList.dispose();
    super.dispose();
  }

  /// 从本地加载最近搜索记录
  Future<void> _loadHistory() async {
    final items = await SearchHistoryStore.load();
    if (!mounted) return;
    setState(() => _history = items);
  }

  /// 滚动接近底部时根据当前搜索类型触发对应分页器加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (_target == _SearchTarget.repos) {
        _repoList.loadMore();
      } else {
        _userList.loadMore();
      }
    }
  }

  /// 提交搜索词（可选传入历史/热搜词），落盘搜索历史并刷新结果列表
  Future<void> _submitSearch([String? preset]) async {
    final text = (preset ?? _keywordController.text).trim();
    if (text.isEmpty) {
      ToastUtils.showToast(context, '请输入搜索关键词');
      return;
    }
    if (preset != null) {
      _keywordController.text = text;
    }
    FocusScope.of(context).unfocus();
    setState(() => _activeQuery = text);
    // 先刷新首屏结果，本地历史落盘不阻塞网络请求（写盘失败不影响搜索）
    _refreshCurrentTarget();
    final updated = await SearchHistoryStore.record(text);
    if (mounted) {
      setState(() => _history = updated);
    }
  }

  /// 根据当前选中的仓库/用户模式重新拉取首屏结果
  void _refreshCurrentTarget() {
    if (_activeQuery.isEmpty) return;
    if (_target == _SearchTarget.repos) {
      _repoList.clear();
      _repoList.refresh();
    } else {
      _userList.clear();
      _userList.refresh();
    }
  }

  /// 清空输入框与结果列表，回到搜索历史/热搜落地页
  void _clearQuery() {
    _keywordController.clear();
    setState(() => _activeQuery = '');
    _repoList.clear();
    _userList.clear();
  }

  /// 清空全部本地搜索历史
  Future<void> _clearHistory() async {
    await SearchHistoryStore.clear();
    if (!mounted) return;
    setState(() => _history = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appColors.pageBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: Column(
            children: [
              _buildSearchHeader(),
              Expanded(
                child: _activeQuery.isEmpty
                    ? _buildLanding()
                    : _buildSearchResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    final sortOptions = _target == _SearchTarget.repos
        ? _repoSorts
        : _userSorts;
    final currentSort = _target == _SearchTarget.repos ? _repoSort : _userSort;

    return Container(
      color: context.appColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '搜索仓库、用户（如 flutter、language:dart）',
                    hintStyle: context.captionStyle,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _keywordController.text.isNotEmpty
                        ? IconButton(
                            onPressed: _clearQuery,
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '清空',
                          )
                        : null,
                    filled: true,
                    fillColor: context.appColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _submitSearch(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.appColors.brandButtonBg,
                  foregroundColor: context.appColors.brandButtonFg,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: const Text('搜索'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ChoiceChip(
                label: const Text('仓库'),
                selected: _target == _SearchTarget.repos,
                onSelected: (_) {
                  if (_target == _SearchTarget.repos) return;
                  setState(() => _target = _SearchTarget.repos);
                  _refreshCurrentTarget();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('用户'),
                selected: _target == _SearchTarget.users,
                onSelected: (_) {
                  if (_target == _SearchTarget.users) return;
                  setState(() => _target = _SearchTarget.users);
                  _refreshCurrentTarget();
                },
              ),
              const Spacer(),
              PopupMenuButton<String>(
                initialValue: currentSort,
                onSelected: (value) {
                  setState(() {
                    if (_target == _SearchTarget.repos) {
                      _repoSort = value;
                    } else {
                      _userSort = value;
                    }
                  });
                  _refreshCurrentTarget();
                },
                itemBuilder: (context) => [
                  for (final (value, label) in sortOptions)
                    PopupMenuItem<String>(value: value, child: Text(label)),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sort,
                      size: 16,
                      color: context.appColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      sortOptions.firstWhere((e) => e.$1 == currentSort).$2,
                      style: context.captionStyle,
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: context.appColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanding() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('搜索历史', style: context.bodyStrongStyle),
              TextButton(
                onPressed: _clearHistory,
                child: Text(
                  '清空',
                  style: TextStyle(color: context.appColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in _history)
                InputChip(
                  label: Text(word),
                  onPressed: () => _submitSearch(word),
                  onDeleted: () async {
                    final next = await SearchHistoryStore.remove(word);
                    if (mounted) setState(() => _history = next);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text('热门搜索', style: context.bodyStrongStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in _hotKeywords)
              ActionChip(
                label: Text(word),
                backgroundColor: context.appColors.pageBackground,
                onPressed: () => _submitSearch(word),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_target == _SearchTarget.repos) {
      return ListenableBuilder(
        listenable: _repoList,
        builder: (context, _) {
          if (_repoList.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_repoList.errorMessage.isNotEmpty && _repoList.isEmpty) {
            return AppErrorView(
              message: _repoList.errorMessage,
              onRetry: _repoList.refresh,
            );
          }
          if (_repoList.isEmpty) {
            return HmEmptyView(
              icon: Icons.search_off,
              title: '未找到相关仓库',
              description: '尝试更换关键词或放宽筛选条件',
              actionText: '清空搜索',
              onAction: _clearQuery,
            );
          }
          return RefreshIndicator(
            onRefresh: _repoList.refresh,
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _repoList.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _repoList.length) {
                  return HmListFooter(
                    loadingMore: _repoList.loadingMore,
                    hasMore: _repoList.hasMore,
                    failed: _repoList.loadMoreFailed,
                    onRetry: _repoList.retryLoadMore,
                    noMoreText: '没有更多搜索结果了',
                  );
                }
                final repo = _repoList[index];
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
        },
      );
    }

    return ListenableBuilder(
      listenable: _userList,
      builder: (context, _) {
        if (_userList.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_userList.errorMessage.isNotEmpty && _userList.isEmpty) {
          return AppErrorView(
            message: _userList.errorMessage,
            onRetry: _userList.refresh,
          );
        }
        if (_userList.isEmpty) {
          return HmEmptyView(
            icon: Icons.person_search_outlined,
            title: '未找到相关用户',
            actionText: '清空搜索',
            onAction: _clearQuery,
          );
        }
        return RefreshIndicator(
          onRefresh: _userList.refresh,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _userList.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == _userList.length) {
                return HmListFooter(
                  loadingMore: _userList.loadingMore,
                  hasMore: _userList.hasMore,
                  failed: _userList.loadMoreFailed,
                  onRetry: _userList.retryLoadMore,
                  noMoreText: '没有更多用户了',
                );
              }
              final user = _userList[index];
              return _UserSearchTile(
                user: user,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.userDetail(user.login),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 搜索结果中的用户 / 组织列表项卡片
class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({required this.user, required this.onTap});

  final RepoOwner user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: context.appColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: context.appColors.divider.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  AppNetworkImage(
                    url: user.avatarUrl,
                    width: 44,
                    height: 44,
                    decodeWidth: 44,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.login, style: context.tileTitleStyle),
                        const SizedBox(height: 2),
                        Text(user.type, style: context.captionStyle),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: context.appColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
