import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 统一加载中弹窗。
///
/// 使用引用计数支持多页面并发 `show()`：只要还有调用方未 `hide()`，
/// 弹窗就保持显示；最后一个调用方 `hide()` 时才真正移除路由。
/// 这样既避免重复弹出，也避免"后一次 show 被吞、前一次 hide 误关"。
class LoadingDialog {
  LoadingDialog._();

  static Route<void>? _route;
  static int _showCount = 0;
  static String _message = '加载中...';

  static bool get isShowing => _route != null;

  static void show(BuildContext context, {String? message = '加载中...'}) {
    // 必须先判 mounted 再自增：context 已卸载时若先加计数，
    // 后续 hide() 会多减一次才能归零，导致遮罩永久卡住。
    if (!context.mounted) return;
    _showCount++;
    _message = message ?? _message;
    if (_route != null) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(_message, style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _route = route;
    navigator.push(route).whenComplete(() {
      if (identical(_route, route)) {
        _route = null;
        _showCount = 0;
      }
    });
  }

  static void hide() {
    if (_showCount > 0) _showCount--;
    if (_showCount > 0) return;
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    route.navigator?.removeRoute(route);
  }
}
