import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';

/// API 速率配额、Token 权限、版本信息与检查更新卡片
class GhMineStatusCard extends StatelessWidget {
  const GhMineStatusCard({
    super.key,
    required this.rateLimit,
    required this.scopes,
    required this.versionText,
    required this.onRefreshRateLimit,
    this.onCheckUpdate,
    this.checkingUpdate = false,
  });

  final RateLimitState rateLimit;
  final List<String> scopes;
  final String versionText;
  final VoidCallback onRefreshRateLimit;

  /// 手动点击检查新版本回调（为空时不展示操作入口）
  final VoidCallback? onCheckUpdate;

  /// 是否正在请求远端 Release 检查更新
  final bool checkingUpdate;

  /// 统一规范版本号显示格式（避免出现 `vv1.0.0`）
  String _formatVersionLabel(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'v1.0.0';
    return v.startsWith('v') || v.startsWith('V') ? v : 'v$v';
  }

  /// 将配额重置时间格式化为本地 `HH:mm` 字符串
  String _formatResetTime(DateTime? dt) {
    if (dt == null) return '--';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = rateLimit.limit > 0
        ? (rateLimit.remaining / rateLimit.limit).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('GitHub API 配额', style: AppTextStyles.bodyStrong),
              ),
              TextButton(
                onPressed: onRefreshRateLimit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
                child: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.inputFill,
              valueColor: AlwaysStoppedAnimation<Color>(
                rateLimit.remaining < 10 ? AppColors.badge : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '剩余 ${rateLimit.remaining} / ${rateLimit.limit} 次',
                style: AppTextStyles.caption,
              ),
              Text(
                '重置时间：${_formatResetTime(rateLimit.resetAt)}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
          if (scopes.isNotEmpty) ...[
            const Divider(height: 22, color: AppColors.divider),
            const Text('当前 Token 权限范围', style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final scope in scopes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      scope,
                      style: AppTextStyles.captionSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 22, color: AppColors.divider),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('应用版本', style: AppTextStyles.bodySmall),
              Text(
                _formatVersionLabel(versionText),
                style: AppTextStyles.caption,
              ),
            ],
          ),
          if (onCheckUpdate != null) ...[
            const Divider(height: 18, color: AppColors.divider),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: checkingUpdate ? null : onCheckUpdate,
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('检查更新', style: AppTextStyles.bodySmall),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (checkingUpdate) ...[
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 6),
                            const Text('检查中...', style: AppTextStyles.caption),
                          ] else ...[
                            const Text('立即检测', style: AppTextStyles.caption),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
