import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/utils/formatters.dart';

/// 公共内联错误提示 + 重试卡片（用于评论/PR 变更文件加载与分页失败恢复）
class GhInlineRetryBanner extends StatelessWidget {
  const GhInlineRetryBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Expanded(child: Text(message, style: context.captionStyle)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// Pull Request 概要状态卡片：分支流向、变更统计、审阅结论徽章与 Merge / Review 入口
class GhPrSummaryCard extends StatelessWidget {
  const GhPrSummaryCard({
    super.key,
    required this.pr,
    required this.reviews,
    required this.isLoggedIn,
    required this.updatingIssue,
    required this.onMergeTap,
    required this.onReviewTap,
  });

  final PullRequestDetail pr;
  final List<PullRequestReview> reviews;
  final bool isLoggedIn;
  final bool updatingIssue;
  final VoidCallback onMergeTap;
  final VoidCallback onReviewTap;

  (Color, Color) _reviewTone(BuildContext context, String state) {
    final c = context.appColors;
    switch (state.toUpperCase()) {
      case 'APPROVED':
        return (c.success, c.successSurface);
      case 'CHANGES_REQUESTED':
        return (c.badge, c.badge.withValues(alpha: 0.12));
      default:
        return (c.primary, c.primarySurface);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 对每位审阅者仅保留最新一条非空审阅结论
    final latestByUser = <String, PullRequestReview>{};
    for (final review in reviews) {
      if (review.user.login.isNotEmpty) {
        latestByUser[review.user.login] = review;
      }
    }

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
          if (latestByUser.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final review in latestByUser.values)
                  Builder(
                    builder: (context) {
                      final (fg, bg) = _reviewTone(context, review.state);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '${review.user.login}: ${review.stateLabel}',
                          style: context.captionSmallStyle.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
          if (isLoggedIn && pr.isOpen && !pr.merged) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!pr.draft)
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      // mergeable == false 表示与基线冲突，直接合并必然失败，先置灰
                      onPressed: (updatingIssue || pr.mergeable == false)
                          ? null
                          : onMergeTap,
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
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: updatingIssue ? null : onReviewTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.rate_review_outlined, size: 15),
                    label: const Text('提交审查', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
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
}

/// PR 行内代码审阅评论卡片（展示文件路径、行号、Diff 上下文片段与审阅正文）
class GhPrReviewCommentTile extends StatelessWidget {
  const GhPrReviewCommentTile({
    super.key,
    required this.comment,
    required this.owner,
    required this.repoName,
  });

  final PullRequestReviewComment comment;
  final String owner;
  final String repoName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hunkLines = comment.diffHunk
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    final previewHunk = hunkLines.length > 4
        ? hunkLines.sublist(hunkLines.length - 4).join('\n')
        : hunkLines.join('\n');

    return Container(
      padding: const EdgeInsets.all(12),
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
              AppNetworkImage(
                url: comment.user.avatarUrl,
                width: 22,
                height: 22,
                decodeWidth: 22,
                borderRadius: BorderRadius.circular(11),
              ),
              const SizedBox(width: 6),
              Text(comment.user.login, style: context.bodyStrongStyle),
              const Spacer(),
              Text(
                formatRelativeTime(comment.createdAt),
                style: context.captionSmallStyle,
              ),
            ],
          ),
          if (comment.path.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment.line > 0
                  ? '${comment.path}:${comment.line}'
                  : comment.path,
              style: context.monoSmallStyle.copyWith(color: colors.primary),
            ),
          ],
          if (previewHunk.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.codeBackground,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(
                previewHunk,
                style: context.monoSmallStyle.copyWith(fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 8),
          GhMarkdownView(data: comment.body, owner: owner, repo: repoName),
        ],
      ),
    );
  }
}
