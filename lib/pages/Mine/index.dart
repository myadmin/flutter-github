import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/user.dart';
import 'package:gh_explorer/components/Mine/gh_mine_header.dart';
import 'package:gh_explorer/components/Mine/gh_mine_quick_actions.dart';
import 'package:gh_explorer/components/Mine/gh_mine_settings_card.dart';
import 'package:gh_explorer/components/Mine/gh_mine_status_card.dart';
import 'package:gh_explorer/components/common/gh_update_dialog.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/services/app_update_service.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 「我的」页面（参考 hm_shop MineView 结构）
class MineView extends StatefulWidget {
  const MineView({super.key, this.updateService, this.isActive = true});

  /// 可注入自定义更新服务（测试用，默认使用全局单例）
  final AppUpdateService? updateService;

  /// 当前「我的」Tab 是否处于前景激活态，切入时自动同步最新 API 配额
  final bool isActive;

  @override
  State<MineView> createState() => _MineViewState();
}

class _MineViewState extends State<MineView> {
  final UserController _userController = Get.find<UserController>();
  final RateLimitController _rateLimitController =
      Get.find<RateLimitController>();
  final StarSyncController _starSyncController = Get.find<StarSyncController>();
  late final ExploreTagsController _tagsController =
      Get.isRegistered<ExploreTagsController>()
      ? Get.find<ExploreTagsController>()
      : Get.put(ExploreTagsController(), permanent: true);

  AppUpdateService get _updateService =>
      widget.updateService ?? AppUpdateService.instance;

  String _versionText = '';
  bool _checkingUpdate = false;
  late final Worker _userWatcher;

  @override
  void initState() {
    super.initState();
    unawaited(_tagsController.ensureLoaded());
    _userWatcher = ever(_userController.user, (_) {
      if (mounted && widget.isActive) {
        unawaited(_refreshRateLimit(silent: true));
      }
    });
    _loadVersion();
    _refreshRateLimit(silent: true);
  }

  @override
  void didUpdateWidget(covariant MineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_refreshRateLimit(silent: true));
    }
  }

  @override
  void dispose() {
    _userWatcher.dispose();
    super.dispose();
  }

  /// 读取当前应用版本号（优先展示 CI 注入的 Release Tag）用于状态卡片展示
  Future<void> _loadVersion() async {
    if (GlobalConstants.appReleaseTag.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _versionText = GlobalConstants.appReleaseTag;
      });
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionText = info.version;
      });
    } catch (_) {
      // 测试环境未注册平台插件时忽略
    }
  }

  /// 手动点击检查更新：绕过 6 小时冷却期即时检测最新 GitHub Release
  Future<void> _checkUpdateManually() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
    });
    try {
      final release = await _updateService.check(force: true);
      if (!mounted) return;
      final current = await _updateService.currentVersion();
      if (!mounted) return;
      if (release == null) {
        final label = current.isEmpty
            ? 'v1.0.0'
            : (current.startsWith('v') ? current : 'v$current');
        ToastUtils.showToast(context, '当前已是最新版本 $label');
        return;
      }
      await showGhUpdateDialog(
        context,
        release: release,
        currentVersion: current,
        service: _updateService,
      );
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '检查更新失败，请稍后重试'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

  /// 主动拉取当前 GitHub API 核心与搜索配额并同步到全局控制器
  Future<void> _refreshRateLimit({bool silent = false}) async {
    try {
      final all = await getAllRateLimitsAPI();
      _rateLimitController.updateFromHeaders(
        limit: all.core.limit,
        remaining: all.core.remaining,
        resetAt: all.core.resetAt,
      );
      if (all.search != null) {
        _rateLimitController.updateSearchFromHeaders(
          limit: all.search!.limit,
          remaining: all.search!.remaining,
          resetAt: all.search!.resetAt,
        );
      }
      if (!silent && mounted) {
        ToastUtils.showToast(context, '配额已刷新：剩余 ${all.core.remaining} 次');
      }
    } catch (e) {
      if (!silent && mounted) {
        ToastUtils.showToast(
          context,
          resolveErrorMessage(e, fallback: '刷新配额失败'),
        );
      }
    }
  }

  /// 访问私有入口前检查登录态，未登录时弹出提示并跳往登录页
  bool _ensureLogin(String hint) {
    if (_userController.isLoggedIn) return true;
    ToastUtils.showToast(context, hint);
    Navigator.pushNamed(context, AppRoutes.login);
    return false;
  }

  /// 二次确认后退出登录，清理本地令牌及跨页内存缓存
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认退出登录吗？'),
          content: const Text('退出后将清空本地保存的 GitHub Token'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await tokenManager.removeToken();
    _userController.clearUserInfo();
    _starSyncController.clearAll();
    _rateLimitController.reset();
    if (!mounted) return;
    ToastUtils.showToast(context, '已退出登录');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              if (_userController.isLoggedIn) {
                try {
                  final res = await getCurrentUserAPI();
                  _userController.updateUserInfo(
                    res.user,
                    tokenScopes: res.scopes,
                  );
                } catch (_) {}
              }
              await _refreshRateLimit(silent: true);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Obx(() {
                  final user = _userController.user.value;
                  return GhMineHeader(
                    user: user,
                    onLoginTap: () =>
                        Navigator.pushNamed(context, AppRoutes.login),
                    onLogoutTap: _confirmLogout,
                    onProfileTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.userDetail(user.login),
                    ),
                    onReposTap: () =>
                        Navigator.pushNamed(context, AppRoutes.myReposPath),
                    onFollowersTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.userFollows(user.login, tab: 'followers'),
                    ),
                    onFollowingTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.userFollows(user.login, tab: 'following'),
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.module),
                GhMineQuickActions(
                  onMyReposTap: () {
                    if (_ensureLogin('登录后查看我的仓库')) {
                      Navigator.pushNamed(context, AppRoutes.myReposPath);
                    }
                  },
                  onMyStarsTap: () {
                    if (_ensureLogin('登录后查看我 Star 的项目')) {
                      Navigator.pushNamed(context, AppRoutes.myStarsPath);
                    }
                  },
                  onNotificationsTap: () {
                    if (_ensureLogin('登录后查看消息通知')) {
                      Navigator.pushNamed(context, AppRoutes.notificationsPath);
                    }
                  },
                  onFootprintTap: () =>
                      Navigator.pushNamed(context, AppRoutes.footprintPath),
                ),
                const SizedBox(height: AppSpacing.module),
                Obx(
                  () => GhMineStatusCard(
                    rateLimit: _rateLimitController.state.value,
                    searchRateLimit: _rateLimitController.searchState.value,
                    scopes: _userController.scopes.toList(),
                    versionText: _versionText,
                    onRefreshRateLimit: _refreshRateLimit,
                    onCheckUpdate: _checkUpdateManually,
                    checkingUpdate: _checkingUpdate,
                  ),
                ),
                const SizedBox(height: AppSpacing.module),
                Obx(
                  () => GhMineSettingsCard(
                    tagCount: _tagsController.displayTags.length,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.settingsPath),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
