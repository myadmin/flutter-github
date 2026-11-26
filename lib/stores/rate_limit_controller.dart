import 'package:get/get.dart';

/// GitHub API 速率限制状态快照
class RateLimitState {
  const RateLimitState({
    required this.limit,
    required this.remaining,
    this.resetAt,
  });

  const RateLimitState.initial() : limit = 60, remaining = 60, resetAt = null;

  final int limit;
  final int remaining;
  final DateTime? resetAt;

  bool get isKnown => limit > 0;
}

/// 跨页面共享当前 GitHub API 配额剩余情况（区分 core 与 search，由 Dio 拦截器自动更新）
class RateLimitController extends GetxController {
  /// 核心 REST API 配额（未登录 60/小时，登录后 5000/小时）
  final Rx<RateLimitState> state = const RateLimitState.initial().obs;

  /// 搜索 API 配额（独立每分钟限流：未登录 10/分钟，登录后 30/分钟）
  final Rxn<RateLimitState> searchState = Rxn<RateLimitState>();

  void updateFromHeaders({
    required int limit,
    required int remaining,
    DateTime? resetAt,
  }) {
    state.value = RateLimitState(
      limit: limit,
      remaining: remaining,
      resetAt: resetAt,
    );
  }

  void updateSearchFromHeaders({
    required int limit,
    required int remaining,
    DateTime? resetAt,
  }) {
    searchState.value = RateLimitState(
      limit: limit,
      remaining: remaining,
      resetAt: resetAt,
    );
  }

  /// 按 `x-ratelimit-resource` 路由更新对应配额桶，防止搜索限流覆盖核心配额
  void updateFromResource({
    required String resource,
    required int limit,
    required int remaining,
    DateTime? resetAt,
  }) {
    final normalized = resource.trim().toLowerCase();
    if (normalized == 'search') {
      updateSearchFromHeaders(
        limit: limit,
        remaining: remaining,
        resetAt: resetAt,
      );
      return;
    }
    if (normalized == 'core' || normalized.isEmpty) {
      updateFromHeaders(limit: limit, remaining: remaining, resetAt: resetAt);
    }
  }

  void reset() {
    state.value = const RateLimitState.initial();
    searchState.value = null;
  }
}
