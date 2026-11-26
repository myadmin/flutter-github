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

/// 代码编辑器明/暗双主题语义配色令牌（基于 GitHub Dark / Light 语法规范）
class EditorPalette {
  const EditorPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.border,
    required this.activeLineBackground,
    required this.gutterBackground,
    required this.gutterText,
    required this.gutterActiveText,
    required this.toolbarText,
    required this.toolbarMuted,
    required this.chipBackground,
    required this.chipActiveBackground,
    required this.chipActiveText,
    required this.scrollbarThumb,
    required this.plain,
    required this.keyword,
    required this.stringLiteral,
    required this.comment,
    required this.number,
    required this.typeName,
    required this.functionCall,
    required this.annotation,
    required this.punctuation,
    required this.matchBackground,
    required this.activeMatchBackground,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color border;
  final Color activeLineBackground;
  final Color gutterBackground;
  final Color gutterText;
  final Color gutterActiveText;
  final Color toolbarText;
  final Color toolbarMuted;
  final Color chipBackground;
  final Color chipActiveBackground;
  final Color chipActiveText;
  final Color scrollbarThumb;
  final Color plain;
  final Color keyword;
  final Color stringLiteral;
  final Color comment;
  final Color number;
  final Color typeName;
  final Color functionCall;
  final Color annotation;
  final Color punctuation;
  final Color matchBackground;
  final Color activeMatchBackground;

  /// GitHub Dark 默认深色编辑器主题
  static const EditorPalette dark = EditorPalette(
    isDark: true,
    background: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    border: Color(0xFF30363D),
    activeLineBackground: Color(0xFF1C2330),
    gutterBackground: Color(0xFF0D1117),
    gutterText: Color(0xFF6E7681),
    gutterActiveText: Color(0xFFE6EDF3),
    toolbarText: Color(0xFFE6EDF3),
    toolbarMuted: Color(0xFF8B949E),
    chipBackground: Color(0xFF21262D),
    chipActiveBackground: Color(0xFF1F6FEB),
    chipActiveText: Color(0xFFFFFFFF),
    scrollbarThumb: Color(0xFF484F58),
    plain: Color(0xFFE6EDF3),
    keyword: Color(0xFFFF7B72),
    stringLiteral: Color(0xFFA5D6FF),
    comment: Color(0xFF8B949E),
    number: Color(0xFF79C0FF),
    typeName: Color(0xFFFFA657),
    functionCall: Color(0xFFD2A8FF),
    annotation: Color(0xFFFFA657),
    punctuation: Color(0xFF9EA7B3),
    matchBackground: Color(0xFF634800),
    activeMatchBackground: Color(0xFFBB8009),
  );

  /// GitHub Light 默认浅色编辑器主题
  static const EditorPalette light = EditorPalette(
    isDark: false,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F8FA),
    border: Color(0xFFD0D7DE),
    activeLineBackground: Color(0xFFF0F6FC),
    gutterBackground: Color(0xFFFAFBFC),
    gutterText: Color(0xFF8C959F),
    gutterActiveText: Color(0xFF1F2328),
    toolbarText: Color(0xFF1F2328),
    toolbarMuted: Color(0xFF57606A),
    chipBackground: Color(0xFFEAEFF4),
    chipActiveBackground: Color(0xFF0969DA),
    chipActiveText: Color(0xFFFFFFFF),
    scrollbarThumb: Color(0xFF8C959F),
    plain: Color(0xFF1F2328),
    keyword: Color(0xFFCF222E),
    stringLiteral: Color(0xFF0A3069),
    comment: Color(0xFF6E7781),
    number: Color(0xFF0550AE),
    typeName: Color(0xFF953800),
    functionCall: Color(0xFF8250DF),
    annotation: Color(0xFF953800),
    punctuation: Color(0xFF57606A),
    matchBackground: Color(0xFFFFF8C5),
    activeMatchBackground: Color(0xFFFFD33D),
  );
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

/// 应用全局动态明/暗双主题语义色板（通过 `ThemeExtension` 下发并在运行时切换）
class AppThemePalette extends ThemeExtension<AppThemePalette> {
  const AppThemePalette({
    required this.isDark,
    required this.primary,
    required this.primaryDisabled,
    required this.primarySurface,
    required this.brandDark,
    required this.brandButtonBg,
    required this.brandButtonFg,
    required this.headerGradientEnd,
    required this.pageBackground,
    required this.cardBackground,
    required this.inputFill,
    required this.imagePlaceholder,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.starActive,
    required this.starSurface,
    required this.badge,
    required this.success,
    required this.successSurface,
    required this.merged,
    required this.mergedSurface,
    required this.link,
    required this.barShadow,
    required this.codeBackground,
  });

  final bool isDark;
  final Color primary;
  final Color primaryDisabled;
  final Color primarySurface;
  final Color brandDark;
  final Color brandButtonBg;
  final Color brandButtonFg;
  final Color headerGradientEnd;
  final Color pageBackground;
  final Color cardBackground;
  final Color inputFill;
  final Color imagePlaceholder;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color starActive;
  final Color starSurface;
  final Color badge;
  final Color success;
  final Color successSurface;
  final Color merged;
  final Color mergedSurface;
  final Color link;
  final Color barShadow;
  final Color codeBackground;

  /// GitHub 浅色主题默认色板
  static const AppThemePalette light = AppThemePalette(
    isDark: false,
    primary: AppColors.primary,
    primaryDisabled: AppColors.primaryDisabled,
    primarySurface: AppColors.primarySurface,
    brandDark: AppColors.brandDark,
    brandButtonBg: AppColors.brandDark,
    brandButtonFg: Colors.white,
    headerGradientEnd: AppColors.headerGradientEnd,
    pageBackground: AppColors.pageBackground,
    cardBackground: AppColors.cardBackground,
    inputFill: AppColors.inputFill,
    imagePlaceholder: AppColors.imagePlaceholder,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    divider: AppColors.divider,
    starActive: AppColors.starActive,
    starSurface: AppColors.starSurface,
    badge: AppColors.badge,
    success: AppColors.success,
    successSurface: AppColors.successSurface,
    merged: AppColors.merged,
    mergedSurface: AppColors.mergedSurface,
    link: AppColors.link,
    barShadow: AppColors.barShadow,
    codeBackground: AppColors.codeBackground,
  );

  /// GitHub 深色主题默认色板
  static const AppThemePalette dark = AppThemePalette(
    isDark: true,
    primary: Color(0xFF58A6FF),
    primaryDisabled: Color(0xFF285380),
    primarySurface: Color(0xFF132C47),
    brandDark: Color(0xFFE6EDF3),
    brandButtonBg: Color(0xFF1F6FEB),
    brandButtonFg: Colors.white,
    headerGradientEnd: Color(0xFF0D1117),
    pageBackground: Color(0xFF0D1117),
    cardBackground: Color(0xFF161B22),
    inputFill: Color(0xFF21262D),
    imagePlaceholder: Color(0xFF21262D),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFF8B949E),
    divider: Color(0xFF30363D),
    starActive: Color(0xFFEAC54F),
    starSurface: Color(0xFF342A11),
    badge: Color(0xFFF85149),
    success: Color(0xFF3FB950),
    successSurface: Color(0xFF122B1B),
    merged: Color(0xFFA371F7),
    mergedSurface: Color(0xFF271B3B),
    link: Color(0xFF58A6FF),
    barShadow: Color(0x55000000),
    codeBackground: Color(0xFF161B22),
  );

  @override
  AppThemePalette copyWith({
    bool? isDark,
    Color? primary,
    Color? primaryDisabled,
    Color? primarySurface,
    Color? brandDark,
    Color? brandButtonBg,
    Color? brandButtonFg,
    Color? headerGradientEnd,
    Color? pageBackground,
    Color? cardBackground,
    Color? inputFill,
    Color? imagePlaceholder,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? starActive,
    Color? starSurface,
    Color? badge,
    Color? success,
    Color? successSurface,
    Color? merged,
    Color? mergedSurface,
    Color? link,
    Color? barShadow,
    Color? codeBackground,
  }) {
    return AppThemePalette(
      isDark: isDark ?? this.isDark,
      primary: primary ?? this.primary,
      primaryDisabled: primaryDisabled ?? this.primaryDisabled,
      primarySurface: primarySurface ?? this.primarySurface,
      brandDark: brandDark ?? this.brandDark,
      brandButtonBg: brandButtonBg ?? this.brandButtonBg,
      brandButtonFg: brandButtonFg ?? this.brandButtonFg,
      headerGradientEnd: headerGradientEnd ?? this.headerGradientEnd,
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      inputFill: inputFill ?? this.inputFill,
      imagePlaceholder: imagePlaceholder ?? this.imagePlaceholder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      starActive: starActive ?? this.starActive,
      starSurface: starSurface ?? this.starSurface,
      badge: badge ?? this.badge,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      merged: merged ?? this.merged,
      mergedSurface: mergedSurface ?? this.mergedSurface,
      link: link ?? this.link,
      barShadow: barShadow ?? this.barShadow,
      codeBackground: codeBackground ?? this.codeBackground,
    );
  }

  @override
  AppThemePalette lerp(ThemeExtension<AppThemePalette>? other, double t) {
    if (other is! AppThemePalette) return this;
    return AppThemePalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      primaryDisabled:
          Color.lerp(primaryDisabled, other.primaryDisabled, t) ??
          primaryDisabled,
      primarySurface:
          Color.lerp(primarySurface, other.primarySurface, t) ?? primarySurface,
      brandDark: Color.lerp(brandDark, other.brandDark, t) ?? brandDark,
      brandButtonBg:
          Color.lerp(brandButtonBg, other.brandButtonBg, t) ?? brandButtonBg,
      brandButtonFg:
          Color.lerp(brandButtonFg, other.brandButtonFg, t) ?? brandButtonFg,
      headerGradientEnd:
          Color.lerp(headerGradientEnd, other.headerGradientEnd, t) ??
          headerGradientEnd,
      pageBackground:
          Color.lerp(pageBackground, other.pageBackground, t) ?? pageBackground,
      cardBackground:
          Color.lerp(cardBackground, other.cardBackground, t) ?? cardBackground,
      inputFill: Color.lerp(inputFill, other.inputFill, t) ?? inputFill,
      imagePlaceholder:
          Color.lerp(imagePlaceholder, other.imagePlaceholder, t) ??
          imagePlaceholder,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      starActive: Color.lerp(starActive, other.starActive, t) ?? starActive,
      starSurface: Color.lerp(starSurface, other.starSurface, t) ?? starSurface,
      badge: Color.lerp(badge, other.badge, t) ?? badge,
      success: Color.lerp(success, other.success, t) ?? success,
      successSurface:
          Color.lerp(successSurface, other.successSurface, t) ?? successSurface,
      merged: Color.lerp(merged, other.merged, t) ?? merged,
      mergedSurface:
          Color.lerp(mergedSurface, other.mergedSurface, t) ?? mergedSurface,
      link: Color.lerp(link, other.link, t) ?? link,
      barShadow: Color.lerp(barShadow, other.barShadow, t) ?? barShadow,
      codeBackground:
          Color.lerp(codeBackground, other.codeBackground, t) ?? codeBackground,
    );
  }
}

/// 便捷从 `BuildContext` 获取当前生效的动态语义色板
extension AppThemeContext on BuildContext {
  AppThemePalette get appColors =>
      Theme.of(this).extension<AppThemePalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppThemePalette.dark
          : AppThemePalette.light);
}
