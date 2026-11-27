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
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// GitHub 消息通知中心
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final UserController _userController = Get.find<UserController>();
  final ScrollController _scrollController = ScrollController();

  bool _showAll = false;
  final Set<String> _locallyReadIds = <String>{};

  late final PagedListController<NotificationItem> _list =
      PagedListController<NotificationItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getNotificationsAPI(all: _showAll, page: page),
        firstPageErrorFallback: '加载通知失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_userController.isLoggedIn) {
      _list.refresh();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 滚动接近底部时触发下一页通知加载
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换「仅未读 / 全部通知」过滤并重新拉取
  void _switchFilter(bool showAll) {
    if (_showAll == showAll) return;
    setState(() => _showAll = showAll);
    _list.clear();
    _list.refresh();
  }

  /// 一键将当前账号的全部未读通知标为已读
  Future<void> _markAllRead() async {
    try {
      await markAllNotificationsReadAPI();
      if (!mounted) return;
      ToastUtils.showToast(context, '已全部标为已读');
      await _list.refresh();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '操作失败'));
    }
  }

  /// 点击通知条：先标为已读（含本地即时反馈），再跳往关联仓库详情页
  Future<void> _openNotification(NotificationItem item) async {
    if (item.unread && !_locallyReadIds.contains(item.id)) {
      setState(() => _locallyReadIds.add(item.id));
      try {
        await markNotificationReadAPI(item.id);
      } catch (_) {}
    }
    if (!mounted) return;
    if (item.repoOwner.isNotEmpty && item.repoName.isNotEmpty) {
      await Navigator.pushNamed(
        context,
        AppRoutes.repoDetail(item.repoOwner, item.repoName),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('消息通知'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_userController.isLoggedIn)
            TextButton(onPressed: _markAllRead, child: const Text('全部已读')),
        ],
      ),
      body: Obx(() {
        if (!_userController.isLoggedIn) {
          return HmEmptyView(
            icon: Icons.notifications_off_outlined,
            title: '登录后查看消息通知',
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
                        label: const Text('仅未读'),
                        selected: !_showAll,
                        onSelected: (_) => _switchFilter(false),
                      ),
                      ChoiceChip(
                        label: const Text('全部通知'),
                        selected: _showAll,
                        onSelected: (_) => _switchFilter(true),
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
        );
      }),
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
        icon: Icons.notifications_none,
        title: _showAll ? '暂无消息通知' : '没有未读通知',
        actionText: '刷新',
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
              noMoreText: '没有更多通知了',
            );
          }
          final item = _list[index];
          final unread = item.unread && !_locallyReadIds.contains(item.id);
          return Material(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              onTap: () => _openNotification(item),
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
                    AppNetworkImage(
                      url: item.repoOwnerAvatar,
                      width: 34,
                      height: 34,
                      decodeWidth: 34,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (unread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: context.appColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  item.repoFullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.captionStyle.copyWith(
                                    color: context.appColors.primary,
                                  ),
                                ),
                              ),
                              if (item.updatedAt != null)
                                Text(
                                  formatRelativeTime(item.updatedAt),
                                  style: context.captionSmallStyle,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subjectTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.bodyStrongStyle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.subjectType} · ${item.reason}',
                            style: context.captionSmallStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
