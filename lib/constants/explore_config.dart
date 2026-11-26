import 'package:flutter/material.dart';
import 'package:gh_explorer/api/search.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';

/// 探索首页专题轮播卡片动作类型
enum ExploreBannerActionType { searchQuery, switchSince, switchFeedMode }

/// 探索首页精选专题 Banner 数据项
class ExploreBannerItem {
  const ExploreBannerItem({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.icon,
    required this.gradient,
    required this.actionType,
    this.query = '',
    this.since,
    this.feedMode,
  });

  final String badge;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final IconData icon;
  final List<Color> gradient;
  final ExploreBannerActionType actionType;
  final String query;
  final TrendingSince? since;
  final ExploreFeedMode? feedMode;
}

/// 探索首页领域快捷入口（0 API 开销，点击即切至搜索 Tab 或筛选）
class ExploreTopicEntry {
  const ExploreTopicEntry({
    required this.label,
    required this.query,
    required this.icon,
    required this.color,
    required this.surfaceColor,
  });

  final String label;
  final String query;
  final IconData icon;
  final Color color;
  final Color surfaceColor;
}

/// 探索首页内置精选专题 Banner 列表
const List<ExploreBannerItem> exploreBanners = [
  ExploreBannerItem(
    badge: '前沿聚焦',
    title: 'AI 与 Agent 开源浪潮',
    subtitle: '精选大模型应用、工作流引擎与热门开发框架',
    ctaLabel: '立即探索',
    icon: Icons.auto_awesome,
    gradient: [AppColors.brandDark, AppColors.bannerSlateEnd],
    actionType: ExploreBannerActionType.searchQuery,
    query: 'topic:llm stars:>200',
  ),
  ExploreBannerItem(
    badge: '今日风向',
    title: '今日新星 · 高速增长榜',
    subtitle: '一键切换今日最新崛起仓库，抢先发掘黑马项目',
    ctaLabel: '看今日榜',
    icon: Icons.trending_up,
    gradient: [AppColors.primary, AppColors.bannerBlueEnd],
    actionType: ExploreBannerActionType.switchSince,
    since: TrendingSince.today,
  ),
  ExploreBannerItem(
    badge: '跨端生态',
    title: 'Flutter / Dart 精品合集',
    subtitle: '高频组件库、状态管理方案与实战开源客户端',
    ctaLabel: '浏览生态',
    icon: Icons.devices,
    gradient: [AppColors.merged, AppColors.bannerPurpleEnd],
    actionType: ExploreBannerActionType.searchQuery,
    query: 'topic:flutter stars:>100',
  ),
  ExploreBannerItem(
    badge: '参与开源',
    title: 'Good First Issue 新手村',
    subtitle: '筛选带新手任务标识的活跃仓库，轻松开启首次 PR',
    ctaLabel: '去看看',
    icon: Icons.volunteer_activism,
    gradient: [AppColors.success, AppColors.bannerGreenEnd],
    actionType: ExploreBannerActionType.switchFeedMode,
    feedMode: ExploreFeedMode.beginner,
  ),
];

/// 探索首页 8 大技术领域快捷入口配置
const List<ExploreTopicEntry> exploreTopics = [
  ExploreTopicEntry(
    label: 'AI / LLM',
    query: 'topic:llm stars:>100',
    icon: Icons.psychology_outlined,
    color: AppColors.merged,
    surfaceColor: AppColors.mergedSurface,
  ),
  ExploreTopicEntry(
    label: 'Flutter',
    query: 'topic:flutter stars:>50',
    icon: Icons.flutter_dash,
    color: AppColors.primary,
    surfaceColor: AppColors.primarySurface,
  ),
  ExploreTopicEntry(
    label: '前端工程',
    query: 'topic:frontend stars:>200',
    icon: Icons.web_outlined,
    color: AppColors.topicTeal,
    surfaceColor: AppColors.topicTealSurface,
  ),
  ExploreTopicEntry(
    label: '后端 Go',
    query: 'language:Go stars:>200',
    icon: Icons.dns_outlined,
    color: AppColors.primary,
    surfaceColor: AppColors.primarySurface,
  ),
  ExploreTopicEntry(
    label: 'Rust 系统',
    query: 'language:Rust stars:>200',
    icon: Icons.memory_outlined,
    color: AppColors.topicOrange,
    surfaceColor: AppColors.topicOrangeSurface,
  ),
  ExploreTopicEntry(
    label: '效率工具',
    query: 'topic:cli stars:>200',
    icon: Icons.build_outlined,
    color: AppColors.success,
    surfaceColor: AppColors.successSurface,
  ),
  ExploreTopicEntry(
    label: '新手 PR',
    query: 'good-first-issues:>5 stars:>50',
    icon: Icons.handshake_outlined,
    color: AppColors.topicPink,
    surfaceColor: AppColors.topicPinkSurface,
  ),
  ExploreTopicEntry(
    label: '学习路线',
    query: 'topic:roadmap stars:>300',
    icon: Icons.menu_book_outlined,
    color: AppColors.brandDark,
    surfaceColor: AppColors.inputFill,
  ),
];

/// 探索首页次级推荐模块内存缓存（20 分钟有效），避免切语言或切换 Tab 重复耗尽 60/hr 配额
class ExploreShowcaseCache {
  const ExploreShowcaseCache._();

  static const Duration ttl = Duration(minutes: 20);

  static List<RepoOwner> _owners = const [];
  static DateTime? _ownersFetchedAt;

  /// 读取当前是否命中未过期的开源作者缓存
  static List<RepoOwner>? get cachedOwners {
    final fetchedAt = _ownersFetchedAt;
    if (fetchedAt == null || _owners.isEmpty) return null;
    if (DateTime.now().difference(fetchedAt) >= ttl) return null;
    return _owners;
  }

  /// 写入开源作者缓存
  static void saveOwners(List<RepoOwner> owners) {
    _owners = List<RepoOwner>.unmodifiable(owners);
    _ownersFetchedAt = DateTime.now();
  }

  /// 清空内存缓存（下拉刷新与单元测试前置清理用）
  static void clear() {
    _owners = const [];
    _ownersFetchedAt = null;
  }
}
