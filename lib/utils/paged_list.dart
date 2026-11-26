import 'dart:collection';

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
  bool _hasMore = true;
  String _errorMessage = '';
  bool _disposed = false;

  List<T> get items => UnmodifiableListView<T>(_items);

  int get length => _items.length;

  T operator [](int index) => _items[index];

  bool get isLoading => _isLoading;

  bool get loadingMore => _loadingMore;

  bool get hasMore => _hasMore;

  String get errorMessage => _errorMessage;

  bool get isEmpty => _items.isEmpty;

  /// 首次加载或下拉刷新
  Future<void> refresh() async {
    if (_disposed) return;
    _isLoading = _items.isEmpty;
    _loadingMore = false;
    _errorMessage = '';
    _hasMore = true;
    notifyListeners();
    await _fetch(page: 1, reset: true);
  }

  /// 上拉加载下一页
  Future<void> loadMore() async {
    if (_disposed ||
        _isLoading ||
        _loadingMore ||
        !_hasMore ||
        _items.isEmpty) {
      return;
    }
    _loadingMore = true;
    notifyListeners();
    await _fetch(page: _page + 1, reset: false);
  }

  /// 本地移除若干项（如取消 Star 后同步我的 Star 列表）
  void removeWhere(bool Function(T item) test) {
    if (_disposed) return;
    final int before = _items.length;
    _items.removeWhere(test);
    if (_items.length != before) notifyListeners();
  }

  /// 清空列表与状态
  void clear() {
    if (_disposed) return;
    _items.clear();
    _page = 1;
    _isLoading = false;
    _loadingMore = false;
    _hasMore = true;
    _errorMessage = '';
    notifyListeners();
  }

  Future<void> _fetch({required int page, required bool reset}) async {
    try {
      final PageResult<T> result = await loader(page);
      if (_disposed) return;
      if (reset) {
        _items
          ..clear()
          ..addAll(result.items);
      } else {
        _items.addAll(result.items);
      }
      _page = result.page > 0 ? result.page : page;
      _hasMore = result.hasMore && result.items.isNotEmpty;
    } catch (error) {
      if (_disposed) return;
      final String message = resolveErrorMessage(
        error,
        fallback: reset ? firstPageErrorFallback : loadMoreErrorFallback,
      );
      if (reset) {
        _errorMessage = message;
      } else {
        onLoadMoreError?.call(message);
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
