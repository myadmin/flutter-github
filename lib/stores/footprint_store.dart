import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地仓库浏览足迹存储（参考 hm_shop FootprintStore：去重 + 最多保留 50 条）
class FootprintStore {
  const FootprintStore._();

  static const int maxItems = 50;

  /// 足迹版本号：写入 / 移除 / 清空后自增，Explore 等常驻页面据此刷新“继续浏览”
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<List<FootprintItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(GlobalConstants.footprintKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final items = decoded
          .whereType<Map<Object?, Object?>>()
          .map((item) => FootprintItem.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.owner.isNotEmpty && item.name.isNotEmpty)
          .toList();
      items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      return items;
    } on FormatException catch (error) {
      debugPrint('足迹数据解析失败，按空列表处理: $error');
      return const [];
    }
  }

  /// 测试用：在每个用例切换 FakeAsync Zone 时重置写入队列，避免跨用例挂起
  @visibleForTesting
  static void resetForTest() {
    _writeQueue = null;
  }

  /// 写操作串行化队列：详情页、搜索页可能同时记录足迹，
  /// 读-改-写并发会互相覆盖导致记录丢失。
  static Future<void>? _writeQueue;

  static Future<T> _serialized<T>(Future<T> Function() task) {
    final prev = _writeQueue;
    final result = prev == null ? task() : prev.then((_) => task());
    final marker = result.then<void>((_) {}, onError: (Object _) {});
    _writeQueue = marker;
    marker.whenComplete(() {
      if (identical(_writeQueue, marker)) {
        _writeQueue = null;
      }
    });
    return result;
  }

  static Future<List<FootprintItem>> record(FootprintItem item) {
    if (item.owner.isEmpty || item.name.isEmpty) {
      return load();
    }
    return _serialized(() => _recordInternal(item));
  }

  /// 删除单条本地足迹并通知监听页同步刷新
  static Future<List<FootprintItem>> remove(String fullName) {
    final target = fullName.trim().toLowerCase();
    if (target.isEmpty) return load();
    return _serialized(() => _removeInternal(target));
  }

  static Future<List<FootprintItem>> _removeInternal(
    String lowerFullName,
  ) async {
    final items = await load();
    final next = items
        .where((item) => item.fullName.toLowerCase() != lowerFullName)
        .toList();
    await _save(next);
    return next;
  }

  static Future<List<FootprintItem>> _recordInternal(FootprintItem item) async {
    final items = await load();
    final next = [
      item,
      ...items.where(
        (existing) =>
            existing.fullName.toLowerCase() != item.fullName.toLowerCase(),
      ),
    ];
    final trimmed = next.take(maxItems).toList();
    await _save(trimmed);
    return trimmed;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(GlobalConstants.footprintKey);
    revision.value++;
  }

  static Future<void> _save(List<FootprintItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((item) => item.toJson()).toList());
    await prefs.setString(GlobalConstants.footprintKey, raw);
    revision.value++;
  }
}
