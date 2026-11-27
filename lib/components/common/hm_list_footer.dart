import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';

/// 分页列表底部状态条
///
/// 支持「加载中 / 加载失败可重试 / 还有更多 / 没有更多」四种状态。
/// 加载更多失败时不自动重试，由用户点击重试按钮触发，避免滚动反复打接口。
class HmListFooter extends StatelessWidget {
  const HmListFooter({
    super.key,
    required this.loadingMore,
    required this.hasMore,
    this.failed = false,
    this.onRetry,
    this.noMoreText = '没有更多了',
    this.retryText = '加载失败，点击重试',
  });

  final bool loadingMore;
  final bool hasMore;
  final bool failed;
  final VoidCallback? onRetry;
  final String noMoreText;
  final String retryText;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(retryText, style: context.captionStyle),
          ),
        ),
      );
    }
    if (hasMore) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(child: Text(noMoreText, style: context.captionStyle)),
    );
  }
}
