import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/stores/theme_controller.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 应用设置页：支持外观主题色切换及探索首页顶部标签自定义
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
  late final ThemeController _themeController =
      Get.isRegistered<ThemeController>()
      ? Get.find<ThemeController>()
      : Get.put(ThemeController(), permanent: true);

  @override
  void initState() {
    super.initState();
    unawaited(_tagsController.ensureLoaded());
    unawaited(_themeController.ensureLoaded());
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

  Future<void> _selectThemeMode(ThemeMode mode) async {
    await _themeController.setThemeMode(mode);
  }

  Future<void> _resetDefaults() async {
    await Future.wait([
      _tagsController.resetDefaults(),
      _themeController.resetDefault(),
    ]);
    if (mounted) {
      ToastUtils.showToast(context, '已恢复默认设置');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: context.appColors.cardBackground,
        foregroundColor: context.appColors.textPrimary,
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
            final themeMode = _themeController.themeMode.value;
            final displayTags = _tagsController.displayTags;
            final selectedTags = _tagsController.selectedTags.toList();
            final availableTags = _tagsController.availableTags;
            final customTags = _tagsController.customTags.toList();
            final showAll = _tagsController.showAllTag.value;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _buildThemeCard(themeMode),
                const SizedBox(height: AppSpacing.module),
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
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: child,
    );
  }

  Widget _buildThemeCard(ThemeMode currentMode) {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final options = <(ThemeMode, String, IconData)>[
      (
        ThemeMode.system,
        ThemeController.labelOf(ThemeMode.system),
        Icons.brightness_auto_outlined,
      ),
      (
        ThemeMode.light,
        ThemeController.labelOf(ThemeMode.light),
        Icons.light_mode_outlined,
      ),
      (
        ThemeMode.dark,
        ThemeController.labelOf(ThemeMode.dark),
        Icons.dark_mode_outlined,
      ),
    ];

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 18,
                color: context.appColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text('外观主题色', style: context.bodyStrongStyle)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.appColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  ThemeController.labelOf(currentMode),
                  style: context.captionSmallStyle.copyWith(
                    color: context.appColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _themeController.descriptionFor(platformBrightness),
            style: context.captionSmallStyle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _buildThemeOption(
                    mode: options[i].$1,
                    label: options[i].$2,
                    icon: options[i].$3,
                    selected: currentMode == options[i].$1,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool selected,
  }) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: '主题模式：$label',
      child: Material(
        color: selected ? colors.brandButtonBg : colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.image),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _selectThemeMode(mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.image),
              border: Border.all(
                color: selected
                    ? colors.brandButtonBg
                    : colors.divider.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? colors.brandButtonFg : colors.textPrimary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.captionSmallStyle.copyWith(
                    color: selected ? colors.brandButtonFg : colors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(List<String> displayTags) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: context.appColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('首页顶部标签预览', style: context.bodyStrongStyle)),
              Text('共 ${displayTags.length} 项', style: context.captionStyle),
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
                          ? context.appColors.brandButtonBg
                          : context.appColors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      tag,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: isFirst
                            ? context.appColors.brandButtonFg
                            : context.appColors.textPrimary,
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
      color: context.appColors.cardBackground,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: context.appColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: SwitchListTile(
        value: showAll,
        onChanged: _toggleShowAll,
        title: Text('首位显示「全部」标签', style: context.bodyStrongStyle),
        subtitle: Text(
          '开启后可在首页一键查看全语言热门开源项目',
          style: context.captionSmallStyle,
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
          Row(
            children: [
              Expanded(child: Text('选择展示标签', style: context.bodyStrongStyle)),
              Text('点击勾选或取消', style: context.captionSmallStyle),
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
      checkmarkColor: context.appColors.brandButtonFg,
      selectedColor: context.appColors.brandButtonBg,
      backgroundColor: context.appColors.inputFill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: selected
            ? context.appColors.brandButtonFg
            : context.appColors.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) => _toggleTag(tag),
      onDeleted: isCustom ? () => _removeCustomTag(tag) : null,
      deleteIconColor: selected
          ? context.appColors.brandButtonFg.withValues(alpha: 0.7)
          : context.appColors.textSecondary,
      deleteButtonTooltipMessage: '删除自定义标签',
    );
  }

  Widget _buildCustomInputCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('添加自定义标签', style: context.bodyStrongStyle),
          const SizedBox(height: 4),
          Text(
            '支持编程语言名称（如 Zig、Solidity）或搜索条件（如 topic:ai）',
            style: context.captionSmallStyle,
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
                    hintStyle: context.captionStyle,
                    filled: true,
                    fillColor: context.appColors.inputFill,
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
                  backgroundColor: context.appColors.brandButtonBg,
                  foregroundColor: context.appColors.brandButtonFg,
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
          Row(
            children: [
              Expanded(child: Text('已选标签顺序', style: context.bodyStrongStyle)),
              Text('拖拽或点箭头调序', style: context.captionSmallStyle),
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
                      ? Border(
                          bottom: BorderSide(
                            color: context.appColors.divider,
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
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: context.appColors.textSecondary,
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
                          style: context.bodyStyle,
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
                        icon: Icon(
                          Icons.close,
                          size: 17,
                          color: context.appColors.textSecondary,
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
