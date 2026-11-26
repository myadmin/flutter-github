import 'dart:math' as math;

import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 探索页热门时间跨度
enum TrendingSince {
  today('今日新星', 1),
  week('本周热门', 7),
  month('本月飙升', 30),
  all('历史经典', 0);

  const TrendingSince(this.label, this.days);

  final String label;
  final int days;
}

/// 根据语言与时间范围构造 GitHub Search API 查询串
String buildExploreQuery({
  String language = '全部',
  TrendingSince since = TrendingSince.week,
  DateTime? now,
}) {
  final parts = <String>[];
  if (since.days > 0) {
    final base = (now ?? DateTime.now()).subtract(Duration(days: since.days));
    final y = base.year.toString().padLeft(4, '0');
    final m = base.month.toString().padLeft(2, '0');
    final d = base.day.toString().padLeft(2, '0');
    parts.add('created:>$y-$m-$d');
    parts.add('stars:>10');
  } else {
    parts.add('stars:>1000');
  }
  final lang = language.trim();
  if (lang.isNotEmpty && lang != '全部') {
    parts.add('language:$lang');
  }
  return parts.join(' ');
}

/// 搜索仓库（支持排序与分页，GitHub Search 最多返回前 1000 条结果）
Future<PageResult<RepoItem>> searchReposAPI({
  required String query,
  String language = '',
  String sort = 'stars',
  String order = 'desc',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final trimmed = query.trim();
  final lang = language.trim();
  final q = lang.isNotEmpty && lang != '全部' && !trimmed.contains('language:')
      ? '$trimmed language:$lang'
      : trimmed;

  final params = <String, dynamic>{
    'q': q,
    'order': order,
    'page': page,
    'per_page': perPage,
  };
  if (sort.isNotEmpty && sort != 'best_match') {
    params['sort'] = sort;
  }

  final raw = await dioRequest.get(
    HttpConstants.searchRepositories,
    params: params,
  );
  final result = RepoSearchResult.fromJson(asMap(raw));
  // GitHub Search API 限制单次检索最多返回前 1000 条结果
  final cappedTotal = math.min(result.totalCount, 1000);
  final hasMore = page * perPage < cappedTotal && result.items.isNotEmpty;
  return PageResult<RepoItem>(
    items: result.items,
    page: page,
    hasMore: hasMore,
  );
}

/// 搜索 GitHub 用户 / 组织
Future<PageResult<RepoOwner>> searchUsersAPI({
  required String query,
  String sort = 'followers',
  String order = 'desc',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final params = <String, dynamic>{
    'q': query.trim(),
    'order': order,
    'page': page,
    'per_page': perPage,
  };
  if (sort.isNotEmpty && sort != 'best_match') {
    params['sort'] = sort;
  }

  final raw = asMap(
    await dioRequest.get(HttpConstants.searchUsers, params: params),
  );
  final totalCount = asInt(raw['total_count']);
  final items = asList(raw['items'], RepoOwner.fromJson);
  // 与仓库搜索一致，对齐 GitHub Search 的 1000 条结果上限
  final cappedTotal = math.min(totalCount, 1000);
  final hasMore = page * perPage < cappedTotal && items.isNotEmpty;
  return PageResult<RepoOwner>(items: items, page: page, hasMore: hasMore);
}
