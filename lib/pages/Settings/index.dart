import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 应用设置页：支持自定义探索首页顶部展示的标签、首位「全部」开关及展示顺序
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _customTagController = TextEditingController();

  late final ExploreTagsController _tagsController =
      Get.isRegistered<ExploreTagsController>()
      ? Get.find<ExploreTagsController>()
      : Get.put(ExploreTagsController(), permanent: true);

  @override
  void initState() {
    super.initState();
    unawaited(_tagsController.ensureLoaded());
  }

  @override
  void dispose() {
    _customTagController.dispose();
    super.dispose();
  }

  Future<void> _toggleTag(String tag) async {
    final ok = await _tagsController.toggleTag(tag);
    if (!ok && mounted) {
      ToastUtils.showToast(context, '至少保留一个首页展示标签');
    }
  }

  Future<void> _toggleShowAll(bool value) async {
    final ok = await _tagsController.setShowAllTag(value);
    if (!ok && mounted) {
      ToastUtils.showToast(context, '请先勾选其他语言标签后再关闭「全部」');
    }
  }

  Future<void> _addCustomTag() async {
    final res = await _tagsController.addCustomTag(_customTagController.text);
    if (res.added) {
      _customTagController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    }
    if (mounted) {
      ToastUtils.showToast(context, res.message);
    }
  }

  Future<void> _removeCustomTag(String tag) async {
    final ok = await _tagsController.removeCustomTag(tag);
    if (!ok && mounted) {
      ToastUtils.showToast(context, '该标签为当前唯一展示项，暂不能删除');
    }
  }

  Future<void> _resetDefaults() async {
    await _tagsController.resetDefaults();
    if (mounted) {
      ToastUtils.showToast(context, '已恢复默认首页标签');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton(onPressed: _resetDefaults, child: const Text('恢复默认')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: Obx(() {
            final displayTags = _tagsController.displayTags;
            final selectedTags = _tagsController.selectedTags.toList();
            final availableTags = _tagsController.availableTags;
            final customTags = _tagsController.customTags.toList();
            final showAll = _tagsController.showAllTag.value;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _buildPreviewCard(displayTags),
                const SizedBox(height: AppSpacing.module),
                _buildShowAllCard(showAll),
                const SizedBox(height: AppSpacing.module),
                _buildAvailableTagsCard(availableTags, customTags),
                const SizedBox(height: AppSpacing.module),
                _buildCustomInputCard(),
                if (selectedTags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.module),
                  _buildOrderCard(selectedTags),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  Widget _buildPreviewCard(List<String> displayTags) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('首页顶部标签预览', style: AppTextStyles.bodyStrong),
              ),
              Text('共 ${displayTags.length} 项', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: displayTags.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = displayTags[index];
                final isFirst = index == 0;
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isFirst
                          ? AppColors.brandDark
                          : AppColors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      tag,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: isFirst ? Colors.white : AppColors.textPrimary,
                        fontWeight: isFirst
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowAllCard(bool showAll) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: SwitchListTile(
        value: showAll,
        onChanged: _toggleShowAll,
        title: const Text('首位显示「全部」标签', style: AppTextStyles.bodyStrong),
        subtitle: const Text(
          '开启后可在首页一键查看全语言热门开源项目',
          style: AppTextStyles.captionSmall,
        ),
      ),
    );
  }

  Widget _buildAvailableTagsCard(
    List<String> availableTags,
    List<String> customTags,
  ) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: Text('选择展示标签', style: AppTextStyles.bodyStrong)),
              Text('点击勾选或取消', style: AppTextStyles.captionSmall),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in availableTags)
                _buildSelectableChip(tag, customTags),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableChip(String tag, List<String> customTags) {
    final selected = _tagsController.isSelected(tag);
    final isCustom = customTags.any(
      (item) => item.toLowerCase() == tag.toLowerCase(),
    );
    return FilterChip(
      label: Text(tag, softWrap: false),
      selected: selected,
      showCheckmark: true,
      checkmarkColor: Colors.white,
      selectedColor: AppColors.brandDark,
      backgroundColor: AppColors.inputFill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: selected ? Colors.white : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) => _toggleTag(tag),
      onDeleted: isCustom ? () => _removeCustomTag(tag) : null,
      deleteIconColor: selected ? Colors.white70 : AppColors.textSecondary,
      deleteButtonTooltipMessage: '删除自定义标签',
    );
  }

  Widget _buildCustomInputCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('添加自定义标签', style: AppTextStyles.bodyStrong),
          const SizedBox(height: 4),
          const Text(
            '支持编程语言名称（如 Zig、Solidity）或搜索条件（如 topic:ai）',
            style: AppTextStyles.captionSmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTagController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addCustomTag(),
                  decoration: InputDecoration(
                    hintText: '输入标签名称...',
                    hintStyle: AppTextStyles.caption,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addCustomTag,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                ),
                child: const Text('添加'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(List<String> selectedTags) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: Text('已选标签顺序', style: AppTextStyles.bodyStrong)),
              Text('拖拽或点箭头调序', style: AppTextStyles.captionSmall),
            ],
          ),
          const SizedBox(height: 6),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: selectedTags.length,
            onReorderItem: _tagsController.reorderTag,
            itemBuilder: (context, index) {
              final tag = selectedTags[index];
              return Container(
                key: ValueKey('tag_order_$tag'),
                decoration: BoxDecoration(
                  border: index < selectedTags.length - 1
                      ? const Border(
                          bottom: BorderSide(
                            color: AppColors.divider,
                            width: 0.5,
                          ),
                        )
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.languageColor(tag),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body,
                        ),
                      ),
                      IconButton(
                        onPressed: index > 0
                            ? () => _tagsController.moveTag(index, -1)
                            : null,
                        icon: const Icon(Icons.arrow_upward, size: 17),
                        tooltip: '上移',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        onPressed: index < selectedTags.length - 1
                            ? () => _tagsController.moveTag(index, 1)
                            : null,
                        icon: const Icon(Icons.arrow_downward, size: 17),
                        tooltip: '下移',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        onPressed: () => _toggleTag(tag),
                        icon: const Icon(
                          Icons.close,
                          size: 17,
                          color: AppColors.textSecondary,
                        ),
                        tooltip: '移除',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
