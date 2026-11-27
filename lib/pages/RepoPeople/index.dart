import 'package:flutter/material.dart';
import 'package:gh_explorer/api/repo.dart';
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
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库社区页（Stargazers / Contributors / Forks 切换浏览）
class RepoCommunityPage extends StatefulWidget {
  const RepoCommunityPage({
    super.key,
    required this.owner,
    required this.repoName,
    this.initialTab = 'stargazers',
  });

  final String owner;
  final String repoName;
  final String initialTab;

  @override
  State<RepoCommunityPage> createState() => _RepoCommunityPageState();
}

class _RepoCommunityPageState extends State<RepoCommunityPage> {
  final ScrollController _scrollController = ScrollController();

  late int _tabIndex = _resolveInitialTab(widget.initialTab);

  late final PagedListController<RepoOwner> _stargazersList =
      PagedListController<RepoOwner>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoStargazersAPI(
          widget.owner,
          widget.repoName,
          page: page,
          cancelToken: _stargazersList.cancelToken,
        ),
        firstPageErrorFallback: '加载 Stargazers 失败',
        onLoadMoreError: _onLoadMoreError,
      );

  late final PagedListController<RepoContributor> _contributorsList =
      PagedListController<RepoContributor>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoContributorsAPI(
          widget.owner,
          widget.repoName,
          page: page,
          cancelToken: _contributorsList.cancelToken,
        ),
        firstPageErrorFallback: '加载贡献者列表失败',
        onLoadMoreError: _onLoadMoreError,
      );

  late final PagedListController<RepoItem> _forksList =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoForksAPI(
          widget.owner,
          widget.repoName,
          page: page,
          cancelToken: _forksList.cancelToken,
        ),
        firstPageErrorFallback: '加载 Forks 列表失败',
        onLoadMoreError: _onLoadMoreError,
      );

  static int _resolveInitialTab(String tab) {
    switch (tab.trim().toLowerCase()) {
      case 'contributors':
        return 1;
      case 'forks':
        return 2;
      default:
        return 0;
    }
  }

  void _onLoadMoreError(String msg) {
    if (mounted) ToastUtils.showToast(context, msg);
  }

  bool get _hasValidArgs =>
      widget.owner.trim().isNotEmpty && widget.repoName.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_hasValidArgs) {
      _ensureTabLoaded(_tabIndex);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _stargazersList.dispose();
    _contributorsList.dispose();
    _forksList.dispose();
    super.dispose();
  }

  void _ensureTabLoaded(int index) {
    final target = switch (index) {
      0 => _stargazersList,
      1 => _contributorsList,
      _ => _forksList,
    };
    if (target.isEmpty && !target.isLoading) {
      target.refresh();
    }
  }

  void _switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
    _ensureTabLoaded(index);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      switch (_tabIndex) {
        case 0:
          _stargazersList.loadMore();
        case 1:
          _contributorsList.loadMore();
        default:
          _forksList.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: Text('${widget.owner}/${widget.repoName} 社区'),
        centerTitle: true,
        backgroundColor: colors.pageBackground,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: !_hasValidArgs
          ? const HmEmptyView(icon: Icons.people_outline, title: '仓库信息缺失')
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: HmBottomBar.maxContentWidth,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: colors.cardBackground,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Stargazers'),
                            selected: _tabIndex == 0,
                            onSelected: (_) => _switchTab(0),
                          ),
                          ChoiceChip(
                            label: const Text('贡献者'),
                            selected: _tabIndex == 1,
                            onSelected: (_) => _switchTab(1),
                          ),
                          ChoiceChip(
                            label: const Text('Forks'),
                            selected: _tabIndex == 2,
                            onSelected: (_) => _switchTab(2),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildActiveList()),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActiveList() {
    if (_tabIndex == 0) {
      return ListenableBuilder(
        listenable: _stargazersList,
        builder: (context, _) => _buildUserPagedList(
          list: _stargazersList,
          emptyTitle: '暂无 Stargazers',
          noMoreText: '已展示全部 Stargazers',
          itemBuilder: (user) => _UserTile(
            owner: user,
            subtitle: user.type,
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.userDetail(user.login)),
          ),
        ),
      );
    }
    if (_tabIndex == 1) {
      return ListenableBuilder(
        listenable: _contributorsList,
        builder: (context, _) => _buildUserPagedList(
          list: _contributorsList,
          emptyTitle: '暂无贡献者记录',
          noMoreText: '已展示全部贡献者',
          itemBuilder: (contributor) => _UserTile(
            owner: contributor.owner,
            subtitle: '${contributor.contributions} 次提交',
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.userDetail(contributor.owner.login),
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: _forksList,
      builder: (context, _) => _buildUserPagedList(
        list: _forksList,
        emptyTitle: '暂无 Fork 仓库',
        noMoreText: '已展示全部 Forks',
        itemBuilder: (repo) => GhRepoCard(
          repo: repo,
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.repoDetail(repo.ownerLogin, repo.repoName),
          ),
        ),
      ),
    );
  }

  Widget _buildUserPagedList<T>({
    required PagedListController<T> list,
    required String emptyTitle,
    required String noMoreText,
    required Widget Function(T item) itemBuilder,
  }) {
    if (list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.errorMessage.isNotEmpty && list.isEmpty) {
      return AppErrorView(message: list.errorMessage, onRetry: list.refresh);
    }
    if (list.isEmpty) {
      return HmEmptyView(icon: Icons.people_outline, title: emptyTitle);
    }
    return RefreshIndicator(
      onRefresh: list.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: list.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == list.length) {
            return HmListFooter(
              loadingMore: list.loadingMore,
              hasMore: list.hasMore,
              failed: list.loadMoreFailed,
              onRetry: list.retryLoadMore,
              noMoreText: noMoreText,
            );
          }
          return itemBuilder(list[index]);
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.owner,
    required this.subtitle,
    required this.onTap,
  });

  final RepoOwner owner;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
        ),
        leading: AppNetworkImage(
          url: owner.avatarUrl,
          width: 40,
          height: 40,
          decodeWidth: 40,
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(owner.login, style: context.bodyStrongStyle),
        subtitle: Text(subtitle, style: context.captionSmallStyle),
        trailing: Icon(Icons.chevron_right, color: colors.textSecondary),
      ),
    );
  }
}
