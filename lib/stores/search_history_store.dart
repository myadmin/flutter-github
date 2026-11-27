import 'package:flutter/foundation.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地搜索历史存储（去重，最多保留 15 条）
///
/// 所有写操作通过 [_writeQueue] 串行化：搜索框可能连续触发多次 record，
/// 读-改-写若并发执行会互相覆盖，导致历史记录丢失。
class SearchHistoryStore {
  const SearchHistoryStore._();

  static const int maxItems = 15;

  /// 测试用：在每个用例切换 FakeAsync Zone 时重置写入队列，避免跨用例挂起
  @visibleForTesting
  static void resetForTest() {
    _writeQueue = null;
  }

  static Future<void>? _writeQueue;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(GlobalConstants.searchHistoryKey) ?? const [];
  }

  static Future<List<String>> record(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return load();
    return _serialized(() => _recordInternal(trimmed));
  }

  static Future<List<String>> _recordInternal(String trimmed) async {
    final current = await load();
    final next = [
      trimmed,
      ...current.where((item) => item.toLowerCase() != trimmed.toLowerCase()),
    ].take(maxItems).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(GlobalConstants.searchHistoryKey, next);
    return next;
  }

  static Future<List<String>> remove(String keyword) {
    return _serialized(() async {
      final current = await load();
      final next = current.where((item) => item != keyword).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(GlobalConstants.searchHistoryKey, next);
      return next;
    });
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(GlobalConstants.searchHistoryKey);
  }

  /// 串行执行写任务，前一次失败不会阻塞后续任务
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
}
