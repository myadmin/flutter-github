import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gh_explorer/utils/api_exception.dart';

/// 分页接口返回的一页数据
@immutable
class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
}

/// 分页列表状态机（复用 hm_shop 约定）
///
/// 收敛首次加载、下拉刷新、上拉加载更多状态，
/// 首页失败写 [errorMessage]，加载更多失败回调 [onLoadMoreError]。
class PagedListController<T> extends ChangeNotifier {
  PagedListController({
    required this.pageSize,
    required this.loader,
    this.firstPageErrorFallback = '加载失败',
    this.loadMoreErrorFallback = '加载更多失败',
    this.onLoadMoreError,
  });

  final int pageSize;
  final Future<PageResult<T>> Function(int page) loader;
  final String firstPageErrorFallback;
  final String loadMoreErrorFallback;
  final ValueChanged<String>? onLoadMoreError;

  final List<T> _items = <T>[];

  int _page = 1;
  bool _isLoading = false;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _hasMore = true;
  bool _loadMoreFailed = false;
  String _errorMessage = '';
  bool _disposed = false;

  /// 请求代际：refresh / clear 时自增，使所有在途请求的响应作废，
  /// 避免旧查询结果覆盖新列表（搜索词/筛选条件/仓库分支切换等场景）。
  int _epoch = 0;

  /// 与当前代际绑定的取消令牌：refresh / clear / dispose 时取消在途请求，
  /// 页面退出或切换筛选后不再占用带宽与 API 配额。
  CancelToken _cancelToken = CancelToken();

  /// 供页面在 loader 中透传给 API：`cancelToken: _list.cancelToken`
  CancelToken get cancelToken => _cancelToken;

  List<T> get items => UnmodifiableListView<T>(_items);

  int get length => _items.length;

  T operator [](int index) => _items[index];

  bool get isLoading => _isLoading;

  bool get loadingMore => _loadingMore;

  bool get hasMore => _hasMore;

  /// 上一次「加载更多」是否失败（失败后需用户点击重试，避免滚动反复请求）
  bool get loadMoreFailed => _loadMoreFailed;

  String get errorMessage => _errorMessage;

  bool get isEmpty => _items.isEmpty;

  /// 首次加载或下拉刷新
  Future<void> refresh() async {
    if (_disposed) return;
    _cancelInFlight();
    final int epoch = ++_epoch;
    _refreshing = true;
    _isLoading = _items.isEmpty;
    _loadingMore = false;
    _loadMoreFailed = false;
    _errorMessage = '';
    _hasMore = true;
    notifyListeners();
    await _fetch(page: 1, reset: true, epoch: epoch);
  }

  /// 上拉加载下一页
  Future<void> loadMore() async {
    if (_disposed ||
        _isLoading ||
        _refreshing ||
        _loadingMore ||
        _loadMoreFailed ||
        !_hasMore ||
        _items.isEmpty) {
      return;
    }
    final int epoch = _epoch;
    _loadingMore = true;
    notifyListeners();
    await _fetch(page: _page + 1, reset: false, epoch: epoch);
  }

  /// 用户点击「加载失败，重试」时重新拉取下一页
  void retryLoadMore() {
    if (_disposed || !_loadMoreFailed || _loadingMore) return;
    _loadMoreFailed = false;
    notifyListeners();
    unawaited(loadMore());
  }

  /// 本地移除若干项（如取消 Star 后同步我的 Star 列表）
  void removeWhere(bool Function(T item) test) {
    if (_disposed) return;
    final int before = _items.length;
    _items.removeWhere(test);
    if (_items.length == before) return;
    // 全部移除后 `loadMore()` 会被 `_items.isEmpty` 守卫拦住，若不把 hasMore
    // 置回 false，列表底部会一直显示「还有更多」却永远加载不出来。
    if (_items.isEmpty) _hasMore = false;
    notifyListeners();
  }

  /// 清空列表与状态
  void clear() {
    if (_disposed) return;
    _cancelInFlight();
    _epoch++; // 作废在途请求，防止旧页数据回填
    _refreshing = false;
    _items.clear();
    _page = 1;
    _isLoading = false;
    _loadingMore = false;
    _loadMoreFailed = false;
    _hasMore = true;
    _errorMessage = '';
    notifyListeners();
  }

  /// 取消当前代际的在途请求，并换上一枚新的取消令牌
  void _cancelInFlight() {
    _cancelToken.cancel();
    _cancelToken = CancelToken();
  }

  Future<void> _fetch({
    required int page,
    required bool reset,
    required int epoch,
  }) async {
    try {
      final PageResult<T> result = await loader(page);
      if (_disposed || epoch != _epoch) return;
      if (reset) {
        _items
          ..clear()
          ..addAll(result.items);
      } else {
        _items.addAll(result.items);
      }
      _page = result.page > 0 ? result.page : page;
      _hasMore = result.hasMore && result.items.isNotEmpty;
      _loadMoreFailed = false;
    } catch (error) {
      if (_disposed || epoch != _epoch) return;
      final String message = resolveErrorMessage(
        error,
        fallback: reset ? firstPageErrorFallback : loadMoreErrorFallback,
      );
      if (reset) {
        _errorMessage = message;
      } else {
        // 记录失败态，滚动不再自动重试，等用户点击 footer 上的重试按钮
        _loadMoreFailed = true;
        onLoadMoreError?.call(message);
      }
    } finally {
      // 只有最新代际的请求才允许恢复状态，旧请求结束时不得覆盖新一轮刷新的 loading 态
      if (!_disposed && epoch == _epoch) {
        _refreshing = false;
        _isLoading = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken.cancel();
    super.dispose();
  }
}
