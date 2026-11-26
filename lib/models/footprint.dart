import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';

/// 本地仓库浏览足迹条目
class FootprintItem {
  const FootprintItem({
    required this.fullName,
    required this.owner,
    required this.name,
    required this.avatarUrl,
    required this.description,
    required this.language,
    required this.stargazersCount,
    required this.viewedAt,
  });

  final String fullName;
  final String owner;
  final String name;
  final String avatarUrl;
  final String description;
  final String language;
  final int stargazersCount;
  final int viewedAt;

  factory FootprintItem.fromRepo(RepoItem repo, {DateTime? now}) {
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return FootprintItem(
      fullName: repo.fullName,
      owner: repo.ownerLogin,
      name: repo.repoName,
      avatarUrl: repo.owner.avatarUrl,
      description: repo.description,
      language: repo.language,
      stargazersCount: repo.stargazersCount,
      viewedAt: time,
    );
  }

  factory FootprintItem.fromJson(Map<String, dynamic> json) {
    return FootprintItem(
      fullName: asString(json['fullName']),
      owner: asString(json['owner']),
      name: asString(json['name']),
      avatarUrl: asString(json['avatarUrl']),
      description: asString(json['description']),
      language: asString(json['language']),
      stargazersCount: asInt(json['stargazersCount']),
      viewedAt: asInt(json['viewedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'owner': owner,
    'name': name,
    'avatarUrl': avatarUrl,
    'description': description,
    'language': language,
    'stargazersCount': stargazersCount,
    'viewedAt': viewedAt,
  };
}

/// 按日期分组的足迹区块
class FootprintGroup {
  const FootprintGroup({required this.title, required this.items});

  final String title;
  final List<FootprintItem> items;
}

/// 将足迹按「今天 / 昨天 / 更早」分组
List<FootprintGroup> groupFootprints(
  List<FootprintItem> items, {
  DateTime? now,
}) {
  if (items.isEmpty) return const [];
  final current = (now ?? DateTime.now()).toLocal();
  final todayStart = DateTime(current.year, current.month, current.day);
  final yesterdayStart = todayStart.subtract(const Duration(days: 1));

  final today = <FootprintItem>[];
  final yesterday = <FootprintItem>[];
  final earlier = <FootprintItem>[];

  for (final item in items) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.viewedAt).toLocal();
    if (!dt.isBefore(todayStart)) {
      today.add(item);
    } else if (!dt.isBefore(yesterdayStart)) {
      yesterday.add(item);
    } else {
      earlier.add(item);
    }
  }

  return [
    if (today.isNotEmpty) FootprintGroup(title: '今天', items: today),
    if (yesterday.isNotEmpty) FootprintGroup(title: '昨天', items: yesterday),
    if (earlier.isNotEmpty) FootprintGroup(title: '更早', items: earlier),
  ];
}
