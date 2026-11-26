import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 统一的整页 / 模块加载失败视图，带重试按钮
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryText = '重新加载',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryText;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandDark,
              side: const BorderSide(color: AppColors.brandDark),
              shape: const StadiumBorder(),
            ),
            child: Text(retryText),
          ),
        ],
      ),
    );
  }
}
