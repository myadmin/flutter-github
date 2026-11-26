import 'package:flutter/foundation.dart';

/// 应用级错误上报入口。
///
/// 统一收集 Flutter 框架异常、未捕获异步异常与业务层异常，
/// 在 Debug 下打印，在 Release 下交给可插拔的 [sink]（如 Sentry / 自建上报），
/// 避免 `PlatformDispatcher.onError` 静默吞掉问题。
class AppErrorReporter {
  AppErrorReporter._();

  /// 外部上报接收器；为空时仅打印，接入监控 SDK 时在 `main()` 中赋值。
  static void Function(Object error, StackTrace? stack, {String? context})?
  sink;

  /// 上报一条异常；永不抛出，避免错误处理本身再次崩溃
  static void report(Object error, StackTrace? stack, {String? context}) {
    final prefix = context == null || context.isEmpty ? '' : '[$context] ';
    debugPrint('$prefix异常: $error');
    if (stack != null) {
      debugPrint('$stack');
    }
    try {
      sink?.call(error, stack, context: context);
    } catch (e) {
      debugPrint('错误上报失败: $e');
    }
  }
}
