import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 全库复用的文字样式
abstract final class AppTextStyles {
  /// 次要说明文字（12 号）
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  /// 更小的说明文字（11 号）
  static const TextStyle captionSmall = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  /// 角标/标签小字（10 号）
  static const TextStyle label = TextStyle(
    fontSize: 10,
    color: AppColors.textSecondary,
  );

  /// 正文（14 号）
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );

  /// 正文强调（14 号、半粗）
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// 小号正文（12 号）
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    color: AppColors.textPrimary,
  );

  /// 卡片/列表标题（15 号、半粗、1.35 行高）
  static const TextStyle tileTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  /// 页面大标题（20 号、特粗）
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 分区标题（16 号、加粗）
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  /// 代码/SHA 等宽正文字体
  static const TextStyle mono = TextStyle(
    fontSize: 13,
    fontFamily: 'monospace',
    color: AppColors.textPrimary,
  );

  /// 代码/SHA 等宽小号字体
  static const TextStyle monoSmall = TextStyle(
    fontSize: 11,
    fontFamily: 'monospace',
    color: AppColors.textSecondary,
  );
}
