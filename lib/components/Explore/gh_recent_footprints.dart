import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/gh_language_dot.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/utils/formatters.dart';

/// 探索首页「继续浏览」横滑足迹栏（读取本机 FootprintStore，不消耗 GitHub API 配额）
class GhRecentFootprints extends StatelessWidget {
  const GhRecentFootprints({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onViewAllTap,
  });

  final List<FootprintItem> items;
  final ValueChanged<FootprintItem> onItemTap;
  final VoidCallback onViewAllTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final preview = items.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 17, color: context.appColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('继续浏览', style: context.bodyStrongStyle)),
            InkWell(
              onTap: onViewAllTap,
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '全部足迹',
                      style: context.captionStyle.copyWith(
                        color: context.appColors.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: context.appColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = preview[index];
              return _CompactFootprintCard(
                item: item,
                onTap: () => onItemTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactFootprintCard extends StatelessWidget {
  const _CompactFootprintCard({required this.item, required this.onTap});

  final FootprintItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Material(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: context.appColors.divider.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodyStrongStyle.copyWith(
                    fontSize: 13,
                    color: context.appColors.primary,
                  ),
                ),
                Text(
                  item.description.isEmpty ? '点击继续查看详情' : item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.captionSmallStyle,
                ),
                Row(
                  children: [
                    if (item.language.isNotEmpty) ...[
                      Expanded(child: GhLanguageDot(language: item.language)),
                    ] else
                      const Spacer(),
                    Icon(
                      Icons.star_border,
                      size: 13,
                      color: context.appColors.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      formatCompactNumber(item.stargazersCount),
                      style: context.captionSmallStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
