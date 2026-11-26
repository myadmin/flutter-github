import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/api/star.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_language_dot.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/components/common/gh_star_button.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// 仓库详情页：概览信息、Star 互动、代码/Issue/Commit 入口与 README 渲染
class RepoDetailPage extends StatefulWidget {
  const RepoDetailPage({
    super.key,
    required this.owner,
    required this.repoName,
  });

  final String owner;
  final String repoName;

  @override
  State<RepoDetailPage> createState() => _RepoDetailPageState();
}

class _RepoDetailPageState extends State<RepoDetailPage> {
  final UserController _userController = Get.find<UserController>();
  final StarSyncController _starSync = Get.find<StarSyncController>();

  RepoItem? _repo;
  String _readme = '';
  bool _isStarred = false;
  bool _isLoading = true;
  String _errorMessage = '';

  late final Worker _userWatcher;

  bool get _hasValidArgs =>
      widget.owner.trim().isNotEmpty && widget.repoName.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _userWatcher = ever(_userController.user, (_) {
      if (!mounted || !_hasValidArgs) return;
      _refreshStarStateOnly();
    });
    if (_hasValidArgs) {
      _load();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _userWatcher.dispose();
    super.dispose();
  }

  /// 登录态变化时仅增量刷新当前仓库的 Star 状态
  Future<void> _refreshStarStateOnly() async {
    if (!_userController.isLoggedIn) {
      if (mounted) setState(() => _isStarred = false);
      return;
    }
    try {
      final starred = await checkRepoStarredAPI(widget.owner, widget.repoName);
      if (!mounted) return;
      setState(() => _isStarred = starred);
      final repo = _repo;
      if (repo != null) {
        _starSync.setSnapshot(
          repo.fullName,
          isStarred: starred,
          starCount: repo.stargazersCount,
        );
      }
    } catch (_) {}
  }

  /// 并发拉取仓库元数据、README 与 Star 状态，并在成功后写入本地足迹
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _repo == null;
      _errorMessage = '';
    });

    try {
      final detailFuture = getRepoDetailAPI(widget.owner, widget.repoName);
      // README 与 Star 检查失败不影响仓库主信息展示
      final readmeFuture = getRepoReadmeRawAPI(
        widget.owner,
        widget.repoName,
      ).catchError((Object _) => '');
      final starFuture = _userController.isLoggedIn
          ? checkRepoStarredAPI(
              widget.owner,
              widget.repoName,
            ).catchError((Object _) => false)
          : Future<bool>.value(false);

      final (repo, readme, starred) = await (
        detailFuture,
        readmeFuture,
        starFuture,
      ).wait;

      if (!mounted) return;
      _starSync.setSnapshot(
        repo.fullName,
        isStarred: starred,
        starCount: repo.stargazersCount,
      );
      // 异步写入本地浏览足迹，不阻塞首屏渲染
      unawaited(FootprintStore.record(FootprintItem.fromRepo(repo)));
      setState(() {
        _repo = repo;
        _readme = readme;
        _isStarred = starred;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '仓库信息加载失败');
      });
    }
  }

  /// 使用外部浏览器打开 GitHub 仓库或项目主页链接
  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ToastUtils.showToast(context, '无法在浏览器中打开');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _hasValidArgs ? '${widget.owner}/${widget.repoName}' : '项目详情';
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (_repo != null && _repo!.htmlUrl.isNotEmpty)
            IconButton(
              onPressed: () => _openInBrowser(_repo!.htmlUrl),
              icon: const Icon(Icons.open_in_new),
              tooltip: '在 GitHub 打开',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasValidArgs) {
      return const HmEmptyView(
        icon: Icons.folder_off_outlined,
        title: '项目信息缺失',
        description: '缺少仓库所属者或仓库名称，请返回重试',
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _repo == null) {
      return AppErrorView(message: _errorMessage, onRetry: _load);
    }
    final repo = _repo!;
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
              _buildOverviewCard(repo),
              const SizedBox(height: 12),
              _buildNavigationCard(repo),
              const SizedBox(height: 12),
              _buildReadmeCard(repo),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(RepoItem repo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.userDetail(repo.ownerLogin),
                ),
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppNetworkImage(
                      url: repo.owner.avatarUrl,
                      width: 32,
                      height: 32,
                      decodeWidth: 32,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      repo.ownerLogin,
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(' / ', style: AppTextStyles.body),
              Expanded(
                child: Text(
                  repo.repoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoChip(
                label: repo.isPrivate ? 'Private' : 'Public',
                icon: repo.isPrivate ? Icons.lock_outline : Icons.public,
              ),
              if (repo.isArchived)
                const _InfoChip(
                  label: 'Archived',
                  icon: Icons.inventory_2_outlined,
                ),
              if (repo.isFork && repo.parentFullName.isNotEmpty)
                _InfoChip(
                  label: 'Forked from ${repo.parentFullName}',
                  icon: Icons.call_split,
                ),
              if (repo.license != null && !repo.license!.isEmpty)
                _InfoChip(
                  label: repo.license!.displayName,
                  icon: Icons.balance,
                ),
              _InfoChip(label: repo.defaultBranch, icon: Icons.alt_route),
            ],
          ),
          if (repo.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              repo.description,
              style: AppTextStyles.body.copyWith(height: 1.5),
            ),
          ],
          if (repo.topics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final topic in repo.topics.take(10))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      topic,
                      style: AppTextStyles.captionSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (repo.language.isNotEmpty)
                GhLanguageDot(language: repo.language),
              _MetricText(
                icon: Icons.call_split,
                label: 'Fork ${formatCompactNumber(repo.forksCount)}',
              ),
              _MetricText(
                icon: Icons.visibility_outlined,
                label: 'Watch ${formatCompactNumber(repo.watchCount)}',
              ),
              if (repo.pushedAt != null)
                Text(
                  '最近提交 ${formatRelativeTime(repo.pushedAt)}',
                  style: AppTextStyles.captionSmall,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GhStarButton(
                owner: repo.ownerLogin,
                repoName: repo.repoName,
                initialCount: repo.stargazersCount,
                initialStarred: _isStarred,
                onToggled: (starred) {
                  if (mounted) setState(() => _isStarred = starred);
                },
              ),
              if (repo.homepage.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openInBrowser(repo.homepage),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('项目主页', maxLines: 1),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(RepoItem repo) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            _NavRow(
              icon: Icons.code,
              title: '浏览代码文件',
              trailingText: repo.defaultBranch,
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.repoFiles(
                  repo.ownerLogin,
                  repo.repoName,
                  ref: repo.defaultBranch,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            _NavRow(
              icon: Icons.adjust,
              title: 'Issues 与 Pull Requests',
              trailingText: '${repo.openIssuesCount} 个未关闭',
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.repoIssues(repo.ownerLogin, repo.repoName),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            _NavRow(
              icon: Icons.commit,
              title: '提交历史 (Commits)',
              trailingText: repo.defaultBranch,
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.repoCommits(
                  repo.ownerLogin,
                  repo.repoName,
                  branch: repo.defaultBranch,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadmeCard(RepoItem repo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18),
              SizedBox(width: 6),
              Text('README.md', style: AppTextStyles.sectionTitle),
            ],
          ),
          const Divider(height: 20, color: AppColors.divider),
          if (_readme.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('该项目暂无 README 文档', style: AppTextStyles.caption),
              ),
            )
          else
            GhMarkdownView(
              data: _readme,
              owner: repo.ownerLogin,
              repo: repo.repoName,
              branch: repo.defaultBranch,
            ),
        ],
      ),
    );
  }
}

/// 仓库属性小标签（Public / Private / License / 默认分支等）
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.captionSmall),
        ],
      ),
    );
  }
}

/// 仓库统计文本项（Fork / Watch）
class _MetricText extends StatelessWidget {
  const _MetricText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// 详情页导航入口行（代码文件 / Issues / 提交历史）
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppColors.brandDark),
      title: Text(title, style: AppTextStyles.bodyStrong),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(trailingText, style: AppTextStyles.caption),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
      onTap: onTap,
    );
  }
}
