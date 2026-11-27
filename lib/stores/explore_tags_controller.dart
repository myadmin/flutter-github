import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 探索首页顶部标签配置控制器（支持勾选、自定义添加、排序与本地持久化）
class ExploreTagsController extends GetxController {
  /// 固定可选的首位全语言标签
  static const String allTag = '全部';

  /// 默认展示的语言标签列表（与首页历史默认一致）
  static const List<String> defaultTags = [
    'Dart',
    'TypeScript',
    'Python',
    'Go',
    'Rust',
    'Swift',
    'Java',
    'Kotlin',
    'Vue',
  ];

  /// 设置页提供的一键勾选预设语言标签全集
  static const List<String> presetTags = [
    'Dart',
    'TypeScript',
    'JavaScript',
    'Python',
    'Go',
    'Rust',
    'Swift',
    'Java',
    'Kotlin',
    'Vue',
    'C++',
    'C',
    'C#',
    'HTML',
    'CSS',
    'Shell',
    'Ruby',
    'PHP',
    'Objective-C',
    'Scala',
    'Zig',
    'Lua',
    'Elixir',
    'Jupyter Notebook',
  ];

  /// 当前首页顶部选中的语言/主题标签（不含「全部」）
  final RxList<String> selectedTags = <String>[...defaultTags].obs;

  /// 是否在首位固定显示「全部」标签
  final RxBool showAllTag = true.obs;

  /// 用户手动添加的自定义标签列表（保留以便取消勾选后仍可再次勾选）
  final RxList<String> customTags = <String>[].obs;

  bool _loaded = false;
  Future<void>? _loadingFuture;
  int _mutationVersion = 0;

  /// 首页顶部实际展示的完整标签列表
  List<String> get displayTags => [
    if (showAllTag.value) allTag,
    ...selectedTags,
  ];

  /// 设置页供勾选的所有备选标签（预设标签 + 自定义标签去重合并）
  List<String> get availableTags {
    final result = <String>[...presetTags];
    for (final tag in customTags) {
      if (!_containsIgnoreCase(result, tag)) {
        result.add(tag);
      }
    }
    for (final tag in selectedTags) {
      if (!_containsIgnoreCase(result, tag)) {
        result.add(tag);
      }
    }
    return result;
  }

  /// 判断指定标签当前是否已启用展示
  bool isSelected(String tag) => _containsIgnoreCase(selectedTags, tag);

  /// 确保已从本地缓存完成一次读取（幂等）
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadingFuture ??= load();
  }

  /// 从 SharedPreferences 读取持久化标签配置
  Future<void> load() async {
    final startVersion = _mutationVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_mutationVersion != startVersion) return;

      final hasSavedTags = prefs.containsKey(GlobalConstants.exploreTagsKey);
      final rawTags = hasSavedTags
          ? (prefs.getStringList(GlobalConstants.exploreTagsKey) ?? const [])
          : defaultTags;
      final rawShowAll =
          prefs.getBool(GlobalConstants.exploreShowAllTagKey) ?? true;
      final rawCustom =
          prefs.getStringList(GlobalConstants.exploreCustomTagsKey) ?? const [];

      final cleanTags = _dedupeTags(rawTags);
      final cleanCustom = _dedupeTags(rawCustom)
          .where((tag) => !_containsIgnoreCase(presetTags, tag))
          .toList();

      // 至少保证首页顶部有一个可展示的标签
      final nextShowAll = cleanTags.isEmpty ? true : rawShowAll;

      showAllTag.value = nextShowAll;
      selectedTags.assignAll(cleanTags);
      customTags.assignAll(cleanCustom);
      _loaded = true;
    } finally {
      _loadingFuture = null;
    }
  }

  /// 勾选或取消勾选单个语言/主题标签；若会导致首页无任何标签则返回 false
  Future<bool> toggleTag(String tag) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || trimmed == allTag) return false;

    final existingIdx = _indexOfIgnoreCase(selectedTags, trimmed);
    if (existingIdx >= 0) {
      if (!showAllTag.value && selectedTags.length <= 1) {
        return false;
      }
      selectedTags.removeAt(existingIdx);
    } else {
      final canonical = _findCanonicalName(trimmed) ?? trimmed;
      selectedTags.add(canonical);
    }
    await _persist();
    return true;
  }

  /// 添加自定义标签并自动勾选展示
  Future<({bool added, String message})> addCustomTag(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (added: false, message: '请输入标签名称');
    }
    if (trimmed == allTag) {
      return (added: false, message: '「全部」标签可通过上方开关控制');
    }

    final existingSelected = _findIgnoreCase(selectedTags, trimmed);
    if (existingSelected != null) {
      return (added: false, message: '「$existingSelected」已在展示列表中');
    }

    final canonical = _findCanonicalName(trimmed);
    if (canonical != null) {
      selectedTags.add(canonical);
      await _persist();
      return (added: true, message: '已勾选展示「$canonical」');
    }

    customTags.add(trimmed);
    selectedTags.add(trimmed);
    await _persist();
    return (added: true, message: '已添加并展示「$trimmed」');
  }

  /// 删除一个自定义标签；若它是当前唯一展示标签则拒绝删除并返回 false
  Future<bool> removeCustomTag(String tag) async {
    final trimmed = tag.trim();
    final selectedIdx = _indexOfIgnoreCase(selectedTags, trimmed);
    if (selectedIdx >= 0 && !showAllTag.value && selectedTags.length <= 1) {
      return false;
    }
    if (selectedIdx >= 0) {
      selectedTags.removeAt(selectedIdx);
    }
    final customIdx = _indexOfIgnoreCase(customTags, trimmed);
    if (customIdx >= 0) {
      customTags.removeAt(customIdx);
    }
    await _persist();
    return true;
  }

  /// 拖拽调整已选标签顺序（对齐 `onReorderItem` 已修正移除偏移后的目标索引）
  Future<void> reorderTag(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= selectedTags.length ||
        newIndex < 0 ||
        newIndex >= selectedTags.length ||
        newIndex == oldIndex) {
      return;
    }
    final item = selectedTags.removeAt(oldIndex);
    selectedTags.insert(newIndex, item);
    await _persist();
  }

  /// 上移或下移已选标签位置（`delta` 为 -1 或 +1）
  Future<bool> moveTag(int index, int delta) async {
    final target = index + delta;
    if (index < 0 ||
        index >= selectedTags.length ||
        target < 0 ||
        target >= selectedTags.length) {
      return false;
    }
    final item = selectedTags.removeAt(index);
    selectedTags.insert(target, item);
    await _persist();
    return true;
  }

  /// 切换首位是否固定显示「全部」标签
  Future<bool> setShowAllTag(bool show) async {
    if (!show && selectedTags.isEmpty) {
      return false;
    }
    if (showAllTag.value == show) return true;
    showAllTag.value = show;
    await _persist();
    return true;
  }

  /// 恢复默认展示的标签集合与顺序
  Future<void> resetDefaults() async {
    showAllTag.value = true;
    selectedTags.assignAll(defaultTags);
    customTags.clear();
    await _persist();
  }

  Future<void> _persist() async {
    _mutationVersion++;
    _loaded = true;
    final tagsSnapshot = List<String>.from(selectedTags);
    final customSnapshot = List<String>.from(customTags);
    final showAllSnapshot = showAllTag.value;
    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait<bool>([
      prefs.setStringList(GlobalConstants.exploreTagsKey, tagsSnapshot),
      prefs.setBool(GlobalConstants.exploreShowAllTagKey, showAllSnapshot),
      prefs.setStringList(GlobalConstants.exploreCustomTagsKey, customSnapshot),
    ]);
    if (results.any((ok) => !ok)) {
      debugPrint('[ExploreTagsController] 探索标签持久化失败，本次仅内存生效');
    }
  }

  List<String> _dedupeTags(List<String> raw) {
    final result = <String>[];
    for (final item in raw) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || trimmed == allTag) continue;
      if (!_containsIgnoreCase(result, trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  String? _findCanonicalName(String target) {
    return _findIgnoreCase(presetTags, target) ??
        _findIgnoreCase(customTags, target);
  }

  static bool _containsIgnoreCase(List<String> list, String target) =>
      _indexOfIgnoreCase(list, target) >= 0;

  static String? _findIgnoreCase(List<String> list, String target) {
    final idx = _indexOfIgnoreCase(list, target);
    return idx >= 0 ? list[idx] : null;
  }

  static int _indexOfIgnoreCase(List<String> list, String target) {
    final lower = target.trim().toLowerCase();
    for (var i = 0; i < list.length; i++) {
      if (list[i].toLowerCase() == lower) return i;
    }
    return -1;
  }
}
