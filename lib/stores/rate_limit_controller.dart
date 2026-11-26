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

/// 跨页面共享当前 GitHub API 配额剩余情况（由 Dio 拦截器自动更新）
class RateLimitController extends GetxController {
  final Rx<RateLimitState> state = const RateLimitState.initial().obs;

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

  void reset() {
    state.value = const RateLimitState.initial();
  }
}
