import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_language_dot.dart';
import 'package:gh_explorer/components/common/gh_star_button.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/utils/formatters.dart';

/// 通用仓库列表卡片（探索、搜索、我的仓库、我的 Star、用户详情共用）
class GhRepoCard extends StatelessWidget {
  const GhRepoCard({
    super.key,
    required this.repo,
    this.onTap,
    this.showStarButton = true,
    this.initialStarred = false,
    this.onStarToggled,
  });

  final RepoItem repo;
  final VoidCallback? onTap;
  final bool showStarButton;
  final bool initialStarred;
  final ValueChanged<bool>? onStarToggled;

  @override
  Widget build(BuildContext context) {
    final starSync = Get.isRegistered<StarSyncController>()
        ? Get.find<StarSyncController>()
        : null;

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: Material(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.divider.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppNetworkImage(
                        url: repo.owner.avatarUrl,
                        width: 24,
                        height: 24,
                        decodeWidth: 24,
                        placeholderIconSize: 16,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          repo.fullName.isNotEmpty
                              ? repo.fullName
                              : '${repo.ownerLogin}/${repo.repoName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.tileTitle.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (repo.isPrivate) ...[
                        const SizedBox(width: 6),
                        const _BadgePill(
                          label: 'Private',
                          color: AppColors.textSecondary,
                          bgColor: AppColors.inputFill,
                        ),
                      ] else if (repo.isFork) ...[
                        const SizedBox(width: 6),
                        const _BadgePill(
                          label: 'Fork',
                          color: AppColors.textSecondary,
                          bgColor: AppColors.inputFill,
                        ),
                      ],
                      if (showStarButton &&
                          repo.ownerLogin.isNotEmpty &&
                          repo.repoName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        GhStarButton(
                          owner: repo.ownerLogin,
                          repoName: repo.repoName,
                          initialCount: repo.stargazersCount,
                          initialStarred: initialStarred,
                          compact: true,
                          onToggled: onStarToggled,
                        ),
                      ],
                    ],
                  ),
                  if (repo.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      repo.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (repo.language.isNotEmpty)
                        GhLanguageDot(language: repo.language),
                      if (!showStarButton)
                        _StatItem(
                          icon: Icons.star_border,
                          text: starSync == null
                              ? formatCompactNumber(repo.stargazersCount)
                              : '',
                          starSync: starSync,
                          repo: repo,
                        ),
                      _StatItem(
                        icon: Icons.call_split,
                        text: formatCompactNumber(repo.forksCount),
                      ),
                      if (repo.updatedAt != null)
                        Text(
                          '更新于 ${formatRelativeTime(repo.updatedAt)}',
                          style: AppTextStyles.captionSmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仓库属性胶囊标签（如 Private / Fork）
class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(label, style: AppTextStyles.label.copyWith(color: color)),
    );
  }
}

/// 仓库底部统计指标项（支持订阅 StarSyncController 实时更新 Star 计数）
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.text,
    this.starSync,
    this.repo,
  });

  final IconData icon;
  final String text;
  final StarSyncController? starSync;
  final RepoItem? repo;

  @override
  Widget build(BuildContext context) {
    if (starSync != null && repo != null) {
      return Obx(() {
        final snapshot = starSync!.snapshotOf(repo!.fullName);
        final count = snapshot?.starCount ?? repo!.stargazersCount;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(formatCompactNumber(count), style: AppTextStyles.caption),
          ],
        );
      });
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: AppTextStyles.caption),
      ],
    );
  }
}
