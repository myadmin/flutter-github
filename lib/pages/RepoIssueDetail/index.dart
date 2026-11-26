import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// Issue / PR 详情与评论页（已登录支持发表评论）
class RepoIssueDetailPage extends StatefulWidget {
  const RepoIssueDetailPage({
    super.key,
    required this.owner,
    required this.repoName,
    required this.number,
  });

  final String owner;
  final String repoName;
  final int number;

  @override
  State<RepoIssueDetailPage> createState() => _RepoIssueDetailPageState();
}

class _RepoIssueDetailPageState extends State<RepoIssueDetailPage> {
  final UserController _userController = Get.find<UserController>();
  final TextEditingController _commentController = TextEditingController();

  IssueItem? _issue;
  List<IssueComment> _comments = const [];
  int _commentsPage = 0;
  bool _commentsLoading = false;
  bool _commentsHasMore = false;
  String _commentsError = '';
  bool _isLoading = true;
  bool _submitting = false;
  String _errorMessage = '';

  bool get _hasValidArgs =>
      widget.owner.isNotEmpty &&
      widget.repoName.isNotEmpty &&
      widget.number > 0;

  @override
  void initState() {
    super.initState();
    if (_hasValidArgs) {
      _load();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// 加载 Issue 主体详情，主体成功后再异步加载评论
  ///
  /// 评论接口需要额外权限（私有仓库或限流时容易 403），因此与主体解耦：
  /// 主体失败显示整页错误，评论失败只影响评论区并允许单独重试。
  Future<void> _load() async {
    setState(() {
      _isLoading = _issue == null;
      _errorMessage = '';
    });
    try {
      final issue = await getRepoIssueDetailAPI(
        widget.owner,
        widget.repoName,
        widget.number,
      );
      if (!mounted) return;
      setState(() {
        _issue = issue;
        _isLoading = false;
      });
      await _reloadComments();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '加载 Issue 详情失败');
      });
    }
  }

  /// 重新加载第一页评论（下拉刷新、发送评论后复用）
  Future<void> _reloadComments() async {
    if (_commentsLoading) return;
    setState(() {
      _commentsLoading = true;
      _commentsError = '';
    });
    try {
      final page = await getIssueCommentsAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _commentsPage = 1;
        _commentsHasMore = page.hasMore;
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = resolveErrorMessage(e, fallback: '评论加载失败');
      });
    }
  }

  /// 加载下一页评论并追加到列表尾部
  Future<void> _loadMoreComments() async {
    if (_commentsLoading || !_commentsHasMore) return;
    final nextPage = _commentsPage + 1;
    setState(() => _commentsLoading = true);
    try {
      final page = await getIssueCommentsAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.items];
        _commentsPage = nextPage;
        _commentsHasMore = page.hasMore;
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = resolveErrorMessage(e, fallback: '评论加载失败');
      });
    }
  }

  /// 校验登录态与内容后发送新评论并立即追加到本地列表
  Future<void> _submitComment() async {
    if (_submitting) return;
    if (!_userController.isLoggedIn) {
      ToastUtils.showToast(context, '登录后即可发表评论');
      await Navigator.pushNamed(context, AppRoutes.login);
      return;
    }
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ToastUtils.showToast(context, '请输入评论内容');
      return;
    }
    setState(() => _submitting = true);
    try {
      final created = await createIssueCommentAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        text,
      );
      if (!mounted) return;
      _commentController.clear();
      setState(() {
        _comments = [..._comments, created];
        _submitting = false;
      });
      ToastUtils.showToast(context, '评论已发送');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '发送评论失败'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(_hasValidArgs ? '#${widget.number}' : 'Issue 详情'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _issue == null
          ? null
          : HmBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _userController.isLoggedIn
                            ? '写下你的评论（支持 Markdown）...'
                            : '登录后可发表评论',
                        hintStyle: context.captionStyle,
                        filled: true,
                        fillColor: context.appColors.inputFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submitComment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appColors.brandButtonBg,
                      foregroundColor: context.appColors.brandButtonFg,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.appColors.brandButtonFg,
                            ),
                          )
                        : const Text('发送'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (!_hasValidArgs) {
      return const HmEmptyView(icon: Icons.error_outline, title: 'Issue 参数缺失');
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _issue == null) {
      return AppErrorView(message: _errorMessage, onRetry: _load);
    }
    final issue = _issue!;
    final isOpen = issue.isOpen;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: HmBottomBar.maxContentWidth,
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Container(
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
                    Text(issue.title, style: context.sectionTitleStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isOpen
                                ? context.appColors.successSurface
                                : context.appColors.mergedSurface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            isOpen ? 'Open' : 'Closed',
                            style: context.captionSmallStyle.copyWith(
                              color: isOpen
                                  ? context.appColors.success
                                  : context.appColors.merged,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${issue.user.login} 创建于 ${formatRelativeTime(issue.createdAt)}',
                          style: context.captionStyle,
                        ),
                      ],
                    ),
                    if (issue.body.trim().isNotEmpty) ...[
                      Divider(height: 20, color: context.appColors.divider),
                      GhMarkdownView(
                        data: issue.body,
                        owner: widget.owner,
                        repo: widget.repoName,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '评论 (${_comments.length}${_commentsHasMore ? '+' : ''})',
                  style: context.bodyStrongStyle,
                ),
              ),
              const SizedBox(height: 6),
              if (_commentsError.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.appColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _commentsError,
                          style: context.captionStyle,
                        ),
                      ),
                      TextButton(
                        onPressed: _reloadComments,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (_comments.isEmpty && !_commentsLoading)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.appColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Center(
                    child: Text('暂无评论', style: context.captionStyle),
                  ),
                )
              else
                for (final comment in _comments) ...[
                  _CommentCard(
                    comment: comment,
                    owner: widget.owner,
                    repoName: widget.repoName,
                  ),
                  const SizedBox(height: 10),
                ],
              if (_commentsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_commentsHasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: _loadMoreComments,
                      child: const Text('加载更多评论'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条 Issue 评论卡片（头像、作者、时间与 Markdown 正文）
class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    required this.owner,
    required this.repoName,
  });

  final IssueComment comment;
  final String owner;
  final String repoName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
                url: comment.user.avatarUrl,
                width: 24,
                height: 24,
                decodeWidth: 24,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 8),
              Text(comment.user.login, style: context.bodyStrongStyle),
              const Spacer(),
              Text(
                formatRelativeTime(comment.createdAt),
                style: context.captionSmallStyle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          GhMarkdownView(data: comment.body, owner: owner, repo: repoName),
        ],
      ),
    );
  }
}
