import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_language_dot.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/footprint_store.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 本地项目浏览足迹页（参考 hm_shop FootprintPage）
class FootprintPage extends StatefulWidget {
  const FootprintPage({super.key});

  @override
  State<FootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends State<FootprintPage> {
  final TextEditingController _filterController = TextEditingController();

  /// 当前筛选关键词，独立成 ValueNotifier：输入框击键只重建列表区域，
  /// 不再整页 setState（原来每次按键都会重建 AppBar、筛选栏与全部卡片）
  final ValueNotifier<String> _filter = ValueNotifier<String>('');
  List<FootprintItem> _items = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    _filterController.dispose();
    super.dispose();
  }

  /// 从本地加载浏览足迹列表
  Future<void> _load() async {
    final items = await FootprintStore.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  /// 二次确认后清空全部本地浏览足迹
  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空浏览足迹？'),
          content: const Text('足迹仅保存在本机，清空后无法恢复'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await FootprintStore.clear();
    if (!mounted) return;
    setState(() => _items = const []);
    ToastUtils.showToast(context, '已清空足迹');
  }

  /// 删除单条本地足迹
  Future<void> _removeItem(FootprintItem item) async {
    final updated = await FootprintStore.remove(item.fullName);
    if (!mounted) return;
    setState(() => _items = updated);
    ToastUtils.showToast(context, '已移除 ${item.fullName}');
  }

  /// 侧滑删除：必须同步从 `_items` 中移除。
  ///
  /// `Dismissible` 在动画结束那一帧会校验「被 dismiss 的子树是否仍在树上」，
  /// 若此时才去 await 落盘再 setState，Widget 仍挂在树上会直接触发框架断言。
  /// 因此这里先同步更新内存，再异步落盘。
  void _removeItemImmediately(FootprintItem item) {
    setState(() {
      _items = _items.where((e) => e.fullName != item.fullName).toList();
    });
    ToastUtils.showToast(context, '已移除 ${item.fullName}');
    unawaited(FootprintStore.remove(item.fullName));
  }

  /// 跳转项目详情，返回后刷新本地足迹排序与浏览时间
  Future<void> _openRepo(FootprintItem item) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.repoDetail(item.owner, item.name),
    );
    if (!mounted) return;
    await _load();
  }

  /// 将毫秒时间戳格式化为「HH:mm 浏览」
  String _formatHourMinute(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm 浏览';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('浏览足迹'),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _clear,
              child: Text(
                '清空',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return HmEmptyView(
        icon: Icons.history,
        title: '还没有浏览足迹',
        description: '查看过的 GitHub 仓库会出现在这里',
        actionText: '去探索',
        onAction: () => Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (_) => false,
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: HmBottomBar.maxContentWidth,
        ),
        child: Column(
          children: [
            Container(
              color: context.appColors.cardBackground,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: ValueListenableBuilder<String>(
                valueListenable: _filter,
                builder: (context, keyword, _) => TextField(
                  controller: _filterController,
                  onChanged: (value) => _filter.value = value,
                  decoration: InputDecoration(
                    hintText: '筛选历史仓库名称、简介或语言...',
                    hintStyle: context.captionStyle,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: keyword.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _filterController.clear();
                              _filter.value = '';
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: context.appColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            // 仅筛选结果依赖关键词：击键时只重建下方列表，不重建筛选栏与页面骨架
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _filter,
                builder: (context, keyword, _) {
                  final query = keyword.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? _items
                      : _items
                            .where(
                              (item) =>
                                  item.fullName.toLowerCase().contains(query) ||
                                  item.description.toLowerCase().contains(
                                    query,
                                  ) ||
                                  item.language.toLowerCase().contains(query),
                            )
                            .toList();
                  if (filtered.isEmpty) {
                    return const HmEmptyView(
                      icon: Icons.search_off,
                      title: '没有匹配的足迹',
                      description: '尝试更换关键词筛选',
                    );
                  }
                  return _buildFootprintList(groupFootprints(filtered));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建按日期分组的足迹列表。
  ///
  /// 先摊平成「分组标题 / 足迹条目」的轻量索引，真正的卡片在 `itemBuilder`
  /// 里按需构建，避免一次把全部分组标题与卡片 Widget 都建出来。
  Widget _buildFootprintList(List<FootprintGroup> groups) {
    final rows = <Object>[];
    for (final group in groups) {
      rows.add(group.title);
      rows.addAll(group.items);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '左滑或点击删除可移除单条记录 · 最多保留 ${FootprintStore.maxItems} 条',
              textAlign: TextAlign.center,
              style: context.captionSmallStyle,
            ),
          );
        }
        final row = rows[index];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
            child: Text(
              row,
              style: context.captionStyle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        final item = row as FootprintItem;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey('footprint_${item.fullName}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 18),
              decoration: BoxDecoration(
                color: context.appColors.badge.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(Icons.delete_outline, color: context.appColors.badge),
            ),
            onDismissed: (_) => _removeItemImmediately(item),
            child: _FootprintTile(
              item: item,
              timeText: _formatHourMinute(item.viewedAt),
              onTap: () => _openRepo(item),
              onDelete: () => _removeItem(item),
            ),
          ),
        );
      },
    );
  }
}

/// 单条历史足迹卡片（头像、仓库名、描述、语言、Star 数、浏览时间与单条删除）
class _FootprintTile extends StatelessWidget {
  const _FootprintTile({
    required this.item,
    required this.timeText,
    required this.onTap,
    required this.onDelete,
  });

  final FootprintItem item;
  final String timeText;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: context.appColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: context.appColors.divider.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNetworkImage(
                    url: item.avatarUrl,
                    width: 36,
                    height: 36,
                    decodeWidth: 36,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tileTitleStyle.copyWith(
                            color: context.appColors.primary,
                          ),
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.captionStyle,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (item.language.isNotEmpty)
                              GhLanguageDot(language: item.language),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_border,
                                  size: 14,
                                  color: context.appColors.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  formatCompactNumber(item.stargazersCount),
                                  style: context.captionSmallStyle,
                                ),
                              ],
                            ),
                            Text(timeText, style: context.captionSmallStyle),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: context.appColors.textSecondary,
                    ),
                    tooltip: '删除足迹',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
