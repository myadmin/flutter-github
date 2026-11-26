import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/routes/app_routes.dart';

/// 未知路由兜底页（参考 hm_shop UnknownRoutePage）
class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key, this.location});

  final String? location;

  void _backToHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.home,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('页面不存在'),
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_outlined,
                size: 56,
                color: context.appColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                '没有找到这个页面',
                style: context.tileTitleStyle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                location == null || location!.isEmpty
                    ? '地址可能已经失效，回首页继续浏览吧'
                    : '地址 $location',
                textAlign: TextAlign.center,
                style: context.captionStyle,
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => _backToHome(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appColors.brandDark,
                  side: BorderSide(color: context.appColors.brandDark),
                  shape: const StadiumBorder(),
                ),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
