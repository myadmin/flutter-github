import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gh_explorer/api/feed.dart';

/// 全局未读通知红点状态（避免重复请求并支持动态/通知页联动消除红点）
class NotificationBadgeStore {
  const NotificationBadgeStore._();

  /// 当前账号是否存在至少一条未读 GitHub 通知
  static final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  /// 主动检测未读通知状态（只拉取 1 条以最小化开销，遇网络异常静默保持现状）
  static Future<bool> refresh({CancelToken? cancelToken}) async {
    try {
      final page = await getNotificationsAPI(
        all: false,
        participating: false,
        page: 1,
        perPage: 1,
        cancelToken: cancelToken,
      );
      final unread = page.items.isNotEmpty;
      hasUnread.value = unread;
      return unread;
    } catch (_) {
      return hasUnread.value;
    }
  }

  /// 直接更新本地红点状态（标为已读或全部已读后立即反馈）
  static void setUnread(bool unread) {
    hasUnread.value = unread;
  }

  /// 退出登录或测试重置时清空红点状态
  static void clear() {
    hasUnread.value = false;
  }
}
