import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/web_url_strategy.dart';

/// 应用入口：初始化跨平台配置、全局异常兜底与共享状态控制器
void main(List<String> args) {
  // 插件（如 SharedPreferences）依赖 Flutter Binding，必须在 runApp 前初始化
  WidgetsFlutterBinding.ensureInitialized();
  // Web 端启用真实路径策略（/repo?...），非 Web 平台为空实现
  configureWebUrlStrategy();

  // 捕获未处理的 Flutter 框架同步异常并打印定位日志
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // 兜底捕获未 await 的异步异常，避免在 Release 构建中静默丢失
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[未捕获异步异常] $error\n$stack');
    return true;
  };

  // 全局共享状态在启动阶段统一注册一次，页面侧仅通过 Get.find 取用
  Get.put(UserController(), permanent: true);
  Get.put(StarSyncController(), permanent: true);
  final rateLimitController = Get.put(RateLimitController(), permanent: true);

  // 将网络层捕获到的 GitHub RateLimit 响应头同步到全局配额控制器
  DioRequest.onRateLimitUpdate =
      ({required int limit, required int remaining, DateTime? resetAt}) {
        rateLimitController.updateFromHeaders(
          limit: limit,
          remaining: remaining,
          resetAt: resetAt,
        );
      };

  runApp(getRootWidget());
}
