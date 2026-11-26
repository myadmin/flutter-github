import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 统一加载中弹窗（复用 hm_shop 的路由引用控制方案，避免误关业务页面）
class LoadingDialog {
  static Route<void>? _route;

  static bool get isShowing => _route != null;

  static void show(BuildContext context, {String? message = '加载中...'}) {
    if (_route != null) {
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    late final Route<void> route;
    route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(message ?? ''),
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
      }
    });
  }

  static void hide() {
    final route = _route;
    if (route == null || !route.isActive) {
      _route = null;
      return;
    }
    _route = null;
    route.navigator?.removeRoute(route);
  }
}
