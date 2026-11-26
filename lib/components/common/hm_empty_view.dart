import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 通用空态 / 未登录态组件（复用 hm_shop HmEmptyView 规范）
class HmEmptyView extends StatelessWidget {
  const HmEmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.actionText = '',
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.appColors.divider),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.appColors.textPrimary,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: context.captionStyle,
              ),
            ),
          ],
          if (actionText.isNotEmpty && onAction != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appColors.brandDark,
                  side: BorderSide(color: context.appColors.brandDark),
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(actionText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
