import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';

/// 探索首页「热门开发者 / 开源组织」横滑栏（参考 hm_shop HmBrandStrip）
class GhFeaturedOwners extends StatelessWidget {
  const GhFeaturedOwners({
    super.key,
    required this.owners,
    required this.onOwnerTap,
  });

  final List<RepoOwner> owners;
  final ValueChanged<RepoOwner> onOwnerTap;

  @override
  Widget build(BuildContext context) {
    if (owners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.groups_outlined,
              size: 18,
              color: context.appColors.brandDark,
            ),
            const SizedBox(width: 6),
            Text('热门开发者与开源组织', style: context.bodyStrongStyle),
            const Spacer(),
            Text(
              '高关注账号',
              style: context.captionSmallStyle.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 98,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: owners.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final owner = owners[index];
              return _FeaturedOwnerCard(
                owner: owner,
                onTap: () => onOwnerTap(owner),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeaturedOwnerCard extends StatelessWidget {
  const _FeaturedOwnerCard({required this.owner, required this.onTap});

  final RepoOwner owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOrg = owner.type.toLowerCase() == 'organization';
    return SizedBox(
      width: 92,
      child: Material(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: context.appColors.divider.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppNetworkImage(
                  url: owner.avatarUrl,
                  width: 38,
                  height: 38,
                  decodeWidth: 40,
                  placeholderIconSize: 20,
                  borderRadius: BorderRadius.circular(19),
                ),
                const SizedBox(height: 6),
                Text(
                  owner.login,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.captionSmallStyle.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOrg ? '组织' : '开发者',
                  style: context.labelStyle.copyWith(
                    color: isOrg
                        ? context.appColors.primary
                        : context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
