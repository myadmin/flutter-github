import 'package:dio/dio.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/event.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 获取当前用户关注的人与仓库动态（received_events）
Future<PageResult<GithubEvent>> getReceivedEventsAPI(
  String username, {
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  CancelToken? cancelToken,
}) async {
  final encoded = Uri.encodeComponent(username.trim());
  final res = await dioRequest.getPaged(
    '${HttpConstants.users}/$encoded/received_events',
    params: {'page': page, 'per_page': perPage},
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<GithubEvent>(
    items: asModelList(res.data, GithubEvent.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 获取 GitHub 通知列表
Future<PageResult<NotificationItem>> getNotificationsAPI({
  bool all = false,
  bool participating = false,
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
  CancelToken? cancelToken,
}) async {
  final res = await dioRequest.getPaged(
    HttpConstants.notifications,
    params: {
      'all': all,
      if (participating) 'participating': true,
      'page': page,
      'per_page': perPage,
    },
    perPage: perPage,
    cancelToken: cancelToken,
  );
  return PageResult<NotificationItem>(
    items: asModelList(res.data, NotificationItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}

/// 将单条通知标为已读
Future<void> markNotificationReadAPI(String threadId) async {
  final encoded = Uri.encodeComponent(threadId.trim());
  await dioRequest.patch('${HttpConstants.notifications}/threads/$encoded');
}

/// 将全部通知标为已读
Future<void> markAllNotificationsReadAPI() async {
  await dioRequest.put(HttpConstants.notifications);
}
