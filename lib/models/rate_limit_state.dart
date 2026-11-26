/// GitHub API 速率限制状态快照（core / search 两个配额桶共用）
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
