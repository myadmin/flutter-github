import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/Repo/gh_diff_patch_view.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/external_link.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// Issue / PR 详情与评论页（支持 PR 分支/Diff 审查、合入，以及编辑、关开状态与发评论）
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
  PullRequestDetail? _prDetail;
  List<CommitFileChange> _prFiles = const [];
  int _prFilesPage = 0;
  bool _prFilesLoading = false;
  bool _prFilesHasMore = false;
  String _prFilesError = '';
  int _activeSectionTab = 0; // 0: 讨论, 1: 变更文件

  List<IssueComment> _comments = const [];
  int _commentsPage = 0;
  bool _commentsLoading = false;
  bool _commentsHasMore = false;
  String _commentsError = '';
  String _commentsMoreError = '';
  int _commentsSeq = 0;
  CancelToken? _commentsToken;
  String _prFilesMoreError = '';
  int _prFilesSeq = 0;
  CancelToken? _prFilesToken;
  bool _isLoading = true;
  bool _submitting = false;
  bool _updatingIssue = false;
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
    // 页面退出时取消所有在途的评论/文件请求，避免占用配额与内存
    _commentsToken?.cancel();
    _prFilesToken?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  /// 加载 Issue 主体详情，主体成功后再异步加载评论及（若为 PR）PR 审查信息
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
      await Future.wait([
        _reloadComments(),
        if (issue.isPullRequest) _loadPullRequestInfo(),
      ]);
    } catch (e) {
      if (!mounted) return;
      final message = resolveErrorMessage(e, fallback: '加载 Issue 详情失败');
      if (_issue != null) {
        // 已有内容时刷新失败只提示，不把已渲染的详情整页替换成错误页
        setState(() => _isLoading = false);
        ToastUtils.showToast(context, message);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      }
    }
  }

  Future<void> _loadPullRequestInfo() async {
    try {
      final detail = await getPullRequestDetailAPI(
        widget.owner,
        widget.repoName,
        widget.number,
      );
      if (!mounted) return;
      setState(() => _prDetail = detail);
    } catch (_) {
      // PR 元数据读取失败时保留基础正文展示，不拖垮页面
    }
    await _reloadPrFiles();
  }

  Future<void> _reloadPrFiles() async {
    final seq = ++_prFilesSeq;
    _prFilesToken?.cancel();
    final token = CancelToken();
    _prFilesToken = token;
    setState(() {
      _prFilesLoading = true;
      _prFilesError = '';
      _prFilesMoreError = '';
    });
    try {
      final page = await getPullRequestFilesAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: 1,
        cancelToken: token,
      );
      if (!mounted || seq != _prFilesSeq) return;
      setState(() {
        _prFiles = page.items;
        _prFilesPage = 1;
        _prFilesHasMore = page.hasMore;
        _prFilesLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _prFilesSeq) return;
      setState(() {
        _prFilesLoading = false;
        _prFilesError = resolveErrorMessage(e, fallback: '变更文件加载失败');
      });
    }
  }

  Future<void> _loadMorePrFiles() async {
    if (_prFilesLoading || !_prFilesHasMore) return;
    final seq = _prFilesSeq;
    final nextPage = _prFilesPage + 1;
    setState(() {
      _prFilesLoading = true;
      _prFilesMoreError = '';
    });
    try {
      final page = await getPullRequestFilesAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: nextPage,
        cancelToken: _prFilesToken,
      );
      if (!mounted || seq != _prFilesSeq) return;
      setState(() {
        _prFiles = [..._prFiles, ...page.items];
        _prFilesPage = nextPage;
        _prFilesHasMore = page.hasMore;
        _prFilesLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _prFilesSeq) return;
      setState(() {
        _prFilesLoading = false;
        // 追加失败只影响尾部，已渲染的文件保持可见
        _prFilesMoreError = resolveErrorMessage(e, fallback: '加载更多文件失败');
      });
    }
  }

  /// 重新加载第一页评论（下拉刷新、发送评论后复用）
  Future<void> _reloadComments() async {
    final seq = ++_commentsSeq;
    _commentsToken?.cancel();
    final token = CancelToken();
    _commentsToken = token;
    setState(() {
      _commentsLoading = true;
      _commentsError = '';
      _commentsMoreError = '';
    });
    try {
      final page = await getIssueCommentsAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: 1,
        cancelToken: token,
      );
      if (!mounted || seq != _commentsSeq) return;
      setState(() {
        _comments = page.items;
        _commentsPage = 1;
        _commentsHasMore = page.hasMore;
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _commentsSeq) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = resolveErrorMessage(e, fallback: '评论加载失败');
      });
    }
  }

  /// 加载下一页评论并追加到列表尾部
  Future<void> _loadMoreComments() async {
    if (_commentsLoading || !_commentsHasMore) return;
    final seq = _commentsSeq;
    final nextPage = _commentsPage + 1;
    setState(() {
      _commentsLoading = true;
      _commentsMoreError = '';
    });
    try {
      final page = await getIssueCommentsAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        page: nextPage,
        cancelToken: _commentsToken,
      );
      if (!mounted || seq != _commentsSeq) return;
      setState(() {
        _comments = [..._comments, ...page.items];
        _commentsPage = nextPage;
        _commentsHasMore = page.hasMore;
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _commentsSeq) return;
      setState(() {
        _commentsLoading = false;
        _commentsMoreError = resolveErrorMessage(e, fallback: '评论加载失败');
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
        _issue = _issue?.copyWith(
          commentsCount: (_issue?.commentsCount ?? _comments.length - 1) + 1,
        );
        _submitting = false;
      });
      ToastUtils.showToast(context, '评论已发送');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '发送评论失败'));
    }
  }

  Future<void> _toggleIssueState() async {
    final issue = _issue;
    if (issue == null || _updatingIssue) return;
    final targetState = issue.isOpen ? 'closed' : 'open';
    final actionText = issue.isOpen ? '关闭' : '重新打开';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionText #${issue.number}'),
        content: Text('确定要$actionText「${issue.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionText),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updatingIssue = true);
    try {
      final updated = await updateRepoIssueAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        state: targetState,
      );
      if (!mounted) return;
      setState(() {
        _issue = updated;
        _updatingIssue = false;
      });
      ToastUtils.showToast(context, '已$actionText');
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingIssue = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '更新状态失败'));
    }
  }

  Future<void> _editIssueContent() async {
    final issue = _issue;
    if (issue == null || _updatingIssue) return;
    final titleCtrl = TextEditingController(text: issue.title);
    final bodyCtrl = TextEditingController(text: issue.body);
    var titleError = '';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('编辑 #${issue.number}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    maxLength: 256,
                    decoration: InputDecoration(
                      labelText: '标题',
                      errorText: titleError.isEmpty ? null : titleError,
                    ),
                    onChanged: (_) {
                      if (titleError.isNotEmpty) {
                        setDialogState(() => titleError = '');
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bodyCtrl,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: '正文内容'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                // 在弹窗内校验，避免关闭后才报错导致刚输入的正文丢失
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) {
                    setDialogState(() => titleError = '标题不能为空');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _updatingIssue = true);
      final updated = await updateRepoIssueAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        title: titleCtrl.text.trim(),
        body: bodyCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _issue = updated;
        _updatingIssue = false;
      });
      ToastUtils.showToast(context, '已保存更新');
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingIssue = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '保存修改失败'));
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
    }
  }

  Future<void> _confirmAndMergePr() async {
    final pr = _prDetail;
    if (pr == null || _updatingIssue) return;
    var method = 'merge';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('合并 PR #${pr.number}'),
          content: RadioGroup<String>(
            groupValue: method,
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => method = value);
              }
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('请选择合并方式：'),
                RadioListTile<String>(
                  value: 'merge',
                  title: Text('Merge commit'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'squash',
                  title: Text('Squash and merge'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'rebase',
                  title: Text('Rebase and merge'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认合并'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updatingIssue = true);
    try {
      // 固定用户审阅过的 head sha：分支被再次推送时 GitHub 会拒绝合并
      final result = await mergePullRequestAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        mergeMethod: method,
        sha: pr.headSha,
      );
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        result.message.isEmpty ? 'Pull Request 已合并' : result.message,
      );
      setState(() => _updatingIssue = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingIssue = false);
      final code = e is ApiException ? e.code : '';
      if (code == '405' || code == '409') {
        ToastUtils.showToast(
          context,
          code == '409'
              ? 'PR 在审阅后有新的提交或存在冲突，已刷新，请重新审阅后再合并'
              : '当前 PR 不可合并（可能是分支保护或状态校验未通过），已刷新',
        );
        // 刷新详情与 diff，让用户看最新的 head 与可合并状态
        await _load();
        return;
      }
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '合并 Pull Request 失败'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(_hasValidArgs ? '#${widget.number}' : 'Issue 详情'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (issue != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'open_browser':
                    if (issue.htmlUrl.isNotEmpty) {
                      openExternalUrl(issue.htmlUrl);
                    }
                  case 'edit':
                    _editIssueContent();
                  case 'toggle_state':
                    _toggleIssueState();
                }
              },
              itemBuilder: (context) => [
                if (issue.htmlUrl.isNotEmpty)
                  const PopupMenuItem<String>(
                    value: 'open_browser',
                    child: Text('在 GitHub 打开'),
                  ),
                if (_userController.isLoggedIn) ...[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('编辑标题与正文'),
                  ),
                  if (!(_prDetail?.merged ?? false))
                    PopupMenuItem<String>(
                      value: 'toggle_state',
                      child: Text(issue.isOpen ? '关闭' : '重新打开'),
                    ),
                ],
              ],
            ),
        ],
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
    final pr = _prDetail;
    final isMerged = pr?.merged ?? issue.isMerged;
    final statusLabel = isMerged
        ? 'Merged'
        : (pr != null && pr.draft && isOpen
              ? 'Draft'
              : (isOpen ? 'Open' : 'Closed'));
    final statusFg = isMerged
        ? context.appColors.merged
        : (pr != null && pr.draft && isOpen
              ? context.appColors.textSecondary
              : (isOpen
                    ? context.appColors.success
                    : context.appColors.merged));
    final statusBg = isMerged
        ? context.appColors.mergedSurface
        : (pr != null && pr.draft && isOpen
              ? context.appColors.inputFill
              : (isOpen
                    ? context.appColors.successSurface
                    : context.appColors.mergedSurface));
    final displayCommentCount = _comments.length > issue.commentsCount
        ? _comments.length
        : issue.commentsCount;

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
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            statusLabel,
                            style: context.captionSmallStyle.copyWith(
                              color: statusFg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${issue.user.login} 创建于 ${formatRelativeTime(issue.createdAt)}',
                          style: context.captionStyle,
                        ),
                      ],
                    ),
                    if (pr != null) ...[
                      const SizedBox(height: 10),
                      _buildPrSummaryCard(pr),
                    ],
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
              if (issue.isPullRequest) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('讨论 ($displayCommentCount)'),
                      selected: _activeSectionTab == 0,
                      onSelected: (_) => setState(() => _activeSectionTab = 0),
                    ),
                    ChoiceChip(
                      label: Text(
                        '变更文件 (${pr?.changedFiles ?? _prFiles.length})',
                      ),
                      selected: _activeSectionTab == 1,
                      onSelected: (_) => setState(() => _activeSectionTab = 1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    '评论 ($displayCommentCount)',
                    style: context.bodyStrongStyle,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (issue.isPullRequest && _activeSectionTab == 1)
                ..._buildPrFilesSection(pr)
              else
                ..._buildCommentsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrSummaryCard(PullRequestDetail pr) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.inputFill.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${pr.headRef} → ${pr.baseRef}',
                  style: context.monoSmallStyle.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text('${pr.commits} 次提交', style: context.captionSmallStyle),
              Text(
                '+${pr.additions}',
                style: context.captionSmallStyle.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '-${pr.deletions}',
                style: context.captionSmallStyle.copyWith(
                  color: colors.badge,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text('${pr.changedFiles} 个文件', style: context.captionSmallStyle),
            ],
          ),
          if (_userController.isLoggedIn &&
              pr.isOpen &&
              !pr.merged &&
              !pr.draft) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ElevatedButton.icon(
                // mergeable == false 表示与基线冲突，直接合并必然失败，先置灰
                onPressed: (_updatingIssue || pr.mergeable == false)
                    ? null
                    : _confirmAndMergePr,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.merge_type, size: 16),
                label: const Text(
                  '合并 Pull Request',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (pr.mergeable == false) ...[
              const SizedBox(height: 6),
              Text(
                '当前分支与基线存在冲突，请先解决冲突后再合并',
                style: context.captionSmallStyle.copyWith(color: colors.badge),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _buildPrFilesSection(PullRequestDetail? pr) {
    final headRef = pr?.headSha.isNotEmpty == true
        ? pr!.headSha
        : (pr?.headRef ?? '');
    return [
      if (_prFilesError.isNotEmpty && _prFiles.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_prFilesError, style: context.captionStyle)),
              TextButton(onPressed: _reloadPrFiles, child: const Text('重试')),
            ],
          ),
        )
      else if (_prFiles.isEmpty && !_prFilesLoading)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Center(child: Text('暂无变更文件', style: context.captionStyle)),
        )
      else
        for (final file in _prFiles) ...[
          GhDiffFileCard(
            file: file,
            initiallyExpanded: _prFiles.length <= 10,
            onViewFile: headRef.isEmpty
                ? null
                : () => Navigator.pushNamed(
                    context,
                    AppRoutes.repoFileView(
                      widget.owner,
                      widget.repoName,
                      path: file.filename,
                      ref: headRef,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
        ],
      if (_prFilesMoreError.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_prFilesMoreError, style: context.captionStyle),
              ),
              TextButton(onPressed: _loadMorePrFiles, child: const Text('重试')),
            ],
          ),
        )
      else if (_prFilesLoading)
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
      else if (_prFilesHasMore)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: OutlinedButton(
              onPressed: _loadMorePrFiles,
              child: const Text('加载更多变更文件'),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildCommentsSection() {
    return [
      if (_commentsError.isNotEmpty && _comments.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_commentsError, style: context.captionStyle),
              ),
              TextButton(onPressed: _reloadComments, child: const Text('重试')),
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
          child: Center(child: Text('暂无评论', style: context.captionStyle)),
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
      if (_commentsMoreError.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_commentsMoreError, style: context.captionStyle),
              ),
              TextButton(onPressed: _loadMoreComments, child: const Text('重试')),
            ],
          ),
        )
      else if (_commentsLoading)
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
    ];
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
