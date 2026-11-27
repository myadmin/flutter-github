import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/user.dart';
import 'package:gh_explorer/components/common/gh_update_dialog.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/pages/Explore/index.dart';
import 'package:gh_explorer/pages/Feed/index.dart';
import 'package:gh_explorer/pages/Mine/index.dart';
import 'package:gh_explorer/pages/Search/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/services/app_update_service.dart';
import 'package:gh_explorer/stores/notification_badge_store.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 底部 4 个主导航 Tab 定义（使用 Dart 3 Record 保存静态结构）
final List<({IconData icon, IconData activeIcon, String label})> _tabList = [
  (icon: Icons.explore_outlined, activeIcon: Icons.explore, label: '探索'),
  (icon: Icons.search_outlined, activeIcon: Icons.search_rounded, label: '搜索'),
  (
    icon: Icons.dynamic_feed_outlined,
    activeIcon: Icons.dynamic_feed,
    label: '动态',
  ),
  (icon: Icons.person_outline, activeIcon: Icons.person, label: '我的'),
];

/// 主框架：底部 4 Tab 懒加载容器（参考 hm_shop MainPage）
class MainPage extends StatefulWidget {
  const MainPage({super.key, this.updateService});

  /// 可注入自定义更新服务（测试用，默认使用全局单例）
  final AppUpdateService? updateService;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const int _exploreTabIndex = 0;
  static const int _searchTabIndex = 1;
  static const int _feedTabIndex = 2;
  static const int _mineTabIndex = 3;

  final UserController _userController = Get.find<UserController>();
  final StarSyncController _starSyncController = Get.find<StarSyncController>();

  AppUpdateService get _updateService =>
      widget.updateService ?? AppUpdateService.instance;

  int _currentIndex = _exploreTabIndex;
  String _searchPresetQuery = '';
  int _searchQueryTicket = 0;

  /// 只在首次切到某个 Tab 时才构建它，避免冷启动一次性发过多请求
  final Set<int> _visitedTabs = <int>{_exploreTabIndex};

  /// 是否已处于跳转登录页过程中，防止并发 401 重复压栈
  bool _redirectingToLogin = false;
  late final Worker _userWatcher;

  @override
  void initState() {
    super.initState();
    // 注册全局 401 凭证失效回调，统一清理用户态并引导重登
    DioRequest.onUnauthorized = _handleUnauthorized;
    // 退出登录时同步清空跨页 Star 缓存与未读通知红点
    _userWatcher = ever(_userController.user, (user) {
      if (!user.isLoggedIn) {
        _starSyncController.clearAll();
        NotificationBadgeStore.clear();
      }
    });
    _initUser().whenComplete(_checkAppUpdate);
  }

  /// 冷启动静默检测 GitHub Release 更新，仅发现更新时弹窗提示
  Future<void> _checkAppUpdate() async {
    final release = await _updateService.check();
    if (release == null || !mounted) return;
    final current = await _updateService.currentVersion();
    if (!mounted) return;
    await showGhUpdateDialog(
      context,
      release: release,
      currentVersion: current,
      service: _updateService,
    );
  }

  @override
  void dispose() {
    DioRequest.onUnauthorized = null;
    _userWatcher.dispose();
    super.dispose();
  }

  /// 处理 401 未授权事件：清空用户态并防重入跳往登录页
  void _handleUnauthorized() {
    _userController.clearUserInfo();
    if (!mounted || _redirectingToLogin) return;
    _redirectingToLogin = true;
    ToastUtils.showToast(context, 'GitHub 登录已失效，请重新登录');
    Navigator.pushNamed(
      context,
      AppRoutes.login,
    ).whenComplete(() => _redirectingToLogin = false);
  }

  /// 冷启动恢复本地持久化 Token，并向 `/user` 拉取最新资料
  Future<void> _initUser() async {
    await tokenManager.init();
    if (tokenManager.hasToken) {
      try {
        final res = await getCurrentUserAPI();
        final scopes = res.scopes.isNotEmpty
            ? res.scopes
            : tokenManager.getScopes();
        if (res.scopes.isNotEmpty) {
          await tokenManager.setScopes(res.scopes);
        }
        _userController.updateUserInfo(res.user, tokenScopes: scopes);
      } catch (e) {
        // 断网等临时错误保留本地凭证，401 已由拦截器统一处理
        debugPrint('恢复 GitHub 登录态失败: $e');
      }
    }
  }

  /// 切换底部 Tab，同时标记目标页已访问以触发首次构建
  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
  }

  /// 由探索页专题或领域快捷入口携带查询词跳转到搜索 Tab 并立即检索
  void _openSearchWithQuery(String query) {
    setState(() {
      _searchPresetQuery = query;
      _searchQueryTicket++;
      _currentIndex = _searchTabIndex;
      _visitedTabs.add(_searchTabIndex);
    });
  }

  /// 按下标懒加载构建 Tab 页面，未切到过的页面用空盒占位
  Widget _buildTabPage(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case _searchTabIndex:
        return SearchView(
          presetQuery: _searchPresetQuery,
          queryTicket: _searchQueryTicket,
        );
      case _feedTabIndex:
        return const FeedView();
      case _mineTabIndex:
        return MineView(isActive: _currentIndex == _mineTabIndex);
      case _exploreTabIndex:
      default:
        return ExploreView(
          isActive: _currentIndex == _exploreTabIndex,
          onSearchTap: () => _selectTab(_searchTabIndex),
          onTopicQueryTap: _openSearchWithQuery,
        );
    }
  }

  /// 渲染底部导航图标：选中态附带胶囊高亮底色与放大尺寸，支持可选未读红点提示
  Widget _buildTabIcon(
    IconData iconData, {
    required bool active,
    bool allowUnreadDot = false,
  }) {
    final colors = context.appColors;
    final activePillColor = colors.isDark
        ? colors.primary.withValues(alpha: 0.18)
        : colors.primarySurface;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: active ? activePillColor : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Icon(iconData, size: active ? 22 : 21),
    );
    if (!allowUnreadDot) return pill;
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationBadgeStore.hasUnread,
      builder: (context, hasUnread, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (hasUnread)
              Positioned(
                right: 6,
                top: 1,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.badge,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
      child: pill,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == _exploreTabIndex,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _selectTab(_exploreTabIndex);
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              for (var i = 0; i < _tabList.length; i++) _buildTabPage(i),
            ],
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: 0.8,
              thickness: 0.8,
              color: context.appColors.divider.withValues(alpha: 0.7),
            ),
            BottomNavigationBar(
              currentIndex: _currentIndex,
              showUnselectedLabels: true,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
              unselectedItemColor: context.appColors.textSecondary.withValues(
                alpha: 0.82,
              ),
              selectedItemColor: context.appColors.primary,
              backgroundColor: context.appColors.cardBackground,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              onTap: _selectTab,
              items: [
                for (var i = 0; i < _tabList.length; i++)
                  BottomNavigationBarItem(
                    icon: _buildTabIcon(
                      _tabList[i].icon,
                      active: false,
                      allowUnreadDot: i == _feedTabIndex,
                    ),
                    activeIcon: _buildTabIcon(
                      _tabList[i].activeIcon,
                      active: true,
                      allowUnreadDot: i == _feedTabIndex,
                    ),
                    label: _tabList[i].label,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
