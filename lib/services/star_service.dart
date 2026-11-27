import 'package:gh_explorer/api/star.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';

/// 仓库 Star 互动领域服务：收敛点赞切换的乐观更新、跨页快照同步与失败回滚
class StarService {
  const StarService._();

  /// 切换仓库 Star 状态，立即通知调用方与全局快照并在接口异常时回滚
  static Future<void> toggleStar({
    required String owner,
    required String repoName,
    required bool prevStarred,
    required int prevCount,
    required bool nextStarred,
    required int nextCount,
    StarSyncController? starSync,
    required void Function(bool starred, int count) onStateChanged,
  }) async {
    final fullName = '$owner/$repoName';
    final clampedNext = nextCount < 0 ? 0 : nextCount;
    onStateChanged(nextStarred, clampedNext);
    starSync?.setSnapshot(
      fullName,
      isStarred: nextStarred,
      starCount: clampedNext,
    );

    try {
      if (nextStarred) {
        await starRepoAPI(owner, repoName);
      } else {
        await unstarRepoAPI(owner, repoName);
      }
    } catch (_) {
      final clampedPrev = prevCount < 0 ? 0 : prevCount;
      onStateChanged(prevStarred, clampedPrev);
      starSync?.setSnapshot(
        fullName,
        isStarred: prevStarred,
        starCount: clampedPrev,
      );
      rethrow;
    }
  }
}
