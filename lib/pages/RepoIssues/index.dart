import 'package:flutter/material.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库 Issues 与 Pull Requests 列表页
class RepoIssuesPage extends StatefulWidget {
  const RepoIssuesPage({
    super.key,
    required this.owner,
    required this.repoName,
  });

  final String owner;
  final String repoName;

  @override
  State<RepoIssuesPage> createState() => _RepoIssuesPageState();
}

class _RepoIssuesPageState extends State<RepoIssuesPage> {
  final ScrollController _scrollController = ScrollController();

  String _state = 'open';

  late final PagedListController<IssueItem> _list =
      PagedListController<IssueItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoIssuesAPI(
          widget.owner,
          widget.repoName,
          state: _state,
          page: page,
        ),
        firstPageErrorFallback: '加载 Issues 失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.owner.isNotEmpty && widget.repoName.isNotEmpty) {
      _list.refresh();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 滚动到底部阈值时触发加载下一页 Issue
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 切换 Issue 状态筛选（Open / Closed / All）并刷新列表
  void _switchState(String next) {
    if (_state == next) return;
    setState(() => _state = next);
    _list.clear();
    _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Issues 与 PR'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
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
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Open'),
                      selected: _state == 'open',
                      onSelected: (_) => _switchState('open'),
                    ),
                    ChoiceChip(
                      label: const Text('Closed'),
                      selected: _state == 'closed',
                      onSelected: (_) => _switchState('closed'),
                    ),
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _state == 'all',
                      onSelected: (_) => _switchState('all'),
                    ),
                  ],
                ),
              ),
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

  Widget _buildBody() {
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return HmEmptyView(
        icon: Icons.check_circle_outline,
        title: '暂无 $_state 状态的记录',
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
              noMoreText: '没有更多记录了',
            );
          }
          final item = _list[index];
          return _IssueCard(
            item: item,
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.repoIssueDetail(
                widget.owner,
                widget.repoName,
                item.number,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单条 Issue / PR 列表项卡片
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.item, required this.onTap});

  final IssueItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.isOpen ? AppColors.success : AppColors.merged;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.isPullRequest
                    ? Icons.merge_type
                    : (item.isOpen ? Icons.adjust : Icons.check_circle_outline),
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppTextStyles.bodyStrong),
                    if (item.labels.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final label in item.labels.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                label.name,
                                style: AppTextStyles.label.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${item.number} · ${item.user.login} · ${formatRelativeTime(item.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.captionSmall,
                          ),
                        ),
                        if (item.commentsCount > 0) ...[
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${item.commentsCount}',
                            style: AppTextStyles.captionSmall,
                          ),
                        ],
                      ],
                    ),
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
