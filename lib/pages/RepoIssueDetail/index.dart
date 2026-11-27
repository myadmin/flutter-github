import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/Issue/gh_issue_comment_card.dart';
import 'package:gh_explorer/components/Issue/gh_pr_review_section.dart';
import 'package:gh_explorer/components/Repo/gh_diff_patch_view.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
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

/// Issue / PR 详情与评论页（支持 PR 分支/Diff/行内审阅、合入、编辑、标签及评论互动）
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
  final FocusNode _commentFocusNode = FocusNode();

  IssueItem? _issue;
  PullRequestDetail? _prDetail;
  List<PullRequestReview> _prReviews = const [];
  List<PullRequestReviewComment> _prReviewComments = const [];
  List<CommitFileChange> _prFiles = const [];
  int _prFilesPage = 0;
  bool _prFilesLoading = false;
  bool _prFilesHasMore = false;
  String _prFilesError = '';
  String _prFilesMoreError = '';
  int _prFilesSeq = 0;
  CancelToken? _prFilesToken;
  int _activeSectionTab = 0; // 0: 讨论, 1: 变更文件

  List<IssueComment> _comments = const [];
  int _commentsPage = 0;
  bool _commentsLoading = false;
  bool _commentsHasMore = false;
  String _commentsError = '';
  String _commentsMoreError = '';
  int _commentsSeq = 0;
  CancelToken? _commentsToken;
  CancelToken? _detailToken;

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
    // 页面退出时取消所有在途请求，避免占用配额与内存
    _detailToken?.cancel();
    _commentsToken?.cancel();
    _prFilesToken?.cancel();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  /// 加载 Issue 主体详情，主体成功后再异步加载评论及（若为 PR）PR 审查信息
  Future<void> _load() async {
    _detailToken?.cancel();
    final token = CancelToken();
    _detailToken = token;
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
      if (!mounted || token.isCancelled) return;
      setState(() {
        _issue = issue;
        _isLoading = false;
      });
      await Future.wait([
        _reloadComments(),
        if (issue.isPullRequest) _loadPullRequestInfo(token),
      ]);
    } catch (e) {
      if (e is RequestCancelledException || !mounted) return;
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

  Future<void> _loadPullRequestInfo(CancelToken token) async {
    try {
      final (detail, reviews, reviewComments) = await (
        getPullRequestDetailAPI(
          widget.owner,
          widget.repoName,
          widget.number,
          cancelToken: token,
        ),
        getPullRequestReviewsAPI(
          widget.owner,
          widget.repoName,
          widget.number,
          cancelToken: token,
        ).catchError((Object _) => const <PullRequestReview>[]),
        getPullRequestReviewCommentsAPI(
          widget.owner,
          widget.repoName,
          widget.number,
          cancelToken: token,
        ).catchError((Object _) => const <PullRequestReviewComment>[]),
      ).wait;
      if (!mounted || token.isCancelled) return;
      setState(() {
        _prDetail = detail;
        _prReviews = reviews;
        _prReviewComments = reviewComments;
      });
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
      if (e is RequestCancelledException || !mounted || seq != _prFilesSeq) {
        return;
      }
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
      if (e is RequestCancelledException || !mounted || seq != _prFilesSeq) {
        return;
      }
      setState(() {
        _prFilesLoading = false;
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
      if (e is RequestCancelledException || !mounted || seq != _commentsSeq) {
        return;
      }
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
      if (e is RequestCancelledException || !mounted || seq != _commentsSeq) {
        return;
      }
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

  void _quoteComment(IssueComment comment) {
    final firstLine = comment.body
        .trim()
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .trim();
    final snippet = firstLine.length > 80
        ? '${firstLine.substring(0, 80)}...'
        : firstLine;
    final prefix = StringBuffer();
    if (snippet.isNotEmpty) {
      prefix.writeln('> $snippet');
    }
    if (comment.user.login.isNotEmpty) {
      prefix.write('@${comment.user.login} ');
    }
    final existing = _commentController.text.trim();
    final nextText = existing.isEmpty
        ? prefix.toString()
        : '$existing\n${prefix.toString()}';
    _commentController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _commentFocusNode.requestFocus();
  }

  Future<void> _reactComment(IssueComment comment, String reaction) async {
    if (!_userController.isLoggedIn) {
      ToastUtils.showToast(context, '登录后可添加回应');
      await Navigator.pushNamed(context, AppRoutes.login);
      return;
    }
    try {
      await addIssueCommentReactionAPI(
        widget.owner,
        widget.repoName,
        comment.id,
        reaction,
      );
      if (!mounted) return;
      ToastUtils.showToast(context, '已添加回应');
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '添加回应失败'));
    }
  }

  Future<void> _editComment(IssueComment comment) async {
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) => _IssueFieldsDialog(
        dialogTitle: '编辑评论',
        bodyLabel: '评论内容',
        initialBody: comment.body,
        bodyEmptyError: '评论内容不能为空',
        bodyMinLines: 3,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final updated = await updateIssueCommentAPI(
        widget.owner,
        widget.repoName,
        comment.id,
        result.body.trim(),
      );
      if (!mounted) return;
      setState(() {
        _comments = _comments
            .map((c) => c.id == comment.id ? updated : c)
            .toList();
      });
      ToastUtils.showToast(context, '评论已更新');
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '更新评论失败'));
    }
  }

  Future<void> _deleteComment(IssueComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定删除这条评论吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await deleteIssueCommentAPI(widget.owner, widget.repoName, comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
        final currentCount = _issue?.commentsCount ?? 0;
        if (currentCount > 0) {
          _issue = _issue?.copyWith(commentsCount: currentCount - 1);
        }
      });
      ToastUtils.showToast(context, '已删除评论');
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '删除评论失败'));
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
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) => _IssueFieldsDialog(
        dialogTitle: '编辑 #${issue.number}',
        titleLabel: '标题',
        initialTitle: issue.title,
        maxTitleLength: 256,
        titleEmptyError: '标题不能为空',
        bodyLabel: '正文内容',
        initialBody: issue.body,
        bodyMinLines: 4,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _updatingIssue = true);
    try {
      final updated = await updateRepoIssueAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        title: result.title.trim(),
        body: result.body,
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
    }
  }

  Future<void> _editIssueLabels() async {
    final issue = _issue;
    if (issue == null || _updatingIssue) return;
    List<IssueLabel> repoLabels;
    try {
      repoLabels = await getRepoLabelsAPI(widget.owner, widget.repoName);
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '获取仓库标签失败'),
      );
      return;
    }
    if (!mounted) return;
    if (repoLabels.isEmpty) {
      ToastUtils.showToast(context, '该仓库暂无可选标签');
      return;
    }
    final selected = issue.labels.map((l) => l.name).toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('设置标签'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in repoLabels)
                  FilterChip(
                    label: Text(label.name),
                    selected: selected.contains(label.name),
                    onSelected: (v) {
                      setDialogState(() {
                        if (v) {
                          selected.add(label.name);
                        } else {
                          selected.remove(label.name);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('保存标签'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updatingIssue = true);
    try {
      final updated = await setIssueLabelsAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        selected.toList(),
      );
      if (!mounted) return;
      setState(() {
        _issue = _issue?.copyWith(labels: updated);
        _updatingIssue = false;
      });
      ToastUtils.showToast(context, '标签已更新');
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingIssue = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '更新标签失败'));
    }
  }

  Future<void> _submitPrReview() async {
    final pr = _prDetail;
    if (pr == null || _updatingIssue) return;
    final result = await showDialog<({String event, String body})>(
      context: context,
      builder: (_) => _PrReviewDialog(number: pr.number),
    );
    if (result == null || !mounted) return;
    setState(() => _updatingIssue = true);
    try {
      final created = await submitPullRequestReviewAPI(
        widget.owner,
        widget.repoName,
        widget.number,
        event: result.event,
        body: result.body.trim(),
      );
      if (!mounted) return;
      setState(() {
        _prReviews = [..._prReviews, created];
        _updatingIssue = false;
      });
      ToastUtils.showToast(context, '审阅意见已提交');
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingIssue = false);
      ToastUtils.showToast(context, resolveErrorMessage(e, fallback: '提交审阅失败'));
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
                  case 'labels':
                    _editIssueLabels();
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
                  const PopupMenuItem<String>(
                    value: 'labels',
                    child: Text('编辑标签'),
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
                      focusNode: _commentFocusNode,
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
            physics: const AlwaysScrollableScrollPhysics(),
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
                    if (issue.labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in issue.labels)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
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
                                style: context.captionSmallStyle.copyWith(
                                  color: context.appColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (pr != null) ...[
                      const SizedBox(height: 10),
                      GhPrSummaryCard(
                        pr: pr,
                        reviews: _prReviews,
                        isLoggedIn: _userController.isLoggedIn,
                        updatingIssue: _updatingIssue,
                        onMergeTap: _confirmAndMergePr,
                        onReviewTap: _submitPrReview,
                      ),
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

  List<Widget> _buildPrFilesSection(PullRequestDetail? pr) {
    final headRef = pr?.headSha.isNotEmpty == true
        ? pr!.headSha
        : (pr?.headRef ?? '');
    return [
      if (_prFilesError.isNotEmpty && _prFiles.isEmpty)
        GhInlineRetryBanner(message: _prFilesError, onRetry: _reloadPrFiles)
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
            // 分页追加文件时保持 State 与文件名一一对应
            key: ValueKey<String>(file.filename),
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
        GhInlineRetryBanner(
          message: _prFilesMoreError,
          onRetry: _loadMorePrFiles,
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
      if (_prReviewComments.isNotEmpty) ...[
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            '行内代码评审批注 (${_prReviewComments.length})',
            style: context.bodyStrongStyle,
          ),
        ),
        const SizedBox(height: 6),
        for (final rc in _prReviewComments) ...[
          GhPrReviewCommentTile(
            comment: rc,
            owner: widget.owner,
            repoName: widget.repoName,
          ),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }

  List<Widget> _buildCommentsSection() {
    final currentLogin = _userController.isLoggedIn
        ? _userController.user.value.login
        : '';
    return [
      if (_commentsError.isNotEmpty && _comments.isEmpty)
        GhInlineRetryBanner(message: _commentsError, onRetry: _reloadComments)
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
          GhIssueCommentCard(
            comment: comment,
            owner: widget.owner,
            repoName: widget.repoName,
            currentUserLogin: currentLogin,
            onQuoteReply: () => _quoteComment(comment),
            onReact: (code) => _reactComment(comment, code),
            onEdit: () => _editComment(comment),
            onDelete: () => _deleteComment(comment),
          ),
          const SizedBox(height: 10),
        ],
      if (_commentsMoreError.isNotEmpty)
        GhInlineRetryBanner(
          message: _commentsMoreError,
          onRetry: _loadMoreComments,
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

/// 弹窗文本编辑表单（由弹窗 State 托管 TextEditingController，避免退场动画期间提前 dispose）
class _IssueFieldsDialog extends StatefulWidget {
  const _IssueFieldsDialog({
    required this.dialogTitle,
    required this.bodyLabel,
    required this.initialBody,
    required this.bodyMinLines,
    this.titleLabel,
    this.initialTitle = '',
    this.maxTitleLength,
    this.titleEmptyError,
    this.bodyEmptyError,
  });

  final String dialogTitle;
  final String? titleLabel;
  final String initialTitle;
  final int? maxTitleLength;
  final String? titleEmptyError;
  final String bodyLabel;
  final String initialBody;
  final int bodyMinLines;
  final String? bodyEmptyError;

  @override
  State<_IssueFieldsDialog> createState() => _IssueFieldsDialogState();
}

class _IssueFieldsDialogState extends State<_IssueFieldsDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  String _titleError = '';
  String _bodyError = '';

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _bodyCtrl = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.titleLabel != null &&
        widget.titleEmptyError != null &&
        _titleCtrl.text.trim().isEmpty) {
      setState(() => _titleError = widget.titleEmptyError!);
      return;
    }
    if (widget.bodyEmptyError != null && _bodyCtrl.text.trim().isEmpty) {
      setState(() => _bodyError = widget.bodyEmptyError!);
      return;
    }
    Navigator.pop(context, (title: _titleCtrl.text, body: _bodyCtrl.text));
  }

  @override
  Widget build(BuildContext context) {
    final bodyField = TextField(
      controller: _bodyCtrl,
      minLines: widget.bodyMinLines,
      maxLines: 8,
      decoration: InputDecoration(
        labelText: widget.bodyLabel,
        errorText: _bodyError.isEmpty ? null : _bodyError,
      ),
      onChanged: (_) {
        if (_bodyError.isNotEmpty) setState(() => _bodyError = '');
      },
    );

    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: widget.titleLabel == null
          ? bodyField
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    maxLength: widget.maxTitleLength,
                    decoration: InputDecoration(
                      labelText: widget.titleLabel,
                      errorText: _titleError.isEmpty ? null : _titleError,
                    ),
                    onChanged: (_) {
                      if (_titleError.isNotEmpty) {
                        setState(() => _titleError = '');
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  bodyField,
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// PR 审阅意见弹窗（由弹窗 State 托管输入控制器）
class _PrReviewDialog extends StatefulWidget {
  const _PrReviewDialog({required this.number});

  final int number;

  @override
  State<_PrReviewDialog> createState() => _PrReviewDialogState();
}

class _PrReviewDialogState extends State<_PrReviewDialog> {
  final TextEditingController _bodyCtrl = TextEditingController();
  String _event = 'APPROVE';
  String _errText = '';

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('审阅 PR #${widget.number}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _event,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _event = v;
                    _errText = '';
                  });
                }
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'APPROVE',
                    title: Text('批准合并 (Approve)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'COMMENT',
                    title: Text('仅发表审阅意见 (Comment)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'REQUEST_CHANGES',
                    title: Text('请求修改 (Request changes)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            TextField(
              controller: _bodyCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: '审阅说明（选填，请求修改时必填）',
                errorText: _errText.isEmpty ? null : _errText,
              ),
              onChanged: (_) {
                if (_errText.isNotEmpty) setState(() => _errText = '');
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (_event == 'REQUEST_CHANGES' && _bodyCtrl.text.trim().isEmpty) {
              setState(() => _errText = '请求修改时请说明原因');
              return;
            }
            Navigator.pop(context, (event: _event, body: _bodyCtrl.text));
          },
          child: const Text('提交审阅'),
        ),
      ],
    );
  }
}
