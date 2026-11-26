import 'package:flutter/material.dart';

/// 全局设计令牌：颜色、圆角、间距及编程语言色板统一在此定义。
///
/// 对齐 hm_shop 的约束：页面与组件不得散落硬编码色值字面量，
/// 统一引用 [AppColors] / [AppRadius] / [AppSpacing]。
class AppColors {
  const AppColors._();

  /// 主色（GitHub 蓝：链接、高亮 tab、主操作强调）
  static const Color primary = Color(0xFF0969DA);

  /// 主色禁用态
  static const Color primaryDisabled = Color(0xFF84B6F4);

  /// 主色极浅底色（标签胶囊、次要操作底色）
  static const Color primarySurface = Color(0xFFDDF4FF);

  /// 深炭黑（GitHub 品牌色：主按钮、标题、图标强调）
  static const Color brandDark = Color(0xFF1F2328);

  /// 个人页头部渐变收尾色
  static const Color headerGradientEnd = Color(0xFFF6F8FA);

  /// 页面背景浅灰（GitHub Canvas Subtle）
  static const Color pageBackground = Color(0xFFF6F8FA);

  /// 卡片背景白
  static const Color cardBackground = Colors.white;

  /// 输入框填充灰
  static const Color inputFill = Color(0xFFF0F2F5);

  /// 头像与图片占位灰
  static const Color imagePlaceholder = Color(0xFFEAECEF);

  /// 主文字色
  static const Color textPrimary = Color(0xFF1F2328);

  /// 次要文字色
  static const Color textSecondary = Color(0xFF656D76);

  /// 分割线与边框色
  static const Color divider = Color(0xFFD0D7DE);

  /// Star 激活金色
  static const Color starActive = Color(0xFFEAC54F);

  /// Star 激活浅底色
  static const Color starSurface = Color(0xFFFFF8C5);

  /// 警示/未读红（角标、错误、关闭状态）
  static const Color badge = Color(0xFFCF222E);

  /// 成功/Open 状态绿
  static const Color success = Color(0xFF1A7F37);

  /// Open 状态浅绿底
  static const Color successSurface = Color(0xFFDAFBE1);

  /// Merged/Closed 紫
  static const Color merged = Color(0xFF8250DF);

  /// Merged 浅紫底
  static const Color mergedSurface = Color(0xFFFBEFFF);

  /// 链接文字色
  static const Color link = Color(0xFF0969DA);

  /// 底部操作栏阴影
  static const Color barShadow = Color(0x14000000);

  /// 代码块浅灰底
  static const Color codeBackground = Color(0xFFF6F8FA);

  /// 首页轮播与专题卡片配色令牌
  static const Color bannerSlateEnd = Color(0xFF32383F);
  static const Color bannerBlueEnd = Color(0xFF0550AE);
  static const Color bannerPurpleEnd = Color(0xFF6639BA);
  static const Color bannerGreenEnd = Color(0xFF116329);

  /// 首页领域入口强调色与浅底色
  static const Color topicTeal = Color(0xFF0E7C7B);
  static const Color topicTealSurface = Color(0xFFE0F7F6);
  static const Color topicOrange = Color(0xFFBC4C00);
  static const Color topicOrangeSurface = Color(0xFFFFF1E5);
  static const Color topicPink = Color(0xFFBF3989);
  static const Color topicPinkSurface = Color(0xFFFFEFF7);

  /// 常见编程语言对应的 GitHub 标准色值
  static const Map<String, Color> _languageColors = {
    'dart': Color(0xFF00B4AB),
    'flutter': Color(0xFF02569B),
    'typescript': Color(0xFF3178C6),
    'javascript': Color(0xFFF1E05A),
    'python': Color(0xFF3572A5),
    'go': Color(0xFF00ADD8),
    'rust': Color(0xFFDEA584),
    'java': Color(0xFFB07219),
    'kotlin': Color(0xFFA97BFF),
    'swift': Color(0xFFF05138),
    'c++': Color(0xFFF34B7D),
    'c': Color(0xFF555555),
    'c#': Color(0xFF178600),
    'html': Color(0xFFE34C26),
    'css': Color(0xFF563D7C),
    'vue': Color(0xFF41B883),
    'shell': Color(0xFF89E051),
    'ruby': Color(0xFF701516),
    'php': Color(0xFF4F5D95),
    'objective-c': Color(0xFF438EFF),
    'jupyter notebook': Color(0xFFDA5B0B),
  };

  /// 根据语言名称返回圆点颜色，未收录的语言回退到次要灰
  static Color languageColor(String language) {
    final key = language.trim().toLowerCase();
    return _languageColors[key] ?? textSecondary;
  }
}

/// 统一圆角
class AppRadius {
  const AppRadius._();

  static const double small = 6;
  static const double image = 8;
  static const double card = 12;
  static const double pill = 28;
  static const double toast = 40;
}

/// 统一间距
class AppSpacing {
  const AppSpacing._();

  static const double small = 6;
  static const double module = 12;
  static const double page = 12;
  static const double large = 20;
}
