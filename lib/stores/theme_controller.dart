import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用外观主题控制器：支持「跟随系统 / 亮色 / 暗色」切换与本地持久化
class ThemeController extends GetxController {
  /// 当前选中的主题模式（默认跟随系统）
  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  bool _loaded = false;
  Future<void>? _loadingFuture;
  int _mutationVersion = 0;

  /// 将主题模式序列化为持久化字符串
  static String serializeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 将持久化字符串反序列化为 `ThemeMode`，未知值回退跟随系统
  static ThemeMode parseMode(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 返回主题模式对应的简短展示名称
  static String labelOf(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '亮色';
      case ThemeMode.dark:
        return '暗色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  /// 当前激活主题模式的简短名称
  String get currentLabel => labelOf(themeMode.value);

  /// 结合当前平台亮度生成设置页说明文案
  String descriptionFor(Brightness platformBrightness) {
    switch (themeMode.value) {
      case ThemeMode.light:
        return '已固定为亮色主题';
      case ThemeMode.dark:
        return '已固定为暗色主题';
      case ThemeMode.system:
        final currentName = platformBrightness == Brightness.dark ? '暗色' : '亮色';
        return '跟随系统色（当前为$currentName）';
    }
  }

  /// 确保已完成至少一次本地读取（幂等）
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadingFuture ??= load();
  }

  /// 从 SharedPreferences 读取持久化主题模式
  Future<void> load() async {
    final startVersion = _mutationVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_mutationVersion != startVersion) return;
      final saved = prefs.getString(GlobalConstants.themeModeKey);
      themeMode.value = parseMode(saved);
      _loaded = true;
    } finally {
      _loadingFuture = null;
    }
  }

  /// 切换并持久化新的主题模式
  Future<void> setThemeMode(ThemeMode next) async {
    _mutationVersion++;
    _loaded = true;
    themeMode.value = next;
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
      GlobalConstants.themeModeKey,
      serializeMode(next),
    );
    if (!ok) {
      debugPrint('[ThemeController] 主题模式持久化失败，本次仅内存生效');
    }
  }

  /// 恢复默认外观设置（跟随系统）
  Future<void> resetDefault() => setThemeMode(ThemeMode.system);
}
