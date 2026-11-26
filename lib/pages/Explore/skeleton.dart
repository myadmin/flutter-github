import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 探索页骨架屏（参考 hm_shop HomeSkeleton 呼吸闪烁动画）
class ExploreSkeleton extends StatefulWidget {
  const ExploreSkeleton({super.key});

  @override
  State<ExploreSkeleton> createState() => _ExploreSkeletonState();
}

class _ExploreSkeletonState extends State<ExploreSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.35,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box({double? width, double height = 14, double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.imagePlaceholder,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _repoSkeletonCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _box(width: 24, height: 24, radius: 12),
              const SizedBox(width: 10),
              _box(width: 160, height: 16),
              const Spacer(),
              _box(width: 56, height: 24, radius: 12),
            ],
          ),
          const SizedBox(height: 10),
          _box(height: 12),
          const SizedBox(height: 6),
          _box(width: 220, height: 12),
          const SizedBox(height: 12),
          Row(
            children: [
              _box(width: 60, height: 12),
              const SizedBox(width: 16),
              _box(width: 48, height: 12),
              const SizedBox(width: 16),
              _box(width: 80, height: 12),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var i = 0; i < 5; i++) ...[
              _repoSkeletonCard(),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
