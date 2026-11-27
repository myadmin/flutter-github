import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/star.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/gh_repo_card.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 我 Star 的项目列表页（支持取消 Star 并同步移除）
class MyStarsPage extends StatefulWidget {
  const MyStarsPage({super.key});

  @override
  State<MyStarsPage> createState() => _MyStarsPageState();
}

class _MyStarsPageState extends State<MyStarsPage> {
  final UserController _userController = Get.find<UserController>();
  final StarSyncController _starSync = Get.find<StarSyncController>();
  final ScrollController _scrollController = ScrollController();

  late final Worker _userWatcher;

  late final PagedListController<RepoItem> _list =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) async {
          final res = await getMyStarredReposAPI(
            page: page,
            cancelToken: _list.cancelToken,
          );
          for (final repo in res.items) {
            _starSync.setSnapshot(
              repo.fullName,
              isStarred: true,
              starCount: repo.stargazersCount,
            );
          }
          return res;
        },
        firstPageErrorFallback: '加载 Star 列表失败',
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

  /// 滚动距底部不足 200px 时自动加载下一页 Star 项目
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('我的 Star'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: Obx(() {
        if (!_userController.isLoggedIn) {
          return HmEmptyView(
            icon: Icons.star_border,
            title: '登录后查看我的 Star',
            actionText: '立即登录',
            onAction: () => Navigator.pushNamed(context, AppRoutes.login),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HmBottomBar.maxContentWidth,
            ),
            child: ListenableBuilder(
              listenable: _list,
              builder: (context, _) => _buildBody(),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBody() {
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return HmEmptyView(
        icon: Icons.star_border,
        title: '还没有 Star 任何项目',
        description: '去探索页发现感兴趣的项目并点亮 Star 吧',
        actionText: '去探索',
        onAction: () => Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (_) => false,
        ),
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
              noMoreText: '没有更多 Star 项目了',
            );
          }
          final repo = _list[index];
          return GhRepoCard(
            repo: repo,
            initialStarred: true,
            onStarToggled: (starred) {
              if (!starred) {
                _list.removeWhere(
                  (item) =>
                      item.fullName.toLowerCase() ==
                      repo.fullName.toLowerCase(),
                );
              }
            },
            onTap: () async {
              await Navigator.pushNamed(
                context,
                AppRoutes.repoDetail(repo.ownerLogin, repo.repoName),
              );
              if (!mounted) return;
              final snap = _starSync.snapshotOf(repo.fullName);
              if (snap != null && !snap.isStarred) {
                _list.removeWhere(
                  (item) =>
                      item.fullName.toLowerCase() ==
                      repo.fullName.toLowerCase(),
                );
              }
            },
          );
        },
      ),
    );
  }
}
