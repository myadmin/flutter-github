import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/user.dart';
import 'package:gh_explorer/utils/formatters.dart';

/// 「我的」页面头部用户信息卡片
class GhMineHeader extends StatelessWidget {
  const GhMineHeader({
    super.key,
    required this.user,
    required this.onLoginTap,
    required this.onLogoutTap,
    required this.onProfileTap,
    required this.onReposTap,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  final GithubUser user;
  final VoidCallback onLoginTap;
  final VoidCallback onLogoutTap;
  final VoidCallback onProfileTap;
  final VoidCallback onReposTap;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final loggedIn = user.isLoggedIn;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.appColors.cardBackground,
            context.appColors.headerGradientEnd,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: loggedIn ? onProfileTap : onLoginTap,
                child: AppNetworkImage(
                  url: loggedIn ? user.avatarUrl : '',
                  width: 60,
                  height: 60,
                  decodeWidth: 60,
                  placeholderIconSize: 32,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GestureDetector(
                  onTap: loggedIn ? onProfileTap : onLoginTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? user.displayName : '点击登录 GitHub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.pageTitleStyle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loggedIn
                            ? '@${user.login}'
                            : '当前为游客浏览，登录后可点 Star 与查看动态',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                ),
              ),
              if (loggedIn)
                OutlinedButton(
                  onPressed: onLogoutTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.appColors.textSecondary,
                    side: BorderSide(color: context.appColors.divider),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('退出', style: TextStyle(fontSize: 12)),
                )
              else
                ElevatedButton(
                  onPressed: onLoginTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appColors.brandButtonBg,
                    foregroundColor: context.appColors.brandButtonFg,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('登录', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
          if (loggedIn && user.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(user.bio, style: context.bodySmallStyle),
          ],
          if (loggedIn) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: context.appColors.divider.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MetricCell(
                      label: '公开仓库',
                      value: formatCompactNumber(user.publicRepos),
                      onTap: onReposTap,
                    ),
                  ),
                  _verticalDivider(context),
                  Expanded(
                    child: _MetricCell(
                      label: 'Followers',
                      value: formatCompactNumber(user.followers),
                      onTap: onFollowersTap,
                    ),
                  ),
                  _verticalDivider(context),
                  Expanded(
                    child: _MetricCell(
                      label: 'Following',
                      value: formatCompactNumber(user.following),
                      onTap: onFollowingTap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 统计项之间的竖向分割线
  Widget _verticalDivider(BuildContext context) {
    return Container(width: 1, height: 24, color: context.appColors.divider);
  }
}

/// 头部个人数据统计单元（公开仓库 / Followers / Following）
class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: context.sectionTitleStyle),
          const SizedBox(height: 2),
          Text(label, style: context.captionSmallStyle),
        ],
      ),
    );
  }
}
