import 'package:flutter/material.dart';
import 'package:gh_explorer/api/user.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
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

/// 用户的 Followers / Following 列表页
class UserFollowsPage extends StatefulWidget {
  const UserFollowsPage({
    super.key,
    required this.login,
    this.initialTab = 'followers',
  });

  final String login;
  final String initialTab;

  @override
  State<UserFollowsPage> createState() => _UserFollowsPageState();
}

class _UserFollowsPageState extends State<UserFollowsPage> {
  final ScrollController _scrollController = ScrollController();

  late String _tab;

  late final PagedListController<RepoOwner> _list =
      PagedListController<RepoOwner>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => _tab == 'following'
            ? getUserFollowingAPI(
                widget.login,
                page: page,
                cancelToken: _list.cancelToken,
              )
            : getUserFollowersAPI(
                widget.login,
                page: page,
                cancelToken: _list.cancelToken,
              ),
        firstPageErrorFallback: '加载用户列表失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'following' ? 'following' : 'followers';
    _scrollController.addListener(_onScroll);
    if (widget.login.isNotEmpty) {
      _list.refresh();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换 Followers / Following 视图并重新请求列表
  void _switchTab(String next) {
    if (_tab == next) return;
    setState(() => _tab = next);
    _list.clear();
    _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(widget.login.isEmpty ? '关注关系' : '${widget.login} 的关系网'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: context.appColors.cardBackground,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Followers'),
                      selected: _tab == 'followers',
                      onSelected: (_) => _switchTab('followers'),
                    ),
                    ChoiceChip(
                      label: const Text('Following'),
                      selected: _tab == 'following',
                      onSelected: (_) => _switchTab('following'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _list,
                  builder: (context, _) => _buildList(),
                ),
              ),
            ],
          ),
        ),
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
      return const HmEmptyView(icon: Icons.people_outline, title: '暂无用户');
    }
    return RefreshIndicator(
      onRefresh: _list.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _list.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _list.length) {
            return HmListFooter(
              loadingMore: _list.loadingMore,
              hasMore: _list.hasMore,
              failed: _list.loadMoreFailed,
              onRetry: _list.retryLoadMore,
              noMoreText: '已展示全部用户',
            );
          }
          final user = _list[index];
          return Material(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(
                  color: context.appColors.divider.withValues(alpha: 0.6),
                ),
              ),
              leading: AppNetworkImage(
                url: user.avatarUrl,
                width: 40,
                height: 40,
                decodeWidth: 40,
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(user.login, style: context.bodyStrongStyle),
              subtitle: Text(user.type, style: context.captionSmallStyle),
              trailing: Icon(
                Icons.chevron_right,
                color: context.appColors.textSecondary,
              ),
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.userDetail(user.login),
              ),
            ),
          );
        },
      ),
    );
  }
}
