import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
import 'package:gh_explorer/stores/user_controller.dart';
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
  final TextEditingController _keywordController = TextEditingController();

  UserController? get _userController =>
      Get.isRegistered<UserController>() ? Get.find<UserController>() : null;

  String _state = 'open';
  IssueKindFilter _kind = IssueKindFilter.all;
  String _activeQuery = '';
  int? _searchTotalCount;

  late final PagedListController<IssueItem> _list =
      PagedListController<IssueItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) {
          if (_activeQuery.isNotEmpty) {
            return searchRepoIssuesAPI(
              widget.owner,
              widget.repoName,
              keyword: _activeQuery,
              state: _state,
              kind: _kind,
              page: page,
              onTotalCount: (total) {
                if (mounted) {
                  setState(() => _searchTotalCount = total);
                }
              },
              cancelToken: _list.cancelToken,
            );
          }
          if (_kind == IssueKindFilter.pr) {
            return getRepoPullsAPI(
              widget.owner,
              widget.repoName,
              state: _state,
              page: page,
              cancelToken: _list.cancelToken,
            );
          }
          if (_kind == IssueKindFilter.issue) {
            return searchRepoIssuesAPI(
              widget.owner,
              widget.repoName,
              keyword: '',
              state: _state,
              kind: IssueKindFilter.issue,
              page: page,
              cancelToken: _list.cancelToken,
            );
          }
          return getRepoIssuesAPI(
            widget.owner,
            widget.repoName,
            state: _state,
            page: page,
            cancelToken: _list.cancelToken,
          );
        },
        firstPageErrorFallback: '加载 Issues 失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  bool get _hasValidArgs =>
      widget.owner.trim().isNotEmpty && widget.repoName.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_hasValidArgs) {
      _list.refresh();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _keywordController.dispose();
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

  /// 切换 Issue 状态筛选（Open / Closed / All）并刷新列表或搜索结果
  void _switchState(String next) {
    if (_state == next) return;
    setState(() {
      _state = next;
      _searchTotalCount = null;
    });
    _list.clear();
    _list.refresh();
  }

  /// 切换类型筛选（全部类型 / 仅 Issue / 仅 PR）
  void _switchKind(IssueKindFilter next) {
    if (_kind == next) return;
    setState(() {
      _kind = next;
      _searchTotalCount = null;
    });
    _list.clear();
    _list.refresh();
  }

  /// 打开新建 Issue 页面（未登录先跳登录，登录成功后自动继续）
  Future<void> _openCreateIssue() async {
    if (!_hasValidArgs) return;
    final userCtrl = _userController;
    if (userCtrl != null && !userCtrl.isLoggedIn) {
      ToastUtils.showToast(context, '登录后即可新建 Issue');
      await Navigator.pushNamed(context, AppRoutes.login);
      if (!mounted || !userCtrl.isLoggedIn) return;
    }
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.repoIssueCreate(widget.owner, widget.repoName),
    );
    if (!mounted) return;
    if (result is IssueItem) {
      await _list.refresh();
    }
  }

  int? get _directIssueNumber {
    final trimmed = _activeQuery.trim();
    final match = RegExp(r'^#?(\d+)$').firstMatch(trimmed);
    if (match == null) return null;
    final n = int.tryParse(match.group(1) ?? '');
    return (n != null && n > 0) ? n : null;
  }

  /// 在当前仓库全部 Issues 与 PR 中执行关键词检索
  void _submitSearch() {
    final text = _keywordController.text.trim();
    if (text.isEmpty) {
      if (_activeQuery.isNotEmpty) {
        _clearSearch();
      } else {
        ToastUtils.showToast(context, '请输入关键词或 Issue 编号');
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _activeQuery = text;
      _searchTotalCount = null;
    });
    _list.clear();
    _list.refresh();
  }

  /// 清空搜索词并恢复当前状态下的常规列表浏览
  void _clearSearch() {
    _keywordController.clear();
    FocusScope.of(context).unfocus();
    if (_activeQuery.isEmpty) {
      setState(() {});
      return;
    }
    setState(() {
      _activeQuery = '';
      _searchTotalCount = null;
    });
    _list.clear();
    _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('Issues 与 PR'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_hasValidArgs)
            IconButton(
              onPressed: _openCreateIssue,
              icon: const Icon(Icons.add),
              tooltip: '新建 Issue',
            ),
        ],
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              hintText: '搜索当前项目全部 Issues / PR（如关键词或 #编号）',
                              hintStyle: context.captionStyle,
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 19),
                              suffixIcon:
                                  _keywordController.text.isNotEmpty ||
                                      _activeQuery.isNotEmpty
                                  ? IconButton(
                                      onPressed: _clearSearch,
                                      icon: const Icon(Icons.clear, size: 18),
                                      tooltip: '清空搜索',
                                    )
                                  : null,
                              filled: true,
                              fillColor: context.appColors.inputFill,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _submitSearch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.appColors.brandButtonBg,
                            foregroundColor: context.appColors.brandButtonFg,
                            elevation: 0,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                          child: const Text('搜索'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
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
                        if (_activeQuery.isNotEmpty &&
                            _searchTotalCount != null)
                          Text(
                            '共 $_searchTotalCount 条',
                            style: context.captionSmallStyle.copyWith(
                              color: context.appColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final item in IssueKindFilter.values) ...[
                            ChoiceChip(
                              label: Text(item.label),
                              selected: _kind == item,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => _switchKind(item),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    if (_directIssueNumber != null) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.repoIssueDetail(
                            widget.owner,
                            widget.repoName,
                            _directIssueNumber!,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: context.appColors.primarySurface,
                            borderRadius: BorderRadius.circular(
                              AppRadius.small,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 15,
                                color: context.appColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '直达 #$_directIssueNumber 详情',
                                  style: context.captionSmallStyle.copyWith(
                                    color: context.appColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: context.appColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
    if (!_hasValidArgs) {
      return const HmEmptyView(icon: Icons.adjust, title: '仓库信息缺失');
    }
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      if (_activeQuery.isNotEmpty) {
        return HmEmptyView(
          icon: Icons.search_off_outlined,
          title: '未找到“$_activeQuery”相关记录',
          description: _state == 'all'
              ? '试试更换关键词或 Issue 编号'
              : '当前仅筛选 $_state 状态，可在全部状态中继续查找',
          actionText: _state == 'all' ? '清除搜索' : '在 All 中搜索',
          onAction: _state == 'all' ? _clearSearch : () => _switchState('all'),
        );
      }
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
              failed: _list.loadMoreFailed,
              onRetry: _list.retryLoadMore,
              noMoreText: '没有更多记录了',
            );
          }
          final item = _list[index];
          return _IssueCard(item: item, onTap: () => _openIssueDetail(item));
        },
      ),
    );
  }

  /// 打开 Issue / PR 详情；返回后刷新当前列表，避免关闭、编辑、合并后状态陈旧
  Future<void> _openIssueDetail(IssueItem item) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.repoIssueDetail(widget.owner, widget.repoName, item.number),
    );
    if (!mounted) return;
    await _list.refresh();
  }
}

/// 单条 Issue / PR 列表项卡片
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.item, required this.onTap});

  final IssueItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.isMerged
        ? context.appColors.merged
        : (item.isOpen ? context.appColors.success : context.appColors.merged);
    return Material(
      color: context.appColors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
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
              Icon(
                item.isPullRequest
                    ? (item.isMerged ? Icons.merge_type : Icons.call_merge)
                    : (item.isOpen ? Icons.adjust : Icons.check_circle_outline),
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: context.bodyStrongStyle),
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
                                color: context.appColors.primarySurface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                label.name,
                                style: context.labelStyle.copyWith(
                                  color: context.appColors.primary,
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
                            style: context.captionSmallStyle,
                          ),
                        ),
                        if (item.commentsCount > 0) ...[
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 13,
                            color: context.appColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${item.commentsCount}',
                            style: context.captionSmallStyle,
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
