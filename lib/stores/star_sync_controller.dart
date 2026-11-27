import 'package:get/get.dart';

/// 单个仓库的 Star 状态快照
class RepoStarSnapshot {
  const RepoStarSnapshot({required this.isStarred, required this.starCount});

  final bool isStarred;
  final int starCount;
}

/// 跨页面同步仓库 Star 状态与 Star 计数（类比 hm_shop 的 CartController）
///
/// 在仓库详情页、探索页、搜索页、「我的 Star」页之间共享状态：
/// 任意位置点 Star 或取消 Star 后，其余列表卡片即时刷新图标与数字。
class StarSyncController extends GetxController {
  final RxMap<String, RepoStarSnapshot> _snapshots =
      <String, RepoStarSnapshot>{}.obs;

  /// 快照上限：列表页会随滚动持续写入，若不设上限，长时间使用后
  /// 这个常驻内存的 Map 会无限增长（每项几十字节，但条目数无界）。
  static const int _maxEntries = 800;

  static String _key(String fullName) => fullName.trim().toLowerCase();

  /// 读取某仓库已同步的快照，未缓存则返回 null
  RepoStarSnapshot? snapshotOf(String fullName) => _snapshots[_key(fullName)];

  /// 写入或更新某仓库的 Star 状态与计数
  void setSnapshot(
    String fullName, {
    required bool isStarred,
    required int starCount,
  }) {
    if (fullName.trim().isEmpty) return;
    _snapshots[_key(fullName)] = RepoStarSnapshot(
      isStarred: isStarred,
      starCount: starCount < 0 ? 0 : starCount,
    );
    _evictIfNeeded();
  }

  /// 批量写入（列表页整页同步时使用）。
  ///
  /// `_snapshots` 是 RxMap，逐条赋值会让每个条目各触发一次响应式通知，
  /// 而每张卡片又各自 `Obx` 订阅同一 Map，整页同步时通知次数是 O(条目数²)。
  /// 这里先合并到普通 Map 再一次性写回，只触发一次通知。
  void setSnapshots(Map<String, RepoStarSnapshot> snapshots) {
    if (snapshots.isEmpty) return;
    final merged = Map<String, RepoStarSnapshot>.from(_snapshots);
    snapshots.forEach((fullName, snapshot) {
      if (fullName.trim().isEmpty) return;
      merged[_key(fullName)] = RepoStarSnapshot(
        isStarred: snapshot.isStarred,
        starCount: snapshot.starCount < 0 ? 0 : snapshot.starCount,
      );
    });
    _snapshots.assignAll(merged);
    _evictIfNeeded();
  }

  /// 超出上限时按插入顺序淘汰最早的条目（列表页重新拉取会自然补回）
  void _evictIfNeeded() {
    while (_snapshots.length > _maxEntries) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  /// 退出登录时清空已登录态下的 Star 标记
  void clearAll() {
    _snapshots.clear();
  }
}
