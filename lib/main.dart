import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/explore_tags_controller.dart';
import 'package:gh_explorer/stores/rate_limit_controller.dart';
import 'package:gh_explorer/stores/star_sync_controller.dart';
import 'package:gh_explorer/stores/theme_controller.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/app_error_reporter.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/web_url_strategy.dart';

/// 应用入口：初始化跨平台配置、全局异常兜底与共享状态控制器
///
/// 启动阶段会等待「主题模式」从本地读取完成后再 `runApp`，避免暗色用户
/// 首帧先闪一下浅色主题（SharedPreferences 读取为毫秒级，不影响启动耗时）。
Future<void> main(List<String> args) async {
  // 插件（如 SharedPreferences）依赖 Flutter Binding，必须在 runApp 前初始化
  WidgetsFlutterBinding.ensureInitialized();
  // 适度放宽图片内存缓存上限，减少列表与头像回滑时的重复解码
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  // Web 端启用真实路径策略（/repo?...），非 Web 平台为空实现
  configureWebUrlStrategy();

  // 捕获未处理的 Flutter 框架同步异常
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppErrorReporter.report(
      details.exception,
      details.stack,
      context: 'FlutterError',
    );
  };

  // 兜底捕获未 await 的异步异常，交给统一上报入口，避免 Release 中静默消失
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppErrorReporter.report(error, stack, context: '未捕获异步异常');
    return true;
  };

  // 全局共享状态在启动阶段统一注册一次，页面侧仅通过 Get.find 取用
  Get.put(UserController(), permanent: true);
  Get.put(StarSyncController(), permanent: true);
  final rateLimitController = Get.put(RateLimitController(), permanent: true);
  final exploreTagsController = Get.put(
    ExploreTagsController(),
    permanent: true,
  );
  unawaited(exploreTagsController.ensureLoaded());
  final themeController = Get.put(ThemeController(), permanent: true);
  // 首帧前就把主题模式读出来，避免暗色用户看到浅色闪屏
  await themeController.ensureLoaded();

  // 将网络层捕获到的 GitHub RateLimit 响应头按资源域同步到全局配额控制器
  DioRequest.onResourceRateLimitUpdate =
      ({
        required String resource,
        required int limit,
        required int remaining,
        DateTime? resetAt,
      }) {
        rateLimitController.updateFromResource(
          resource: resource,
          limit: limit,
          remaining: remaining,
          resetAt: resetAt,
        );
      };

  runApp(getRootWidget());
}
