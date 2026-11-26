import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地搜索历史存储（去重，最多保留 15 条）
class SearchHistoryStore {
  const SearchHistoryStore._();

  static const int maxItems = 15;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(GlobalConstants.searchHistoryKey) ?? const [];
  }

  static Future<List<String>> record(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return load();
    final current = await load();
    final next = [
      trimmed,
      ...current.where((item) => item.toLowerCase() != trimmed.toLowerCase()),
    ].take(maxItems).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(GlobalConstants.searchHistoryKey, next);
    return next;
  }

  static Future<List<String>> remove(String keyword) async {
    final current = await load();
    final next = current.where((item) => item != keyword).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(GlobalConstants.searchHistoryKey, next);
    return next;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(GlobalConstants.searchHistoryKey);
  }
}
