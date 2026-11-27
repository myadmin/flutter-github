import 'package:flutter/material.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/components/common/hm_list_footer.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/app_release.dart';
import 'package:gh_explorer/utils/external_link.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/paged_list.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库 Releases 发布版本与附件列表页
class RepoReleasesPage extends StatefulWidget {
  const RepoReleasesPage({
    super.key,
    required this.owner,
    required this.repoName,
  });

  final String owner;
  final String repoName;

  @override
  State<RepoReleasesPage> createState() => _RepoReleasesPageState();
}

class _RepoReleasesPageState extends State<RepoReleasesPage> {
  final ScrollController _scrollController = ScrollController();

  late final PagedListController<AppRelease> _list =
      PagedListController<AppRelease>(
        pageSize: GlobalConstants.defaultPageSize,
        loader: (page) => getRepoReleasesAPI(
          widget.owner,
          widget.repoName,
          page: page,
          cancelToken: _list.cancelToken,
        ),
        firstPageErrorFallback: '加载 Releases 失败',
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
    _list.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _list.loadMore();
    }
  }

  Future<void> _openUrl(String url) async {
    final opened = await openExternalUrl(url);
    if (!opened && mounted) {
      ToastUtils.showToast(context, '无法在浏览器中打开');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text('Releases 版本'),
        centerTitle: true,
        backgroundColor: colors.pageBackground,
        foregroundColor: colors.textPrimary,
        elevation: 0,
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
    if (!_hasValidArgs) {
      return const HmEmptyView(
        icon: Icons.new_releases_outlined,
        title: '仓库信息缺失',
      );
    }
    if (_list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.errorMessage.isNotEmpty && _list.isEmpty) {
      return AppErrorView(message: _list.errorMessage, onRetry: _list.refresh);
    }
    if (_list.isEmpty) {
      return const HmEmptyView(
        icon: Icons.new_releases_outlined,
        title: '暂无 Release 发布记录',
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
              noMoreText: '已展示全部版本',
            );
          }
          final rel = _list[index];
          return _ReleaseCard(
            release: rel,
            owner: widget.owner,
            repoName: widget.repoName,
            onOpenUrl: _openUrl,
          );
        },
      ),
    );
  }
}

class _ReleaseCard extends StatefulWidget {
  const _ReleaseCard({
    required this.release,
    required this.owner,
    required this.repoName,
    required this.onOpenUrl,
  });

  final AppRelease release;
  final String owner;
  final String repoName;
  final ValueChanged<String> onOpenUrl;

  @override
  State<_ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<_ReleaseCard> {
  bool _showAssets = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rel = widget.release;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(rel.displayTitle, style: context.sectionTitleStyle),
              ),
              if (rel.htmlUrl.isNotEmpty)
                IconButton(
                  onPressed: () => widget.onOpenUrl(rel.htmlUrl),
                  icon: Icon(
                    Icons.open_in_new,
                    size: 17,
                    color: colors.textSecondary,
                  ),
                  tooltip: '在 GitHub 打开',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  rel.tagName,
                  style: context.monoSmallStyle.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (rel.prerelease)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.starSurface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Pre-release',
                    style: context.captionSmallStyle.copyWith(
                      color: colors.brandDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (rel.publishedAt != null)
                Text(
                  '发布于 ${formatRelativeTime(rel.publishedAt)}',
                  style: context.captionSmallStyle,
                ),
            ],
          ),
          if (rel.notes.trim().isNotEmpty) ...[
            Divider(height: 18, color: colors.divider),
            GhMarkdownView(
              data: rel.notes,
              owner: widget.owner,
              repo: widget.repoName,
            ),
          ],
          if (rel.assets.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _showAssets = !_showAssets),
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '构建产物 (${rel.assets.length})',
                        style: context.bodySmallStyle.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _showAssets ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_showAssets) ...[
              const SizedBox(height: 6),
              for (final asset in rel.assets)
                InkWell(
                  onTap: asset.downloadUrl.isEmpty
                      ? null
                      : () => widget.onOpenUrl(asset.downloadUrl),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.download_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            asset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.monoSmallStyle.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (asset.sizeText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            asset.sizeText,
                            style: context.captionSmallStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
