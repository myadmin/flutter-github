import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gh_explorer/api/repo.dart';
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
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库提交历史页面（Commits 分页列表 + SHA 一键复制）
class RepoCommitsPage extends StatefulWidget {
  const RepoCommitsPage({
    super.key,
    required this.owner,
    required this.repoName,
    this.branch = '',
  });

  final String owner;
  final String repoName;
  final String branch;

  @override
  State<RepoCommitsPage> createState() => _RepoCommitsPageState();
}

class _RepoCommitsPageState extends State<RepoCommitsPage> {
  final ScrollController _scrollController = ScrollController();
  late String _currentBranch;
  List<RepoBranch> _branches = const [];
  CancelToken? _branchesToken;

  late final PagedListController<CommitItem> _list =
      PagedListController<CommitItem>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoCommitsAPI(
          widget.owner,
          widget.repoName,
          branch: _currentBranch,
          page: page,
          cancelToken: _list.cancelToken,
        ),
        firstPageErrorFallback: '加载提交历史失败',
        onLoadMoreError: (msg) {
          if (mounted) ToastUtils.showToast(context, msg);
        },
      );

  @override
  void initState() {
    super.initState();
    _currentBranch = widget.branch;
    _scrollController.addListener(_onScroll);
    if (widget.owner.isNotEmpty && widget.repoName.isNotEmpty) {
      _list.refresh();
      _loadBranches();
    }
  }

  @override
  void dispose() {
    _branchesToken?.cancel();
    _scrollController.dispose();
    _list.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final token = CancelToken();
    _branchesToken = token;
    try {
      final list = await getAllRepoBranchesAPI(
        widget.owner,
        widget.repoName,
        maxPages: 1,
        cancelToken: token,
      );
      if (!mounted) return;
      setState(() => _branches = list);
    } catch (_) {}
  }

  void _switchBranch(String branch) {
    if (branch == _currentBranch) return;
    setState(() => _currentBranch = branch);
    _list.clear();
    _list.refresh();
  }

  /// 滚动距底部不足 200px 时自动加载下一页提交记录
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  /// 复制完整 Commit SHA 到剪贴板并给出短码提示
  Future<void> _copySha(String sha) async {
    await Clipboard.setData(ClipboardData(text: sha));
    if (!mounted) return;
    final short = sha.length > 7 ? sha.substring(0, 7) : sha;
    ToastUtils.showToast(context, '已复制 SHA: $short');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(
          _currentBranch.isEmpty ? '提交历史' : '提交历史 ($_currentBranch)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_branches.isNotEmpty)
            PopupMenuButton<String>(
              initialValue: _currentBranch,
              onSelected: _switchBranch,
              tooltip: '切换分支',
              itemBuilder: (context) => [
                for (final branch in _branches)
                  PopupMenuItem<String>(
                    value: branch.name,
                    child: Text(branch.name),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alt_route, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _currentBranch.isEmpty ? '默认分支' : _currentBranch,
                      style: context.bodySmallStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: ListenableBuilder(
            listenable: _list,
            builder: (context, _) => _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.owner.trim().isEmpty || widget.repoName.trim().isEmpty) {
      return const HmEmptyView(icon: Icons.commit, title: '仓库信息缺失');
    }
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return const HmEmptyView(icon: Icons.commit, title: '暂无提交记录');
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
              noMoreText: '已展示全部提交',
            );
          }
          final commit = _list[index];
          return Material(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              onTap: commit.sha.isEmpty
                  ? null
                  : () => Navigator.pushNamed(
                      context,
                      AppRoutes.repoCommitDetail(
                        widget.owner,
                        widget.repoName,
                        commit.sha,
                      ),
                    ),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: context.appColors.divider.withValues(alpha: 0.6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(commit.titleLine, style: context.bodyStrongStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AppNetworkImage(
                          url: commit.authorAvatar,
                          width: 20,
                          height: 20,
                          decodeWidth: 20,
                          placeholderIconSize: 12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${commit.displayAuthor} · ${formatRelativeTime(commit.committedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.captionStyle,
                          ),
                        ),
                        InkWell(
                          onTap: () => _copySha(commit.sha),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.appColors.inputFill,
                              borderRadius: BorderRadius.circular(
                                AppRadius.small,
                              ),
                            ),
                            child: Text(
                              commit.shortSha,
                              style: context.monoSmallStyle,
                            ),
                          ),
                        ),
                      ],
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
