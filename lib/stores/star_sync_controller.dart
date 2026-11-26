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
  }

  /// 退出登录时清空已登录态下的 Star 标记
  void clearAll() {
    _snapshots.clear();
  }
}
