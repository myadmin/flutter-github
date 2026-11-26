import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 底部操作栏与内容最大宽度限制外壳（对齐 hm_shop 的宽屏收窄约定）
class HmBottomBar extends StatelessWidget {
  const HmBottomBar({super.key, required this.child});

  final Widget child;

  /// 内容最大阅读宽度（宽屏 / Web 居中收窄）
  static const double maxContentWidth = 680;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.barShadow,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
