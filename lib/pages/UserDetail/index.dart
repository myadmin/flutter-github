import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/star.dart';
import 'package:gh_explorer/api/user.dart';
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
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 开发者 / 组织主页（资料卡片 + Follow 互动 + 公开仓库与 Star 列表）
class UserDetailPage extends StatefulWidget {
  const UserDetailPage({super.key, required this.login});

  final String login;

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  final UserController _userController = Get.find<UserController>();
  final ScrollController _scrollController = ScrollController();

  GithubUser? _profile;
  bool _isFollowing = false;
  bool _followPending = false;
  bool _isLoading = true;
  String _errorMessage = '';
  int _tabIndex = 0;
  CancelToken? _profileToken;

  late final PagedListController<RepoItem> _reposList =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getUserReposAPI(
          widget.login,
          page: page,
          cancelToken: _reposList.cancelToken,
        ),
        firstPageErrorFallback: '加载仓库失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  late final PagedListController<RepoItem> _starsList =
      PagedListController<RepoItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getUserStarredReposAPI(
          widget.login,
          page: page,
          cancelToken: _starsList.cancelToken,
        ),
        firstPageErrorFallback: '加载 Star 项目失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  bool get _isSelf =>
      _userController.isLoggedIn &&
      _userController.user.value.login.toLowerCase() ==
          widget.login.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.login.trim().isNotEmpty) {
      _loadProfile();
      _reposList.refresh();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _profileToken?.cancel();
    _scrollController.dispose();
    _reposList.dispose();
    _starsList.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (_tabIndex == 0) {
        _reposList.loadMore();
      } else {
        _starsList.loadMore();
      }
    }
  }

  /// 并发拉取用户资料与关注状态（本人主页与未登录跳过关注检查）
  Future<void> _loadProfile() async {
    _profileToken?.cancel();
    final token = CancelToken();
    _profileToken = token;
    setState(() {
      _isLoading = _profile == null;
      _errorMessage = '';
    });
    try {
      final profileFuture = getUserDetailAPI(widget.login, cancelToken: token);
      final followFuture = _userController.isLoggedIn && !_isSelf
          ? checkFollowingUserAPI(
              widget.login,
              cancelToken: token,
            ).catchError((Object _) => false)
          : Future<bool>.value(false);

      final (profile, following) = await (profileFuture, followFuture).wait;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isFollowing = following;
        _isLoading = false;
      });
    } catch (e) {
      if (e is RequestCancelledException || !mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '用户信息加载失败');
      });
    }
  }

  /// 切换 Follow / Unfollow 状态：未登录跳登录，已登录乐观更新并在失败时回滚
  Future<void> _toggleFollow() async {
    if (_followPending || _profile == null) return;
    if (!_userController.isLoggedIn) {
      ToastUtils.showToast(context, '登录后即可关注开发者');
      await Navigator.pushNamed(context, AppRoutes.login);
      // 登录成功后自动续做关注操作
      if (!mounted || !_userController.isLoggedIn) return;
    }
    final prev = _isFollowing;
    setState(() {
      _followPending = true;
      _isFollowing = !prev;
    });
    try {
      if (!prev) {
        await followUserAPI(widget.login);
      } else {
        await unfollowUserAPI(widget.login);
      }
      if (!mounted) return;
      ToastUtils.showToast(context, !prev ? '已关注 ${widget.login}' : '已取消关注');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFollowing = prev);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '操作失败'));
    } finally {
      if (mounted) setState(() => _followPending = false);
    }
  }

  /// 切换「公开仓库 / Star 的项目」Tab，首次切到 Star Tab 时懒加载数据
  void _switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
    if (index == 1 && _starsList.isEmpty && !_starsList.isLoading) {
      _starsList.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(widget.login.isEmpty ? '用户主页' : widget.login),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.login.trim().isEmpty) {
      return const HmEmptyView(
        icon: Icons.person_off_outlined,
        title: '用户信息缺失',
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _profile == null) {
      return AppErrorView(message: _errorMessage, onRetry: _loadProfile);
    }
    final user = _profile!;
    final activeList = _tabIndex == 0 ? _reposList : _starsList;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: HmBottomBar.maxContentWidth,
        ),
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadProfile();
            await activeList.refresh();
          },
          child: ListenableBuilder(
            listenable: activeList,
            builder: (context, _) {
              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  _buildUserHeader(user),
                  const SizedBox(height: 12),
                  _buildTabBar(),
                  const SizedBox(height: 10),
                  ..._buildTabContent(activeList),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(GithubUser user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppNetworkImage(
                url: user.avatarUrl,
                width: 60,
                height: 60,
                decodeWidth: 60,
                borderRadius: BorderRadius.circular(30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName, style: context.sectionTitleStyle),
                    const SizedBox(height: 2),
                    Text('@${user.login}', style: context.captionStyle),
                  ],
                ),
              ),
              if (!_isSelf && !user.isOrganization)
                OutlinedButton(
                  onPressed: _followPending ? null : _toggleFollow,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _isFollowing
                        ? context.appColors.primarySurface
                        : context.appColors.cardBackground,
                    foregroundColor: _isFollowing
                        ? context.appColors.primary
                        : context.appColors.brandDark,
                    side: BorderSide(
                      color: _isFollowing
                          ? context.appColors.primary
                          : context.appColors.divider,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(_isFollowing ? 'Following' : 'Follow'),
                ),
            ],
          ),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(user.bio, style: context.bodySmallStyle),
          ],
          if (user.company.isNotEmpty || user.location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (user.company.isNotEmpty)
                  _MetaRow(icon: Icons.business_outlined, text: user.company),
                if (user.location.isNotEmpty)
                  _MetaRow(
                    icon: Icons.location_on_outlined,
                    text: user.location,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '公开仓库 ${formatCompactNumber(user.publicRepos)}',
                style: context.captionStyle,
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.userFollows(user.login, tab: 'followers'),
                ),
                child: Text(
                  'Followers ${formatCompactNumber(user.followers)}',
                  style: context.captionStyle.copyWith(
                    color: context.appColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.userFollows(user.login, tab: 'following'),
                ),
                child: Text(
                  'Following ${formatCompactNumber(user.following)}',
                  style: context.captionStyle.copyWith(
                    color: context.appColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('公开仓库'),
          selected: _tabIndex == 0,
          onSelected: (_) => _switchTab(0),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Star 的项目'),
          selected: _tabIndex == 1,
          onSelected: (_) => _switchTab(1),
        ),
      ],
    );
  }

  List<Widget> _buildTabContent(PagedListController<RepoItem> list) {
    if (list.isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (list.errorMessage.isNotEmpty && list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: AppErrorView(
            message: list.errorMessage,
            onRetry: list.refresh,
          ),
        ),
      ];
    }
    if (list.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: HmEmptyView(icon: Icons.folder_open, title: '暂无项目'),
        ),
      ];
    }
    return [
      for (final repo in list.items) ...[
        GhRepoCard(
          repo: repo,
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.repoDetail(repo.ownerLogin, repo.repoName),
          ),
        ),
        const SizedBox(height: 10),
      ],
      HmListFooter(
        loadingMore: list.loadingMore,
        hasMore: list.hasMore,
        failed: list.loadMoreFailed,
        onRetry: list.retryLoadMore,
        noMoreText: '已展示全部项目',
      ),
    ];
  }
}

/// 用户资料元信息行（公司 / 地区）
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.appColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: context.captionStyle),
      ],
    );
  }
}
