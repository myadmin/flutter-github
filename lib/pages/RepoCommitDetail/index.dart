import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/components/Repo/gh_diff_patch_view.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/external_link.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// Commit 详情页：展示完整提交信息、作者、父节点及逐文件 Diff 对比
class RepoCommitDetailPage extends StatefulWidget {
  const RepoCommitDetailPage({
    super.key,
    required this.owner,
    required this.repoName,
    required this.sha,
  });

  final String owner;
  final String repoName;
  final String sha;

  @override
  State<RepoCommitDetailPage> createState() => _RepoCommitDetailPageState();
}

class _RepoCommitDetailPageState extends State<RepoCommitDetailPage> {
  CommitDetail? _detail;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _expandAll = true;
  int _loadSeq = 0;
  CancelToken? _loadToken;

  bool get _hasValidArgs =>
      widget.owner.trim().isNotEmpty &&
      widget.repoName.trim().isNotEmpty &&
      widget.sha.trim().isNotEmpty;

  String get _shortSha =>
      widget.sha.length > 7 ? widget.sha.substring(0, 7) : widget.sha;

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
    _loadToken?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    _loadToken?.cancel();
    final token = CancelToken();
    _loadToken = token;
    setState(() {
      _isLoading = _detail == null;
      _errorMessage = '';
    });
    try {
      final detail = await getRepoCommitDetailAPI(
        widget.owner,
        widget.repoName,
        widget.sha,
        cancelToken: token,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _detail = detail;
        _expandAll = detail.files.length <= 15;
        _isLoading = false;
      });
    } catch (e) {
      if (e is RequestCancelledException || !mounted || seq != _loadSeq) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '加载提交详情失败');
      });
    }
  }

  Future<void> _copySha() async {
    await Clipboard.setData(ClipboardData(text: widget.sha));
    if (!mounted) return;
    ToastUtils.showToast(context, '已复制 SHA: $_shortSha');
  }

  Future<void> _openInBrowser(String url) async {
    final opened = await openExternalUrl(url);
    if (!opened && mounted) {
      ToastUtils.showToast(context, '无法在浏览器中打开');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(_hasValidArgs ? _shortSha : '提交详情'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_hasValidArgs)
            IconButton(
              onPressed: _copySha,
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制 SHA',
            ),
          if (_detail != null && _detail!.commit.htmlUrl.isNotEmpty)
            IconButton(
              onPressed: () => _openInBrowser(_detail!.commit.htmlUrl),
              icon: const Icon(Icons.open_in_new, size: 19),
              tooltip: '在 GitHub 打开',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasValidArgs) {
      return const HmEmptyView(icon: Icons.commit, title: '提交参数缺失');
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _detail == null) {
      return AppErrorView(message: _errorMessage, onRetry: _load);
    }
    final detail = _detail!;
    final commit = detail.commit;
    final messageLines = commit.message.replaceAll('\r\n', '\n').split('\n');
    final bodyMessage = messageLines.length > 1
        ? messageLines.skip(1).join('\n').trim()
        : '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: HmBottomBar.maxContentWidth,
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          // 用 CustomScrollView + SliverList 替代 ListView(children:)：
          // 一次提交可能改动上百个文件，非懒加载会在首帧构建全部 diff 卡片。
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverList.list(
                  children: [
                    _buildSummaryCard(detail, bodyMessage),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '变更文件 (${detail.files.length})',
                            style: context.bodyStrongStyle,
                          ),
                        ),
                        if (detail.files.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _expandAll = !_expandAll),
                            icon: Icon(
                              _expandAll
                                  ? Icons.unfold_less
                                  : Icons.unfold_more,
                              size: 16,
                            ),
                            label: Text(_expandAll ? '全部收起' : '全部展开'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (detail.files.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.appColors.cardBackground,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Center(
                          child: Text('无文件改动明细', style: context.captionStyle),
                        ),
                      ),
                  ],
                ),
              ),
              if (detail.files.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverList.separated(
                    itemCount: detail.files.length,
                    itemBuilder: (context, index) {
                      final file = detail.files[index];
                      return GhDiffFileCard(
                        // 用文件名做 key，避免列表变化时 State 被复用导致折叠/展开状态串台
                        key: ValueKey<String>(file.filename),
                        file: file,
                        initiallyExpanded: _expandAll,
                        onViewFile: () => Navigator.pushNamed(
                          context,
                          AppRoutes.repoFileView(
                            widget.owner,
                            widget.repoName,
                            path: file.filename,
                            ref: commit.sha,
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(CommitDetail detail, String bodyMessage) {
    final colors = context.appColors;
    final commit = detail.commit;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(commit.titleLine, style: context.sectionTitleStyle),
          if (bodyMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(bodyMessage, style: context.bodySmallStyle),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              InkWell(
                onTap: commit.authorLogin.isEmpty
                    ? null
                    : () => Navigator.pushNamed(
                        context,
                        AppRoutes.userDetail(commit.authorLogin),
                      ),
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppNetworkImage(
                      url: commit.authorAvatar,
                      width: 24,
                      height: 24,
                      decodeWidth: 24,
                      placeholderIconSize: 14,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 8),
                    Text(commit.displayAuthor, style: context.bodyStrongStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatRelativeTime(commit.committedAt),
                  style: context.captionStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatBadge(
                label: '+${detail.stats.additions}',
                color: colors.success,
                surface: colors.successSurface,
              ),
              _StatBadge(
                label: '-${detail.stats.deletions}',
                color: colors.badge,
                surface: colors.badge.withValues(alpha: 0.12),
              ),
              for (final parentSha in detail.parents)
                InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.repoCommitDetail(
                      widget.owner,
                      widget.repoName,
                      parentSha,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      '父提交 ${parentSha.length > 7 ? parentSha.substring(0, 7) : parentSha}',
                      style: context.monoSmallStyle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: context.captionSmallStyle.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
