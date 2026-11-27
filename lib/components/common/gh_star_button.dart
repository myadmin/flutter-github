import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/services/star_service.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库 Star / 取消 Star 互动按钮
///
/// 支持紧凑图标模式（列表卡片）与完整胶囊模式（仓库详情页），
/// 内置：未登录引导跳转、同一仓库防重连点、乐观更新与失败回滚、跨页状态同步。
class GhStarButton extends StatefulWidget {
  const GhStarButton({
    super.key,
    required this.owner,
    required this.repoName,
    required this.initialCount,
    this.initialStarred = false,
    this.compact = false,
    this.onToggled,
  });

  final String owner;
  final String repoName;
  final int initialCount;
  final bool initialStarred;
  final bool compact;

  /// Star 状态切换成功后的回调，可用于「我的 Star」页实时移除条目
  final ValueChanged<bool>? onToggled;

  @override
  State<GhStarButton> createState() => _GhStarButtonState();
}

class _GhStarButtonState extends State<GhStarButton> {
  /// 是否正在发送 Star / 取消 Star 请求，防止用户连点发重
  bool _pending = false;

  /// 当全局未注册 StarSyncController 时使用的本地兜底状态
  late bool _localStarred;
  late int _localCount;

  String get _fullName => '${widget.owner}/${widget.repoName}';

  /// 测试环境中可能未注册全局控制器，按需安全读取
  UserController? get _userController =>
      Get.isRegistered<UserController>() ? Get.find<UserController>() : null;

  StarSyncController? get _starSync => Get.isRegistered<StarSyncController>()
      ? Get.find<StarSyncController>()
      : null;

  @override
  void initState() {
    super.initState();
    _localStarred = widget.initialStarred;
    _localCount = widget.initialCount;
  }

  @override
  void didUpdateWidget(covariant GhStarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner ||
        oldWidget.repoName != widget.repoName ||
        oldWidget.initialStarred != widget.initialStarred ||
        oldWidget.initialCount != widget.initialCount) {
      _localStarred = widget.initialStarred;
      _localCount = widget.initialCount;
    }
  }

  /// 读取当前仓库的展示状态（优先取跨页面同步快照）
  (bool, int) _currentState() {
    final snapshot = _starSync?.snapshotOf(_fullName);
    if (snapshot != null) {
      return (snapshot.isStarred, snapshot.starCount);
    }
    return (_localStarred, _localCount);
  }

  /// 更新本地与跨页面同步快照
  void _applySnapshot(bool starred, int count) {
    _localStarred = starred;
    _localCount = count < 0 ? 0 : count;
    _starSync?.setSnapshot(
      _fullName,
      isStarred: starred,
      starCount: _localCount,
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// 点击 Star 按钮：校验登录态 -> 乐观切换界面 -> 调用接口并在失败时回滚
  Future<void> _handleTap() async {
    if (_pending) return;

    final userCtrl = _userController;
    if (userCtrl != null && !userCtrl.isLoggedIn) {
      ToastUtils.showToast(context, '登录后即可 Star 项目');
      await Navigator.pushNamed(context, AppRoutes.login);
      // 登录成功后自动续做本次 Star 操作，避免用户再点一次
      if (!mounted || !userCtrl.isLoggedIn) return;
    }

    final (prevStarred, prevCount) = _currentState();
    final nextStarred = !prevStarred;
    final nextCount = nextStarred
        ? prevCount + 1
        : (prevCount > 0 ? prevCount - 1 : 0);

    _pending = true;
    if (mounted) setState(() {});

    try {
      await StarService.toggleStar(
        owner: widget.owner,
        repoName: widget.repoName,
        prevStarred: prevStarred,
        prevCount: prevCount,
        nextStarred: nextStarred,
        nextCount: nextCount,
        starSync: _starSync,
        onStateChanged: _applySnapshot,
      );
      if (!mounted) return;
      ToastUtils.showToast(context, nextStarred ? '已 Star 该项目' : '已取消 Star');
      widget.onToggled?.call(nextStarred);
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '操作失败，请稍后重试'),
      );
    } finally {
      _pending = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = _starSync;
    if (sync == null) {
      return _buildButton(_localStarred, _localCount);
    }
    return Obx(() {
      final snapshot = sync.snapshotOf(_fullName);
      final starred = snapshot?.isStarred ?? _localStarred;
      final count = snapshot?.starCount ?? _localCount;
      return _buildButton(starred, count);
    });
  }

  Widget _buildButton(bool starred, int count) {
    final icon = Icon(
      starred ? Icons.star : Icons.star_border,
      size: widget.compact ? 18 : 18,
      color: starred
          ? context.appColors.starActive
          : context.appColors.textSecondary,
    );

    if (widget.compact) {
      return Semantics(
        button: true,
        label: starred ? '取消 Star，当前 $count' : '点 Star，当前 $count',
        child: InkWell(
          onTap: _pending ? null : _handleTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: starred
                  ? context.appColors.starSurface
                  : context.appColors.inputFill,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: starred
                    ? context.appColors.starActive
                    : context.appColors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 4),
                Text(
                  formatCompactNumber(count),
                  style: context.captionSmallStyle.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: starred ? '已 Star' : 'Star',
      child: OutlinedButton.icon(
        onPressed: _pending ? null : _handleTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: starred
              ? context.appColors.starSurface
              : context.appColors.cardBackground,
          foregroundColor: context.appColors.textPrimary,
          side: BorderSide(
            color: starred
                ? context.appColors.starActive
                : context.appColors.divider,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        icon: icon,
        label: Text(
          '${starred ? 'Starred' : 'Star'} · ${formatCompactNumber(count)}',
          style: context.bodyStrongStyle,
        ),
      ),
    );
  }
}
