import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 编程语言圆点 + 名称标签
class GhLanguageDot extends StatelessWidget {
  const GhLanguageDot({super.key, required this.language, this.textStyle});

  final String language;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (language.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.languageColor(language),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          language,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle ?? AppTextStyles.caption,
        ),
      ],
    );
  }
}
