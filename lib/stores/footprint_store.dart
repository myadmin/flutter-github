import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/footprint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地仓库浏览足迹存储（参考 hm_shop FootprintStore：去重 + 最多保留 50 条）
class FootprintStore {
  const FootprintStore._();

  static const int maxItems = 50;

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

  static Future<List<FootprintItem>> record(FootprintItem item) async {
    if (item.owner.isEmpty || item.name.isEmpty) {
      return load();
    }
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
  }

  static Future<void> _save(List<FootprintItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((item) => item.toJson()).toList());
    await prefs.setString(GlobalConstants.footprintKey, raw);
  }
}
