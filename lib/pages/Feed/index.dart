import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/feed.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/event.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/notification_badge_store.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 关注动态页（received_events）
class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  final UserController _userController = Get.find<UserController>();
  final ScrollController _scrollController = ScrollController();

  late final Worker _userWatcher;
  CancelToken? _badgeToken;

  late final PagedListController<GithubEvent> _list =
      PagedListController<GithubEvent>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getReceivedEventsAPI(
          _userController.user.value.login,
          page: page,
          cancelToken: _list.cancelToken,
        ),
        firstPageErrorFallback: '加载关注动态失败',
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
        _refreshUnreadBadge();
      } else {
        _list.clear();
        NotificationBadgeStore.clear();
      }
    });
    if (_userController.isLoggedIn) {
      _list.refresh();
      _refreshUnreadBadge();
    }
  }

  @override
  void dispose() {
    _badgeToken?.cancel();
    _userWatcher.dispose();
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  void _refreshUnreadBadge() {
    if (!_userController.isLoggedIn) return;
    _badgeToken?.cancel();
    final token = CancelToken();
    _badgeToken = token;
    unawaited(NotificationBadgeStore.refresh(cancelToken: token));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
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
              _buildHeader(),
              Expanded(
                child: Obx(() {
                  if (!_userController.isLoggedIn) {
                    return HmEmptyView(
                      icon: Icons.rss_feed,
                      title: '登录后查看关注动态',
                      description: '跟踪已关注开发者和项目的 Star、发布与代码推送',
                      actionText: '立即登录',
                      onAction: () =>
                          Navigator.pushNamed(context, AppRoutes.login),
                    );
                  }
                  return ListenableBuilder(
                    listenable: _list,
                    builder: (context, _) => _buildList(),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: context.appColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.rss_feed, color: context.appColors.brandDark, size: 22),
          const SizedBox(width: 8),
          Text('关注动态', style: context.sectionTitleStyle),
          const Spacer(),
          IconButton(
            onPressed: () async {
              if (!_userController.isLoggedIn) {
                ToastUtils.showToast(context, '登录后查看消息通知');
                await Navigator.pushNamed(context, AppRoutes.login);
                if (!mounted || !_userController.isLoggedIn) return;
              }
              await Navigator.pushNamed(context, AppRoutes.notificationsPath);
              if (mounted) _refreshUnreadBadge();
            },
            icon: ValueListenableBuilder<bool>(
              valueListenable: NotificationBadgeStore.hasUnread,
              builder: (context, hasUnread, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none),
                    if (hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.appColors.badge,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            tooltip: '消息通知',
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
        icon: Icons.timeline,
        title: '暂时没有动态',
        description: '去关注一些开发者或项目，动态会出现在这里',
        actionText: '刷新重试',
        onAction: _list.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _refreshUnreadBadge();
        await _list.refresh();
      },
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
              noMoreText: '没有更多动态了',
            );
          }
          final event = _list[index];
          return _EventCard(
            event: event,
            onActorTap: () => Navigator.pushNamed(
              context,
              AppRoutes.userDetail(event.actorLogin),
            ),
            onRepoTap: () => Navigator.pushNamed(
              context,
              AppRoutes.repoDetailFromFullName(event.repoName),
            ),
          );
        },
      ),
    );
  }
}

/// 关注动态事件卡片（支持点击头像看用户、点击卡片看仓库）
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onActorTap,
    required this.onRepoTap,
  });

  final GithubEvent event;
  final VoidCallback onActorTap;
  final VoidCallback onRepoTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onRepoTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: context.appColors.divider.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onActorTap,
                child: AppNetworkImage(
                  url: event.actorAvatar,
                  width: 38,
                  height: 38,
                  decodeWidth: 38,
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: event.actorLogin,
                            style: context.bodyStrongStyle,
                          ),
                          TextSpan(
                            text: ' ${event.actionText}',
                            style: context.bodyStyle,
                          ),
                        ],
                      ),
                    ),
                    if (event.repoName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.repoName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.bodySmallStyle.copyWith(
                          color: context.appColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (event.detailText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.detailText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.captionStyle,
                      ),
                    ],
                    if (event.createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        formatRelativeTime(event.createdAt),
                        style: context.captionSmallStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
