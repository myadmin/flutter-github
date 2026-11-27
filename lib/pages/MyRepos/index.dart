import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/user.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 我的仓库列表页（支持全部 / 公开 / 私有筛选与分页）
class MyReposPage extends StatefulWidget {
  const MyReposPage({super.key});

  @override
  State<MyReposPage> createState() => _MyReposPageState();
}

class _MyReposPageState extends State<MyReposPage> {
  final UserController _userController = Get.find<UserController>();
  final ScrollController _scrollController = ScrollController();

  String _visibility = 'all';
  late final Worker _userWatcher;

  late final PagedListController<RepoItem> _list =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getMyReposAPI(page: page, visibility: _visibility),
        firstPageErrorFallback: '加载仓库列表失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _userWatcher = ever(_userController.user, (_) {
      if (!mounted) return;
      if (_userController.isLoggedIn) {
        _list.refresh();
      } else {
        _list.clear();
      }
    });
    if (_userController.isLoggedIn) {
      _list.refresh();
    }
  }

  @override
  void dispose() {
    _userWatcher.dispose();
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 滚动距底部不足 200px 时自动加载下一页仓库
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换仓库可见性筛选（全部 / 公开 / 私有）并刷新列表
  void _switchVisibility(String next) {
    if (_visibility == next) return;
    setState(() => _visibility = next);
    _list.clear();
    _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('我的仓库'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: Obx(() {
        if (!_userController.isLoggedIn) {
          return HmEmptyView(
            icon: Icons.lock_outline,
            title: '登录后查看我的仓库',
            actionText: '立即登录',
            onAction: () => Navigator.pushNamed(context, AppRoutes.login),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HmBottomBar.maxContentWidth,
            ),
            child: Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _list,
                    builder: (context, _) => _buildList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFilterBar() {
    const options = [('all', '全部'), ('public', '公开'), ('private', '私有')];
    return Container(
      width: double.infinity,
      color: context.appColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (value, label) in options)
            ChoiceChip(
              label: Text(label),
              selected: _visibility == value,
              onSelected: (_) => _switchVisibility(value),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return HmEmptyView(
        icon: Icons.folder_open,
        title: '暂无仓库',
        description: '该筛选条件下没有找到仓库',
        actionText: '刷新重试',
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
              failed: _list.loadMoreFailed,
              onRetry: _list.retryLoadMore,
              noMoreText: '已展示全部仓库',
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
