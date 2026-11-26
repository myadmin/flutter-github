import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/explore_config.dart';

/// 探索首页热门技术领域横滑快捷入口（参考 hm_shop HmCategory 横滑分类条，0 API 请求开销）
class GhTopicGrid extends StatelessWidget {
  const GhTopicGrid({
    super.key,
    required this.topics,
    required this.onTopicTap,
  });

  final List<ExploreTopicEntry> topics;
  final ValueChanged<ExploreTopicEntry> onTopicTap;

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: topics.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = topics[index];
          return SizedBox(
            width: 68,
            child: _TopicTile(entry: item, onTap: () => onTopicTap(item)),
          );
        },
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.entry, required this.onTap});

  final ExploreTopicEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.appColors.isDark;
    final baseColor = (isDark && entry.color == AppColors.brandDark)
        ? context.appColors.brandDark
        : entry.color;
    final tileSurface = isDark
        ? baseColor.withValues(alpha: 0.18)
        : entry.surfaceColor;
    final tileIconColor = isDark
        ? (Color.lerp(baseColor, context.appColors.cardBackground, 0.25) ??
              baseColor)
        : baseColor;

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: entry.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tileSurface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(entry.icon, size: 20, color: tileIconColor),
                ),
                const SizedBox(height: 5),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.captionSmallStyle.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
