import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 「我的」页面快捷功能入口（我的仓库 / 我的 Star / 通知中心 / 浏览足迹）
class GhMineQuickActions extends StatelessWidget {
  const GhMineQuickActions({
    super.key,
    required this.onMyReposTap,
    required this.onMyStarsTap,
    required this.onNotificationsTap,
    required this.onFootprintTap,
  });

  final VoidCallback onMyReposTap;
  final VoidCallback onMyStarsTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onFootprintTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.folder_copy_outlined,
              color: context.appColors.primary,
              label: '我的仓库',
              onTap: onMyReposTap,
            ),
          ),
          Expanded(
            child: _ActionTile(
              icon: Icons.star_outline,
              color: context.appColors.starActive,
              label: '我的 Star',
              onTap: onMyStarsTap,
            ),
          ),
          Expanded(
            child: _ActionTile(
              icon: Icons.notifications_none,
              color: context.appColors.merged,
              label: '消息通知',
              onTap: onNotificationsTap,
            ),
          ),
          Expanded(
            child: _ActionTile(
              icon: Icons.history,
              color: context.appColors.success,
              label: '浏览足迹',
              onTap: onFootprintTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(label, style: context.bodySmallStyle),
            ],
          ),
        ),
      ),
    );
  }
}
