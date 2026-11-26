import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';

/// 分页列表底部状态条
class HmListFooter extends StatelessWidget {
  const HmListFooter({
    super.key,
    required this.loadingMore,
    required this.hasMore,
    this.noMoreText = '没有更多了',
  });

  final bool loadingMore;
  final bool hasMore;
  final String noMoreText;

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
    if (hasMore) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(child: Text(noMoreText, style: context.captionStyle)),
    );
  }
}
