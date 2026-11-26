import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 「我的」页面设置入口卡片，跳转外观主题色与首页标签展示等个性化设置
class GhMineSettingsCard extends StatelessWidget {
  const GhMineSettingsCard({
    super.key,
    required this.tagCount,
    this.themeLabel = '跟随系统',
    required this.onTap,
  });

  final int tagCount;
  final String themeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: Semantics(
        button: true,
        label: '设置',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.appColors.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: context.appColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('设置', style: context.bodyStrongStyle),
                        const SizedBox(height: 2),
                        Text(
                          '外观主题（$themeLabel）与首页顶部标签展示设置',
                          style: context.captionSmallStyle,
                        ),
                      ],
                    ),
                  ),
                  Text('已选 $tagCount 项', style: context.captionStyle),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: context.appColors.textSecondary,
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
